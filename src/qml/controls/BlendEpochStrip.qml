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

    // Mirror EpochBarChart's layout EXACTLY so title-Y and the chart baseline line up across the
    // by-epoch row: [title row] + [Item preferredHeight 180 → Canvas], and the hover caption is
    // painted INSIDE the canvas (no separate LogosText row — that row is what dropped the title 14px).
    contentItem: ColumnLayout {
        spacing: Theme.spacing.small
        RowLayout {
            Layout.fillWidth: true
            LogosText { text: root.title; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            Item { Layout.fillWidth: true }
            // (legend removed — the hovered-cell caption painted in-canvas names the mode)
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
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 180   // == EpochBarChart body → same baseline
            Canvas {
                id: strip
                anchors.fill: parent
                readonly property var s: root.series
                // same insets as EpochBarChart so the baseline + left edge align across the row
                readonly property int padL: 6
                readonly property int padR: 6
                readonly property int padT: 22
                readonly property int padB: 8
                readonly property int minSlot: 6
                readonly property var vis: {
                    var d = s || []
                    var pw = Math.max(1, width - padL - padR)
                    var maxN = Math.max(1, Math.floor(pw / minSlot))
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
                    var d = vis, n = d.length, W = width, H = height
                    if (n === 0) return
                    var ph = Math.max(1, H - padT - padB)
                    var baseY = padT + ph                 // == H - padB, matches the bar chart axis
                    // baseline axis (same faint line as EpochBarChart) so the two read as one row
                    ctx.strokeStyle = Theme.palette.border; ctx.globalAlpha = 0.4; ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(padL, baseY); ctx.lineTo(W - padR, baseY); ctx.stroke(); ctx.globalAlpha = 1
                    var slot = minSlot, cw = slot - 1
                    for (var j = 0; j < n; j++) {
                        ctx.fillStyle = root._color(d[j].mode)
                        ctx.globalAlpha = (j === hoverIdx) ? 1.0 : 0.9
                        // full-height cell sitting ON the baseline (top at padT, bottom at baseY)
                        ctx.fillRect(padL + slot * j, padT, cw, ph)
                        // declared-but-edge: a 2px gold underline at the baseline over the edge blue
                        if (d[j].mode === "coredeclared") {
                            ctx.globalAlpha = 1
                            ctx.fillStyle = root._gold
                            ctx.fillRect(padL + slot * j, baseY - 2, cw, 2)
                        }
                    }
                    ctx.globalAlpha = 1
                    // hovered-cell caption painted in the top gutter, like EpochBarChart
                    if (hoverIdx >= 0 && hoverIdx < n) {
                        var hv = qsTr("Epoch %1: %2").arg(d[hoverIdx].epoch).arg(root._label(d[hoverIdx].mode))
                        ctx.font = "11px sans-serif"; ctx.fillStyle = Theme.palette.text
                        ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
                        var tw = ctx.measureText(hv).width
                        var hx = padL + slot * (hoverIdx + 0.5)
                        hx = Math.max(padL + tw / 2, Math.min(W - padR - tw / 2, hx))
                        ctx.fillText(hv, hx, padT - 7)
                    }
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: {
                        var d = strip.vis
                        if (!d || d.length === 0) { strip.hoverIdx = -1; return }
                        var idx = Math.floor((mouseX - strip.padL) / strip.minSlot)
                        strip.hoverIdx = (idx >= 0 && idx < d.length) ? idx : -1
                    }
                    onExited: strip.hoverIdx = -1
                }
            }
        }
    }
}
