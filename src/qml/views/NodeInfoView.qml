import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// "Node info" card — node identity that doesn't depend on the consensus
// runtime. Currently the self libp2p peer id (derived from the user config).
Rectangle {
    id: root

    property string peerId: ""

    signal copyToClipboard(string text)

    implicitHeight: contentCol.implicitHeight + 2 * Theme.spacing.large
    color: Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.color: Theme.palette.border
    border.width: 1

    ColumnLayout {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.large
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Node info")
            font.pixelSize: Theme.typography.secondaryText
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                text: qsTr("Peer ID")
                Layout.preferredWidth: 70
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
            LogosText {
                Layout.fillWidth: true
                text: root.peerId || qsTr("—")
                elide: Text.ElideMiddle
                font.pixelSize: Theme.typography.secondaryText
            }
            BcCopyButton {
                Layout.preferredHeight: 24
                Layout.preferredWidth: 24
                visible: root.peerId.length > 0
                onCopyText: root.copyToClipboard(root.peerId)
            }
        }
    }
}
