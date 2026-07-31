import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Node dashboard (one-click UX #13). Status-first: a state-tinted status block
// (Stop control + Testnet badge + Peer ID line), a row of stat tiles
// (Slot / Height / Balance / Peers) and the Tip / LIB chain refs — all copyable.
// Design tokens only; never the non-existent `Theme.palette.orange`.
Item {
    id: root

    property int    statusEnum: -1
    property string statusText: ""
    property color  statusColor: Theme.palette.textSecondary
    property bool   isRunning: false
    property string errorText: ""
    property string peerId: ""
    property string infoJson: ""
    property string balanceText: "0"
    property string apiBase: "http://127.0.0.1:8080"

    signal copyText(string text)
    signal startRequested()
    signal stopRequested()

    readonly property color ctaOrange: Theme.palette.primaryHover

    // ── Consensus JSON parsing (mirrors CryptarchiaInfoView) ──
    readonly property var _info: {
        try { return infoJson && infoJson.length > 0 ? JSON.parse(infoJson) : null }
        catch (e) { return null }
    }
    function _field(key) {
        if (!_info) return undefined
        if (_info.cryptarchia_info && _info.cryptarchia_info[key] !== undefined)
            return _info.cryptarchia_info[key]
        return _info[key]
    }
    function _num(key) {
        var v = _field(key)
        return (v === undefined || v === null) ? "—" : Number(v).toLocaleString(Qt.locale(), "f", 0)
    }
    function _hash(key) {
        var v = _field(key)
        return (v === undefined || v === null || v === "") ? "—" : String(v)
    }
    function _statusDisplay() {
        if (errorText && errorText.length > 0) return errorText
        if (isRunning) {
            var m = _info ? _info.mode : undefined
            if (typeof m === "string") return m
            if (typeof m === "number") return ["Bootstrapping", "Online", "Not Started"][m] || String(m)
            if (m && typeof m === "object") { for (var k in m) return String(k) }
            return qsTr("Bootstrapping")
        }
        return statusText
    }
    function _statusColor() {
        if (errorText && errorText.length > 0) return Theme.palette.error
        var s = _statusDisplay()
        if (s === "Online") return Theme.palette.success
        if (s === "Bootstrapping") return ctaOrange
        return statusColor
    }
    // State-tinted status-block background (~10% of the status colour).
    function _statusBg() {
        var c = Theme.palette.backgroundTertiary
        var a = 0.10
        if (errorText && errorText.length > 0) c = Theme.palette.error
        else {
            var s = _statusDisplay()
            if (s === "Online") { c = Theme.palette.success; a = 0.05 }  // green: more subtle
            else if (s === "Bootstrapping") c = ctaOrange
            else return Theme.palette.backgroundTertiary
        }
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Peer / connection counts — fed from BlockchainView (backend curl, #21),
    // because the app's QML XHR can't reliably reach the node's :8080 API.
    property int peerCount: -1
    property int connectionCount: -1

    // ── Sub-status line: bootstrap progress (#17) or staking state (auto-stake) ──
    property int _bootSecs: 0
    function _isBootstrapping() { return root._statusDisplay() === "Bootstrapping" }
    function _balancePositive() { var n = Number(root.balanceText); return !isNaN(n) && n > 0 }
    function _fmtSecs(s) {
        var m = Math.floor(s / 60); var ss = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss
    }
    function _subStatusText() {
        if (root._isBootstrapping()) {
            return (root._bootSecs > 300
                    ? qsTr("Taking a bit longer than usual — still catching up… %1")
                    : qsTr("Syncing… %1")).arg(root._fmtSecs(root._bootSecs))
        }
        if (root.isRunning && root._balancePositive())
            return qsTr("◆ Staking — eligible for leader slots")
        return ""
    }
    Timer {
        interval: 1000; repeat: true; running: root._isBootstrapping()
        onTriggered: root._bootSecs += 1
        onRunningChanged: if (!running) root._bootSecs = 0
    }

    implicitHeight: col.implicitHeight

    // ── value text that "breathes": softly flashes green on every change, then
    //    eases back to its rest colour (issue: live-value change animation) ──
    component FlashValue: LogosText {
        id: fv
        property color restColor: Theme.palette.text
        color: restColor
        onTextChanged: flashAnim.restart()
        SequentialAnimation {
            id: flashAnim
            ColorAnimation { target: fv; property: "color"
                to: Theme.palette.success; duration: 160; easing.type: Easing.OutQuad }
            ColorAnimation { target: fv; property: "color"
                to: fv.restColor; duration: 1100; easing.type: Easing.InOutQuad }
        }
    }

    // ── small, gray copy button (matches text colour) ──
    component CopyBtn: Button {
        property string value
        property bool copied: false
        flat: true; padding: 2
        implicitWidth: 22; implicitHeight: 22
        display: AbstractButton.IconOnly
        enabled: value && value.length > 0 && value !== "—"
        opacity: enabled ? 1 : 0.3
        icon.source: Qt.resolvedUrl("../icons/copy.svg")
        icon.width: 14; icon.height: 14
        icon.color: copied ? root.ctaOrange
                    : (hovered ? Theme.palette.text : Theme.palette.textSecondary)
        ToolTip.visible: hovered && enabled; ToolTip.text: copied ? qsTr("Copied") : qsTr("Copy")
        onClicked: { root.copyText(value); copied = true; copiedReset.restart() }
        Timer { id: copiedReset; interval: 1200; onTriggered: copied = false }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: Theme.spacing.medium

        // ═══ Status block ═══
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 128
            radius: Theme.spacing.radiusLarge
            color: root._statusBg()
            border.color: Theme.palette.border

            // top-left: "Node status" label, level with the Testnet badge
            LogosText {
                anchors.top: parent.top; anchors.left: parent.left
                anchors.topMargin: Theme.spacing.medium; anchors.leftMargin: Theme.spacing.medium
                text: qsTr("Node status")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            // top-right: Testnet badge + copy
            RowLayout {
                anchors.top: parent.top; anchors.right: parent.right
                anchors.topMargin: Theme.spacing.medium; anchors.rightMargin: Theme.spacing.medium
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Testnet v0.2")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textTertiary
                }
                CopyBtn { value: root._statusDisplay() }
            }

            // centered status value + sub-line (staking / bootstrap progress)
            Column {
                anchors.centerIn: parent
                width: root.width - 4 * Theme.spacing.large
                spacing: 3
                LogosText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root._statusDisplay()
                    color: root._statusColor()
                    font.pixelSize: Theme.typography.titleText
                    font.weight: Theme.typography.weightMedium
                    elide: Text.ElideRight
                }
                LogosText {
                    width: parent.width
                    visible: text.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root._subStatusText()
                    color: root._isBootstrapping() ? Theme.palette.textSecondary
                                                   : Theme.palette.success
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }
            }

            // bottom: Peer ID on one line, centered, gray
            RowLayout {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: Theme.spacing.medium
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Peer ID:")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                LogosText {
                    Layout.maximumWidth: root.width - 8 * Theme.spacing.large
                    text: root.peerId && root.peerId.length ? root.peerId : "—"
                    font.pixelSize: Theme.typography.secondaryText
                    font.family: Theme.typography.publicSans
                    color: Theme.palette.textSecondary
                    elide: Text.ElideMiddle
                }
                CopyBtn { value: root.peerId }
            }
        }

        // ═══ Stat tiles: Slot · Height · Balance · Peers ═══
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium
            Repeater {
                model: [
                    { label: qsTr("Slot"),    value: root._num("slot"), tip: "" },
                    { label: qsTr("Height"),  value: root._num("height"), tip: "" },
                    { label: qsTr("Balance"), value: root.balanceText, tip: "" },
                    { label: qsTr("Peers"),   value: root.peerCount >= 0 ? String(root.peerCount) : "—",
                      tip: root.connectionCount >= 0 ? qsTr("%1 connections").arg(root.connectionCount) : "" }
                ]
                delegate: Rectangle {
                    id: tileRect
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: Theme.spacing.radiusLarge
                    color: Theme.palette.backgroundTertiary
                    border.color: Theme.palette.border
                    HoverHandler { id: tileHover }
                    ToolTip.visible: tileHover.hovered && modelData.tip && modelData.tip.length > 0
                    ToolTip.text: modelData.tip || ""
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        LogosText {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.label
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                        }
                        FlashValue {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.value
                            font.pixelSize: Theme.typography.panelTitleText
                            font.weight: Theme.typography.weightMedium
                        }
                    }
                }
            }
        }

        // ═══ Tip / LIB (one block, two rows) ═══
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 58
            radius: Theme.spacing.radiusLarge
            color: Theme.palette.backgroundTertiary
            border.color: Theme.palette.border
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.spacing.large
                anchors.rightMargin: Theme.spacing.medium
                spacing: 3
                Repeater {
                    model: [
                        { label: qsTr("Tip"), value: root._hash("tip") },
                        { label: qsTr("LIB"), value: root._hash("lib") }
                    ]
                    delegate: RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.medium
                        LogosText {
                            text: modelData.label
                            Layout.preferredWidth: 32
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                        }
                        FlashValue {
                            Layout.fillWidth: true
                            text: modelData.value
                            font.pixelSize: Theme.typography.primaryText
                            font.family: Theme.typography.publicSans
                            elide: Text.ElideMiddle
                        }
                        CopyBtn { value: modelData.value }
                    }
                }
            }
        }
    }
}
