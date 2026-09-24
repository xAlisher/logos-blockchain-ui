import QtQuick
import QtTest
TestCase {
    id: test
    name: "BlendRecoveryProgress"
    width:1000; height:1100; visible:true
    when:windowShown
    property var panel
    function recovery(active) {
        return {active:active,phase:active?"waiting_removal":"idle",title:"Waiting for chain removal",detail:"Withdrawal submitted; waiting for verified chain removal. Core is not guaranteed to persist.",tone:"warning",canStart:!active,canPause:active,canResume:false,
            steps:["Withdraw once","Chain removal","Fresh declaration","Binding","Core activation","Accepted renewals"].map(function(label,i){return {label:label,state:i===0?"complete":i===1?"current":"pending"}})}
    }
    function state(active) { return {ok:true,state:"lapsed",title:"Core activity lapsed",tone:"warning",action:"repair",actionLabel:"Restore binding",steps:[],recovery:recovery(active)} }
    function init() {
        var c = Qt.createComponent("../../src/qml/controls/BlendCoreProgress.qml")
        compare(c.status,Component.Ready,c.errorString())
        panel = c.createObject(test,{width:920,lifecycle:state(false)})
        verify(panel !== null); waitForRendering(panel)
        spy.target=panel; spy.signalName="recoverRequested"; spy.clear()
    }
    function cleanup() { panel.destroy(); panel=null }
    SignalSpy { id:spy }
    function test_confirmation_geometry_data() { return [{tag:"narrow",width:320},{tag:"wide",width:920}] }
    function test_confirmation_geometry(row) {
        test.width=row.width; panel.width=row.width; panel.backendReady=true
        mouseClick(findChild(panel,"blendRecover"))
        var dialog=findChild(panel,"blendRecoveryConfirmation")
        tryCompare(dialog,"opened",true); wait(30)
        verify(dialog.width<=test.width)
        var text=findChild(panel,"blendRecoveryDisclosure")
        verify(text.width>0 && text.width<=dialog.width)
        verify(dialog.height<=test.height)
        var image=grabImage(test); verify(image.width>0 && image.height>0)
        image.save("/extra/tmp/blend-recovery-confirm-synthetic-"+row.tag+".png")
        dialog.close(); test.width=1000
    }
    function test_confirm_only() {
        var start=findChild(panel,"blendRecover")
        verify(start !== null,"Recover Core CTA missing")
        panel.backendReady=true
        wait(30); compare(spy.count,0)
        mouseClick(start); compare(spy.count,0)
        var dialog=findChild(panel,"blendRecoveryConfirmation")
        tryCompare(dialog,"opened",true)
        var disclosure=findChild(panel,"blendRecoveryDisclosure")
        verify(disclosure.text.indexOf("fees")>=0)
        verify(disclosure.text.indexOf("Edge")>=0)
        verify(disclosure.text.indexOf("identity")>=0)
        mouseClick(findChild(panel,"blendRecoveryConfirm"))
        compare(spy.count,1)
        mouseClick(start); tryCompare(dialog,"opened",true)
        panel.backendReady=false
        verify(!findChild(panel,"blendRecoveryConfirm").enabled)
        mouseClick(findChild(panel,"blendRecoveryConfirm")); compare(spy.count,1)
    }
    function test_active_visible_and_dynamic_data() { return [{tag:"narrow",width:320},{tag:"wide",width:920}] }
    function test_active_visible_and_dynamic(row) {
        verify(findChild(panel,"blendRecoveryProgress") !== null,"Recovery progress missing")
        panel.width=row.width; panel.backendReady=true; panel.lifecycle=state(true)
        panel.userToggled=true; panel.expanded=false; wait(30)
        verify(!findChild(panel,"blendExplanation").visible)
        compare(findChild(panel,"blendRecoveryDetail").wrapMode,Text.Wrap)
        ;["blendRecoveryProgress","blendRecoveryTitle","blendRecoveryDetail","blendRecoveryStep5"].forEach(function(name){
            var item=findChild(panel,name); verify(item.visible,name+" visible collapsed")
            var pos=item.mapToItem(panel,0,0)
            verify(pos.x>=0 && pos.x+item.width<=panel.width+1,name+" horizontal")
            verify(pos.y>=0 && pos.y+item.height<=panel.height+1,name+" vertical")
        })
        compare(findChild(panel,"blendRecoveryStep1").modelData.state,"current")
        var r=state(true); r.recovery.phase="monitoring"; r.recovery.title="Monitoring accepted renewals"
        r.recovery.detail="Synthetic fixture: watching for chain-accepted renewals. Future Core membership is not guaranteed."
        r.recovery.steps[1].state="complete"; r.recovery.steps[5].state="current"
        panel.lifecycle=r; wait(30)
        compare(findChild(panel,"blendRecoveryTitle").text,"Monitoring accepted renewals")
        compare(findChild(panel,"blendRecoveryStep5").modelData.state,"current")
        var image=grabImage(panel); verify(image.width>0 && image.height>0)
        image.save("/extra/tmp/blend-recovery-synthetic-"+row.tag+".png")
    }
    function test_lock_blocks_manual_but_not_refresh() {
        verify(findChild(panel,"blendRecoveryProgress") !== null)
        panel.backendReady=true; panel.lifecycle=state(true); panel.expanded=true
        spy.signalName="repairRequested"; spy.clear(); wait(30)
        var manual=findChild(panel,"blendAction"); verify(!manual.enabled)
        mouseClick(manual); compare(spy.count,0)
        spy.signalName="refreshRequested"; spy.clear()
        var refresh=findChild(panel,"blendRecoveryRefresh"); verify(refresh.enabled)
        mouseClick(refresh); compare(spy.count,1)
        spy.signalName="pauseRecoveryRequested"; spy.clear()
        mouseClick(findChild(panel,"blendRecoveryPause")); compare(spy.count,1)
        panel.recoveryBusy=true; mouseClick(findChild(panel,"blendRecoveryPause")); compare(spy.count,1)
    }
    function test_pause_available_without_chain_telemetry() {
        panel.backendReady=true; panel.lifecycle=state(true)
        panel.recoveryNeedsRead=true
        wait(30)
        spy.signalName="pauseRecoveryRequested"; spy.clear()
        var pause=findChild(panel,"blendRecoveryPause")
        verify(pause.enabled)
        mouseClick(pause); compare(spy.count,1)
    }
}
