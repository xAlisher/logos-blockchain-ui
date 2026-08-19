import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

import "../amounts.js" as Amounts

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
    // Chain-recovery (block replay after an unclean restart) — fed from BlockchainView.
    property bool   recoveryActive: false
    property int    recoveryBlocks: 0
    property string infoJson: ""
    property string balanceText: "0"
    // leader.wallet.funding_pk — named in the Balance tooltip so the
    // reader knows which wallet the figure describes.
    property string leaderKey: ""
    // Kept in sync with metadata.json BY THE BUILD, not by hand: CMake compares this literal
    // against metadata.json and fails the configure step if they disagree. The previous
    // "keep in sync" comment drifted three releases — the UI still said 0.2.6 while the
    // module shipped as 0.2.12 — because a comment cannot enforce anything.
    //
    // Not read from metadata.json at runtime on purpose: the file IS deployed beside the
    // plugin, but no shipped module reads JSON from QML, and sandbox file/network access
    // fails SILENTLY. That would trade a stale version for a blank one.
    property string moduleVersion: "0.2.16"

    // ── Blend status (fed from BlockchainView → backend.blendStatus/lastBlendEvent) ──
    // Label carries the Blend state only (node state is in the status block above);
    // blue while actively mixing (edge/core), gray otherwise. blendEvent is the
    // honest, plain-language line about the current epoch (verbatim on errors).
    property string blendText: ""
    property color  blendColor: Theme.palette.textSecondary
    property string blendEvent: ""

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
        if (recoveryActive) return qsTr("Recovering chain")
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
        if (recoveryActive) return ctaOrange
        if (errorText && errorText.length > 0) return Theme.palette.error
        var s = _statusDisplay()
        if (s === "Online") return Theme.palette.success
        if (s === "Bootstrapping") return ctaOrange
        return statusColor
    }
    // Title is split so an animated ellipsis can own RESERVED space — the base label,
    // then a fixed-width dots block. Keeps the centered title from jumping left-right.
    function _titleBase() {
        return root._statusDisplay().replace(/\s*(?:\.\.\.|…)\s*$/, "")
    }
    function _titleDots() {   // which states get the working "…" (Starting/Stopping/Bootstrapping/Recovering)
        if (root.recoveryActive) return true
        var s = root._statusDisplay()
        if (s === qsTr("Bootstrapping")) return true
        return /(?:\.\.\.|…)\s*$/.test(s)
    }
    // State-tinted status-block background (~10% of the status colour).
    function _statusBg() {
        var c = Theme.palette.backgroundTertiary
        var a = 0.10
        if (errorText && errorText.length > 0) c = Theme.palette.error
        else {
            var s = _statusDisplay()
            if (s === "Online") { c = Theme.palette.success; a = 0.025 }  // green: extra subtle (half of the old 0.05)
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
    // LGO display. The raw u64 from wallet_get_balance IS LGO — there is no
    // sub-unit. This used to divide by an invented `baseUnitsPerLgo = 10000`,
    // making every balance read 10,000x too small. Upstream disagrees on all
    // counts: core/src/mantle/transactions/gas.rs cites the spec as
    // "P_STR(0) = 1 LGO/gas" and writes GasPrice::new(1); the official
    // logos-blockchain-ui renders the raw string; hackyguru/persona formats the
    // raw value with no division. No client we looked at divides.
    //
    // (An earlier comment here claimed `baseUnitsPerLgo` had "zero hits on
    // GitHub". That is not reproducible — `gh search code` returns [] even for
    // strings that demonstrably exist in a repo, so an empty result proves
    // nothing. Removed rather than left as an unsupported assertion.)
    //
    // Formatting now lives in controls/AmountText.qml so exactly one place
    // decides what a number means. These two wrappers keep the existing stat-tile
    // call sites (value + tip) working.
    function _fmtBalance(raw) { return Amounts.short(raw) }
    function _balanceExact(raw) { return Amounts.exact(raw) }

    function _fmtSecs(s) {
        var m = Math.floor(s / 60); var ss = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss
    }
    function _bootDots() { return ["", ".", "..", "..."][root._dotPhase] }
    function _subStatusText() {
        if (root.recoveryActive)
            return root.recoveryBlocks > 0
                ? qsTr("Replaying %1 stored blocks…").arg(root.recoveryBlocks)
                : qsTr("Replaying stored blocks…")
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
            Layout.preferredHeight: 140
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
                // Base label + a fixed-width animated ellipsis. The three dots always occupy
                // their width (only opacity is animated), so the centered title never jumps
                // left-right while "Starting / Recovering chain / Bootstrapping…" ticks.
                Item {
                    id: titleWrap
                    width: parent.width
                    height: bigStatus.implicitHeight
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0
                        LogosText {
                            id: bigStatus
                            width: Math.min(implicitWidth, titleWrap.width - (titleDots.visible ? titleDots.width : 0))
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: root._titleBase()
                            color: root._statusColor()
                            font.pixelSize: Theme.typography.titleText
                            font.weight: Theme.typography.weightMedium
                            // Bootstrapping / recovering gently breathes (~10% opacity, not to full off).
                            SequentialAnimation on opacity {
                                running: root._isBootstrapping() || root.recoveryActive
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 0.9; duration: 950; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 950; easing.type: Easing.InOutSine }
                                onRunningChanged: if (!running) bigStatus.opacity = 1
                            }
                        }
                        // Reserved-width ellipsis: all three dots present; only opacity animates.
                        Row {
                            id: titleDots
                            visible: root._titleDots()
                            spacing: 0
                            Repeater {
                                model: 3
                                LogosText {
                                    text: "."
                                    color: bigStatus.color
                                    font.pixelSize: Theme.typography.titleText
                                    font.weight: Theme.typography.weightMedium
                                    opacity: 0.25
                                    SequentialAnimation on opacity {
                                        running: titleDots.visible
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: index * 260 }
                                        NumberAnimation { to: 1.0; duration: 180 }
                                        NumberAnimation { to: 0.25; duration: 180 }
                                        PauseAnimation { duration: (2 - index) * 260 + 520 }
                                    }
                                }
                            }
                        }
                    }
                }
                LogosText {
                    width: parent.width
                    visible: text.length > 0
                    horizontalAlignment: Text.AlignHCenter
                    text: root._subStatusText()
                    color: (root._isBootstrapping() || root.recoveryActive) ? Theme.palette.textSecondary
                                                                            : Theme.palette.success
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                }
                // ── Blend line: a centred dot + "Blend <state> — <detail>". The dot is a real
                //    circle vertically centred with the text (the inline "●" glyph sat a touch
                //    low). Blue while mixing, gray otherwise; detail is the epoch event. ──
                Item {
                    id: blendWrap
                    width: parent.width
                    height: blendLbl.implicitHeight
                    visible: root.isRunning && root.blendText.length > 0
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 5
                        Rectangle {
                            width: 7; height: 7; radius: 3.5
                            color: root.blendColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        LogosText {
                            id: blendLbl
                            width: Math.min(implicitWidth, blendWrap.width - 12)
                            elide: Text.ElideRight
                            text: root.blendText
                                  + (root.blendEvent.length > 0 ? " — " + root.blendEvent : "")
                            color: root.blendColor
                            font.pixelSize: Theme.typography.secondaryText
                            font.weight: Theme.typography.weightMedium
                        }
                    }
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
                    // This is the LEADER FUNDING KEY's balance — the wallet that
                    // proposes blocks, receives leader rewards and pays claim fees.
                    // It is a different key from the node's first known address
                    // (ui#35), so the tooltip names it rather than leaving the
                    // reader to assume it matches the top of the Accounts list.
                    { label: qsTr("Balance"), value: root._fmtBalance(root.balanceText),
                      tip: root._balanceExact(root.balanceText)
                           + (root.leaderKey.length > 0
                              ? qsTr("\nLeader funding key %1…%2 — proposals, rewards and claim fees")
                                  .arg(root.leaderKey.substring(0, 8))
                                  .arg(root.leaderKey.slice(-6))
                              : "") },
                    { label: qsTr("Peers"),   value: root.peerCount >= 0 ? String(root.peerCount) : "—",
                      tip: root.connectionCount >= 0 ? qsTr("%1 connections").arg(root.connectionCount) : "" }
                ]
                // Shared with the Leader Rewards tiles (controls/StatTile.qml) so
                // the two pages cannot drift. FlashValue's behaviour moved into
                // the control as `flashOnChange`.
                delegate: StatTile {
                    label: modelData.label
                    value: modelData.value
                    // Click-to-open (i) rather than a hover tooltip — the Balance
                    // explanation is two lines and was unreadable on hover.
                    info: modelData.tip || ""
                    // Slot and Height tick constantly; the flash is what makes a
                    // live node visibly live.
                    flashOnChange: true
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
