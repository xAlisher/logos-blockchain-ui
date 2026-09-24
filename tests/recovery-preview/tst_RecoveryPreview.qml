import QtQuick
import QtTest

// Presentation-only synthetic fixtures. The packaged native integration tests,
// not these pictures, validate recovery decisions and network request counts.
TestCase {
    id: test
    name: "RecoveryPreview"
    visible: true
    width: 1000
    height: 1100
    when: windowShown
    property var panel: null
    Rectangle {
        id: canvas
        width: 960
        height: panel ? panel.height + 78 : 800
        color: "#101318"
        Text {
            x: 20; y: 17
            color: "#9da4ae"
            font.pixelSize: 12
            text: "SYNTHETIC RECOVERY PREVIEW · no transactions"
            width: parent.width - 40
            wrapMode: Text.Wrap
        }
    }
    function init() {
        var component = Qt.createComponent("../../src/qml/controls/BlendCoreProgress.qml")
        compare(component.status, Component.Ready, component.errorString())
        panel = component.createObject(canvas, {x: 20, y: 55, width: 920})
        verify(panel !== null)
    }
    function cleanup() {
        if (panel) { panel.destroy(); panel = null }
    }
    function test_recovery_data() {
        var stages = [
            {phase: "withdrawal-pending", title: "Withdrawal requested", detail: "Waiting for on-chain inclusion. No duplicate request will be sent.", index: 0},
            {phase: "waiting-removal", title: "Waiting for removal", detail: "Withdrawal is scheduled. Waiting for registry removal and finality before re-declaring.", index: 1},
            {phase: "declaration-pending", title: "Fresh declaration submitted", detail: "Waiting for the new declaration to appear on chain. Your identity is unchanged.", index: 2},
            {phase: "activation", title: "Waiting for Core", detail: "The fresh declaration is bound. Waiting for runtime Core membership.", index: 4},
            {phase: "monitoring", title: "Monitoring renewals", detail: "Two consecutive accepted activity epochs observed. Waiting for the third.", index: 5},
            {phase: "paused", title: "Recovery paused", detail: "Future automation is paused. An already submitted withdrawal is not cancelled.", index: 1},
            {phase: "attention", title: "Withdrawal outcome uncertain", detail: "The response was lost. Waiting for chain evidence; the paid request will not be retried.", index: 0}
        ]
        var rows = []
        stages.forEach(function(stage) {
            ;[320, 920].forEach(function(width) {
                rows.push({tag: stage.phase + "_" + width, stage: stage, panelWidth: width})
            })
        })
        return rows
    }
    function test_recovery(row) {
        var s = row.stage
        var recovery = {
            active: true, phase: s.phase, title: s.title, detail: s.detail,
            tone: s.phase === "attention" ? "warning" : "neutral",
            canStart: false, canPause: s.phase !== "paused", canResume: s.phase === "paused",
            steps: ["Withdraw", "Removal", "Re-declare", "Binding", "Core", "Renewals"].map(function(label, i) {
                return {label: label, state: i < s.index ? "complete" : i === s.index ? "current" : "pending"}
            })
        }
        panel.width = row.panelWidth
        canvas.width = row.panelWidth + 40
        panel.lifecycle = {
            ok: true, state: "at-risk", title: "Activity at risk", tone: "warning",
            detail: "The previous declaration cannot sustain continuous membership.",
            epoch: 44, created: 35, active: 40, nonce: "1", withdrawAt: 44,
            mode: "Online", healthyPeers: 3, action: "none", recovery: recovery
        }
        panel.expanded = false
        wait(50)
        waitForRendering(panel, 100)
        verify(panel.height > 100 && panel.height < 1000)
        verify(canvas.height <= test.height)
        // Even collapsed, recovery must remain visibly identifiable.
        var status = findChild(panel, "blendRecoveryTitle")
        verify(status !== null, "Recovery title must be identifiable in the production component")
        verify(status.visible)
        var pos = status.mapToItem(panel, 0, 0)
        verify(pos.x >= 0 && pos.x + status.width <= panel.width + 1)
        var image = grabImage(canvas)
        verify(image.width > 0 && image.height > 0)
        image.save("/extra/tmp/blend-recovery-delivery/screenshots/" + row.tag + ".png")
    }
}
