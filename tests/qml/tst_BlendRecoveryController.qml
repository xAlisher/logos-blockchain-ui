import QtQuick
import QtTest
TestCase {
    id: test
    name: "BlendRecoveryController"
    property var controller
    property var calls: []
    property var callbacks: ({})
    property bool throwCall: false
    property bool throwWatch: false
    QtObject {
        id: backend
        property bool blendRecoveryActive: false
        function getBlendLifecycle() { test.calls.push("read"); return "read" }
        function startBlendRecovery() { test.calls.push("start"); if (test.throwCall) throw new Error("invoke failure"); return "start" }
        function pauseBlendRecovery() { test.calls.push("pause"); return "pause" }
        function resumeBlendRecovery() { test.calls.push("resume"); return "resume" }
        function repairBlendBinding() { test.calls.push("repair"); return "repair" }
    }
    QtObject {
        id: bridge
        function watch(call, ok, fail) { if (test.throwWatch) throw new Error("watch failure"); test.callbacks[call] = {ok:ok, fail:fail} }
    }
    function state(active) {
        return {ok:true, state:"lapsed", action:"repair", recovery:{active:active,phase:active?"waiting_removal":"idle",title:"Recovery",detail:"Waiting for chain removal",steps:[],canStart:!active,canPause:active,canResume:false}}
    }
    function init() {
        calls = []; callbacks = {}; throwCall = false; throwWatch = false; backend.blendRecoveryActive = false
        var c = Qt.createComponent("../../src/qml/controls/BlendLifecycleController.qml")
        compare(c.status, Component.Ready, c.errorString())
        controller = c.createObject(test, {backend:backend,bridge:bridge,ready:true,timeoutMs:60})
        controller.lifecycle = state(false)
    }
    function cleanup() { controller.destroy(); controller = null }
    function test_replica_active_retained_without_snapshot() {
        backend.blendRecoveryActive = true
        verify(controller.recoveryLocked)
        controller.backend = null
        verify(controller.recoveryLocked, "replica active must survive loss before next poll")
    }
    function test_read_failure_still_allows_restrictive_pause() {
        controller.lifecycle = state(true)
        controller.refresh(); callbacks.read.fail("offline")
        controller.pauseRecovery()
        compare(calls.join(","),"read,pause")
        callbacks.pause.ok({ok:true,message:"Paused"})
        verify(controller.recoveryLocked)
        verify(controller.recoveryNeedsRead)
        controller.startRecovery(); controller.resumeRecovery()
        compare(calls.join(","),"read,pause")
    }
    function test_pause_unlocks_stop_only_after_ack_and_resume_relocks() {
        controller.lifecycle = state(true)
        controller.refresh(); var staleRead = callbacks.read.ok
        controller.pauseRecovery()
        compare(controller.recoveryCanStop, false)
        callbacks.pause.ok({ok:true,message:"Paused"})
        compare(controller.recoveryCanStop, true)
        verify(controller.recoveryLocked, "other mutations remain locked")
        staleRead(state(true))
        compare(controller.recoveryCanStop, true, "pre-pause read cannot undo pause acknowledgement")
        var paused = state(true); paused.recovery.phase = "paused"; paused.recovery.canResume = true
        controller.refresh(); callbacks.read.ok(paused)
        controller.resumeRecovery()
        compare(controller.recoveryCanStop, false, "lock before resume response")
        callbacks.resume.fail("reply lost")
        compare(controller.recoveryCanStop, false)
        controller.refresh(); callbacks.read.ok(paused)
        compare(controller.recoveryCanStop, true, "fresh paused evidence reconciles unknown resume")
        controller.ready = false
        compare(controller.recoveryCanStop, false)
    }
    function test_failed_pause_does_not_unlock_stop() {
        controller.lifecycle = state(true)
        controller.pauseRecovery(); callbacks.pause.ok({ok:false,error:"write failed"})
        compare(controller.recoveryCanStop, false)
    }
    function test_paused_read_without_chain_telemetry_not_cached_fallback() {
        var paused = state(true); paused.ok = false; paused.recovery.phase = "paused"
        controller.lifecycle = paused
        controller.refresh(); callbacks.read.ok({ok:false,state:"unavailable"})
        compare(controller.recoveryCanStop, false, "cached pause cannot grant stop")
        controller.refresh(); callbacks.read.ok(paused)
        compare(controller.recoveryCanStop, true, "fresh pause survives chain telemetry failure")
        controller.refresh(); callbacks.read.fail("telemetry failed")
        compare(controller.recoveryCanStop, true, "a read failure cannot undo a confirmed pause")
    }
    function test_structured_request_error_preserved() {
        controller.startRecovery()
        callbacks.start.ok({ok:false,error:"fee_unavailable",message:"Insufficient balance"})
        compare(controller.recoveryReply.error,"fee_unavailable")
        verify(controller.recoveryResultText.indexOf("Insufficient balance") >= 0)
        verify(controller.recoveryResultText.indexOf("fee_unavailable") >= 0)
        verify(controller.recoveryLocked)
        controller.refresh(); callbacks.read.ok(state(false))
        verify(!controller.recoveryLocked)
    }
    function test_exceptions_data() { return [{tag:"invoke",invoke:true},{tag:"watch",invoke:false}] }
    function test_exceptions(row) {
        throwCall = row.invoke; throwWatch = !row.invoke
        controller.startRecovery()
        verify(!controller.recoveryBusy); verify(controller.recoveryLocked)
        verify(controller.recoveryResultError)
        verify(controller.recoveryResultText.indexOf("outcome unknown") >= 0)
    }
    function test_requests_data() { return [{tag:"start"},{tag:"pause"},{tag:"resume"}] }
    function test_requests(row) {
        var r = state(row.tag !== "start"); r.recovery.canResume = row.tag === "resume"
        controller.lifecycle = r
        controller.ready = false
        controller[row.tag + "Recovery"](); compare(calls.length,0)
        controller.ready = true
        controller.refresh(); callbacks.read.ok(r); calls = []
        controller[row.tag + "Recovery"](); controller[row.tag + "Recovery"]()
        compare(calls.join(","),row.tag)
        var old = callbacks[row.tag].ok
        old({ok:true,message:"first"}); old({ok:false,error:"stale"})
        compare(controller.recoveryResultText,"first")
        controller[row.tag + "Recovery"]()
        // Pause is restrictive and idempotent, including after a lost reply.
        compare(calls.join(","),row.tag === "pause" ? "pause,pause" : row.tag)
    }
    function test_missing_recovery_never_unlocks_unknown_start() {
        controller.startRecovery(); callbacks.start.fail("lost")
        controller.refresh(); callbacks.read.ok({ok:true,state:"lapsed",action:"repair"})
        verify(controller.recoveryLocked,"missing recovery is not proof of inactivity")
        verify(controller.recoveryNeedsRead)
    }
    function test_production_deadline() {
        controller.timeoutMs = 20000
        var started = Date.now()
        controller.startRecovery()
        tryCompare(controller,"recoveryBusy",false,22000)
        verify(Date.now() - started >= 19500)
        verify(controller.recoveryLocked); verify(controller.recoveryResultError)
    }
    function test_disconnect_retains_progress_and_invalidates_callback() {
        controller.lifecycle = state(true)
        controller.pauseRecovery(); var stale = callbacks.pause.ok
        controller.ready = false
        verify(controller.recoveryLocked)
        compare(controller.lifecycle.recovery.phase,"waiting_removal")
        verify(!controller.recoveryBusy)
        verify(controller.recoveryResultError)
        stale({ok:true,message:"stale"})
        verify(controller.recoveryResultText !== "stale")
    }
    function test_structured_unavailable_keeps_recovery() {
        controller.lifecycle = state(true)
        controller.refresh()
        var r = state(true); r.ok = false; r.state = "unavailable"; r.error = "rpc_down"
        r.detail = "RPC unavailable"; r.recovery.phase = "uncertain"; r.recovery.detail = "Paid transaction outcome unknown"
        callbacks.read.ok(r)
        compare(controller.lifecycle.error,"rpc_down")
        compare(controller.lifecycle.recovery.phase,"uncertain")
        verify(controller.recoveryLocked)
        controller.refresh(); callbacks.read.fail("offline")
        compare(controller.lifecycle.recovery.phase,"uncertain")
        verify(controller.recoveryLocked)
    }
    function test_backend_replacement_invalidates_both_requests() {
        controller.startRecovery(); var stale = callbacks.start.ok
        controller.refresh(); var staleRead = callbacks.read.ok
        controller.backend = null
        verify(!controller.recoveryBusy); verify(!controller.loading)
        verify(controller.recoveryLocked)
        stale({ok:true,message:"stale"}); staleRead(state(false))
        verify(controller.recoveryResultText !== "stale")
        verify(controller.recoveryLocked)
    }
    function test_timeout_requires_read_before_resume() {
        var r = state(true); r.recovery.canPause = false; r.recovery.canResume = true
        controller.lifecycle = r
        controller.resumeRecovery(); var stale = callbacks.resume.ok
        tryCompare(controller,"recoveryBusy",false)
        verify(controller.recoveryLocked); verify(controller.recoveryResultError)
        controller.resumeRecovery(); compare(calls.join(","),"resume")
        controller.refresh(); callbacks.read.ok(r)
        controller.resumeRecovery(); compare(calls.join(","),"resume,read,resume")
        stale({ok:true,message:"old"}); verify(controller.recoveryBusy)
        callbacks.resume.ok({ok:true,message:"new"}); verify(!controller.recoveryBusy)
        stale({ok:true,message:"old"}); compare(controller.recoveryResultText,"new")
    }
    function test_explicit_start_independent_poll() {
        wait(80); compare(calls.length,0)
        verify(typeof controller.startRecovery === "function", "explicit recovery command missing")
        controller.startRecovery(); controller.startRecovery()
        compare(calls.join(","),"start")
        verify(controller.recoveryBusy); verify(controller.recoveryLocked)
        controller.refresh()
        compare(calls.join(","),"start,read")
        callbacks.read.ok(state(true))
        callbacks.start.ok({ok:true,message:"Recovery started"})
        verify(!controller.recoveryBusy); verify(controller.recoveryLocked)
        controller.repair(); compare(calls.indexOf("repair"),-1)
        controller.refresh(); compare(calls[calls.length-1],"read")
    }
}
