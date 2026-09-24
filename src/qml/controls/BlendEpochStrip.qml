import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Per-epoch "Blend type" strip: one coloured cell per epoch, colour = the blend mode the node
// was in that epoch (core / declared-but-edge / edge / off). `series` is a CONTINUOUS
// list [{ epoch, mode }] (fill gaps with mode "none" upstream — a "none" cell means the node was
// down / mode unknown that epoch). Fed by the persisted blend-mode history store.
LogosFrame {
    id: root

    property var series: []          // [{ epoch:int, mode:string }], oldest→newest
    property string title: qsTr("Blend type by epoch")
    property var info: null
    signal infoRequested(var info)

    readonly property string _gold: "#d9a521"
    function _color(mode) {
        switch (mode) {
        case "core":         return root._gold                    // mixing as Core (gold)
        // declared-on-chain but running Edge → the SAME normal edge blue, distinguished by a
        // gold underline drawn on top (see onPaint / the legend swatch), not a darker shade.
        case "coredeclared": return Theme.palette.info
        case "edge":         return Theme.palette.info            // normal edge blue
        case "broadcast":    return "#9b7bd4"
        case "off":          return Theme.palette.textMuted
        default:             return Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.18)
        }
    }
    function _label(mode) {
        switch (mode) {
        case "core": return qsTr("Core")
        case "coredeclared": return qsTr("Declared (edge)")
        case "edge": return qsTr("Edge")
        case "broadcast": return qsTr("Broadcast")
        case "off": return qsTr("Off")
        default: return qsTr("—")
        }
    }

    Layout.fillWidth: true
    visible: series && series.length > 0
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: "transparent"
    radius: Theme.spacing.radiusLarge
    padding: Theme.spacing.large

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small
        RowLayout {
            Layout.fillWidth: true
            LogosText { text: root.title; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            Item { Layout.fillWidth: true }
            // (legend removed — the hovered-cell caption below names the mode)
            Rectangle {
                id: ib
                Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: 8
                visible: root.info !== null && root.info !== undefined
                readonly property bool hovered: ma.containsMouse
                width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1
                border.color: hovered ? Theme.palette.text : Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.35)
                LogosText { anchors.centerIn: parent; text: "i"; font.pixelSize: 9; color: ib.hovered ? Theme.palette.text : Theme.palette.textMuted }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.infoRequested(root.info) }
            }
        }
        // hovered cell caption: "Epoch N: <mode>"
        LogosText {
            Layout.fillWidth: true; Layout.preferredHeight: 14
            text: strip.hoverIdx >= 0 && strip.hoverIdx < strip.vis.length
                  ? qsTr("Epoch %1: %2").arg(strip.vis[strip.hoverIdx].epoch).arg(root._label(strip.vis[strip.hoverIdx].mode))
                  : ""
            color: Theme.palette.textTertiary; font.pixelSize: 11
        }
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 44   // taller bars
            Canvas {
                id: strip
                anchors.fill: parent
                readonly property var s: root.series
                readonly property int minSlot: 6
                readonly property var vis: {
                    var d = s || []
                    var maxN = Math.max(1, Math.floor(width / minSlot))
                    return d.length > maxN ? d.slice(-maxN) : d
                }
                property int hoverIdx: -1
                onSChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onHoverIdxChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var d = vis, n = d.length
                    if (n === 0) return
                    var slot = minSlot, cw = slot - 1, H = height
                    for (var j = 0; j < n; j++) {
                        ctx.fillStyle = root._color(d[j].mode)
                        ctx.globalAlpha = (j === hoverIdx) ? 1.0 : 0.9
                        ctx.fillRect(slot * j, 0, cw, H)
                        // declared-but-edge: a 2px gold underline over the normal edge blue
                        if (d[j].mode === "coredeclared") {
                            ctx.globalAlpha = 1
                            ctx.fillStyle = root._gold
                            ctx.fillRect(slot * j, H - 2, cw, 2)
                        }
                    }
                    ctx.globalAlpha = 1
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: {
                        var d = strip.vis
                        if (!d || d.length === 0) { strip.hoverIdx = -1; return }
                        var idx = Math.floor(mouseX / strip.minSlot)
                        strip.hoverIdx = (idx >= 0 && idx < d.length) ? idx : -1
                    }
                    onExited: strip.hoverIdx = -1
                }
            }
        }
    }
}
