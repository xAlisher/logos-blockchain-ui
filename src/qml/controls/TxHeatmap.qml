import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// "TX on blocks" — one rounded square per recent block, GitHub-contribution style: the busiest
// block in the shown window is full green, an empty block is grey, shades of green in between
// (scaled to that window's max). `series` is [{ slot, txCount }], oldest→newest. Width-adaptive:
// shows the most recent blocks that fit, packed left→right.
LogosFrame {
    id: root

    property var series: []
    property string title: qsTr("TX on blocks")
    property var info: null
    signal infoRequested(var info)

    readonly property string _empty: "#2d333b"
    function _heat(t) {
        if (t <= 0) return root._empty
        t = Math.max(0, Math.min(1, t))
        var lo = [14, 68, 41], hi = [57, 211, 83]   // #0e4429 → #39d353
        return Qt.rgba((lo[0] + (hi[0] - lo[0]) * t) / 255,
                       (lo[1] + (hi[1] - lo[1]) * t) / 255,
                       (lo[2] + (hi[2] - lo[2]) * t) / 255, 1)
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
            // "less → more" scale, GitHub-style
            LogosText { text: qsTr("less"); color: Theme.palette.textTertiary; font.pixelSize: 10 }
            Repeater {
                model: [0, 0.25, 0.5, 0.75, 1]
                delegate: Rectangle { width: 9; height: 9; radius: 2; Layout.leftMargin: 2
                                      Layout.alignment: Qt.AlignVCenter; color: root._heat(modelData) }
            }
            LogosText { text: qsTr("more"); color: Theme.palette.textTertiary; font.pixelSize: 10; Layout.leftMargin: 2 }
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
        // hovered-square caption
        LogosText {
            Layout.fillWidth: true; Layout.preferredHeight: 14
            text: (grid.hoverIdx >= 0 && grid.hoverIdx < grid.vis.length)
                  ? qsTr("Slot %1 · %2 tx").arg(grid.vis[grid.hoverIdx].slot).arg(grid.vis[grid.hoverIdx].txCount)
                  : ""
            color: Theme.palette.textTertiary; font.pixelSize: 11
        }
        Item {
            Layout.fillWidth: true; Layout.preferredHeight: 20
            Canvas {
                id: grid
                anchors.fill: parent
                readonly property var s: root.series
                readonly property int cell: 14
                readonly property int gap: 3
                readonly property int slotW: cell + gap
                readonly property var vis: {
                    var d = s || []
                    var maxN = Math.max(1, Math.floor((width + gap) / slotW))
                    return d.length > maxN ? d.slice(-maxN) : d
                }
                property int hoverIdx: -1
                onSChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHoverIdxChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                function _rr(ctx, x, y, w, h, r) {
                    ctx.beginPath()
                    ctx.moveTo(x + r, y)
                    ctx.lineTo(x + w - r, y); ctx.quadraticCurveTo(x + w, y, x + w, y + r)
                    ctx.lineTo(x + w, y + h - r); ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
                    ctx.lineTo(x + r, y + h); ctx.quadraticCurveTo(x, y + h, x, y + h - r)
                    ctx.lineTo(x, y + r); ctx.quadraticCurveTo(x, y, x + r, y)
                    ctx.closePath()
                }
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var d = vis, n = d.length
                    if (n === 0) return
                    var mx = 0
                    for (var i = 0; i < n; i++) mx = Math.max(mx, Number(d[i].txCount) || 0)
                    if (mx <= 0) mx = 1
                    var y = Math.max(0, (height - cell) / 2)
                    for (var j = 0; j < n; j++) {
                        var t = (Number(d[j].txCount) || 0) / mx
                        ctx.fillStyle = root._heat(t)
                        ctx.globalAlpha = (j === hoverIdx) ? 1.0 : 0.92
                        _rr(ctx, slotW * j, y, cell, cell, 3); ctx.fill()
                        if (j === hoverIdx) {
                            ctx.globalAlpha = 1; ctx.strokeStyle = Theme.palette.text; ctx.lineWidth = 1
                            _rr(ctx, slotW * j + 0.5, y + 0.5, cell - 1, cell - 1, 3); ctx.stroke()
                        }
                    }
                    ctx.globalAlpha = 1
                }
                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: {
                        var d = grid.vis
                        if (!d || d.length === 0) { grid.hoverIdx = -1; return }
                        var idx = Math.floor(mouseX / grid.slotW)
                        grid.hoverIdx = (idx >= 0 && idx < d.length) ? idx : -1
                    }
                    onExited: grid.hoverIdx = -1
                }
            }
        }
    }
}
