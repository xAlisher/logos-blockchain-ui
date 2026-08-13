import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Leader rewards panel: claim action plus a read-only, horizontally-sliding
// list of the wallet's claimable ("pending") vouchers with a count. The
// protocol picks which voucher a claim consumes — the list is informational.
ColumnLayout {
    id: root

    // JSON from wallet_get_claimable_vouchers:
    //   { "tip": "<hex>", "vouchers": [ {commitment, nullifier}, ... ] }
    property string vouchersJson: ""

    signal claimLeaderRewardsRequested()
    signal copyToClipboard(string text)

    function setLeaderClaimResult(text) {
        leaderClaimResultText.text = text
    }

    readonly property var _parsed: safeParse(vouchersJson)
    readonly property var vouchers: (_parsed && _parsed.vouchers)
        ? _parsed.vouchers
        : (Array.isArray(_parsed) ? _parsed : [])
    readonly property string tip: (_parsed && _parsed.tip) ? String(_parsed.tip) : ""

    function safeParse(s) {
        try { return s && s.length > 0 ? JSON.parse(s) : null } catch (e) { return null }
    }

    spacing: Theme.spacing.large

    // ---- Claimable vouchers card ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: vouchersCol.implicitHeight + 2 * Theme.spacing.large
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: vouchersCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosText {
                    text: qsTr("Claimable vouchers")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                // Pending counter badge
                Rectangle {
                    radius: Theme.spacing.radiusSmall
                    color: Theme.palette.backgroundSecondary
                    border.color: Theme.palette.border
                    border.width: 1
                    implicitWidth: pendingText.implicitWidth + 2 * Theme.spacing.small
                    implicitHeight: pendingText.implicitHeight + Theme.spacing.tiny
                    LogosText {
                        id: pendingText
                        anchors.centerIn: parent
                        text: qsTr("%1 pending").arg(root.vouchers.length)
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                    }
                }
                Item { Layout.fillWidth: true }
                LogosText {
                    visible: root.tip.length > 0
                    text: qsTr("tip %1").arg(root.tip)
                    elide: Text.ElideMiddle
                    Layout.maximumWidth: 140
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Claim block-leader rewards. The list shows your pending claimable vouchers (refreshed each block). Claim submits a claim transaction; the protocol selects which voucher it consumes.")
                }
            }

            // Horizontally-sliding list of voucher cards.
            ListView {
                id: vouchersList
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                visible: root.vouchers.length > 0
                orientation: ListView.Horizontal
                clip: true
                spacing: Theme.spacing.small
                model: root.vouchers
                snapMode: ListView.SnapToItem
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: 260
                    height: ListView.view.height
                    radius: Theme.spacing.radiusSmall
                    color: Theme.palette.backgroundSecondary
                    border.color: Theme.palette.border
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacing.small
                        spacing: Theme.spacing.tiny

                        LogosText {
                            text: qsTr("Voucher %1").arg(index + 1)
                            font.pixelSize: Theme.typography.secondaryText
                            font.bold: true
                            color: Theme.palette.textSecondary
                        }
                        VoucherField {
                            label: qsTr("cm")
                            value: modelData && modelData.commitment ? String(modelData.commitment) : ""
                        }
                        VoucherField {
                            label: qsTr("nf")
                            value: modelData && modelData.nullifier ? String(modelData.nullifier) : ""
                        }
                    }
                }
            }

            LogosText {
                visible: root.vouchers.length === 0
                text: qsTr("No claimable vouchers.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }

    // ---- Claim action ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: claimRow.height + 2 * Theme.spacing.large
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        RowLayout {
            id: claimRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacing.large

            LogosButton {
                id: leaderClaimButton
                Layout.preferredWidth: 140
                text: qsTr("Claim")
                onClicked: root.claimLeaderRewardsRequested()
            }

            LogosButton {
                Layout.fillWidth: true
                enabled: true
                padding: Theme.spacing.small
                contentItem: RowLayout {
                    width: parent.width
                    anchors.centerIn: parent
                    LogosText {
                        id: leaderClaimResultText
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
                        onCopyText: root.copyToClipboard(leaderClaimResultText.text)
                        visible: leaderClaimResultText.text
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }

    // A labelled, elided, copyable hash inside a voucher card.
    component VoucherField: RowLayout {
        id: vf
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Theme.spacing.tiny
        LogosText {
            text: vf.label
            Layout.preferredWidth: 20
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            text: vf.value || "—"
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
            font.family: "monospace"
        }
        BcCopyButton {
            Layout.preferredHeight: 24
            Layout.preferredWidth: 24
            visible: vf.value.length > 0
            onCopyText: root.copyToClipboard(vf.value)
        }
    }
}
