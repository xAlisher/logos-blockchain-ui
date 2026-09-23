import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Accounts panel: the list of known wallet addresses with per-account
// balance refresh and copy. Extracted from the former WalletView.
ColumnLayout {
    id: root

    required property var accountsModel

    property string lastBalanceError: ""
    property string lastBalanceErrorAddress: ""

    signal getBalanceRequested(string addressHex)
    signal fundRequested(string addressHex)
    signal refreshAccountsRequested()
    signal copyToClipboard(string text)

    spacing: Theme.spacing.large

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.large

            RowLayout {
                Layout.fillWidth: true
                LogosText {
                    text: qsTr("Accounts")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    text: qsTr("Refresh")
                    padding: Theme.spacing.small
                    onClicked: root.refreshAccountsRequested()
                }
                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Your wallet addresses and balances. Press Refresh to fetch the latest known addresses and their balances from the running node.")
                }
            }

            LogosText {
                text: qsTr("Start node to see accounts here.")
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                wrapMode: Text.WordWrap
                visible: balanceListView.count === 0
            }

            ListView {
                id: balanceListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.accountsModel
                spacing: Theme.spacing.small

                // Group into "Spendable" (wallet + funding keys, with balances) and
                // "Identity" (signing keys, copy-only). The backend emits them contiguously.
                section.property: "group"
                section.criteria: ViewSection.FullString
                section.delegate: LogosText {
                    required property string section
                    width: ListView.view ? ListView.view.width : implicitWidth
                    topPadding: Theme.spacing.small
                    text: section === "identity" ? qsTr("Identity keys") : qsTr("Spendable")
                    font.pixelSize: 11
                    font.bold: true
                    color: Theme.palette.textTertiary
                }

                delegate: AccountDelegate {
                    balanceError: root.lastBalanceErrorAddress === model.address ?
                                      root.lastBalanceError : ""
                    onGetBalanceRequested: (addr) => root.getBalanceRequested(addr)
                    onFundRequested: (addr) => root.fundRequested(addr)
                    onCopyRequested: (text) => root.copyToClipboard(text)
                }
            }
        }
    }
}
