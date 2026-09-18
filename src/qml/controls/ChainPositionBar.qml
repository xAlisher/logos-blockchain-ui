import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// "Chain position" — Slot and Height as one picture. A horizontal SLOT axis carrying three
// markers: lib (finalized edge) ≤ tip (your latest block) ≤ now (the clock / current_slot).
//   [lib ── tip]  solid  = built but not yet finalized
//   [tip ── now]  faint  = the gap you're catching up to the clock
// Height is the block count annotation. When synced, tip ≈ now (faint part vanishes); during a
// prolonged bootstrap, lib freezes far behind — which shows up here as a long finality lag.
LogosFrame {
    id: root

    property int libSlot: -1
    property int tipSlot: -1
    property int nowSlot: -1
    property int blockHeight: -1
    property var info: null
    signal infoRequested(var info)

    readonly property int _lo: Math.min(libSlot >= 0 ? libSlot : tipSlot, tipSlot)
    readonly property int _hi: Math.max(nowSlot, tipSlot)
    function _fx(s) { return _hi <= _lo ? 0 : (s - _lo) / (_hi - _lo) }

    Layout.fillWidth: true
    visible: tipSlot >= 0 && nowSlot >= 0
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: "transparent"
    radius: Theme.spacing.radiusLarge
    padding: Theme.spacing.large

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small
        RowLayout {
            Layout.fillWidth: true
            LogosText { text: qsTr("Chain position"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            Item { Layout.fillWidth: true }
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
            Layout.fillWidth: true; Layout.preferredHeight: 46
            Canvas {
                id: bar
                anchors.fill: parent
                readonly property int lib: root.libSlot
                readonly property int tip: root.tipSlot
                readonly property int now: root.nowSlot
                onLibChanged: requestPaint()
                onTipChanged: requestPaint()
                onNowChanged: requestPaint()
                onWidthChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var padL = 6, padR = 6
                    var W = width - padL - padR, y = 14, h = 12
                    if (W <= 0) return
                    var xLib = padL + root._fx(root.libSlot >= 0 ? root.libSlot : root.tipSlot) * W
                    var xTip = padL + root._fx(root.tipSlot) * W
                    var xNow = padL + root._fx(root.nowSlot) * W
                    var info = Theme.palette.info
                    // track
                    ctx.fillStyle = Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.15)
                    ctx.fillRect(padL, y, W, h)
                    // [lib..tip] solid — built but not finalized
                    ctx.fillStyle = info; ctx.globalAlpha = 0.85
                    ctx.fillRect(xLib, y, Math.max(0, xTip - xLib), h); ctx.globalAlpha = 1
                    // [tip..now] faint — catching up to the clock
                    ctx.fillStyle = info; ctx.globalAlpha = 0.30
                    ctx.fillRect(xTip, y, Math.max(0, xNow - xTip), h); ctx.globalAlpha = 1
                    // marker ticks + labels
                    function tick(x, label, col) {
                        ctx.strokeStyle = col; ctx.lineWidth = 1.5
                        ctx.beginPath(); ctx.moveTo(x, y - 4); ctx.lineTo(x, y + h + 4); ctx.stroke()
                        ctx.fillStyle = col; ctx.font = "10px sans-serif"; ctx.textBaseline = "top"
                        var tw = ctx.measureText(label).width
                        var lx = Math.max(padL, Math.min(width - padR - tw, x - tw / 2))
                        ctx.fillText(label, lx, y + h + 6)
                    }
                    var gold = "#d9a521", white = Theme.palette.text
                    if (root.libSlot >= 0) tick(xLib, qsTr("lib"), Theme.palette.textTertiary)
                    tick(xTip, qsTr("tip"), gold)
                    tick(xNow, qsTr("now"), white)
                }
            }
        }
        LogosText {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: {
                var parts = []
                if (root.blockHeight >= 0) parts.push(qsTr("%1 blocks").arg(root.blockHeight))
                if (root.nowSlot >= 0 && root.tipSlot >= 0) parts.push(qsTr("%1 slots behind").arg(Math.max(0, root.nowSlot - root.tipSlot)))
                if (root.tipSlot >= 0 && root.libSlot >= 0) parts.push(qsTr("%1 slots to finality").arg(Math.max(0, root.tipSlot - root.libSlot)))
                return parts.join(" · ")
            }
            color: Theme.palette.textTertiary; font.pixelSize: 11
        }
    }
}
