import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Blocks THIS node proposed (#14). Cryptarchia leadership is private on-chain (each
// block's leader_key is per-note-derived), so we can't match blocks by a node key.
// Instead the backend parses the node's OWN log ("proposed block HeaderId(…)") — the
// authoritative record. Left: an epoch sidebar (All + each epoch present, current
// marked). Right: the proposals, grouped by epoch when All is selected.
Control {
    id: root

    property string proposalsJson: ""   // JSON array of {id, txs, removed, time}, newest first
    property int voucherCount: 0
    property int currentEpoch: -1       // chain's current epoch (sidebar marks it)

    signal copyToClipboard(string text)
    signal openLeaderRewardsRequested()
    signal clearRequested()             // host clears proposals-history.json

    // epoch_length is the testnet const (36000 slots · 1s · genesis 1788525000000 ms)
    // until the node exposes it (#61). Proposals carry only `time`, so derive epoch from it.
    function _pEpoch(t) {
        var ms = Date.parse(String(t).replace(" ", "T"))
        if (isNaN(ms)) return -1
        return Math.floor((ms - 1788525000000) / 1000 / 36000)
    }
    readonly property var proposals: {
        var arr
        try { arr = proposalsJson && proposalsJson.length > 0 ? JSON.parse(proposalsJson) : [] }
        catch (e) { return [] }
        var out = []
        for (var i = 0; i < arr.length; i++) {
            var p = arr[i]; var e = _pEpoch(p.time)
            out.push({ id: p.id, txs: p.txs, removed: p.removed, time: p.time,
                       epoch: e, epochLabel: e < 0 ? qsTr("Unknown epoch") : qsTr("Epoch %1").arg(e) })
        }
        return out
    }
    readonly property var epochsInData: {
        var seen = {}, list = []
        for (var i = 0; i < proposals.length; i++) { var e = proposals[i].epoch; if (e >= 0 && !seen[e]) { seen[e] = 1; list.push(e) } }
        list.sort(function(a, b) { return b - a })
        return list
    }
    // Blocks proposed per epoch, shown in the sidebar rows (epoch -> count).
    readonly property var proposalCounts: {
        var m = ({})
        for (var i = 0; i < proposals.length; i++) { var e = proposals[i].epoch; if (e >= 0) m[e] = (m[e] || 0) + 1 }
        return m
    }
    readonly property var filtered: {
        if (epochNav.selected === -1) return proposals
        var out = []
        for (var i = 0; i < proposals.length; i++) if (proposals[i].epoch === epochNav.selected) out.push(proposals[i])
        return out
    }
    function shortId(h) { return h && h.length > 16 ? h.slice(0, 10) + "…" + h.slice(-6) : (h || "—") }

    background: Rectangle { color: Theme.palette.background }

    RowLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacing.small
        spacing: Theme.spacing.large

        EpochNav {
            id: epochNav
            Layout.fillHeight: true
            epochs: root.epochsInData
            currentEpoch: root.currentEpoch
            counts: root.proposalCounts
            total: root.proposals.length
        }

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Theme.spacing.medium

            // Clear only — per-epoch counts now live in the sidebar rows, so the
            // "Leadership vouchers / Proposed blocks" summary line is gone.
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.large
                Item { Layout.fillWidth: true }
                LogosButton {
                    text: qsTr("Clear"); enabled: root.proposals.length > 0
                    onClicked: clearProposalsDlg.open()
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                color: Theme.palette.backgroundSecondary; radius: Theme.spacing.radiusLarge; border.width: 0

                ListView {
                    id: lv
                    anchors.fill: parent; anchors.margins: Theme.spacing.small
                    clip: true; spacing: 2
                    model: root.filtered
                    section.property: epochNav.selected === -1 ? "epochLabel" : ""
                    section.delegate: Rectangle {
                        width: lv.width; height: 26; color: "transparent"
                        LogosText {
                            anchors.left: parent.left; anchors.leftMargin: Theme.spacing.small
                            anchors.verticalCenter: parent.verticalCenter
                            text: section; color: Theme.palette.textTertiary
                            font.pixelSize: 11; font.weight: Theme.typography.weightBold
                        }
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Theme.palette.border; opacity: 0.5 }
                    }

                    delegate: Rectangle {
                        id: rowDelegate
                        width: lv.width; height: 40
                        color: rowHover.hovered ? Theme.palette.backgroundHover : "transparent"
                        radius: Theme.spacing.radiusSmall
                        HoverHandler { id: rowHover }
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: Theme.spacing.small; anchors.rightMargin: Theme.spacing.small
                            spacing: Theme.spacing.medium
                            LogosText { text: (modelData.time || ""); font.pixelSize: Theme.typography.secondaryText; color: Theme.palette.textSecondary; Layout.preferredWidth: 150 }
                            LogosText { text: root.shortId(modelData.id); font.family: "monospace"; font.pixelSize: Theme.typography.secondaryText; color: Theme.palette.text; Layout.fillWidth: true }
                            LogosText { text: qsTr("%1 tx").arg(modelData.txs !== undefined ? modelData.txs : 0); font.pixelSize: Theme.typography.secondaryText; color: Theme.palette.textSecondary; Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight }
                            Button {
                                id: copyBtn
                                property bool copied: false
                                flat: true; padding: 2; implicitWidth: 22; implicitHeight: 22
                                display: AbstractButton.IconOnly
                                icon.source: Qt.resolvedUrl("../icons/copy.svg"); icon.width: 14; icon.height: 14
                                icon.color: copied ? Theme.palette.primaryHover : (hovered ? Theme.palette.text : Theme.palette.textSecondary)
                                ToolTip.visible: hovered; ToolTip.text: copied ? qsTr("Copied") : qsTr("Copy")
                                onClicked: { root.copyToClipboard(modelData.id || ""); copied = true; copyReset.restart() }
                                Timer { id: copyReset; interval: 1200; onTriggered: copyBtn.copied = false }
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Theme.palette.border; opacity: 0.5 }
                    }

                    Column {
                        anchors.centerIn: parent; width: parent.width - 2 * Theme.spacing.large; spacing: Theme.spacing.small
                        visible: root.filtered.length === 0
                        LogosText { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("No blocks proposed yet"); font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightMedium; color: Theme.palette.text }
                        LogosText { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                            text: qsTr("Once your staked balance wins a leader slot, the blocks your node proposes appear here automatically — you never click “propose”.")
                            font.pixelSize: Theme.typography.secondaryText; color: Theme.palette.textSecondary }
                    }
                }
            }
        }
    }

    LogosWarningDialog {
        id: clearProposalsDlg
        anchors.centerIn: Overlay.overlay; modal: true; width: 460
        title: qsTr("Clear proposals?")
        message: qsTr("This clears the stored proposals history. Blocks your node proposes after this still appear. Use it after a chain reset or key change to drop stale entries.")
        leftActions: [ LogosButton { text: qsTr("Cancel"); onClicked: clearProposalsDlg.close() } ]
        rightActions: [ LogosButton { text: qsTr("Clear"); variant: LogosButton.Variant.Primary; onClicked: { clearProposalsDlg.close(); root.clearRequested() } } ]
    }
}
