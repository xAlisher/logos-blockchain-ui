import QtQuick
import QtTest

// Production modal, fake QtRO calls only. Use tests/preview/imports for the
// enum-only backend module and the application's Logos design-system imports.
TestCase {
    id: test
    name: "BlendModal"
    width: 1000; height: 1100; visible: true
    when: windowShown
    property var modal
    property int calls: 0
    property var success
    property var failure
    property string throwsAt: ""
    QtObject {
        id: backend
        property int blendStatus: 0
        property string leaderKey: ""
        property string primaryAddress: ""
        function withdrawBlendCore() {
            test.calls++
            if (test.throwsAt === "backend") throw new Error("backend unavailable")
            return "mutation"
        }
        function getSdpFundingKey() { return "read" }
        function checkBlendPortReachable() { return "read" }
        function getBlendDeclarations() { return "read" }
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
        calls = 0; success = null; failure = null; throwsAt = ""
        var c = Qt.createComponent("../../src/qml/views/EnableBlendCoreModal.qml")
        compare(c.status, Component.Ready, c.errorString())
        modal = c.createObject(test, {backend: backend, backendReady:true, width:1000, height:1100, phase:"core"})
        verify(modal !== null)
    }
    function cleanup() { if (modal) { modal.destroy(); modal = null } }
    function controlWithText(item, text) {
        if (item.text === text) return item
        var children = item.children || []
        for (var i = 0; i < children.length; ++i) {
            var found = controlWithText(children[i], text)
            if (found) return found
        }
        return null
    }
    function test_controls_disabled_during_mutation() {
        modal.visible = true
        waitForRendering(modal)
        var disable = controlWithText(modal, "Disable Blend Core")
        verify(disable !== null && disable.visible && disable.enabled)
        mouseClick(disable)
        compare(calls, 1); verify(modal.requestBusy)
        verify(!disable.enabled)
        // The stale-declaration path remains in gates with other mutations visible.
        failure("transport lost")
        modal.phase = "gates"; modal.mineId = "fixture-stale-declaration"
        wait(0)
        var stale = controlWithText(modal, "Withdraw stale declaration")
        var faucet = controlWithText(modal, "Request test funds")
        verify(stale !== null && stale.visible && stale.enabled)
        verify(faucet !== null && faucet.visible && faucet.enabled)
        modal._withdrawStale()
        verify(!stale.enabled); verify(!faucet.enabled)
        modal._gateAction("faucet"); modal._withdrawStale()
        compare(calls, 2)
        success({ok:false, error:"fixture rejection"})
        verify(stale.enabled); verify(faucet.enabled)
    }
    function test_backend_replacement_invalidates() {
        modal._disable()
        var late = success
        modal.backend = null
        verify(!modal.requestBusy)
        verify(modal.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        late({ok:true}); compare(modal.phase, "core")
    }
    function test_response_consumed_once() {
        modal._disable()
        success({ok:false, error:"WithdrawalWhileLocked"})
        verify(!modal.requestBusy)
        compare(modal.errorText, "WithdrawalWhileLocked")
        success({ok:true}); failure("late transport error")
        compare(modal.phase, "core")
        compare(modal.errorText, "WithdrawalWhileLocked")
        wait(50); compare(calls, 1)
    }
    function test_async_failure_is_unknown() {
        modal._disable(); failure("transport unavailable")
        verify(!modal.requestBusy)
        verify(modal.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        success({ok:true}); compare(modal.phase, "core")
    }
    function test_disconnect_invalidates_late_callbacks() {
        modal._disable()
        var oldSuccess = success, oldFailure = failure
        modal.backendReady = false
        verify(!modal.requestBusy)
        verify(modal.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        var message = modal.errorText
        oldSuccess({ok:true}); oldFailure("late failure")
        compare(modal.errorText, message)
        compare(modal.phase, "core")
        modal._disable(); compare(calls, 1)
        modal.backendReady = true
        compare(calls, 1) // reconnect must never retry
        modal._disable(); compare(calls, 2)
        oldSuccess({ok:true}); oldFailure("older request")
        verify(modal.requestBusy)
        success({ok:true})
        verify(!modal.requestBusy)
        compare(modal.phase, "disabled")
    }
    function startMutation(kind) {
        if (kind === "stale") {
            modal.phase = "gates"; modal.mineId = "fixture-stale-declaration"
            modal._withdrawStale()
        } else {
            modal._disable()
        }
    }
    function test_synchronous_throw_data() {
        return [{tag:"backend-disable", at:"backend", kind:"disable"},
                {tag:"watch-disable", at:"watch", kind:"disable"},
                {tag:"backend-stale", at:"backend", kind:"stale"},
                {tag:"watch-stale", at:"watch", kind:"stale"}]
    }
    function test_synchronous_throw(data) {
        throwsAt = data.at
        // No exception may escape a user action and strand requestBusy.
        startMutation(data.kind)
        compare(calls, 1)
        verify(!modal.requestBusy)
        verify(modal.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        compare(modal.phase, data.kind === "stale" ? "gates" : "core")
        if (success) {
            var message = modal.errorText
            success({ok:true})
            compare(modal.errorText, message)
            compare(modal.phase, data.kind === "stale" ? "gates" : "core")
        }
    }
    function test_timeout_unknown_no_retry_data() {
        return [{tag:"disable", kind:"disable"}, {tag:"stale", kind:"stale"}]
    }
    function test_timeout_unknown_no_retry(data) {
        var started = Date.now()
        startMutation(data.kind); startMutation(data.kind)
        compare(calls, 1)
        verify(modal.requestBusy)
        var late = success
        // Check the actual production deadline, not an accelerated imitation.
        tryCompare(modal, "requestBusy", false, 21000)
        verify(Date.now() - started >= 19500, "Production deadline must be 20 seconds")
        verify(modal.errorText.toLowerCase().indexOf("outcome unknown") >= 0)
        var message = modal.errorText
        late({ok:true})
        compare(modal.errorText, message)
        verify(modal.phase !== "disabled")
        wait(50); compare(calls, 1)
    }
}
