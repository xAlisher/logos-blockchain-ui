import QtQuick

// QtRO orchestration kept separate from presentation for isolated contract tests.
QtObject {
    id: root
    property var backend: null
    property var bridge: null
    property bool ready: false
    property bool externalBusy: false
    property bool loading: false
    property bool repairing: false
    readonly property bool busy: repairing || externalBusy
    property int timeoutMs: 20000
    property int generation: 0
    property var lifecycle: unavailable(qsTr("Waiting for lifecycle evidence."))
    property string resultText: ""
    property bool resultError: false
    property bool manualRefreshPending: false
    function finishRefreshFeedback(error, unchanged) {
        if (!manualRefreshPending) return
        manualRefreshPending = false
        resultError = !!error
        resultText = error ? qsTr("Refresh failed: %1").arg(String(error))
            : unchanged ? qsTr("Checked — no change.") : qsTr("Status updated.")
    }
    function unavailable(detail) {
        return {ok:false, state:"unavailable", title:qsTr("Status unavailable"), detail:detail, tone:"warning", action:"refresh", actionLabel:qsTr("Refresh"), steps:[], evidence:qsTr("Current evidence unavailable; no activity or earnings inferred.")}
    }
    property Timer deadline: Timer {
        interval: root.timeoutMs
        onTriggered: {
            root.generation++
            if (root.repairing) {
                root.resultError = true
                root.resultText = qsTr("Binding request timed out; outcome unknown. Refresh before retrying.")
                root.repairing = false
            }
            root.loading = false
            root.finishRefreshFeedback(qsTr("Request timed out."), false)
            root.lifecycle = root.unavailable(qsTr("Lifecycle request timed out. Refresh to try again."))
        }
    }
    onReadyChanged: if (!ready) {
        generation++; deadline.stop(); loading = false
        finishRefreshFeedback(qsTr("Node connection unavailable."), false)
        if (repairing) { resultError = true; resultText = qsTr("Connection lost during binding request; outcome unknown."); repairing = false }
        lifecycle = unavailable(qsTr("Node connection unavailable."))
    }
    function refresh(userInitiated) {
        if (userInitiated) {
            manualRefreshPending = true
            resultError = false
            resultText = qsTr("Refreshing…")
        }
        if (!ready || !backend || !bridge) {
            finishRefreshFeedback(qsTr("Node connection unavailable."), false)
            return
        }
        if (busy) {
            finishRefreshFeedback(qsTr("Another Blend operation is in progress."), false)
            return
        }
        if (loading) return
        var previous = JSON.stringify(lifecycle)
        loading = true
        var token = ++generation
        deadline.restart()
        function failed(error) {
            if (token !== root.generation) return
            error = String(error || qsTr("Request failed."))
            root.deadline.stop(); root.loading = false
            root.generation++
            root.lifecycle = root.unavailable(String(error))
            root.finishRefreshFeedback(error, false)
        }
        try {
            bridge.watch(backend.getBlendLifecycle(), function(r) {
                if (token !== root.generation) return
                if (!r || !r.state || r.ok !== true) {
                    failed(r && (r.error || r.detail) ? (r.error || r.detail) : qsTr("Invalid lifecycle response."))
                    return
                }
                root.deadline.stop(); root.loading = false
                root.generation++
                root.lifecycle = r
                root.finishRefreshFeedback("", JSON.stringify(r) === previous)
            }, failed)
        } catch (e) { failed(e) }
    }
    // Called only by a user click. Never retries or declares/withdraws automatically.
    function repair() {
        if (!ready || !backend || !bridge || busy || loading || lifecycle.action !== "repair") return
        repairing = true; resultText = ""; resultError = false
        var token = ++generation
        deadline.restart()
        function finish(ok, message) {
            if (token !== root.generation) return
            root.deadline.stop(); root.repairing = false
            root.resultError = !ok
            root.resultText = ok ? qsTr("Binding acknowledged. Waiting for chain-accepted activity; no earnings confirmed.") : String(message)
            // Invalidate stale repair eligibility. A subsequent read must offer repair anew.
            root.lifecycle = root.unavailable(qsTr("Refresh to verify binding and activity after the request."))
        }
        try {
            bridge.watch(backend.repairBlendBinding(), function(r) {
                finish(!!(r && r.ok), r && r.error ? r.error : qsTr("Binding request failed."))
            }, function(e) { finish(false, e) })
        } catch (e) { finish(false, e) }
    }
}
