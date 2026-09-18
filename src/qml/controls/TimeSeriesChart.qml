import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Reusable rolling time-series line chart. `series` is a list of lines:
//   [{ label, color, values: [number, …], latest: "13%" }]
// Each line is normalised to its OWN max over the window (so mixed units — CPU %, RAM GB,
// Disk GB — are comparable as trends on one chart); the legend + hover show the real values.
// In-session only: the buffer resets when the node stops. Oldest→newest, packed left→right.
LogosFrame {
    id: root

    property var series: []        // [{label, color, values:[num], latest:string}]
    property string title: ""
    property var info: null
    property bool smoothLine: false    // round the corners (quadratic through midpoints) vs sharp polyline
    signal infoRequested(var info)

    readonly property int _maxLen: {
        var n = 0
        for (var i = 0; i < (series ? series.length : 0); i++)
            n = Math.max(n, (series[i].values || []).length)
        return n
    }

    Layout.fillWidth: true
    visible: _maxLen > 0
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
            // legend: colour dot + label + latest value, per line
            Repeater {
                model: root.series
                delegate: RowLayout {
                    spacing: 4; Layout.leftMargin: 10
                    Rectangle { width: 8; height: 8; radius: 4; color: modelData.color; Layout.alignment: Qt.AlignVCenter }
                    LogosText { text: (modelData.label || "") + (modelData.latest ? "  " + modelData.latest : "")
                                color: Theme.palette.textTertiary; font.pixelSize: 11 }
                }
            }
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
            Layout.fillWidth: true; Layout.preferredHeight: 140
            Canvas {
                id: chart
                anchors.fill: parent
                readonly property var s: root.series
                readonly property int padL: 6
                readonly property int padR: 6
                readonly property int padT: 8
                readonly property int padB: 8
                property int hoverIdx: -1     // index into the shared time axis (0…maxLen-1)
                onSChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onHoverIdxChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                function _fmt(line, v) {
                    return (typeof line.fmt === "function") ? line.fmt(v) : String(Math.round(v))
                }
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var W = width, H = height
                    var pw = Math.max(1, W - padL - padR), ph = Math.max(1, H - padT - padB)
                    var baseY = padT + ph
                    ctx.strokeStyle = Theme.palette.border; ctx.globalAlpha = 0.4; ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(padL, baseY); ctx.lineTo(W - padR, baseY); ctx.stroke(); ctx.globalAlpha = 1
                    var lines = s || []
                    var n = root._maxLen
                    var xAt = function(j, len) { return padL + (len <= 1 ? 0 : (j / (len - 1)) * pw) }
                    for (var li = 0; li < lines.length; li++) {
                        var vals = lines[li].values || []
                        if (vals.length < 2) continue
                        var mx = 0
                        for (var k = 0; k < vals.length; k++) mx = Math.max(mx, Number(vals[k]) || 0)
                        if (mx <= 0) mx = 1
                        ctx.strokeStyle = lines[li].color; ctx.lineWidth = 1.5; ctx.globalAlpha = 0.9
                        ctx.lineJoin = "round"; ctx.lineCap = "round"
                        var pts = []
                        for (var j = 0; j < vals.length; j++)
                            pts.push({ x: xAt(j, vals.length), y: baseY - (Math.max(0, Number(vals[j]) || 0) / mx) * ph })
                        ctx.beginPath(); ctx.moveTo(pts[0].x, pts[0].y)
                        if (root.smoothLine && pts.length > 2) {
                            // quadratic through the midpoints — rounds the corners without overshooting
                            for (var p = 1; p < pts.length - 1; p++)
                                ctx.quadraticCurveTo(pts[p].x, pts[p].y, (pts[p].x + pts[p + 1].x) / 2, (pts[p].y + pts[p + 1].y) / 2)
                            ctx.quadraticCurveTo(pts[pts.length - 1].x, pts[pts.length - 1].y, pts[pts.length - 1].x, pts[pts.length - 1].y)
                        } else {
                            for (var q = 1; q < pts.length; q++) ctx.lineTo(pts[q].x, pts[q].y)
                        }
                        ctx.stroke(); ctx.globalAlpha = 1
                    }
                    // ── hover: vertical tracking line + a dot per series + a value tooltip ──
                    if (hoverIdx >= 0 && n > 1) {
                        var hx = xAt(hoverIdx, n)
                        ctx.strokeStyle = Theme.palette.textTertiary; ctx.globalAlpha = 0.55; ctx.lineWidth = 1
                        ctx.beginPath(); ctx.moveTo(hx, padT); ctx.lineTo(hx, baseY); ctx.stroke(); ctx.globalAlpha = 1
                        var rows = []
                        for (var m = 0; m < lines.length; m++) {
                            var lv = lines[m].values || []
                            if (hoverIdx >= lv.length) continue
                            var mmx = 0
                            for (var q = 0; q < lv.length; q++) mmx = Math.max(mmx, Number(lv[q]) || 0)
                            if (mmx <= 0) mmx = 1
                            var vy = baseY - (Math.max(0, Number(lv[hoverIdx]) || 0) / mmx) * ph
                            ctx.fillStyle = lines[m].color
                            ctx.beginPath(); ctx.arc(hx, vy, 2.5, 0, 2 * Math.PI); ctx.fill()
                            rows.push({ color: lines[m].color, text: (lines[m].label || "") + "  " + _fmt(lines[m], Number(lv[hoverIdx])) })
                        }
                        // tooltip box, flipped to whichever side of the line has room
                        ctx.font = "11px sans-serif"
                        var tw = 0
                        for (var r = 0; r < rows.length; r++) tw = Math.max(tw, ctx.measureText(rows[r].text).width)
                        var boxW = tw + 22, boxH = rows.length * 15 + 8
                        var bx = (hx + 10 + boxW < W - padR) ? hx + 8 : hx - 8 - boxW
                        var by = padT + 2
                        ctx.fillStyle = Theme.palette.background; ctx.globalAlpha = 0.9
                        ctx.fillRect(bx, by, boxW, boxH); ctx.globalAlpha = 1
                        ctx.strokeStyle = Theme.palette.border; ctx.lineWidth = 1; ctx.strokeRect(bx, by, boxW, boxH)
                        ctx.textBaseline = "middle"
                        for (var t = 0; t < rows.length; t++) {
                            var ry = by + 12 + t * 15
                            ctx.fillStyle = rows[t].color
                            ctx.beginPath(); ctx.arc(bx + 8, ry, 3, 0, 2 * Math.PI); ctx.fill()
                            ctx.fillStyle = Theme.palette.text; ctx.textAlign = "left"
                            ctx.fillText(rows[t].text, bx + 15, ry)
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: {
                        var n = root._maxLen
                        if (n < 2) { chart.hoverIdx = -1; return }
                        var pw = Math.max(1, chart.width - chart.padL - chart.padR)
                        var frac = (mouseX - chart.padL) / pw
                        var idx = Math.round(frac * (n - 1))
                        chart.hoverIdx = (idx >= 0 && idx < n) ? idx : -1
                    }
                    onExited: chart.hoverIdx = -1
                }
            }
        }
    }
}
