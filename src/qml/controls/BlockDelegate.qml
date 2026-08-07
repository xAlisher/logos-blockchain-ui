import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Collapsible card for a single block (BlockModel row).
//   Collapsed: timestamp · slot · version · tx count
//   Expanded:  header hashes, proof-of-leadership group, transactions list
// Unparsed payloads fall back to showing their raw text.
Rectangle {
    id: del

    signal copyToClipboard(string text)

    property bool expanded: false
    property bool proofExpanded: false

    // The transactions role is a QStringList; surface it for the Repeater.
    readonly property var transactionsList: model.transactions || []

    // Roles read as `undefined` during the brief QtRO replica sync at node
    // startup. Treat the fallback as active ONLY when the model says so
    // explicitly (parsed === false); undefined means "still loading", not
    // "unparsed" — otherwise freshly-arrived blocks flash as Unparsed.
    readonly property bool isUnparsed: model.parsed === false

    // Node's own leader key → this block was proposed by *your* node (#3).
    property string myKey: ""
    readonly property bool isMine: myKey.length > 0 && (model.leaderKey || "") === myKey

    // Collapse to zero height (used by the filtered Proposals view, #14).
    property bool collapsed: false

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: col.implicitHeight + 2 * Theme.spacing.medium
    visible: !collapsed
    height: collapsed ? 0 : implicitHeight
    clip: collapsed

    color: del.isMine ? Qt.rgba(Theme.palette.success.r, Theme.palette.success.g,
                                Theme.palette.success.b, 0.08)
                      : Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.width: 0                       // no stroke around block cards (isMine kept via fill)

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.medium
        spacing: Theme.spacing.small

        // ---- Summary row (always visible, toggles expansion) ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                text: del.expanded ? "▾" : "▸"
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosText {
                text: model.timestamp || ""
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            LogosText {
                visible: !del.isUnparsed
                text: qsTr("slot %1").arg(model.slot || qsTr("?"))
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            // "proposed by your node" badge — the payoff of funding/staking (#3).
            Rectangle {
                visible: del.isMine
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 18
                implicitWidth: mineRow.implicitWidth + 12
                radius: 9
                color: Qt.rgba(Theme.palette.success.r, Theme.palette.success.g,
                               Theme.palette.success.b, 0.18)
                Row {
                    id: mineRow
                    anchors.centerIn: parent
                    spacing: 3
                    LogosText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "◆"; color: Theme.palette.success; font.pixelSize: 9
                    }
                    LogosText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("your node"); color: Theme.palette.success
                        font.pixelSize: Theme.typography.secondaryText
                        font.weight: Theme.typography.weightMedium
                    }
                }
            }

            // Version badge
            Rectangle {
                visible: !del.isUnparsed && (model.version || "").length > 0
                radius: Theme.spacing.radiusSmall
                color: Theme.palette.backgroundSecondary
                border.color: Theme.palette.border
                border.width: 1
                implicitWidth: versionText.implicitWidth + 2 * Theme.spacing.small
                implicitHeight: versionText.implicitHeight + Theme.spacing.tiny
                LogosText {
                    id: versionText
                    anchors.centerIn: parent
                    text: model.version || ""
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }

            LogosText {
                visible: del.isUnparsed
                text: qsTr("Unparsed block")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.warning
            }

            Item { Layout.fillWidth: true }

            LogosText {
                visible: !del.isUnparsed
                text: qsTr("%1 tx").arg(model.txCount || 0)
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }

            TapHandler { onTapped: del.expanded = !del.expanded }
        }

        // ---- Expanded details ----
        ColumnLayout {
            Layout.fillWidth: true
            visible: del.expanded
            spacing: Theme.spacing.small

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.palette.borderSecondary
            }

            // Parsed: structured header
            HashRow {
                label: qsTr("Parent block"); value: model.parentBlock || ""; visible: !del.isUnparsed
                onCopyRequested: (t) => del.copyToClipboard(t)
            }
            HashRow {
                label: qsTr("Block root"); value: model.blockRoot || ""; visible: !del.isUnparsed
                onCopyRequested: (t) => del.copyToClipboard(t)
            }
            HashRow {
                label: qsTr("Signature"); value: model.signature || ""; visible: !del.isUnparsed
                onCopyRequested: (t) => del.copyToClipboard(t)
            }

            // Proof of leadership (collapsible sub-group)
            RowLayout {
                Layout.fillWidth: true
                visible: !del.isUnparsed
                spacing: Theme.spacing.small
                LogosText {
                    text: (del.proofExpanded ? "▾ " : "▸ ") + qsTr("Proof of leadership")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                TapHandler { onTapped: del.proofExpanded = !del.proofExpanded }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacing.medium
                visible: !del.isUnparsed && del.proofExpanded
                spacing: Theme.spacing.small
                HashRow { label: qsTr("Leader key"); value: model.leaderKey || ""; onCopyRequested: (t) => del.copyToClipboard(t) }
                HashRow { label: qsTr("Entropy");    value: model.entropy || "";   onCopyRequested: (t) => del.copyToClipboard(t) }
                HashRow { label: qsTr("Proof");      value: model.proof || "";     onCopyRequested: (t) => del.copyToClipboard(t) }
                HashRow { label: qsTr("Voucher cm"); value: model.voucherCm || ""; onCopyRequested: (t) => del.copyToClipboard(t) }
            }

            // Transactions
            LogosText {
                visible: !del.isUnparsed
                text: qsTr("Transactions (%1)").arg(model.txCount || 0)
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: !del.isUnparsed
                spacing: Theme.spacing.small

                Repeater {
                    model: del.expanded ? del.transactionsList : []
                    delegate: TransactionDelegate {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        idx: index
                        json: modelData
                        onCopyToClipboard: (t) => del.copyToClipboard(t)
                    }
                }

                LogosText {
                    visible: (model.txCount || 0) === 0
                    text: qsTr("No transactions in this block.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }

            // Unparsed: raw fallback
            RowLayout {
                Layout.fillWidth: true
                visible: del.isUnparsed
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Raw payload")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                BcCopyButton { onCopyText: del.copyToClipboard(model.rawJson || "") }
            }
            JsonBlock {
                Layout.fillWidth: true
                visible: del.isUnparsed
                json: model.rawJson || qsTr("(no payload)")
            }
        }
    }
}
