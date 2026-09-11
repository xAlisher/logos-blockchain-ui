import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Settings — prototype. Node/Dev/Keys config (change · backup · apply=restart),
// bootstrap nodes, rewards/mining auto-claim, hardware caps, destructive actions.
// Mock local state; real wiring (file dialogs, zip backup, restart, backend
// toggles) lands later. Backup creates <filename>_backup_<date>.zip beside the file.
Item {
    id: root

    // mock state (would be fed from / written to config + backend)
    property string nodeConfigPath: "~/.logos/node/config.yaml"
    property string devConfigPath: "~/.logos/node/deployment.yaml"
    property string keysConfigPath: "~/.logos/node/keys.json"
    property string bootstrapIps: "104.21.5.11:3000\n172.67.190.44:3000"
    property bool rewardsAutoClaim: true
    property bool miningAutoClaim: true

    signal copyText(string t)
    signal keysBackedUp()          // Download keystore.yaml → host clears the "back up your keys" banner

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
        LogosButton { text: qsTr("Change") }
    }
    component SwitchRow: RowLayout {
        property string label: ""
        property string desc: ""
        property alias checked: sw.checked
        Layout.fillWidth: true; spacing: Theme.spacing.medium
        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            LogosText { text: label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText }
            LogosText { visible: desc.length > 0; text: desc; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        LogosSwitch { id: sw; Layout.alignment: Qt.AlignVCenter }
    }
    component CapRow: RowLayout {
        property string label: ""
        property string valueText: ""
        property string unit: "%"
        Layout.fillWidth: true; spacing: Theme.spacing.medium
        LogosText { text: label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
        LogosTextField { text: valueText; Layout.preferredWidth: 80; enabled: sw.checked }
        LogosText { text: unit; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter }
        Item { Layout.fillWidth: true }
        LogosSwitch { id: sw; Layout.alignment: Qt.AlignVCenter }
    }

    // red pill with white text (DS LogosButton has no danger variant)
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
            Layout.margins: Theme.spacing.xlarge     // side/top margins matching the dashboard (Layout.margins only applies inside a layout)
            spacing: Theme.spacing.large

            // NODE
            Card {
                heading: qsTr("Node")
                ConfigRow { label: qsTr("Node config"); path: root.nodeConfigPath }
                ConfigRow { label: qsTr("Dev config"); path: root.devConfigPath }
                ConfigRow { label: qsTr("Keys config"); path: root.keysConfigPath }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
                    LogosButton { text: qsTr("Apply"); variant: LogosButton.Variant.Primary }   // restarts the node
                    LogosText { text: qsTr("Applying restarts the node."); color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter; Layout.leftMargin: Theme.spacing.small }
                    Item { Layout.fillWidth: true }
                }
            }

            // BACK UP YOUR KEYS
            Card {
                heading: qsTr("Back up your keys")
                LogosText { text: qsTr("Your keystore holds the keys that control this node's identity, stake, and rewards. There is no way to recover them if lost. Download and store the file somewhere safe."); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.medium
                    LogosButton { text: qsTr("Download keystore.yaml"); variant: LogosButton.Variant.Primary; onClicked: root.keysBackedUp() }
                    Item { Layout.fillWidth: true }
                }
            }

            // BOOTSTRAP NODES
            Card {
                heading: qsTr("Bootstrap nodes")
                LogosText { text: qsTr("Peers the node dials on start, one per line (IP:port)."); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                LogosTextArea { text: root.bootstrapIps; Layout.fillWidth: true; Layout.preferredHeight: 96 }
                RowLayout { Layout.fillWidth: true; LogosButton { text: qsTr("Apply"); variant: LogosButton.Variant.Primary } Item { Layout.fillWidth: true } }
            }

            // REWARDS
            Card {
                heading: qsTr("Rewards")
                SwitchRow { label: qsTr("Auto-claim leader rewards"); desc: qsTr("Claim proposing rewards automatically in the background."); checked: root.rewardsAutoClaim }
            }

            // MINING
            Card {
                heading: qsTr("Mining")
                SwitchRow { label: qsTr("Auto-claim mined tickets"); desc: qsTr("Claim mined tickets automatically until the target balance is reached; otherwise claim manually."); checked: root.miningAutoClaim }
            }

            // HARDWARE
            Card {
                heading: qsTr("Hardware")
                CapRow { label: qsTr("CPU cap"); valueText: "80"; unit: "%" }
                CapRow { label: qsTr("RAM cap"); valueText: "80"; unit: "%" }
                CapRow { label: qsTr("Disk cap"); valueText: "50"; unit: "GB" }
                LogosText { text: qsTr("When the CPU or RAM cap is hit, the node stops automatically. When the disk cap is hit, older logs are pruned automatically."); color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
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
        rightActions: [ DangerButton { text: qsTr("Reset"); onClicked: resetDlg.close() } ]
    }
    LogosWarningDialog {
        id: regenDlg
        anchors.centerIn: parent; modal: true; width: 460
        title: qsTr("Regenerate keys?")
        message: qsTr("This creates a new node identity and Peer ID. Any stake, rewards or reputation tied to the current keys will no longer be reachable. Back up your keys first. This cannot be undone.")
        leftActions: [ LogosButton { text: qsTr("Cancel"); onClicked: regenDlg.close() } ]
        rightActions: [ DangerButton { text: qsTr("Regenerate"); onClicked: regenDlg.close() } ]
    }
}
