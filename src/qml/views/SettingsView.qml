import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Settings — community preview. Every value here is fed from the live backend by the
// host (BlockchainView); nothing is mocked. Actions the 0.2.4 node has no direct API
// for are implemented as self-liquidating WORKAROUNDS (marked PREVIEW in the host):
//   • bootstrap peers  → generateConfig(edited peers) + restart
//   • hardware caps     → app-side enforcement using /proc CPU/RAM sampling
//   • config backup     → backend copies the file next to itself
// They graduate to the node's own API as it lands.
Item {
    id: root

    // Live backend state (fed by the host).
    property string nodeConfigPath: "—"
    property string devConfigPath: "—"
    property string keysConfigPath: "—"
    property string bootstrapPeers: ""           // real initial peers, one per line
    property bool rewardsAutoClaim: false
    property string cpuUsage: ""                  // real, from /proc sampling ("" = unknown)
    property string ramUsage: ""
    // Persisted caps (host-backed); enforcement runs app-side in the host.
    property string cpuCap: "80"
    property string ramCap: "80"
    property string diskCap: "50"
    property bool capsEnabled: false

    signal copyText(string t)
    signal resetChainRequested()
    signal regenerateKeysRequested()
    signal rewardsAutoClaimToggled(bool on)
    signal applyBootstrapPeers(string peersText)   // host: generateConfig + restart
    signal changeConfigRequested()                 // host: open the config setup screen
    signal backupConfigRequested()                 // host: copy the node config beside itself
    signal capsChanged(bool enabled, string cpu, string ram, string disk)

    // ---- reusable rows ----
    component Card: LogosFrame {
        default property alias body: col.data
        property string heading: ""
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
        radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        contentItem: ColumnLayout {
            id: col; spacing: Theme.spacing.medium
            LogosText { text: heading; color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold; visible: heading.length > 0 }
        }
    }
    component ConfigRow: RowLayout {
        property string label: ""
        property string path: ""
        Layout.fillWidth: true; spacing: Theme.spacing.medium
        LogosText { text: label; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
        LogosText { text: path; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; elide: Text.ElideMiddle; Layout.fillWidth: true }
        LogosButton { text: qsTr("Copy"); enabled: path.length > 0 && path !== "—"; onClicked: root.copyText(path) }
    }
    component SwitchRow: RowLayout {
        property string label: ""
        property string desc: ""
        property alias checked: sw.checked
        signal userToggled(bool on)
        Layout.fillWidth: true; spacing: Theme.spacing.medium
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            LogosText { text: label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText }
            LogosText { visible: desc.length > 0; text: desc; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        LogosSwitch { id: sw; Layout.alignment: Qt.AlignVCenter
            onCheckedChanged: if (checked !== root.rewardsAutoClaim) parent.userToggled(checked) }
    }
    // A cap row: label · current live usage · editable cap · unit.
    component CapRow: RowLayout {
        property string label: ""
        property string usage: ""              // live value (real), read-only
        property alias capValue: cap.text
        property string unit: "%"
        Layout.fillWidth: true; spacing: Theme.spacing.medium
        LogosText { text: label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 80 }
        LogosText { text: usage.length ? usage : "—"; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
        Item { Layout.fillWidth: true }
        LogosText { text: qsTr("cap"); color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter }
        LogosTextField { id: cap; Layout.preferredWidth: 70; enabled: root.capsEnabled }
        LogosText { text: unit; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter }
    }

    component DangerButton: Rectangle {
        id: db
        property alias text: lbl.text
        signal clicked()
        implicitHeight: Math.max(40, lbl.implicitHeight + 2 * Theme.spacing.medium)
        implicitWidth: lbl.implicitWidth + 2 * Theme.spacing.large
        radius: height / 2
        color: ma.pressed ? Theme.palette.errorPressed : (ma.containsMouse ? Theme.palette.errorHover : Theme.palette.error)
        LogosText { id: lbl; anchors.centerIn: parent; color: "#FFFFFF"; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightMedium }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: db.clicked() }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth
        ColumnLayout {
            width: root.width
            ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Theme.spacing.xlarge
            spacing: Theme.spacing.large

            // NODE
            Card {
                heading: qsTr("Node")
                ConfigRow { label: qsTr("Node config"); path: root.nodeConfigPath }
                ConfigRow { label: qsTr("Dev config"); path: root.devConfigPath }
                ConfigRow { label: qsTr("Keys config"); path: root.keysConfigPath }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.medium
                    LogosButton { text: qsTr("Change config"); onClicked: root.changeConfigRequested() }
                    LogosButton { text: qsTr("Back up config"); enabled: root.nodeConfigPath !== "—"; onClicked: root.backupConfigRequested() }
                    Item { Layout.fillWidth: true }
                }
            }

            // BOOTSTRAP NODES
            Card {
                heading: qsTr("Bootstrap nodes")
                LogosText { text: qsTr("Peers the node dials on start (libp2p multiaddrs, one per line). Applying regenerates the config and restarts the node."); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                LogosTextArea { id: peersArea; text: root.bootstrapPeers; Layout.fillWidth: true; Layout.preferredHeight: 120 }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.medium
                    LogosButton { text: qsTr("Apply"); variant: LogosButton.Variant.Primary; onClicked: root.applyBootstrapPeers(peersArea.text) }
                    LogosButton { text: qsTr("Reset to default"); onClicked: peersArea.text = root.bootstrapPeers }
                    Item { Layout.fillWidth: true }
                }
            }

            // REWARDS
            Card {
                heading: qsTr("Rewards")
                SwitchRow {
                    label: qsTr("Auto-claim leader rewards")
                    desc: qsTr("Claim proposing rewards automatically in the background.")
                    checked: root.rewardsAutoClaim
                    onUserToggled: (on) => root.rewardsAutoClaimToggled(on)
                }
            }

            // HARDWARE
            Card {
                heading: qsTr("Hardware")
                SwitchRow {
                    id: capsSwitch
                    label: qsTr("Enforce resource caps")
                    desc: qsTr("Stop the node if it exceeds the CPU or RAM cap; prune old logs at the disk cap. Enforced by the app while it's open.")
                    checked: root.capsEnabled
                    onUserToggled: (on) => root.capsChanged(on, cpuRow.capValue, ramRow.capValue, diskRow.capValue)
                }
                CapRow { id: cpuRow; label: qsTr("CPU"); usage: root.cpuUsage; capValue: root.cpuCap; unit: "%" }
                CapRow { id: ramRow; label: qsTr("RAM"); usage: root.ramUsage; capValue: root.ramCap; unit: "%" }
                CapRow { id: diskRow; label: qsTr("Disk"); usage: ""; capValue: root.diskCap; unit: "GB" }
                RowLayout {
                    Layout.fillWidth: true
                    LogosButton { text: qsTr("Apply caps"); enabled: root.capsEnabled; onClicked: root.capsChanged(true, cpuRow.capValue, ramRow.capValue, diskRow.capValue) }
                    Item { Layout.fillWidth: true }
                }
            }

            // DESTRUCTIVE
            Card {
                heading: qsTr("Destructive")
                LogosText { text: qsTr("These actions cannot be undone."); color: Theme.palette.error; font.pixelSize: Theme.typography.secondaryText }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.medium
                    DangerButton { text: qsTr("Reset chain state"); onClicked: resetDlg.open() }
                    DangerButton { text: qsTr("Regenerate keys"); onClicked: regenDlg.open() }
                    Item { Layout.fillWidth: true }
                }
            }
            Item { Layout.preferredHeight: Theme.spacing.large }
            }
        }
    }

    LogosWarningDialog {
        id: resetDlg
        anchors.centerIn: parent; modal: true; width: 460
        title: qsTr("Reset chain state?")
        message: qsTr("This deletes the node's local chain data and re-syncs from genesis. It can take a while and cannot be undone.")
        leftActions: [ LogosButton { text: qsTr("Cancel"); onClicked: resetDlg.close() } ]
        rightActions: [ DangerButton { text: qsTr("Reset"); onClicked: { resetDlg.close(); root.resetChainRequested() } } ]
    }
    LogosWarningDialog {
        id: regenDlg
        anchors.centerIn: parent; modal: true; width: 460
        title: qsTr("Regenerate keys?")
        message: qsTr("This creates a new node identity and Peer ID. Any stake, rewards or reputation tied to the current keys will no longer be reachable. Back up your keys first. This cannot be undone.")
        leftActions: [ LogosButton { text: qsTr("Cancel"); onClicked: regenDlg.close() } ]
        rightActions: [ DangerButton { text: qsTr("Regenerate"); onClicked: { regenDlg.close(); root.regenerateKeysRequested() } } ]
    }
}
