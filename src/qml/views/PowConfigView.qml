pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Proof-of-Work mining settings, fork-native (mirrors the official app's
// PowConfigView with this fork's control vocabulary). The node reads every value
// here ONCE, when its PoW service starts — there is no runtime setter — so these
// are edited into the user config and applied by one powConfigure() call. A node
// restart is what makes a change take effect.
//
// Presentational: the parent reads configJson() on Apply and calls the backend.
// auto_claim_targets is passed through unchanged (target editing is a follow-up).
ColumnLayout {
    id: root
    spacing: Theme.spacing.medium

    // --- Public API ---
    property bool busy: false
    // Defaults are what a desktop node wants; an operator who does not care passes through.
    property int maxThreads: 1
    property int maxTicketsPerBlock: 2
    property int claimTickSeconds: 300

    readonly property bool valid: d.settingsValid()
    function configJson() { return d.buildConfigJson() }

    // Seed the fields from a pow section read by getPowConfig (QVariantMap → JS object).
    function loadFrom(section) {
        if (!section)
            return
        if (section.max_threads === null || section.max_threads === undefined) {
            d.autoThreads = true
        } else {
            d.autoThreads = false
            maxThreadsField.text = String(section.max_threads)
        }
        if (section.max_tickets_per_block)
            maxTicketsField.text = String(section.max_tickets_per_block)
        if (section.tick_seconds)
            claimTickField.text = String(section.tick_seconds)
        // Preserve any configured auto-claim targets verbatim across a save.
        d.autoClaimTargets = section.auto_claim_targets || []
    }

    QtObject {
        id: d
        property bool autoThreads: false
        property var autoClaimTargets: []

        // The node types the mining counts as non-zero integers, so a 0 is a
        // startup deserialization error — require each to parse as an int >= 1.
        function isPos(s) { var n = parseInt(s); return !isNaN(n) && n >= 1 }
        function settingsValid() {
            return (d.autoThreads || isPos(maxThreadsField.text))
                && isPos(maxTicketsField.text)
                && isPos(claimTickField.text)
        }

        // The whole pow section in one object — what powConfigure takes. The knobs
        // go with the targets so what this screen shows and what lands cannot drift.
        function buildConfigJson() {
            return JSON.stringify({
                max_threads: d.autoThreads ? null : parseInt(maxThreadsField.text),
                max_tickets_per_block: parseInt(maxTicketsField.text),
                tick_seconds: parseInt(claimTickField.text),
                auto_claim_targets: d.autoClaimTargets
            })
        }
    }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        text: qsTr("Mining settings")
        color: Theme.palette.text
        font.pixelSize: Theme.typography.secondaryText
        font.weight: Theme.typography.weightMedium
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        text: qsTr("Read once when the node's mining starts, so a change needs a node restart "
                   + "to take effect.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }

    // Search threads (Auto = let the node pick).
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Search threads")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosText {
            text: qsTr("Auto")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        LogosSwitch {
            objectName: "powAutoThreadsSwitch"
            enabled: !root.busy
            checked: d.autoThreads
            onToggled: d.autoThreads = checked
        }
        LogosTextField {
            id: maxThreadsField
            objectName: "powMaxThreadsField"
            Layout.preferredWidth: 90
            enabled: !root.busy
            visible: !d.autoThreads
            Component.onCompleted: text = String(root.maxThreads)
            validator: IntValidator { bottom: 1 }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Tickets in flight per block")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosTextField {
            id: maxTicketsField
            objectName: "powMaxTicketsField"
            Layout.preferredWidth: 90
            enabled: !root.busy
            Component.onCompleted: text = String(root.maxTicketsPerBlock)
            validator: IntValidator { bottom: 1 }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosText {
            text: qsTr("Claim attempt period (seconds)")
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        Item { Layout.fillWidth: true }
        LogosTextField {
            id: claimTickField
            objectName: "powClaimTickField"
            Layout.preferredWidth: 90
            enabled: !root.busy
            Component.onCompleted: text = String(root.claimTickSeconds)
            validator: IntValidator { bottom: 1 }
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        objectName: "powMiningFieldError"
        visible: !d.settingsValid()
        text: qsTr("Search threads, tickets per block and the claim period must each be a "
                   + "whole number of at least 1.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.error
        wrapMode: Text.WordWrap
    }
}
