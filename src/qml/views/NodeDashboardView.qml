import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import Logos.BlockchainBackend 1.0

// Redesigned node dashboard (epic #56). Tab nav + Status/Blend hero pair + 4×3 metric grid +
// Blocks/Proposals, all Logos DS, one Block component. Wired via properties fed by BlockchainView.
// Intermediate states use warning (yellow); Error = red; Online/active = success (green).
// Stubs (Blend/Peers/CPU/RAM/Empowering/Proposed) are marked TODO with their issue #.
Item {
    id: root
    implicitWidth: 1040
    implicitHeight: 900

    // ── WIRED inputs (fed by BlockchainView from the real backend) ──
    property int status: BlockchainBackend.Running          // #57 backend.status
    property bool nodeRecovering: false                     // #57 backend.nodeRecovering (replaying)
    property string lastErrorMessage: ""                    // backend.lastErrorMessage
    property string infoJson: ""                            // get_cryptarchia_info → slot/height/tip/lib/mode
    property string timeInfoJson: ""                        // get_time_info → current_slot
    property string peerId: ""                              // #63 getPeerId
    // ── derived from the JSON (mock fallback so it still renders standalone) ──
    function _parse(s) { try { return (s && s.length) ? JSON.parse(s) : null } catch (e) { return null } }
    function _short(s) { return (s && s.length > 14) ? (s.substring(0, 6) + "…" + s.substring(s.length - 4)) : (s || "") }
    readonly property var _info: _parse(infoJson)
    readonly property var _time: _parse(timeInfoJson)
    function _field(k) { if (!_info) return undefined; if (_info.cryptarchia_info && _info.cryptarchia_info[k] !== undefined) return _info.cryptarchia_info[k]; return _info[k] }
    readonly property string mode: (_info && _info.mode) ? String(_info.mode) : "Online"
    readonly property string slot: (_time && _time.current_slot !== undefined) ? String(_time.current_slot)
                                   : (_field("slot") !== undefined ? String(_field("slot")) : "151,548")
    readonly property string heightStr: _field("height") !== undefined ? String(_field("height")) : "151,548"
    readonly property string lib: _field("lib") ? _short(String(_field("lib"))) : "0x71bd…9e4a"
    readonly property string tip: _field("tip") ? _short(String(_field("tip"))) : "0x8a3f…c012"
    readonly property string peerIdShort: (peerId && peerId.length) ? _short(peerId) : "12D3…EwLz"
    // ── display-only / not-yet-wired (mocked; see issue refs) ──
    property string uptime: "345:43:23"
    property string replayProgress: "123 345 / 983 134"
    property string bootCountdown: "~59:59"
    property bool bootOverran: false
    property string foundingAddr: "0x71bd…9e4a"
    property string stakeStr: "5T LGO"                      // #59 (derive from balance later)
    property string earnedStr: "1530 LGO"                   // #60
    property string feePct: "56%"
    property string blendState: "edge"                      // #58: none | edge | core  (NOT in 0.3 API)
    property string epoch: "174"
    property int proposed: 234                              // #61
    property string validation: "active"                    // active | inactive
    property int epochsToActivate: 0
    property string peers: "83"                             // #62: NOT in 0.3 API (curl)
    property string connections: "87 connections"
    property string empowering: "Active"                    // #64: no API (#85)
    property string empoweringAmount: "123 345 LGO"
    property string cpu: "12%"                              // #65: no API (#89)
    property string cpuCap: "Cap: 30%"
    property string ram: "1.4GB"                            // #66: no API (#89)
    property string ramCap: "Cap not set"

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    // ── Status hero state → {label, sub, color} (design ref #57) ──
    readonly property var _st:
        status === BlockchainBackend.Error
            ? ({ label: qsTr("Error"), sub: (lastErrorMessage.length ? lastErrorMessage : qsTr("Honest error state is here.")), c: Theme.palette.error, copy: true })
      : nodeRecovering
            ? ({ label: qsTr("Replaying blocks…"), sub: replayProgress, c: Theme.palette.warning, copy: false })
      : status === BlockchainBackend.Starting
            ? ({ label: qsTr("Starting…"), sub: qsTr("Checking configuration"), c: Theme.palette.warning, copy: false })
      : (status === BlockchainBackend.Running && mode === "Bootstrapping")
            ? ({ label: qsTr("Bootstrapping…"), sub: (bootOverran ? qsTr("Takes a bit longer.") : bootCountdown), c: Theme.palette.warning, copy: false })
      : status === BlockchainBackend.Running
            ? ({ label: qsTr("Online"), sub: qsTr("Uptime: ") + uptime, c: Theme.palette.success, copy: true })
      : ({ label: qsTr("Not started"), sub: "", c: Theme.palette.textSecondary, copy: false })
    readonly property var _blend: blendState === "core" ? ({ label: qsTr("Core"), c: Theme.palette.info })
                                : blendState === "edge" ? ({ label: qsTr("Edge"), c: Theme.palette.info })
                                : ({ label: qsTr("Not active"), c: Theme.palette.text })
    readonly property string _proposedSub: validation === "active" ? qsTr("Validation active")
                                : (epochsToActivate > 0 ? qsTr("Validation inactive, %1 more epoch to activate").arg(epochsToActivate)
                                                        : qsTr("Validation inactive"))

    // ── shared bits ──
    component Info: Rectangle {
        width: 15; height: 15; radius: 8; color: "transparent"
        border.width: 1; border.color: Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.35)
        LogosText { anchors.centerIn: parent; text: "i"; font.pixelSize: 9; color: Theme.palette.textMuted }
    }
    component CopyGlyph: Canvas {
        implicitWidth: 16; implicitHeight: 16
        property color stroke: Theme.palette.textMuted
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            ctx.strokeStyle = stroke; ctx.lineWidth = 1.3; ctx.lineJoin = "round"; ctx.lineCap = "round";
            var r = 2, x = 1, y = 1, s = 9;
            ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + s, y, x + s, y + s, r); ctx.arcTo(x + s, y + s, x, y + s, r);
            ctx.arcTo(x, y + s, x, y, r); ctx.arcTo(x, y, x + s, y, r); ctx.closePath(); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(10, 5); ctx.lineTo(14 - r, 5); ctx.arcTo(14, 5, 14, 14, r);
            ctx.arcTo(14, 14, 5, 14, r); ctx.lineTo(5, 14); ctx.lineTo(5, 10); ctx.stroke();
        }
    }
    component Block: LogosFrame {
        property string label: ""
        property string value: "—"
        property string sub: ""
        property color accent: Theme.palette.text
        property color tint: Theme.palette.surfaceRaised
        property bool copyable: false
        property bool hero: false
        backgroundColor: hero ? Qt.rgba(tint.r, tint.g, tint.b, 0.12) : Theme.palette.surfaceRaised
        borderColor: "transparent"; radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        implicitHeight: hero ? 124 : 108
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout { Layout.fillWidth: true
                LogosText { text: label; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                Item { Layout.fillWidth: true }
                Info {} }
            LogosText { Layout.fillWidth: true; text: value; color: accent
                        font.pixelSize: hero ? 32 : 24; font.weight: Theme.typography.weightBold; elide: Text.ElideRight }
            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 16; spacing: Theme.spacing.small
                LogosText { visible: sub.length > 0; text: sub; color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText; elide: Text.ElideRight }
                CopyGlyph { visible: copyable && sub.length > 0; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true } }
        }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth
        ColumnLayout {
            width: root.width; spacing: 0
            // header
            RowLayout {
                Layout.fillWidth: true; Layout.margins: Theme.spacing.xlarge; spacing: Theme.spacing.medium
                LogosText { text: "λ"; color: Theme.palette.text; font.pixelSize: 24; font.weight: Theme.typography.weightBold }
                LogosText { text: qsTr("Blockchain Node"); color: Theme.palette.text; font.pixelSize: 21; font.weight: Theme.typography.weightBold }
                LogosText { text: "core 0.3.2 · UI 0.3.1 · testnet 0.3.2"; color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter }
                CopyGlyph { Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                LogosButton { text: qsTr("Start Empowering") }                                   // #64/#75
                LogosButton { text: qsTr("Stop Node"); variant: LogosButton.Variant.Primary }    // stopBlockchain()
            }
            LogosTabBar {
                Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.xlarge; Layout.rightMargin: Theme.spacing.xlarge; currentIndex: 0
                LogosTabButton { text: qsTr("Dashboard") }
                LogosTabButton { text: qsTr("Rewards") }
                LogosTabButton { text: qsTr("Empowering") }
                LogosTabButton { text: qsTr("Accounts") }
                LogosTabButton { text: qsTr("Explorer") }
                LogosTabButton { text: qsTr("Settings") }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: Theme.spacing.xlarge; spacing: Theme.spacing.large
                GridLayout {
                    Layout.fillWidth: true; columns: 2; columnSpacing: Theme.spacing.large; rowSpacing: Theme.spacing.large
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; hero: true; label: qsTr("Status"); value: root._st.label; sub: root._st.sub; accent: root._st.c; tint: root._st.c; copyable: root._st.copy }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; hero: true; label: qsTr("Blend"); value: root._blend.label; sub: qsTr("Epoch ") + root.epoch; accent: root._blend.c; tint: root._blend.c; copyable: true }
                }
                GridLayout {
                    Layout.fillWidth: true; columns: 4; columnSpacing: Theme.spacing.large; rowSpacing: Theme.spacing.large
                    Block { Layout.fillWidth: true; label: qsTr("Stake"); value: root.stakeStr; sub: root.foundingAddr; copyable: true }
                    Block { Layout.fillWidth: true; label: qsTr("Earned"); value: root.earnedStr; sub: qsTr("Fees this epoch: ") + root.feePct; copyable: true }
                    Block { Layout.fillWidth: true; label: qsTr("Proposed in epoch"); value: root.proposed + qsTr(" Blocks"); sub: root._proposedSub }
                    Block { Layout.fillWidth: true; label: qsTr("Peers"); value: root.peers; sub: root.connections }
                    Block { Layout.fillWidth: true; label: qsTr("Peer ID"); value: root.peerIdShort; sub: root.foundingAddr; copyable: true }
                    Block { Layout.fillWidth: true; label: qsTr("Empowering"); value: root.empowering; sub: root.empoweringAmount }
                    Block { Layout.fillWidth: true; label: qsTr("CPU"); value: root.cpu; sub: root.cpuCap }
                    Block { Layout.fillWidth: true; label: qsTr("RAM"); value: root.ram; sub: root.ramCap }
                    Block { Layout.fillWidth: true; label: qsTr("Slot"); value: root.slot }
                    Block { Layout.fillWidth: true; label: qsTr("Height"); value: root.heightStr }
                    Block { Layout.fillWidth: true; label: qsTr("LiB"); value: root.lib }
                    Block { Layout.fillWidth: true; label: qsTr("TiP"); value: root.tip }
                }
                // Blocks/Proposals table → reuse BlocksView / (1-click) ProposalsView (#68). Placeholder shell:
                LogosFrame {
                    Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                    radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
                    contentItem: LogosTabBar {
                        currentIndex: 0
                        LogosTabButton { text: qsTr("Blocks") }
                        LogosTabButton { text: qsTr("Proposals") }
                    }
                }
            }
        }
    }
}
