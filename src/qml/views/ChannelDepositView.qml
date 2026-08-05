import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Multi-step wizard for channel_deposit_with_notes:
//   1. Select notes  → wallet_get_notes, pick UTXOs to consume
//   2. Fill fields   → channel id, change/funding keys, fee, metadata, tip
//   3. Confirm       → review the exact payload
//   4. Result        → tx hash (copyable) or error
ColumnLayout {
    id: root

    // Known wallet addresses (auto-remoted accounts model). Also used as
    // public keys for the change/funding key pickers.
    property var accountsModel: null
    property bool nodeRunning: false

    signal getNotesRequested(string addressHex, string optionalTipHex)
    signal submitRequested(string channelIdHex, var inputNoteIdHexes, string metadataBase58, string changePublicKeyHex, var fundingPublicKeyHexes, string maxTxFee, string optionalTipHex)
    signal copyToClipboard(string text)

    // --- Called by the parent after async backend calls return ---

    function setNotesLoading() {
        noteSelector.loading = true
        noteSelector.errorText = ""
    }

    function setNotes(jsonStr) {
        noteSelector.loading = false
        var s = jsonStr || ""
        try {
            var parsed = JSON.parse(s)
            d.notesTip = parsed.tip || ""
            noteSelector.errorText = ""
            noteSelector.notes = parsed.notes || []
        } catch (e) {
            noteSelector.errorText = qsTr("Failed to parse notes: %1").arg(s)
            noteSelector.notes = []
        }
    }

    function setNotesError(message) {
        noteSelector.loading = false
        noteSelector.errorText = message
        noteSelector.notes = []
    }

    function setSubmitResult(success, text) {
        d.resultPending = false
        d.resultSuccess = success
        d.resultText = text
    }

    spacing: Theme.spacing.large

    QtObject {
        id: d

        property int step: 0
        readonly property int stepCount: 4
        property string notesTip: ""

        // Address whose notes are currently loaded. Selecting/entering a
        // different address clears the old notes and loads the new ones.
        property string loadedAddress: ""

        // result state
        property bool resultPending: false
        property bool resultSuccess: false
        property string resultText: ""

        // Clear any loaded notes and (re)load for `addr` — but only when it
        // actually differs from what's already loaded.
        function loadNotesFor(addr) {
            var a = (addr || "").trim()
            if (a === "" || a === loadedAddress)
                return
            loadedAddress = a
            noteSelector.clearSelection()
            noteSelector.notes = []
            noteSelector.errorText = ""
            notesTip = ""
            if (!root.nodeRunning)
                return
            root.setNotesLoading()
            root.getNotesRequested(a, "")
        }

        function fundingKeyList() {
            return fundingKeysArea.text.split("\n")
                .map(function(s) { return s.trim() })
                .filter(function(s) { return s.length > 0 })
        }

        // --- Metadata (base58-encoded bytes) ---

        // The actual base58 → bytes decoding happens in the C++ backend; here we
        // only check the input uses the base58 (Bitcoin) alphabet. Plain base58
        // has no checksum, so a valid-alphabet string always decodes.
        function metadataIsValid() {
            var s = metadataField.text.trim()
            if (s === "")
                return true // optional
            return /^[1-9A-HJ-NP-Za-km-z]+$/.test(s)
        }

        function canAdvance() {
            switch (step) {
            case 0:
                return noteSelector.selectedCount > 0
            case 1:
                return channelIdField.text.trim().length > 0
                    && changeKeyField.text.trim().length > 0
                    && fundingKeyList().length > 0
                    && maxFeeField.text.trim().length > 0
                    && metadataIsValid()
            default:
                return true
            }
        }

        function goNext() {
            if (step === 1) {
                // entering confirm — nothing else
            }
            if (step < stepCount - 1)
                step++
            // Prefill key fields from the selected wallet when first reaching step 1.
            if (step === 1) {
                if (changeKeyField.text.trim() === "")
                    changeKeyField.text = walletField.text.trim()
                if (fundingKeysArea.text.trim() === "" && walletField.text.trim() !== "")
                    fundingKeysArea.text = walletField.text.trim()
            }
        }

        function goBack() {
            if (step > 0)
                step--
        }

        function submit() {
            d.resultPending = true
            d.resultSuccess = false
            d.resultText = ""
            step = 3
            root.submitRequested(
                channelIdField.text.trim(),
                noteSelector.selectedIds(),
                metadataField.text.trim(),
                changeKeyField.text.trim(),
                fundingKeyList(),
                maxFeeField.text.trim(),
                tipField.text.trim())
        }

        function reset() {
            noteSelector.clearSelection()
            noteSelector.notes = []
            noteSelector.errorText = ""
            walletField.text = ""
            loadedAddress = ""
            channelIdField.text = ""
            changeKeyField.text = ""
            fundingKeysArea.text = ""
            maxFeeField.text = ""
            metadataField.text = ""
            tipField.text = ""
            notesTip = ""
            resultText = ""
            resultPending = false
            step = 0
        }

        function summaryLines() {
            var ids = noteSelector.selectedIds()
            return [
                { k: qsTr("Channel ID"), v: channelIdField.text.trim() },
                { k: qsTr("Notes to consume (%1)").arg(ids.length), v: ids.join("\n") },
                { k: qsTr("Total amount"), v: String(noteSelector.selectedTotal) },
                { k: qsTr("Change public key"), v: changeKeyField.text.trim() },
                { k: qsTr("Funding public keys"), v: fundingKeyList().join("\n") },
                { k: qsTr("Max tx fee"), v: maxFeeField.text.trim() },
                { k: qsTr("Metadata (base58)"), v: metadataField.text.trim() || qsTr("(none)") },
                { k: qsTr("Optional tip hex"), v: tipField.text.trim() || qsTr("(current tip)") }
            ]
        }
    }

    // ---- Header / step indicator ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.medium

        LogosText {
            text: qsTr("Channel Deposit")
            font.pixelSize: Theme.typography.primaryText
            font.bold: true
        }
        Item { Layout.fillWidth: true }
        LogosText {
            text: qsTr("Step %1 of %2").arg(d.step + 1).arg(d.stepCount)
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        InfoButton {
            Layout.alignment: Qt.AlignVCenter
            text: qsTr("Deposit wallet notes (UTXOs) into a channel. Pick an address to load its notes, select the notes to consume, fill in the channel id, change/funding keys and max fee, then confirm to submit.")
        }
    }

    LogosText {
        Layout.fillWidth: true
        visible: !root.nodeRunning
        text: qsTr("Start the node before making a deposit.")
        color: Theme.palette.warning
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: d.step

        // ---- Step 0: Select notes ----
        ColumnLayout {
            spacing: Theme.spacing.medium

            LogosText {
                Layout.fillWidth: true
                text: qsTr("Select the notes (UTXOs) to deposit into the channel. Their full value is consumed.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosComboBox {
                    Layout.preferredWidth: 200
                    placeholderText: qsTr("Known address…")
                    model: root.accountsModel
                    textRole: "address"
                    currentIndex: -1
                    // Selecting a (different) known address loads its notes.
                    onActivated: function(index) {
                        walletField.text = currentText
                        d.loadNotesFor(currentText)
                    }
                }
                LogosTextField {
                    id: walletField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Wallet address hex")

                    // LogosTextField has no editingFinished; reach the inner
                    // TextInput. Manually entered address loads on commit
                    // (Enter / focus out).
                    Connections {
                        target: walletField.textInput
                        function onEditingFinished() { d.loadNotesFor(walletField.text) }
                    }
                }
            }

            NoteSelector {
                id: noteSelector
                Layout.fillWidth: true
            }

            Item { Layout.fillHeight: true }
        }

        // ---- Step 1: Fields ----
        ScrollView {
            id: fieldsScroll
            clip: true
            ColumnLayout {
                width: fieldsScroll.availableWidth
                spacing: Theme.spacing.medium

                LogosText {
                    text: qsTr("Channel ID hex")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTextField {
                    id: channelIdField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Channel ID hex")
                }

                LogosText {
                    text: qsTr("Change public key (receives change)")
                    font.pixelSize: Theme.typography.secondaryText
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosComboBox {
                        Layout.preferredWidth: 200
                        placeholderText: qsTr("Known address…")
                        model: root.accountsModel
                        textRole: "address"
                        currentIndex: -1
                        onActivated: function(index) { changeKeyField.text = currentText }
                    }
                    LogosTextField {
                        id: changeKeyField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Change public key hex")
                    }
                }

                LogosText {
                    text: qsTr("Funding public keys (one per line, fund the gas fee)")
                    font.pixelSize: Theme.typography.secondaryText
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    Item { Layout.fillWidth: true }
                    LogosComboBox {
                        Layout.preferredWidth: 220
                        placeholderText: qsTr("Add known address…")
                        model: root.accountsModel
                        textRole: "address"
                        currentIndex: -1
                        onActivated: function(index) {
                            var t = fundingKeysArea.text.trim()
                            fundingKeysArea.text = (t.length > 0 ? t + "\n" : "") + currentText
                        }
                    }
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 80
                    clip: true
                    TextArea {
                        id: fundingKeysArea
                        background: Rectangle {
                            radius: Theme.spacing.radiusSmall
                            color: Theme.palette.backgroundSecondary
                            border.width: 1
                            border.color: Theme.palette.backgroundElevated
                        }
                        placeholderText: qsTr("Funding public key hex, one per line")
                        placeholderTextColor: Theme.palette.textTertiary
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.text
                    }
                }

                LogosText {
                    text: qsTr("Max tx fee")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTextField {
                    id: maxFeeField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Maximum transaction fee")
                }

                LogosText {
                    text: qsTr("Metadata (base58, optional)")
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosTextField {
                    id: metadataField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Base58-encoded metadata bytes")
                }
                LogosText {
                    Layout.fillWidth: true
                    text: qsTr("Input must be base58-encoded; it is decoded to bytes before submission.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }
                LogosText {
                    Layout.fillWidth: true
                    visible: metadataField.text.trim() !== "" && !d.metadataIsValid()
                    text: qsTr("Invalid base58 input")
                    color: Theme.palette.error
                    font.pixelSize: Theme.typography.secondaryText
                    wrapMode: Text.WordWrap
                }

                LogosText {
                    text: qsTr("Optional tip hex (leave empty for current tip)")
                    font.pixelSize: Theme.typography.secondaryText
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosTextField {
                        id: tipField
                        Layout.fillWidth: true
                        placeholderText: qsTr("Tip hex")
                    }
                    LogosButton {
                        text: qsTr("Use query tip")
                        enabled: d.notesTip !== ""
                        onClicked: tipField.text = d.notesTip
                    }
                }
            }
        }

        // ---- Step 2: Confirm ----
        ColumnLayout {
            spacing: Theme.spacing.medium

            LogosText {
                Layout.fillWidth: true
                text: qsTr("Review the deposit. This is the exact payload that will be submitted.")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Theme.palette.backgroundTertiary
                radius: Theme.spacing.radiusLarge
                border.color: Theme.palette.border
                border.width: 1

                ScrollView {
                    id: confirmScroll
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.large
                    clip: true
                    ColumnLayout {
                        width: confirmScroll.availableWidth
                        spacing: Theme.spacing.medium
                        Repeater {
                            // Re-evaluated when the confirm step is shown so it
                            // reflects the latest field values.
                            model: d.step === 2 ? d.summaryLines() : []
                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.tiny
                                LogosText {
                                    text: modelData.k
                                    font.pixelSize: Theme.typography.secondaryText
                                    color: Theme.palette.textSecondary
                                }
                                LogosText {
                                    Layout.fillWidth: true
                                    text: modelData.v
                                    font.pixelSize: Theme.typography.secondaryText
                                    wrapMode: Text.WrapAnywhere
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Step 3: Result ----
        ColumnLayout {
            spacing: Theme.spacing.medium

            LogosText {
                Layout.alignment: Qt.AlignHCenter
                visible: d.resultPending
                text: qsTr("Submitting deposit…")
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                visible: d.resultPending
                running: d.resultPending
            }

            LogosText {
                Layout.fillWidth: true
                visible: !d.resultPending
                text: d.resultSuccess ? qsTr("Deposit submitted") : qsTr("Deposit failed")
                color: d.resultSuccess ? Theme.palette.success : Theme.palette.error
                font.pixelSize: Theme.typography.primaryText
                font.bold: true
            }

            // Success: tx hash + copy
            RowLayout {
                Layout.fillWidth: true
                visible: !d.resultPending && d.resultSuccess
                spacing: Theme.spacing.small
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: txHashText.implicitHeight + Theme.spacing.medium
                    color: Theme.palette.backgroundTertiary
                    radius: Theme.spacing.radiusSmall
                    border.color: Theme.palette.border
                    border.width: 1
                    LogosText {
                        id: txHashText
                        anchors.fill: parent
                        anchors.margins: Theme.spacing.small
                        text: d.resultText
                        font.pixelSize: Theme.typography.secondaryText
                        wrapMode: Text.WrapAnywhere
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                BcCopyButton {
                    Layout.preferredHeight: 40
                    Layout.preferredWidth: 40
                    onCopyText: root.copyToClipboard(d.resultText)
                }
            }

            // Error
            LogosText {
                Layout.fillWidth: true
                visible: !d.resultPending && !d.resultSuccess && d.resultText !== ""
                text: d.resultText
                color: Theme.palette.error
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ---- Footer navigation ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small

        LogosButton {
            text: qsTr("Back")
            visible: d.step > 0 && d.step < 3
            onClicked: d.goBack()
        }
        Item { Layout.fillWidth: true }

        // Steps 0 & 1: Next
        LogosButton {
            text: qsTr("Next")
            visible: d.step < 2
            enabled: d.canAdvance()
            onClicked: d.goNext()
        }
        // Step 2: Confirm & submit
        LogosButton {
            text: qsTr("Confirm & deposit")
            visible: d.step === 2
            enabled: root.nodeRunning
            onClicked: d.submit()
        }
        // Step 3: New deposit (after completion)
        LogosButton {
            text: qsTr("New deposit")
            visible: d.step === 3 && !d.resultPending
            onClicked: d.reset()
        }
    }
}
