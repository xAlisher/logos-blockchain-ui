import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Reusable per-epoch bar chart (same shape/behaviour as the inline "Earned by epoch" chart):
// fixed-width, left-packed white bars; a no-value epoch renders as an EMPTY slot; hover reveals
// "Epoch N: <value> <unit>". Feed it a CONTINUOUS series (fill gaps with value 0 upstream) so the
// axis never collapses epochs. `series` is [{ epoch, value }] with value already in display units.
LogosFrame {
    id: root

    property var series: []               // [{ epoch: int, value: number }] — continuous, oldest→newest
    property string title: ""
    property string unit: ""              // e.g. "blocks", "vouchers"
    property int decimals: 0
    property string emptyText: qsTr("Nothing to show yet.")
    property var info: null               // InfoContent entry for the (i)
    signal infoRequested(var info)

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
            // circled-i matching the metric tiles → opens the shared InfoModal via infoRequested
            Rectangle {
                id: ib
                Layout.alignment: Qt.AlignVCenter
                visible: root.info !== null && root.info !== undefined
                readonly property bool hovered: ma.containsMouse
                width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1
                border.color: hovered ? Theme.palette.text : Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.35)
                LogosText { anchors.centerIn: parent; text: "i"; font.pixelSize: 9; color: ib.hovered ? Theme.palette.text : Theme.palette.textMuted }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.infoRequested(root.info) }
            }
        }
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 180
            Canvas {
                id: chart
                anchors.fill: parent
                readonly property var s: root.series
                readonly property int padL: 6
                readonly property int padR: 6
                readonly property int padT: 22
                readonly property int padB: 8
                readonly property int minSlot: 5
                // Width-adaptive: only the most recent epochs that fit at minSlot each.
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
                function niceMax(v) {
                    if (v <= 0) return 1
                    var exp = Math.floor(Math.log(v) / Math.LN10)
                    var base = Math.pow(10, exp)
                    var f = v / base
                    var nf = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10
                    return nf * base
                }
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var W = width, H = height
                    var white = Theme.palette.text
                    if ((s || []).length === 0) {
                        ctx.font = "10px sans-serif"; ctx.fillStyle = Theme.palette.textTertiary
                        ctx.textAlign = "center"; ctx.textBaseline = "middle"
                        ctx.fillText(root.emptyText, W / 2, H / 2)
                        return
                    }
                    var d = vis
                    var maxV = 0
                    for (var i = 0; i < d.length; i++) maxV = Math.max(maxV, Math.max(0, Number(d[i].value)))
                    var top = niceMax(maxV)
                    var pw = Math.max(1, W - padL - padR), ph = Math.max(1, H - padT - padB)
                    var baseY = padT + ph
                    ctx.strokeStyle = Theme.palette.border; ctx.globalAlpha = 0.4; ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(padL, baseY); ctx.lineTo(W - padR, baseY); ctx.stroke(); ctx.globalAlpha = 1
                    var slot = minSlot, bw = slot - 1
                    for (var j = 0; j < d.length; j++) {
                        var v = Math.max(0, Number(d[j].value))
                        var cx = padL + slot * (j + 0.5)
                        var bh = top > 0 ? (v / top) * ph : 0
                        ctx.fillStyle = white; ctx.globalAlpha = (j === hoverIdx) ? 1.0 : 0.8
                        ctx.fillRect(cx - bw / 2, baseY - bh, bw, bh); ctx.globalAlpha = 1
                    }
                    if (hoverIdx >= 0 && hoverIdx < d.length) {
                        var hv = qsTr("Epoch %1: %2 %3").arg(d[hoverIdx].epoch).arg(Number(d[hoverIdx].value).toFixed(root.decimals)).arg(root.unit)
                        ctx.font = "11px sans-serif"; ctx.fillStyle = white
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
                        var d = chart.vis
                        if (!d || d.length === 0) { chart.hoverIdx = -1; return }
                        var idx = Math.floor((mouseX - chart.padL) / chart.minSlot)
                        chart.hoverIdx = (idx >= 0 && idx < d.length) ? idx : -1
                    }
                    onExited: chart.hoverIdx = -1
                }
            }
        }
    }
}
