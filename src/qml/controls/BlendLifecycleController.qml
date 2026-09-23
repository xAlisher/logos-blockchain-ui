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
    readonly property bool busy: repairing || externalBusy || recoveryLocked || recoveryBusy
    property bool recoveryBusy: false
    property bool recoveryHeld: false
    property bool recoveryNeedsRead: false
    property bool recoveryPausedConfirmed: false
    readonly property bool recoveryCanStop: ready && !!backend && recoveryPausedConfirmed
        && !recoveryBusy && !repairing && !externalBusy
    property var lastRecovery: ({})
    property var recoveryReply: ({})
    readonly property bool backendRecoveryActive: !!(backend && backend.blendRecoveryActive)
    onBackendRecoveryActiveChanged: if (backendRecoveryActive) recoveryHeld = true
    onLifecycleChanged: {
        if (lifecycle && lifecycle.recovery) {
            lastRecovery = lifecycle.recovery
            if (lastRecovery.active) recoveryHeld = true
        }
    }
    readonly property bool recoveryLocked: recoveryHeld || backendRecoveryActive
    property int recoveryGeneration: 0
    property string recoveryResultText: ""
    property bool recoveryResultError: false
    property Timer recoveryDeadline: Timer {
        interval: root.timeoutMs
        onTriggered: root.recoveryUnknown(qsTr("Recovery request timed out; outcome unknown. Refresh to reconcile before another action."))
    }
    function recoveryUnknown(message) {
        recoveryGeneration++; recoveryDeadline.stop(); recoveryBusy = false
        recoveryPausedConfirmed = false
        recoveryHeld = true; recoveryNeedsRead = true
        recoveryResultError = true; recoveryResultText = message
    }
    function startRecovery() { requestRecovery("start") }
    function pauseRecovery() { requestRecovery("pause") }
    function resumeRecovery() { requestRecovery("resume") }
    function dismissRecovery() { requestRecovery("dismiss") }
    function requestRecovery(action) {
        var r = lifecycle.recovery || ({})
        if (!ready || !backend || !bridge || recoveryBusy || repairing || externalBusy) return
        // Pause/dismiss only restrict or clear; a telemetry failure must not stop the
        // operator from halting future submissions or clearing a terminally-stopped job.
        if (action !== "pause" && action !== "dismiss" && recoveryNeedsRead) return
        if (action === "start" ? (recoveryLocked || !r.canStart)
            : action === "pause" ? !r.canPause
            : action === "dismiss" ? !r.canDismiss
            : !r.canResume) return
        recoveryBusy = true; recoveryHeld = true; recoveryNeedsRead = true
        recoveryPausedConfirmed = false
        recoveryResultText = qsTr("Sending recovery request…"); recoveryResultError = false
        var token = ++recoveryGeneration
        recoveryDeadline.restart()
        function failed(error) {
            if (token !== root.recoveryGeneration) return
            root.recoveryUnknown(qsTr("Recovery request outcome unknown: %1. Refresh before another action.").arg(String(error || qsTr("Connection failed"))))
        }
        try {
            var call = action === "start" ? backend.startBlendRecovery()
                : action === "pause" ? backend.pauseBlendRecovery()
                : action === "dismiss" ? backend.dismissBlendRecovery()
                : backend.resumeBlendRecovery()
            bridge.watch(call, function(reply) {
                if (token !== root.recoveryGeneration) return
                if (!reply || typeof reply.ok !== "boolean") { failed(qsTr("Invalid response")); return }
                root.recoveryGeneration++; root.recoveryDeadline.stop(); root.recoveryBusy = false
                root.recoveryReply = reply
                root.recoveryPausedConfirmed = reply.ok && action === "pause"
                root.recoveryResultError = !reply.ok
                root.recoveryResultText = (reply.error ? String(reply.error) + ": " : "") + String(reply.message || reply.error || (reply.ok ? qsTr("Recovery request acknowledged. Refresh for verified progress.") : qsTr("Recovery request rejected.")))
            }, failed)
        } catch (e) { failed(e) }
    }
    property int timeoutMs: 20000
    property int generation: 0
    property var lifecycle: ({ok:false, state:"unavailable", title:qsTr("Status unavailable"), detail:qsTr("Waiting for lifecycle evidence."), tone:"warning", action:"refresh", steps:[]})
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
        return {ok:false, state:"unavailable", title:qsTr("Status unavailable"), detail:detail, tone:"warning", action:"refresh", actionLabel:qsTr("Refresh"), steps:[], evidence:qsTr("Current evidence unavailable; no activity or earnings inferred."), recovery:lastRecovery || ({})}
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
            root.recoveryNeedsRead = true
            root.lifecycle = root.unavailable(qsTr("Lifecycle request timed out. Refresh to try again."))
        }
    }
    onReadyChanged: if (!ready) connectionLost()
    onBackendChanged: connectionLost()
    onBridgeChanged: connectionLost()
    function connectionLost() {
        recoveryPausedConfirmed = false
        if (Object.keys(lastRecovery).length) recoveryNeedsRead = true
        if (recoveryBusy) recoveryUnknown(qsTr("Connection changed during recovery request; outcome unknown. Refresh to reconcile."))
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
        if (repairing || externalBusy) {
            finishRefreshFeedback(qsTr("Another Blend operation is in progress."), false)
            return
        }
        if (loading) return
        var previous = JSON.stringify(lifecycle)
        var recoveryToken = recoveryGeneration
        loading = true
        var token = ++generation
        deadline.restart()
        function failed(error) {
            if (token !== root.generation) return
            error = String(error || qsTr("Request failed."))
            root.deadline.stop(); root.loading = false
            root.generation++
            root.recoveryNeedsRead = true
            root.lifecycle = root.unavailable(String(error))
            root.finishRefreshFeedback(error, false)
        }
        try {
            bridge.watch(backend.getBlendLifecycle(), function(r) {
                if (token !== root.generation) return
                if (!r || !r.state || typeof r.ok !== "boolean") {
                    failed(r && (r.error || r.detail) ? (r.error || r.detail) : qsTr("Invalid lifecycle response."))
                    return
                }
                root.deadline.stop(); root.loading = false
                root.generation++
                // A structured unavailable result still carries durable recovery evidence.
                var hasRecovery = r.recovery && typeof r.recovery.active === "boolean"
                if (!hasRecovery && Object.keys(root.lastRecovery).length) r.recovery = root.lastRecovery
                root.lifecycle = r
                // Durable pause does not require healthy chain telemetry. Never
                // use a cached fallback or a read predating a mutation reply.
                if (hasRecovery && !root.recoveryBusy && recoveryToken === root.recoveryGeneration)
                    root.recoveryPausedConfirmed = r.recovery.active === true && r.recovery.phase === "paused"
                if (r.ok && hasRecovery
                        && !root.recoveryBusy && recoveryToken === root.recoveryGeneration) {
                    root.recoveryHeld = r.recovery.active
                    root.recoveryNeedsRead = false
                }
                root.finishRefreshFeedback(r.ok ? "" : (r.message || r.detail || r.error || qsTr("Status unavailable.")), JSON.stringify(r) === previous)
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
            root.generation++; root.deadline.stop(); root.repairing = false
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
