import QtQuick
import QtTest

// Production Blend TAB (BlendView), fake QtRO calls only — no live backend.
// Uses tests/preview/imports for the enum-only backend module and the
// application's Logos design-system import path. Covers: the component loads
// (imports + qmldir resolve — the headless catch for QML-load errors the nix
// build can't see), the phase→step-indicator mapping, the openWallet shortcut,
// that it is not a dismissable modal, and the mutation/invalidation invariants
// carried over verbatim from the former modal (the flow logic is unchanged).
TestCase {
    id: test
    name: "BlendView"
    width: 1000; height: 1100; visible: true
    when: windowShown
    property var view
    property int calls: 0
    property var success
    property var failure
    property string throwsAt: ""
    property int walletOpens: 0

    // Fake backend: read calls return a non-"mutation" token the fake logos.watch
    // ignores; mutations return "mutation" so watch captures the callbacks.
    QtObject {
        id: backend
        property int blendStatus: 3            // Core → open() lands the manage ("core") phase
        property string leaderKey: ""          // empty → _refreshGates skips getNotes
        property string primaryAddress: ""
        function withdrawBlendCore() {
            test.calls++
            if (test.throwsAt === "backend") throw new Error("backend unavailable")
            return "mutation"
        }
        function declareBlendCore(locator, note) { test.calls++; return "mutation" }
        property int status: 2            // BlockchainStatus.Running (node up)
        property string lastErrorMessage: ""
        function getSdpFundingKey() { return "read" }
        function getBalance(k) { return "read" }
        function getNotes(k, tip) { return "read" }
        function checkBlendPortReachable() { return "read" }
        function getBlendDeclarations() { return "read" }
        function getBlendIdentity() { return "read" }
        function requestFaucetFunds(k) { return }
        function startBlockchain() { return }
    }
    QtObject {
        id: logos
        function watch(call, ok, error) {
            if (call !== "mutation") return
            test.success = ok; test.failure = error
            if (test.throwsAt === "watch") throw new Error("watch unavailable")
        }
    }

    function init() {
        calls = 0; success = null; failure = null; throwsAt = ""; walletOpens = 0
        var c = Qt.createComponent("../../src/qml/views/BlendView.qml")
        // Component.Ready proves BlendView + its imports (../controls/BlendCoreProgress,
        // Logos.*) and the views qmldir all resolve — the load error static checks miss.
        compare(c.status, Component.Ready, c.errorString())
        view = c.createObject(test, {backend: backend, backendReady: true, controller: null,
                                     width: 1000, height: 1100, phase: "core"})
        verify(view !== null)
        view.onOpenWallet.connect(function() { test.walletOpens++ })
    }
    function cleanup() { if (view) { view.destroy(); view = null } }

    function controlWithText(item, text) {
        if (item.text === text) return item
        var children = item.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = controlWithText(children[i], text)
            if (found) return found
        }
        return null
    }
    function hasTextContaining(item, needle) {
        if (item.text !== undefined && ("" + item.text).indexOf(needle) >= 0) return true
        var children = item.children || []
        for (var i = 0; i < children.length; ++i)
            if (hasTextContaining(children[i], needle)) return true
        return false
    }

    // ── tab-specific behaviour ──
    function test_loads_and_shows_strip() {
        // The component instantiated (init compared Component.Ready) and renders the
        // shipped strip label. The "Step N of 3" indicator was intentionally removed.
        waitForRendering(view)
        verify(hasTextContaining(view, "Blend Core"))
    }
    function test_not_a_dismissable_modal() {
        // close() must NOT hide the tab (it is a StackLayout child, not a popup).
        view.visible = true
        view.close()
        verify(view.visible)
    }
    function test_fund_keys_opens_wallet() {
        view.phase = "gates"; wait(0)
        var fund = controlWithText(view, "Fund keys")   // visible in gates while not all-green
        verify(fund !== null && fund.visible)
        mouseClick(fund)
        compare(walletOpens, 1)
    }

    // ── mutation / invalidation invariants (flow copied verbatim from the modal) ──
    function test_disable_marks_busy_and_invalidates_on_backend_loss() {
        view.phase = "core"; wait(0)
        view._disable()
        compare(calls, 1); verify(view.requestBusy)
        var late = success
        view.backend = null
        verify(!view.requestBusy)
        verify(view.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        late({ok: true}); compare(view.phase, "core")
    }
    function test_response_consumed_once() {
        view.phase = "core"; wait(0)
        view._disable()
        success({ok: false, error: "WithdrawalWhileLocked"})
        verify(!view.requestBusy)
        compare(view.errorText, "WithdrawalWhileLocked")
        success({ok: true}); failure("late transport error")
        compare(view.phase, "core")
        compare(view.errorText, "WithdrawalWhileLocked")
        wait(50); compare(calls, 1)
    }
    function test_async_failure_is_unknown() {
        view.phase = "core"; wait(0)
        view._disable(); failure("transport unavailable")
        verify(!view.requestBusy)
        verify(view.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        success({ok: true}); compare(view.phase, "core")
    }
    function test_synchronous_throw_never_strands_busy_data() {
        return [{tag: "backend", at: "backend"}, {tag: "watch", at: "watch"}]
    }
    function test_synchronous_throw_never_strands_busy(data) {
        view.phase = "core"; wait(0)
        throwsAt = data.at
        view._disable()
        compare(calls, 1)
        verify(!view.requestBusy)
        verify(view.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        compare(view.phase, "core")
    }
}
