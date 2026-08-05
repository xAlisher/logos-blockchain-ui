import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Structured view of a single block transaction (a SignedMantleTx JSON string).
//
// Shape (see nomos-node core/src/mantle):
//   { "mantle_tx": { "ops": [ {opcode, payload}, ... ] },
//     "ops_proofs": [ <proof>, ... ] }            // paired with ops by index
//
// Each op is labelled by its opcode name; the payload (and paired proof) are
// shown as prettified JSON. Unparsable transactions fall back to raw JSON.
ColumnLayout {
    id: txRoot

    property string json: ""
    property int idx: 0
    property bool open: false

    signal copyToClipboard(string text)

    readonly property var parsed: safeParse(json)
    readonly property bool parseFailed: parsed === null
    readonly property var ops: (parsed && parsed.mantle_tx && parsed.mantle_tx.ops)
        ? parsed.mantle_tx.ops : []
    readonly property var proofs: (parsed && parsed.ops_proofs) ? parsed.ops_proofs : []

    // Transaction id, if the block payload includes one. Falls back to the
    // positional "Transaction N" label when absent.
    readonly property string txId: (parsed && parsed.id) ? String(parsed.id) : ""

    spacing: Theme.spacing.tiny

    function safeParse(s) {
        try { return JSON.parse(s) } catch (e) { return null }
    }

    function opName(code) {
        switch (code) {
        case 0:  return qsTr("Transfer")
        case 16: return qsTr("Channel Config")
        case 17: return qsTr("Channel Inscribe")
        case 18: return qsTr("Channel Deposit")
        case 19: return qsTr("Channel Withdraw")
        case 32: return qsTr("SDP Declare")
        case 33: return qsTr("SDP Withdraw")
        case 34: return qsTr("SDP Active")
        case 48: return qsTr("Leader Claim")
        default: return qsTr("Op 0x%1").arg(Number(code).toString(16))
        }
    }

    function pretty(v) {
        try { return JSON.stringify(v, null, 2) } catch (e) { return String(v) }
    }

    function proofVariant(p) {
        if (!p || typeof p !== "object") return ""
        var ks = Object.keys(p)
        return ks.length ? ks[0] : ""
    }

    // ---- Header (toggle) ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: txRoot.open ? "▾" : "▸"
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
            TapHandler { onTapped: txRoot.open = !txRoot.open }
        }
        LogosText {
            // Show the tx id when present, else the positional label.
            Layout.fillWidth: true
            text: txRoot.txId !== "" ? txRoot.txId : qsTr("Transaction %1").arg(txRoot.idx + 1)
            elide: Text.ElideMiddle
            font.pixelSize: Theme.typography.secondaryText
            font.bold: true
            font.family: txRoot.txId !== "" ? "monospace" : Theme.typography.publicSans
            TapHandler { onTapped: txRoot.open = !txRoot.open }
        }
        BcCopyButton {
            // Copy the tx id when available, otherwise the full tx JSON.
            onCopyText: txRoot.copyToClipboard(txRoot.txId !== "" ? txRoot.txId : txRoot.json)
        }
    }

    // ---- Body ----
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.spacing.medium
        visible: txRoot.open
        spacing: Theme.spacing.small

        JsonBlock {
            Layout.fillWidth: true
            visible: txRoot.parseFailed
            json: txRoot.json
        }

        Repeater {
            model: txRoot.open && !txRoot.parseFailed ? txRoot.ops : []
            delegate: OpView {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                op: modelData
                proof: txRoot.proofs.length > index ? txRoot.proofs[index] : null
            }
        }
    }

    // ---- Inline: one operation (opcode name + payload/proof JSON) ----
    component OpView: ColumnLayout {
        id: opView
        property var op
        property var proof: null
        spacing: Theme.spacing.tiny

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Rectangle {
                radius: Theme.spacing.radiusSmall
                color: Theme.palette.backgroundSecondary
                border.color: Theme.palette.border
                border.width: 1
                implicitWidth: opcodeText.implicitWidth + 2 * Theme.spacing.small
                implicitHeight: opcodeText.implicitHeight + Theme.spacing.tiny
                LogosText {
                    id: opcodeText
                    anchors.centerIn: parent
                    text: qsTr("op %1").arg(opView.op && opView.op.opcode !== undefined ? opView.op.opcode : "?")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }
            LogosText {
                Layout.fillWidth: true
                text: txRoot.opName(opView.op ? opView.op.opcode : -1)
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
            BcCopyButton {
                onCopyText: txRoot.copyToClipboard(txRoot.pretty(opView.op ? opView.op.payload : null))
            }
        }

        // payload as JSON
        JsonBlock {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing.medium
            json: txRoot.pretty(opView.op ? opView.op.payload : null)
        }

        // paired proof
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing.medium
            visible: opView.proof !== null && opView.proof !== undefined
            spacing: Theme.spacing.small
            LogosText {
                text: qsTr("Proof · %1").arg(txRoot.proofVariant(opView.proof) || qsTr("unknown"))
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
            Item { Layout.fillWidth: true }
            BcCopyButton { onCopyText: txRoot.copyToClipboard(txRoot.pretty(opView.proof)) }
        }
        JsonBlock {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.spacing.medium
            visible: opView.proof !== null && opView.proof !== undefined
            json: (opView.proof !== null && opView.proof !== undefined) ? txRoot.pretty(opView.proof) : ""
        }
    }
}
