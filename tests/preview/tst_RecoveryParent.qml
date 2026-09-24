import QtQuick
import QtTest
import Logos.BlockchainBackend
TestCase {
    id: test
    name: "RecoveryParent"
    width:1440; height:1100; visible:true
    when:windowShown
    property var view
    property bool active: false
    property var lifecycleCallback
    property var pauseCallback
    InertRecoveryBackend { id: backend }
    QtObject {
        id: logos
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        function module(name) { return backend }
        function model(name, key) { return null }
        function isViewModuleReady(name) { return true }
        function watch(call, ok, error) {
            if (call === "getBlendLifecycle") {
                test.lifecycleCallback=ok
                ok(test.state())
            } else if (call === "startBlendRecovery") {
                test.active=true; backend.blendRecoveryActive=true
                ok({ok:true,message:"Synthetic recovery accepted"})
            } else if (call === "pauseBlendRecovery") {
                test.pauseCallback=ok
            } else if (call === "getCryptarchiaInfo") {
                ok({success:true,value:JSON.stringify({mode:"Online",slot:1000,height:900})})
            }
        }
    }
    function state() { return {ok:true,state:"lapsed",title:"Core activity lapsed",tone:"warning",action:"repair",actionLabel:"Restore binding",steps:[],recovery:{active:active,phase:active?"waiting_removal":"idle",title:active?"Waiting for removal":"Recover Core",detail:"Synthetic recovery evidence",tone:"warning",steps:[],canStart:!active,canPause:active,canResume:false}} }
    function init() {
        active=false; backend.calls=[]; backend.blendRecoveryActive=false; backend.status=BlockchainBackend.Running
        var c=Qt.createComponent("../../src/qml/BlockchainView.qml")
        compare(c.status,Component.Ready,c.errorString())
        view=c.createObject(test,{width:1440,height:1100})
        verify(view!==null); waitForRendering(view); wait(100)
    }
    function cleanup() { view.destroy(); view=null }
    function withProperty(item, key) {
        if (item[key] !== undefined) return item
        var children=item.children || []
        for(var i=0;i<children.length;i++) { var found=withProperty(children[i],key); if(found) return found }
        return null
    }
    function withText(item, text) {
        if (item.text === text) return item
        var children=item.children || []
        for(var i=0;i<children.length;i++) { var found=withText(children[i],text); if(found) return found }
        return null
    }
    function test_actual_modal_readiness() {
        var modal=findChild(view,"manualBlendModal")
        verify(modal!==null)
        compare(modal.backendReady,true,"real owner must bind modal readiness")
        logos.viewModuleReadyChanged("logos_node_1click",false)
        compare(modal.backendReady,false)
        logos.viewModuleReadyChanged("logos_node_1click",true)
        compare(modal.backendReady,true)
    }
    function test_confirm_and_locks() {
        var start=findChild(view,"blendRecover")
        verify(start!==null && start.visible && start.enabled,"dashboard forwards recovery availability")
        compare(backend.calls.indexOf("startBlendRecovery"),-1)
        mouseClick(start)
        var confirm=findChild(view,"blendRecoveryConfirm")
        tryCompare(confirm,"visible",true)
        compare(backend.calls.indexOf("startBlendRecovery"),-1)
        mouseClick(confirm)
        compare(backend.calls.filter(function(c){return c==="startBlendRecovery"}).length,1)
        var stop=findChild(view,"nodeRunControl"), manage=findChild(view,"manualBlendControl")
        verify(stop!==null && !stop.enabled)
        verify(manage!==null && !manage.enabled)
        mouseClick(stop); mouseClick(manage)
        view._resetChainThenRestart(); view._regenerateKeysThenRestart(); view._wipeAndStart()
        compare(backend.calls.indexOf("stopBlockchain"),-1)
        compare(backend.calls.indexOf("resetChainState"),-1)
        compare(backend.calls.indexOf("regenerateNodeKeys"),-1)
        var refresh=findChild(view,"blendRecoveryRefresh")
        verify(refresh.enabled)
        mouseClick(refresh)
        compare(findChild(view,"blendRecoveryTitle").text,"Waiting for removal")
        logos.viewModuleReadyChanged("logos_node_1click",false)
        verify(!stop.enabled); verify(!manage.enabled)
        verify(findChild(view,"blendRecoveryProgress").visible)
    }
    function test_confirmed_pause_enables_stop_but_not_reset() {
        mouseClick(findChild(view,"blendRecover"))
        var confirm=findChild(view,"blendRecoveryConfirm")
        tryCompare(confirm,"visible",true); mouseClick(confirm)
        var control=findChild(view,"nodeRunControl")
        verify(!control.enabled)
        var pause=findChild(view,"blendRecoveryPause")
        mouseClick(findChild(view,"blendRecoveryRefresh"))
        verify(pause!==null && pause.visible && pause.enabled)
        wait(50)
        mouseClick(pause)
        verify(typeof pauseCallback === "function", "Pause reaches backend")
        verify(!control.enabled, "request is not a persisted pause")
        pauseCallback({ok:true,message:"Paused"})
        tryCompare(control,"enabled",true)
        verify(!findChild(view,"manualBlendControl").enabled)
        view._resetChainThenRestart(); view._regenerateKeysThenRestart()
        compare(backend.calls.indexOf("resetChainState"),-1)
        compare(backend.calls.indexOf("regenerateNodeKeys"),-1)
        mouseClick(control)
        compare(backend.calls.filter(function(c){return c==="stopBlockchain"}).length,1)
        backend.status=BlockchainBackend.Stopping
        verify(!control.enabled)
        backend.status=BlockchainBackend.Stopped
        compare(control.text,"Start"); verify(control.enabled)
    }
    function test_crashed_node_can_be_started_without_restarting_live_node_data() {
        return [{tag:"not-started",status:BlockchainBackend.NotStarted},
                {tag:"stopped",status:BlockchainBackend.Stopped}]
    }
    function test_crashed_node_can_be_started_without_restarting_live_node(row) {
        mouseClick(findChild(view,"blendRecover"))
        var confirm=findChild(view,"blendRecoveryConfirm")
        tryCompare(confirm,"visible",true); mouseClick(confirm)
        var control=findChild(view,"nodeRunControl")
        verify(!control.enabled)
        backend.status=row.status
        tryCompare(control,"text","Start")
        verify(control.enabled,"recovery must not lock the only way to start a crashed node")
        mouseClick(control)
        compare(backend.calls.filter(function(c){return c==="startBlockchain"}).length,1)
        compare(backend.calls.indexOf("stopBlockchain"),-1)
        compare(backend.calls.indexOf("resetChainState"),-1)
        backend.status=BlockchainBackend.Starting
        verify(!control.enabled,"an in-progress start must not be interrupted")
        backend.status=BlockchainBackend.Running
        verify(!control.enabled)
    }
}
