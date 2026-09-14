import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Blocks page. A block/transaction explorer sits on top (spanning both columns);
// searching shows the result there, and clearing it (the ✕ in the field) returns
// to the block list below: an epoch sidebar + the recent blocks, grouped by epoch
// under "All epochs" and filtered to one epoch otherwise.
Control {
    id: root

    required property var blockModel
    property string myKey: ""       // node's own leader key → highlight our blocks (#3)
    property int currentEpoch: -1   // chain's current epoch (sidebar marks it)
    property bool nodeRunning: false
    property bool bootstrapping: false   // node running but not yet synced (IBD replay)

    signal clearRequested()
    signal copyToClipboard(string text)
    signal searchRequested(string id)   // host orchestrates the block/tx lookup

    // Host feeds explorer results back through these (delegated to the embedded view).
    function setBlockResult(id, v) { explorer.setBlockResult(id, v) }
    function setTransactionResult(id, v, s, b) { explorer.setTransactionResult(id, v, s, b) }
    function setNotFound(id) { explorer.setNotFound(id) }
    function setError(id, m) { explorer.setError(id, m) }

    background: Rectangle { color: Theme.palette.background }

    // Epochs present in the (remoted) model — delegates read the `epoch` role.
    Instantiator {
        id: epochCollector
        model: root.blockModel
        delegate: QtObject { property int e: (model.epoch !== undefined ? model.epoch : -1) }
        property var epochs: []
        function rebuild() {
            var seen = ({}), list = []
            for (var i = 0; i < count; i++) { var o = objectAt(i); var e = o ? o.e : -1; if (e >= 0 && !seen[e]) { seen[e] = 1; list.push(e) } }
            list.sort(function(a, b) { return b - a }); epochs = list
        }
        onCountChanged: rebuild()
        onObjectAdded: rebuild()
        onObjectRemoved: rebuild()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Theme.spacing.small
        spacing: Theme.spacing.large

        // Explorer on top (both columns). Fills only when it has a result to show.
        ExplorerView {
            id: explorer
            Layout.fillWidth: true
            Layout.fillHeight: explorer.hasResult
            nodeRunning: root.nodeRunning
            onSearchRequested: (id) => root.searchRequested(id)
            onCopyToClipboard: (t) => root.copyToClipboard(t)
        }

        // Block list (epoch sidebar + list) — shown when there's no explorer result.
        RowLayout {
            visible: !explorer.hasResult
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Theme.spacing.large

            EpochNav {
                id: epochNav
                Layout.fillHeight: true
                epochs: epochCollector.epochs
                currentEpoch: root.currentEpoch
                bootstrapping: root.bootstrapping
            }

            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                // Unified: transparent list surface — the row cards carry the visual
                // weight, so no extra container fill or stroke behind them.
                color: "transparent"; border.width: 0

                ListView {
                    id: blocksListView
                    anchors.fill: parent
                    clip: true; spacing: Theme.spacing.small
                    model: root.blockModel

                    // No epoch grouping during IBD (headers would churn 0,1,2… as it replays).
                    section.property: (root.bootstrapping || epochNav.selected !== -1) ? "" : "epoch"
                    section.delegate: Rectangle {
                        // Taller header: label + divider sit up top, leaving a gap
                        // below the divider before the first block card.
                        width: blocksListView.width; height: 44; color: "transparent"
                        LogosText {
                            id: secLabel
                            anchors.left: parent.left; anchors.leftMargin: Theme.spacing.small
                            anchors.top: parent.top; anchors.topMargin: Theme.spacing.tiny
                            text: qsTr("Epoch %1").arg(section)
                            color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold
                        }
                        Rectangle { anchors.top: secLabel.bottom; anchors.topMargin: Theme.spacing.small; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Theme.palette.border; opacity: 0.5 }
                    }

                    delegate: BlockDelegate {
                        myKey: root.myKey
                        collapsed: epochNav.selected !== -1 && (model.epoch === undefined || model.epoch !== epochNav.selected)
                        onCopyToClipboard: (text) => root.copyToClipboard(text)
                    }

                    LogosText {
                        visible: blocksListView.count === 0
                        anchors.centerIn: parent
                        text: qsTr("No blocks yet...")
                        font.pixelSize: Theme.typography.secondaryText; color: Theme.palette.textSecondary
                    }
                }
            }
        }
    }
}
