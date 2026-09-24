import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ItemDelegate {
    id: root

    property string balanceError: ""

    signal getBalanceRequested(string addressHex)
    signal fundRequested(string addressHex)
    signal copyRequested(string text)

    width: ListView.view ? ListView.view.width : implicitWidth

    background: Rectangle {
        color: root.hovered ? Theme.palette.backgroundSecondary : "transparent"
    }

    readonly property bool _fundable: model.fundable === true

    contentItem: ColumnLayout {
        spacing: 2

        // Row 1: the human LABEL (Wallet / Leader funding key / Blend public key …) + balance.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                Layout.fillWidth: true
                text: model.label || qsTr("Key")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }

            LogosText {
                Layout.preferredWidth: contentWidth
                Layout.alignment: Qt.AlignRight
                visible: root._fundable && (model.balance || "").length > 0
                text: model.balance || ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                elide: Text.ElideRight
            }

            // Fund — request test funds to this spendable key via the faucet (#117).
            LogosButton {
                visible: root._fundable
                Layout.alignment: Qt.AlignRight
                text: qsTr("Fund")
                padding: Theme.spacing.small
                onClicked: root.fundRequested(model.address || "")
            }

            // balance refresh — only for spendable/fundable keys
            Button {
                visible: root._fundable
                Layout.alignment: Qt.AlignRight
                Layout.leftMargin: parent.spacing
                Layout.preferredHeight: 32
                Layout.preferredWidth: 32
                display: AbstractButton.IconOnly
                flat: true
                icon.source: Qt.resolvedUrl("../icons/refresh.svg")
                icon.color: Theme.palette.textSecondary
                padding: 4
                onClicked: root.getBalanceRequested(model.address || "")
            }

            BcCopyButton {
                Layout.alignment: Qt.AlignRight
                Layout.preferredHeight: 32
                Layout.preferredWidth: 32
                onCopyText: root.copyRequested(model.address || "")
            }
        }

        // Row 2: the address itself (mono, elided) — the value the copy button yields.
        LogosText {
            Layout.fillWidth: true
            text: model.address || ""
            elide: Text.ElideMiddle
            font.pixelSize: 11
            font.family: "monospace"
            color: Theme.palette.textSecondary
        }

        // Row 3: one-line hint of what the key is FOR.
        LogosText {
            Layout.fillWidth: true
            visible: (model.hint || "").length > 0
            text: model.hint || ""
            font.pixelSize: 11
            color: Theme.palette.textTertiary
            wrapMode: Text.WordWrap
        }

        LogosText {
            Layout.fillWidth: true
            visible: !!text
            text: root.balanceError || ""
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.error
            wrapMode: Text.WordWrap
        }
    }
}
