import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Blocks THIS node proposed (#14). Cryptarchia leadership is private on-chain (each
// block's leader_key is per-note-derived), so we can't match blocks by a node key.
// Instead the backend parses the node's OWN log ("proposed block HeaderId(…)") — the
// authoritative record — same source the logos-node-dashboard uses. Plus a leadership
// voucher count (claimable rewards = blocks led).
Control {
    id: root

    property string proposalsJson: ""   // JSON array of {id, txs, removed, time}, newest first
    property int voucherCount: 0

    signal copyToClipboard(string text)

    readonly property var proposals: {
        try { return proposalsJson && proposalsJson.length > 0 ? JSON.parse(proposalsJson) : [] }
        catch (e) { return [] }
    }
    function shortId(h) { return h && h.length > 16 ? h.slice(0, 10) + "…" + h.slice(-6) : (h || "—") }

    background: Rectangle { color: Theme.palette.background }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacing.small
        spacing: Theme.spacing.medium

        // Summary row: leadership vouchers (rewards you can claim) + proposed count.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.large
            LogosText {
                text: qsTr("Leadership vouchers: %1").arg(root.voucherCount)
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
                color: root.voucherCount > 0 ? Theme.palette.success : Theme.palette.textSecondary
            }
            LogosText {
                text: qsTr("Proposed blocks: %1").arg(root.proposals.length)
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            Item { Layout.fillWidth: true }
        }

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
                model: root.proposals
                spacing: 2

                delegate: Rectangle {
                    width: lv.width
                    height: 40
                    color: "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacing.small
                        anchors.rightMargin: Theme.spacing.small
                        spacing: Theme.spacing.medium
                        LogosText {
                            text: (modelData.time || "")
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                            Layout.preferredWidth: 150
                        }
                        LogosText {
                            text: root.shortId(modelData.id)
                            font.family: "monospace"
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.text
                            Layout.fillWidth: true
                        }
                        LogosText {
                            text: qsTr("%1 tx").arg(modelData.txs !== undefined ? modelData.txs : 0)
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                            Layout.preferredWidth: 60
                            horizontalAlignment: Text.AlignRight
                        }
                        BcCopyButton {
                            onCopyText: root.copyToClipboard(modelData.id || "")
                        }
                    }
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        height: 1; color: Theme.palette.border; opacity: 0.5
                    }
                }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.spacing.large
                    spacing: Theme.spacing.small
                    visible: root.proposals.length === 0
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
