import QtQuick
import QtTest

TestCase {
    id: test
    name: "BlendCoreProgress"
    width: 1000; height: 900; visible: true
    when: windowShown
    property var panel
    function fixture(tone, action) {
        return {ok: true, state: "collecting", title: "Core collecting", detail: "Connectivity is not accepted activity.", tone: tone,
            epoch: 42, declarationId: "public-declaration", created: 39, active: 41, nonce: "0", withdrawAt: -1,
            mode: "Core", healthyPeers: 3, bindingStatus: "unknown", action: action, actionLabel: "Check again",
            steps: ["Online", "Declared", "Activated", "Connected", "Activity", "Maintaining"].map(function(label, i) { return {label: label, state: i < 3 ? "complete" : i === 3 ? "current" : "pending"} }), evidence: "Activity unknown; no attributed receipts."}
    }
    function init() {
        var component = Qt.createComponent("../../src/qml/controls/BlendCoreProgress.qml")
        compare(component.status, Component.Ready, component.errorString())
        panel = component.createObject(test, {width: 920, lifecycle: fixture("neutral", "refresh")})
        verify(panel !== null)
        waitForRendering(panel)
        wait(20)
    }
    function cleanup() { if (panel) { panel.destroy(); panel = null } }
    SignalSpy { id: actionSpy }
    function test_actions_data() { return [{tag:"manage"}, {tag:"repair"}, {tag:"refresh"}] }
    function test_actions(row) {
        panel.lifecycle = fixture("warning", row.tag)
        compare(panel.expanded, true)
        actionSpy.target = panel; actionSpy.signalName = row.tag + "Requested"; actionSpy.clear()
        wait(20)
        var button = findChild(panel, "blendAction")
        mouseClick(button); compare(actionSpy.count, 1)
        panel.busy = true
        verify(!button.enabled)
        mouseClick(button); compare(actionSpy.count, 1)
        mouseClick(findChild(panel, "blendTitle")); compare(panel.expanded, false)
        panel.lifecycle = fixture("error", row.tag)
        compare(panel.expanded, false) // user choice survives polls
    }
    function test_error_stays_visible() {
        panel.expanded = true    // the result now lives in the expanded detail area
        panel.resultText = "Binding request failed"; panel.resultError = true
        verify(findChild(panel, "blendResult").visible)
        panel.lifecycle = fixture("success", "none")
        verify(findChild(panel, "blendResult").visible)
    }
    function test_matrix_data() {
        var rows = []
        var states = ["unavailable", "offline", "bootstrap", "no_declaration", "submission_pending", "activation_pending", "collecting", "binding_missing", "binding_confirmed", "healthy", "at_risk", "lapsed", "withdrawal_requested", "withdrawal_scheduled", "removed", "ambiguous_identity", "api_error"]
        states.forEach(function(state, i) {
            ;[320, 920].forEach(function(width) { rows.push({tag: state + "_" + width, state: state, width: width, tone: i % 3 === 0 ? "warning" : i % 3 === 1 ? "error" : "neutral"}) })
        })
        return rows
    }
    function test_matrix(row) {
        var f = fixture(row.tone, "none")
        f.state = row.state; f.title = row.state.replace(/_/g, " ")
        f.evidence = "Unknown evidence " + "0123456789abcdef".repeat(16)
        panel.width = row.width; panel.lifecycle = f; panel.expanded = true
        wait(30)
        verify(panel.height > 0 && panel.height < 900)
        verify(!findChild(panel, "blendAction").visible)
        ;["blendStrip", "blendTitle", "blendEvidence"].forEach(function(name) {
            var item = findChild(panel, name), pos = item.mapToItem(panel, 0, 0)
            verify(pos.x >= 0 && pos.x + item.width <= panel.width + 1, name + " horizontal bounds")
            verify(pos.y >= 0 && pos.y + item.height <= panel.height + 1, name + " vertical bounds")
        })
        compare(findChild(panel, "blendStep4").modelData.state, "pending")
        var image = grabImage(panel)
        verify(image.width > 0 && image.height > 0)
    }
    function test_unavailable_keeps_strip() {
        panel.lifecycle = ({})
        wait(20)
        verify(findChild(panel, "blendStep5") !== null)
        compare(findChild(panel, "blendStep5").modelData.state, "pending")
    }
    function test_collapsed_expansion() {
        compare(panel.expanded, false)
        verify(!findChild(panel, "blendExplanation").visible)
        mouseClick(findChild(panel, "blendTitle"))
        compare(panel.expanded, true)
        verify(findChild(panel, "blendExplanation").visible)
        verify(findChild(panel, "blendAction").visible)
    }
}
