import QtQuick
import QtTest
TestCase {
    id: test
    name: "BlendLifecycleController"
    property var controller
    property int reads: 0
    property int repairs: 0
    property var success
    property var failure
    QtObject {
        id: backend
        function getBlendLifecycle() { test.reads++; return "read" }
        function repairBlendBinding() { test.repairs++; return "repair" }
    }
    QtObject {
        id: bridge
        function watch(call, ok, error) { test.success = ok; test.failure = error }
    }
    function init() {
        reads = 0; repairs = 0
        var c = Qt.createComponent("../../src/qml/controls/BlendLifecycleController.qml")
        compare(c.status, Component.Ready, c.errorString())
        controller = c.createObject(test, {backend: backend, bridge: bridge, ready: true, timeoutMs: 50})
    }
    function cleanup() { if (controller) { controller.destroy(); controller = null } }
    function test_poll_guard_timeout() {
        controller.refresh(); controller.refresh()
        compare(reads, 1); compare(repairs, 0)
        var stale = success
        tryCompare(controller, "loading", false)
        verify(controller.lifecycle.ok === false)
        stale({ok:true, title:"stale"})
        verify(controller.lifecycle.title !== "stale")
    }
    function test_repair_explicit() {
        compare(repairs, 0)
        controller.lifecycle = {action:"repair"}
        controller.repair(); controller.repair()
        compare(repairs, 1); verify(controller.busy)
        success({ok:true, message:"Binding acknowledged"})
        verify(!controller.busy); verify(!controller.resultError)
        verify(controller.resultText.indexOf("activity") >= 0)
    }
    function test_repair_error_persists() {
        controller.lifecycle = {action:"repair"}
        controller.repair(); failure("transport failed")
        verify(controller.resultError)
        controller.refresh(); success({ok:true, action:"none"})
        verify(controller.resultError)
    }
    function test_manual_refresh_unchanged_feedback() {
        var state = {ok:true, state:"at-risk", action:"refresh"}
        controller.lifecycle = state
        controller.refresh(true)
        compare(controller.resultText, "Refreshing…")
        success(state)
        compare(controller.resultText, "Checked — no change.")
        verify(!controller.resultError)
    }
    function test_manual_refresh_changed_feedback() {
        controller.refresh(true)
        success({ok:true, state:"collecting", action:"refresh"})
        compare(controller.resultText, "Status updated.")
    }
    function test_manual_refresh_failure_feedback() {
        controller.refresh(true); failure("transport failed")
        verify(controller.resultError)
        verify(controller.resultText.indexOf("transport failed") >= 0)
    }
    function test_manual_refresh_empty_error_feedback() {
        controller.refresh(true); failure("")
        verify(controller.resultError)
        verify(controller.resultText.indexOf("failed") >= 0)
    }
    function test_manual_refresh_invalid_feedback() {
        controller.refresh(true); success(null)
        verify(controller.resultError)
        verify(controller.resultText.indexOf("Invalid") >= 0)
    }
    function test_manual_refresh_timeout_feedback() {
        controller.refresh(true)
        tryCompare(controller, "loading", false)
        verify(controller.resultError)
        verify(controller.resultText.indexOf("timed out") >= 0)
    }
    function test_manual_refresh_disconnect_feedback() {
        controller.refresh(true); var stale = success
        controller.ready = false
        verify(controller.resultError)
        verify(controller.resultText.indexOf("connection") >= 0)
        stale({ok:true, state:"collecting"})
        verify(controller.resultError)
    }
    function test_manual_refresh_joins_existing_poll() {
        controller.refresh(); controller.refresh(true)
        compare(reads, 1)
        compare(controller.resultText, "Refreshing…")
        success({ok:true, state:"collecting"})
        compare(controller.resultText, "Status updated.")
    }
}
