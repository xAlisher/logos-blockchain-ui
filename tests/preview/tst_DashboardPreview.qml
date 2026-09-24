import QtQuick
import QtTest
TestCase {
    id: test
    name: "DashboardPreview"
    width: 1440; height: 1000; visible: true
    when: windowShown
    function test_dashboard() {
        var component = Qt.createComponent("../../src/qml/views/NodeDashboardView.qml")
        compare(component.status, Component.Ready, component.errorString())
        var panel = component.createObject(test, {
            width:1440, height:1000, status:2, nodeRunning:true, nodeConnected:true,
            infoJson:JSON.stringify({mode:"Online",slot:1404200,height:95000}),
            timeInfoJson:JSON.stringify({current_slot:1404200,slot_duration_ms:1000}),
            funded:true, eligibleNoteCount:1,
            blendLifecycle:{ok:true,state:"binding-missing",title:"Local SDP binding missing",tone:"error",action:"repair",actionLabel:"Restore activity binding",
                detail:"Core connectivity is present, but SDP cannot submit activity without its declaration binding. Restore the existing binding; no withdrawal or redeclaration is needed for this step.",
                evidence:"Fixture preview · epoch 39 · Core · 5 peers · no accepted activity. Binding acknowledgement is not activity inclusion.",
                steps:["Online","Declared","Activated","Connected","Activity","Maintaining"].map(function(label,i){return {label:label,state:i<4?"complete":i===4?"error":"pending"}})}
        })
        verify(panel !== null)
        waitForRendering(panel); wait(200)
        var block = findChild(panel, "blendTitle")
        verify(block !== null)
        verify(block.mapToItem(panel,0,0).y > 100, "Blend block is below node progress")
        var button = findChild(panel, "blendAction")
        verify(button.visible && button.enabled)
        var image = grabImage(panel)
        verify(image.width === 1440 && image.height === 1000)
        image.save("/extra/tmp/blend-core-dashboard-preview.png")
        panel.destroy()
    }
}
