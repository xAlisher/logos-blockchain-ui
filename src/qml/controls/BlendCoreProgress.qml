import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Presentation only: independent evidence per stage, never inferred from Core mode.
LogosFrame {
    id: root
    property var lifecycle: ({})
    property bool busy: false
    property string resultText: ""
    property bool resultError: false
    property bool expanded: false
    property bool userToggled: false
    onDataChanged: if (!userToggled) expanded = data.tone === "warning" || data.tone === "error"
    Component.onCompleted: if (!userToggled) expanded = data.tone === "warning" || data.tone === "error"
    signal manageRequested()
    signal repairRequested()
    signal refreshRequested()
    readonly property var data: lifecycle || ({})
    readonly property color accent: data.tone === "error" ? Theme.palette.error
        : data.tone === "warning" ? Theme.palette.warning
        : data.tone === "success" ? Theme.palette.success : Theme.palette.textSecondary
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: "transparent"
    background: Rectangle { color: root.backgroundColor; radius: Theme.spacing.radiusLarge }
    padding: Theme.spacing.large
    implicitWidth: 920
    contentItem: ColumnLayout {
        spacing: Theme.spacing.small
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                LogosText { text: qsTr("Blend Core"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                LogosText {
                    objectName: "blendTitle"
                    Layout.fillWidth: true
                    text: root.data.title || qsTr("Status unavailable")
                    color: root.accent; font.pixelSize: 24; font.weight: Theme.typography.weightBold
                    wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                }
            }
            QQC.ToolButton {
                objectName: "blendToggle"
                text: root.expanded ? "⌃" : "⌄"
                Accessible.name: root.expanded ? qsTr("Collapse Blend Core details") : qsTr("Expand Blend Core details")
                onClicked: { root.userToggled = true; root.expanded = !root.expanded }
                contentItem: LogosText { text: parent.text; color: Theme.palette.textSecondary; horizontalAlignment: Text.AlignHCenter; font.pixelSize: 24 }
                background: Rectangle { color: "transparent" }
            }
        }
        Item {
            id: lane
            objectName: "blendStrip"
            Layout.fillWidth: true
            implicitHeight: 30
            readonly property var steps: root.data.steps && root.data.steps.length ? root.data.steps
                : [qsTr("Online"), qsTr("Declared"), qsTr("Activated"), qsTr("Connected"), qsTr("Activity"), qsTr("Maintaining")].map(function(label) { return {label: label, state: "pending"} })
            readonly property real depth: 14
            readonly property real segmentWidth: (width + (steps.length - 1) * 12) / Math.max(1, steps.length)
            function segmentLeft(i) { return i * (segmentWidth - 12) }
            onStepsChanged: canvas.requestPaint()
            onWidthChanged: canvas.requestPaint()
            Canvas {
                id: canvas
                anchors.fill: parent
                onAvailableChanged: if (available) requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    for (var i = 0; i < lane.steps.length; ++i) {
                        var x0 = lane.segmentLeft(i), x1 = x0 + lane.segmentWidth
                        var state = lane.steps[i].state
                        var c = state === "error" ? Theme.palette.error : root.accent
                        ctx.fillStyle = state === "complete" ? Theme.palette.surface
                            : state === "pending" ? Theme.palette.surfaceRecessed : Qt.rgba(c.r, c.g, c.b, 0.20)
                        var pts = [[x0, 0]]
                        if (i === lane.steps.length - 1) pts.push([x1, 0], [x1, height])
                        else pts.push([x1 - 14, 0], [x1, height / 2], [x1 - 14, height])
                        pts.push([x0, height])
                        if (i > 0) pts.push([x0 + 14, height / 2])
                        var last = pts[pts.length - 1], first = pts[0]
                        ctx.beginPath(); ctx.moveTo((last[0] + first[0]) / 2, (last[1] + first[1]) / 2)
                        for (var k = 0; k < pts.length; ++k) {
                            var p = pts[k], next = pts[(k + 1) % pts.length]
                            ctx.arcTo(p[0], p[1], next[0], next[1], 3)
                        }
                        ctx.closePath(); ctx.fill()
                    }
                }
            }
            Repeater {
                model: lane.steps
                LogosText {
                    required property int index
                    required property var modelData
                    objectName: "blendStep" + index
                    x: lane.segmentLeft(index) + (index > 0 ? 14 : 0)
                    width: lane.segmentWidth - (index > 0 ? 14 : 0) - (index < lane.steps.length - 1 ? 14 : 0)
                    height: lane.height
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    text: (modelData.state === "complete" ? "✓ " : "") + modelData.label
                    font.pixelSize: 12; elide: Text.ElideRight; textFormat: Text.PlainText
                    color: modelData.state === "error" ? Theme.palette.error : modelData.state === "current" ? root.accent
                        : modelData.state === "complete" ? Theme.palette.textSecondary : Theme.palette.textTertiary
                    QQC.ToolTip.visible: stepHover.hovered
                    QQC.ToolTip.text: modelData.label + " · " + modelData.state
                    HoverHandler { id: stepHover }
                }
            }
        }
        LogosText {
            objectName: "blendResult"
            Layout.fillWidth: true
            visible: root.resultText.length > 0
            text: root.resultText; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
            color: root.resultError ? Theme.palette.error : Theme.palette.textSecondary
        }
        ColumnLayout {
            objectName: "blendExplanation"
            visible: root.expanded
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                Layout.fillWidth: true; text: root.data.detail || qsTr("Refresh to check the node's current evidence.")
                wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                color: Theme.palette.textSecondary
            }
            LogosText {
                objectName: "blendEvidence"
                Layout.fillWidth: true; text: root.data.evidence || qsTr("Evidence unavailable.")
                wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText
            }
            LogosButton {
                objectName: "blendAction"
                Layout.maximumWidth: parent.width
                text: root.data.actionLabel || qsTr("Refresh")
                visible: ["manage", "repair", "refresh"].indexOf(root.data.action) >= 0
                enabled: !root.busy
                onClicked: {
                    if (root.busy) return
                    if (root.data.action === "manage") root.manageRequested()
                    else if (root.data.action === "repair") root.repairRequested()
                    else if (root.data.action === "refresh") root.refreshRequested()
                }
            }
        }
    }
}
