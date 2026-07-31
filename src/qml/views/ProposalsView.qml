import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Blocks proposed by THIS node — the payoff of funding/staking (#14). Filters the
// live block stream to entries whose leader key matches the node's own key; each
// non-matching row collapses to zero height.
Control {
    id: root

    required property var blockModel
    property string myKey: ""

    signal copyToClipboard(string text)

    background: Rectangle { color: Theme.palette.background }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacing.small
        spacing: Theme.spacing.medium

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1

            ListView {
                id: lv
                anchors.fill: parent
                anchors.margins: Theme.spacing.small
                clip: true
                model: root.blockModel
                spacing: 0

                delegate: BlockDelegate {
                    myKey: root.myKey
                    // Show only blocks proposed by our node; collapse the rest.
                    collapsed: !(root.myKey.length > 0 && (model.leaderKey || "") === root.myKey)
                    onCopyToClipboard: (text) => root.copyToClipboard(text)
                }

                // Empty state — nothing of ours yet (all rows collapsed → ~0 content).
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.spacing.large
                    spacing: Theme.spacing.small
                    visible: lv.contentHeight < 4
                    LogosText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("No blocks proposed yet")
                        font.pixelSize: Theme.typography.subtitleText
                        font.weight: Theme.typography.weightMedium
                        color: Theme.palette.text
                    }
                    LogosText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: qsTr("Once your staked balance wins a leader slot, the blocks your "
                                   + "node proposes appear here automatically — you never click "
                                   + "“propose”.")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                }
            }
        }
    }
}
