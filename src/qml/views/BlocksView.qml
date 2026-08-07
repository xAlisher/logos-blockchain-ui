import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Structured view of recent blocks (BlockModel). Newest block is at the top;
// only the latest 100 are retained by the model.
Control {
    id: root

    // --- Public API ---
    required property var blockModel
    property string myKey: ""   // node's own leader key → highlight our blocks (#3)

    signal clearRequested()
    signal copyToClipboard(string text)

    background: Rectangle {
        color: Theme.palette.background
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacing.small
        spacing: Theme.spacing.medium

        // Block list (the "Blocks" tab label is header enough)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge
            border.width: 0

            ListView {
                id: blocksListView
                anchors.fill: parent
                anchors.margins: Theme.spacing.small
                clip: true
                model: root.blockModel
                spacing: Theme.spacing.small

                delegate: BlockDelegate {
                    myKey: root.myKey
                    onCopyToClipboard: (text) => root.copyToClipboard(text)
                }

                LogosText {
                    // ListView's `count` has a NOTIFY signal, unlike the remoted
                    // model's own count property — use it for the empty state.
                    visible: blocksListView.count === 0
                    anchors.centerIn: parent
                    text: qsTr("No blocks yet...")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }
        }
    }
}
