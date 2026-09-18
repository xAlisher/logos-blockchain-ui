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
                onSChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onAvailableChanged: if (available) requestPaint()
                Component.onCompleted: requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    var W = width, H = height
                    var pw = Math.max(1, W - padL - padR), ph = Math.max(1, H - padT - padB)
                    var baseY = padT + ph
                    ctx.strokeStyle = Theme.palette.border; ctx.globalAlpha = 0.4; ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(padL, baseY); ctx.lineTo(W - padR, baseY); ctx.stroke(); ctx.globalAlpha = 1
                    var lines = s || []
                    for (var li = 0; li < lines.length; li++) {
                        var vals = lines[li].values || []
                        if (vals.length < 2) continue
                        var mx = 0
                        for (var k = 0; k < vals.length; k++) mx = Math.max(mx, Number(vals[k]) || 0)
                        if (mx <= 0) mx = 1
                        ctx.strokeStyle = lines[li].color; ctx.lineWidth = 1.5; ctx.globalAlpha = 0.9
                        ctx.beginPath()
                        for (var j = 0; j < vals.length; j++) {
                            var x = padL + (vals.length === 1 ? 0 : (j / (vals.length - 1)) * pw)
                            var y = baseY - (Math.max(0, Number(vals[j]) || 0) / mx) * ph
                            if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                        }
                        ctx.stroke(); ctx.globalAlpha = 1
                    }
                }
            }
        }
    }
}
