import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Block/transaction explorer. The user pastes a block header id or a
// transaction hash; the lookup is auto-detected (block first, then tx —
// both are hex hashes and can't be told apart by shape) and the matching
// entity is rendered with every field copyable.
//
// Orchestration lives in BlockchainView: `searchRequested` triggers a
// get_block; on a miss it falls back to get_transaction. Results flow back
// through setBlockResult / setTransactionResult / setNotFound / setError.
ColumnLayout {
    id: root

    signal searchRequested(string id)
    signal copyToClipboard(string text)

    property bool nodeRunning: false

    // ---- Result state (driven by BlockchainView) ----
    //   kind: "" (none) | "block" | "transaction" | "notfound" | "error"
    property string kind: ""
    property string queriedId: ""
    property string rawJson: ""
    property string errorText: ""
    property bool busy: false

    // Block context for a transaction resolved from a loaded block (empty when
    // the tx came from the node's mempool lookup).
    property string txSlot: ""
    property string txBlockId: ""

    // Parsed block fields (populated when kind === "block").
    property var block: null

    function _reset() {
        root.kind = ""
        root.rawJson = ""
        root.errorText = ""
        root.block = null
        root.txSlot = ""
        root.txBlockId = ""
    }

    // Called by BlockchainView when a get_block succeeds. `value` is the JSON
    // string returned by the module (tolerant of a few nesting shapes, mirroring
    // BlockModel::appendRaw).
    function setBlockResult(id, value) {
        root.busy = false
        root._reset()
        root.queriedId = id
        root.kind = "block"
        root.rawJson = value
        root.block = parseBlock(value)
    }

    // `slot` / `blockId` are optional — supplied when the tx was resolved from
    // a loaded block, omitted for a pending mempool tx.
    function setTransactionResult(id, value, slot, blockId) {
        root.busy = false
        root._reset()
        root.queriedId = id
        root.kind = "transaction"
        root.rawJson = value
        root.txSlot = slot !== undefined && slot !== null ? String(slot) : ""
        root.txBlockId = blockId !== undefined && blockId !== null ? String(blockId) : ""
    }

    function setNotFound(id) {
        root.busy = false
        root._reset()
        root.queriedId = id
        root.kind = "notfound"
    }

    function setError(id, message) {
        root.busy = false
        root._reset()
        root.queriedId = id
        root.kind = "error"
        root.errorText = message
    }

    // Tolerant block parser mirroring BlockModel::appendRaw:
    //   { "block": "<stringified block>" } | { "block": {...} } | { "header": ... }
    // Returns a normalised object { header, slot, version, parentBlock, blockRoot,
    // signature, proof, entropy, leaderKey, voucherCm, transactions:[jsonStr] } or null.
    function parseBlock(s) {
        var obj = null
        try { obj = JSON.parse(s) } catch (e) { return null }
        if (!obj || typeof obj !== "object") return null

        var b = null
        if (obj.block !== undefined) {
            if (typeof obj.block === "string") {
                try { b = JSON.parse(obj.block) } catch (e) { b = null }
            } else if (typeof obj.block === "object") {
                b = obj.block
            }
        } else if (obj.header !== undefined) {
            b = obj
        }
        if (!b || typeof b !== "object") return null

        var header = b.header || {}
        var pol = header.proof_of_leadership || {}
        var txs = []
        var arr = b.transactions || []
        for (var i = 0; i < arr.length; ++i) {
            try { txs.push(JSON.stringify(arr[i])) }
            catch (e) { txs.push(String(arr[i])) }
        }
        return {
            slot: header.slot !== undefined ? String(header.slot) : "",
            version: header.version !== undefined ? String(header.version) : "",
            parentBlock: header.parent_block || "",
            blockRoot: header.block_root || "",
            signature: b.signature || "",
            proof: pol.proof || "",
            entropy: pol.entropy_contribution || "",
            leaderKey: pol.leader_key || "",
            voucherCm: pol.voucher_cm || "",
            transactions: txs
        }
    }

    function pretty(s) {
        try { return JSON.stringify(JSON.parse(s), null, 2) } catch (e) { return s }
    }

    function doSearch() {
        var id = idField.text.trim()
        if (id.length === 0) return
        root.busy = true
        root.searchRequested(id)
    }

    spacing: Theme.spacing.large

    // ---- Search bar ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: searchCol.implicitHeight + 2 * Theme.spacing.large
        color: Theme.palette.backgroundTertiary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1

        ColumnLayout {
            id: searchCol
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                LogosText {
                    text: qsTr("Explorer")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                InfoButton {
                    Layout.alignment: Qt.AlignVCenter
                    text: qsTr("Paste a block header id or a transaction hash, then press Search. The lookup is auto-detected: it tries a block first, then a transaction.")
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosTextField {
                    id: idField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30
                    placeholderText: qsTr("Block id or transaction hash (hex)")
                    enabled: root.nodeRunning && !root.busy

                    // LogosTextField wraps a TextInput (no `accepted` signal of
                    // its own); connect to the inner input to search on Enter.
                    Connections {
                        target: idField.textInput
                        function onAccepted() { root.doSearch() }
                    }
                }

                LogosButton {
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 30
                    text: root.busy ? qsTr("…") : qsTr("Search")
                    enabled: root.nodeRunning && !root.busy && idField.text.trim().length > 0
                    onClicked: root.doSearch()
                }
            }

            LogosText {
                Layout.fillWidth: true
                visible: !root.nodeRunning
                text: qsTr("Start the node to look up blocks and transactions.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }
        }
    }

    // ---- Status line (not found / error) ----
    LogosText {
        Layout.fillWidth: true
        visible: root.kind === "notfound" || root.kind === "error"
        text: root.kind === "notfound"
            ? qsTr("Nothing found for “%1”.\nBlocks are looked up by header id. Transactions resolve from the blocks currently loaded above, or from the node's mempool while still pending — mined transactions can't be fetched by hash, so open their block instead.").arg(root.queriedId)
            : root.errorText
        color: root.kind === "notfound" ? Theme.palette.textSecondary : Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    // ---- Result area ----
    ScrollView {
        id: resultScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.kind === "block" || root.kind === "transaction"
        clip: true

        ColumnLayout {
            width: resultScroll.availableWidth
            spacing: Theme.spacing.large

            // ---- Block result ----
            Rectangle {
                Layout.fillWidth: true
                visible: root.kind === "block"
                Layout.preferredHeight: blockCol.implicitHeight + 2 * Theme.spacing.large
                color: Theme.palette.backgroundTertiary
                radius: Theme.spacing.radiusLarge
                border.color: Theme.palette.border
                border.width: 1

                ColumnLayout {
                    id: blockCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.spacing.large
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small
                        LogosText {
                            text: qsTr("Block")
                            font.pixelSize: Theme.typography.secondaryText
                            font.bold: true
                        }
                        // slot / version badges
                        LogosText {
                            visible: root.block && root.block.slot.length > 0
                            text: qsTr("slot %1").arg(root.block ? root.block.slot : "")
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                        }
                        Rectangle {
                            visible: root.block && root.block.version.length > 0
                            radius: Theme.spacing.radiusSmall
                            color: Theme.palette.backgroundSecondary
                            border.color: Theme.palette.border
                            border.width: 1
                            implicitWidth: verText.implicitWidth + 2 * Theme.spacing.small
                            implicitHeight: verText.implicitHeight + Theme.spacing.tiny
                            LogosText {
                                id: verText
                                anchors.centerIn: parent
                                text: root.block ? root.block.version : ""
                                font.pixelSize: Theme.typography.secondaryText
                                color: Theme.palette.textSecondary
                            }
                        }
                        Item { Layout.fillWidth: true }
                        BcCopyButton {
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Copy raw block JSON")
                            onCopyText: root.copyToClipboard(root.pretty(root.rawJson))
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.palette.borderSecondary
                    }

                    HashRow {
                        label: qsTr("Block id"); value: root.queriedId
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        label: qsTr("Parent block"); value: root.block ? root.block.parentBlock : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        label: qsTr("Block root"); value: root.block ? root.block.blockRoot : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        label: qsTr("Signature"); value: root.block ? root.block.signature : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }

                    LogosText {
                        text: qsTr("Proof of leadership")
                        font.pixelSize: Theme.typography.secondaryText
                        font.bold: true
                        Layout.topMargin: Theme.spacing.small
                    }
                    HashRow {
                        label: qsTr("Leader key"); value: root.block ? root.block.leaderKey : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        label: qsTr("Entropy"); value: root.block ? root.block.entropy : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        label: qsTr("Proof"); value: root.block ? root.block.proof : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        label: qsTr("Voucher cm"); value: root.block ? root.block.voucherCm : ""
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }

                    LogosText {
                        text: qsTr("Transactions (%1)").arg(root.block ? root.block.transactions.length : 0)
                        font.pixelSize: Theme.typography.secondaryText
                        font.bold: true
                        Layout.topMargin: Theme.spacing.small
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small

                        Repeater {
                            model: root.block ? root.block.transactions : []
                            delegate: TransactionDelegate {
                                required property int index
                                required property string modelData
                                Layout.fillWidth: true
                                idx: index
                                json: modelData
                                onCopyToClipboard: (t) => root.copyToClipboard(t)
                            }
                        }
                        LogosText {
                            visible: root.block && root.block.transactions.length === 0
                            text: qsTr("No transactions in this block.")
                            color: Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                        }
                    }
                }
            }

            // ---- Transaction result ----
            Rectangle {
                Layout.fillWidth: true
                visible: root.kind === "transaction"
                Layout.preferredHeight: txCol.implicitHeight + 2 * Theme.spacing.large
                color: Theme.palette.backgroundTertiary
                radius: Theme.spacing.radiusLarge
                border.color: Theme.palette.border
                border.width: 1

                ColumnLayout {
                    id: txCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.spacing.large
                    spacing: Theme.spacing.small

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.small
                        LogosText {
                            text: qsTr("Transaction")
                            font.pixelSize: Theme.typography.secondaryText
                            font.bold: true
                        }
                        LogosText {
                            visible: root.txSlot.length > 0
                            text: qsTr("in block · slot %1").arg(root.txSlot)
                            font.pixelSize: Theme.typography.secondaryText
                            color: Theme.palette.textSecondary
                        }
                        Item { Layout.fillWidth: true }
                        BcCopyButton {
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("Copy raw transaction JSON")
                            onCopyText: root.copyToClipboard(root.pretty(root.rawJson))
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.palette.borderSecondary
                    }

                    HashRow {
                        label: qsTr("Transaction id"); value: root.queriedId
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }
                    HashRow {
                        visible: root.txBlockId.length > 0
                        label: qsTr("Block id"); value: root.txBlockId
                        onCopyRequested: (t) => root.copyToClipboard(t)
                    }

                    TransactionDelegate {
                        Layout.fillWidth: true
                        idx: 0
                        json: root.rawJson
                        open: true
                        onCopyToClipboard: (t) => root.copyToClipboard(t)
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
        visible: root.kind === "" || root.kind === "notfound" || root.kind === "error"
    }
}
