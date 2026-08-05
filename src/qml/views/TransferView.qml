import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Transfer funds panel. Extracted from the former WalletView.
ColumnLayout {
    id: root

    required property var accountsModel

    signal transferRequested(string fromKeyHex, string toKeyHex, string amount)
    signal copyToClipboard(string text)

    function setTransferResult(text) {
        transferResultText.text = text
    }

    spacing: Theme.spacing.large

    Rectangle {
        id: transferRect

        Layout.fillWidth: true
        Layout.preferredHeight: transferCol.height + 2 * Theme.spacing.large
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: transferCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                LogosText {
                    text: qsTr("Transfer funds")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Send funds between addresses. Choose a source address (its balance is shown), enter the recipient key and amount, then press Send.")
                }
            }

            StyledAddressComboBox {
                id: transferFromCombo
                model: root.accountsModel
                textRole: "address"
            }

            LogosTextField {
                id: transferToField
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                placeholderText: qsTr("To key (64 hex chars)")
            }

            LogosTextField {
                id: transferAmountField
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                placeholderText: qsTr("Amount")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: transferButton.implicitHeight

                LogosButton {
                    id: transferButton
                    Layout.preferredWidth: 60
                    Layout.alignment: Qt.AlignRight
                    text: qsTr("Send")
                    onClicked: root.transferRequested(transferFromCombo.currentText.trim(), transferToField.text.trim(), transferAmountField.text)
                }

                LogosButton {
                    Layout.fillWidth: true
                    enabled: true
                    padding: Theme.spacing.small
                    contentItem: RowLayout {
                        width: parent.width
                        anchors.centerIn: parent
                        LogosText {
                            id: transferResultText
                            Layout.fillWidth: true
                            color: Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                            font.weight: Theme.typography.weightMedium
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }
                        BcCopyButton {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredHeight: 40
                            Layout.preferredWidth: 40
                            onCopyText: root.copyToClipboard(transferResultText.text)
                            visible: transferResultText.text
                        }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    component StyledAddressComboBox: ComboBox {
        id: comboControl

        Layout.fillWidth: true
        padding: Theme.spacing.large
        editable: true
        // Balance of the selected row, shown read-only in the closed box (the
        // editable text holds only the address — it's used as the transfer key).
        valueRole: "balance"
        font.pixelSize: Theme.typography.secondaryText

        background: Rectangle {
            color: Theme.palette.backgroundTertiary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1
        }
        indicator: LogosText {
            id: comboIndicator
            text: "▼"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            x: comboControl.width - width - Theme.spacing.small
            y: (comboControl.height - height) / 2
            visible: comboControl.count > 0
        }
        contentItem: Item {
            implicitWidth: 200
            implicitHeight: 30

            TextField {
                id: comboTextField
                anchors.fill: parent
                leftPadding: 0
                rightPadding: (comboControl.count > 0 ? comboIndicator.width + Theme.spacing.small : Theme.spacing.small)
                              + (balanceLabel.visible ? balanceLabel.width + Theme.spacing.small : 0)
                topPadding: 0
                bottomPadding: 0
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Theme.typography.secondaryText
                text: comboControl.editText
                onTextChanged: if (text !== comboControl.editText) comboControl.editText = text
                selectByMouse: true
                color: Theme.palette.text
                background: Item { }
            }
            LogosText {
                id: balanceLabel
                anchors.right: parent.right
                anchors.rightMargin: (comboControl.count > 0 ? comboIndicator.width + Theme.spacing.small : 0)
                                     + Theme.spacing.small
                anchors.verticalCenter: parent.verticalCenter
                visible: comboControl.currentIndex >= 0 && text.length > 0
                text: comboControl.currentValue || ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            MouseArea {
                anchors.fill: parent
                visible: comboControl.count > 0
                z: 1
                onPressed: {
                    comboControl.popup.visible ? comboControl.popup.close() : comboControl.popup.open()
                }
            }
        }
        delegate: ItemDelegate {
            id: comboDelegate
            width: comboControl.width
            contentItem: RowLayout {
                spacing: Theme.spacing.small
                LogosText {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight + Theme.spacing.large
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                    text: (typeof model.address !== "undefined" ? model.address : modelData) || ""
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                }
                LogosText {
                    visible: (typeof model.balance !== "undefined") && (model.balance || "").length > 0
                    text: model.balance || ""
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            background: Rectangle {
                color: comboDelegate.highlighted ?
                           Theme.palette.backgroundTertiary :
                           Theme.palette.backgroundSecondary
            }
            highlighted: comboControl.highlightedIndex === index
        }
        popup: Popup {
            y: comboControl.height - 1
            width: comboControl.width
            height: contentItem.implicitHeight
            padding: 1

            onOpened: if (comboControl.count === 0) close()

            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: comboControl.popup.visible ? comboControl.delegateModel : null
                ScrollIndicator.vertical: ScrollIndicator { }
                highlightFollowsCurrentItem: false
            }

            background: Rectangle {
                color: Theme.palette.backgroundSecondary
                border.color: Theme.palette.border
                border.width: 1
                radius: Theme.spacing.radiusLarge
            }
        }
    }
}
