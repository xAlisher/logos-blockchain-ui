import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ItemDelegate {
    id: root

    property string balanceError: ""

    signal getBalanceRequested(string addressHex)
    signal copyRequested(string text)

    width: ListView.view ? ListView.view.width : implicitWidth

    background: Rectangle {
        color: root.hovered ? Theme.palette.backgroundSecondary : "transparent"
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            LogosText {
                Layout.fillWidth: true
                text: model.address || ""
                elide: Text.ElideMiddle
                font.pixelSize: Theme.typography.secondaryText
            }

            LogosText {
                Layout.preferredWidth: contentWidth
                Layout.alignment: Qt.AlignRight
                visible: (model.balance || "").length > 0
                text: model.balance || ""
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
                elide: Text.ElideRight
            }

            Button {
                Layout.alignment: Qt.AlignRight
                Layout.leftMargin: parent.spacing
                Layout.preferredHeight: 40
                Layout.preferredWidth: 40
                display: AbstractButton.IconOnly
                flat: true
                icon.source: Qt.resolvedUrl("../icons/refresh.svg")
                icon.color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                padding: 4
                onClicked: root.getBalanceRequested(model.address || "")
            }

            BcCopyButton {
                Layout.alignment: Qt.AlignRight
                Layout.preferredHeight: 40
                Layout.preferredWidth: 40
                onCopyText: root.copyRequested(model.address || "")
            }
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
