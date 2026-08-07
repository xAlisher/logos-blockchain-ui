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
    property string moduleVersion: "0.2.4"   // this fork's build; keep in sync with metadata.json

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
    // because sandboxed ui_qml (v0.2.3) can't reach the node's :8080 API from QML.
    property int peerCount: -1
    property int connectionCount: -1

    // ── Sub-status line: bootstrap countdown (#17) or staking state (auto-stake) ──
    property int _bootSecs: 0
    property int _dotPhase: 0
    readonly property int _bootTotal: 3600     // count DOWN from 60:00
    function _isBootstrapping() { return root._statusDisplay() === "Bootstrapping" }
    function _balancePositive() { var n = Number(root.balanceText); return !isNaN(n) && n > 0 }
    // LGO display: wallet_get_balance returns base units. 1 LGO = 10^4 base units
    // (2000000000000 base = 200,000,000 LGO → "200M LGO"). Abbreviate + ticker so the
    // value stays inside the stat tile; the tooltip carries the exact amount.
    readonly property real baseUnitsPerLgo: 10000
    function _lgoTrim(x) { return (Math.round(x * 100) / 100).toString() }
    function _fmtBalance(raw) {
        var n = Number(raw)
        if (isNaN(n)) return "— LGO"
        var v = n / root.baseUnitsPerLgo
        var a = Math.abs(v), s
        if      (a >= 1e12) s = root._lgoTrim(v / 1e12) + "T"
        else if (a >= 1e9)  s = root._lgoTrim(v / 1e9)  + "B"
        else if (a >= 1e6)  s = root._lgoTrim(v / 1e6)  + "M"
        else if (a >= 1e3)  s = root._lgoTrim(v / 1e3)  + "K"
        else                s = root._lgoTrim(v)
        return s + " LGO"
    }
    function _balanceExact(raw) {
        var n = Number(raw)
        if (isNaN(n)) return ""
        return (n / root.baseUnitsPerLgo).toLocaleString(Qt.locale(), 'f', 0) + " LGO"
    }
    function _fmtSecs(s) {
        var m = Math.floor(s / 60); var ss = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss
    }
    function _bootDots() { return ["", ".", "..", "..."][root._dotPhase] }
    function _subStatusText() {
        if (root._isBootstrapping()) {
            var rem = root._bootTotal - root._bootSecs
            if (rem > 0) return qsTr("Syncing… %1").arg(root._fmtSecs(rem))   // counts down
            return qsTr("Taking a bit longer") + root._bootDots()            // overran → dots
        }
        if (root.isRunning && root._balancePositive())
            return qsTr("◆ Staking — eligible for leader slots")
        return ""
    }
    Timer {   // countdown tick
        interval: 1000; repeat: true; running: root._isBootstrapping()
        onTriggered: if (root._bootSecs < root._bootTotal + 3) root._bootSecs += 1
        onRunningChanged: if (!running) root._bootSecs = 0
    }
    Timer {   // animated dots for the "Taking a bit longer…" overrun
        interval: 450; repeat: true; running: root._isBootstrapping()
        onTriggered: root._dotPhase = (root._dotPhase + 1) % 4
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
            border.width: 0

            // top-left: module build version (replaces the redundant "Node status" label),
            // level with the Testnet badge — lets you tell which fork build is running at a glance.
            LogosText {
                anchors.top: parent.top; anchors.left: parent.left
                anchors.topMargin: Theme.spacing.medium; anchors.leftMargin: Theme.spacing.medium
                text: qsTr("Module v%1").arg(root.moduleVersion)
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            // top-right: Testnet badge + copy
            RowLayout {
                anchors.top: parent.top; anchors.right: parent.right
                anchors.topMargin: Theme.spacing.medium; anchors.rightMargin: Theme.spacing.medium
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Testnet v0.2.1")
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
                    id: bigStatus
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root._statusDisplay()
                    color: root._statusColor()
                    font.pixelSize: Theme.typography.titleText
                    font.weight: Theme.typography.weightMedium
                    elide: Text.ElideRight
                    // Bootstrapping gently breathes (~10% opacity, not to full off).
                    SequentialAnimation on opacity {
                        running: root._isBootstrapping()
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.9; duration: 950; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 950; easing.type: Easing.InOutSine }
                        onRunningChanged: if (!running) bigStatus.opacity = 1
                    }
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
                    { label: qsTr("Balance"), value: root._fmtBalance(root.balanceText),
                      tip: root._balanceExact(root.balanceText) },
                    { label: qsTr("Peers"),   value: root.peerCount >= 0 ? String(root.peerCount) : "—",
                      tip: root.connectionCount >= 0 ? qsTr("%1 connections").arg(root.connectionCount) : "" }
                ]
                delegate: Rectangle {
                    id: tileRect
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: Theme.spacing.radiusLarge
                    color: Theme.palette.backgroundTertiary
                    border.width: 0
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
            border.width: 0
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
