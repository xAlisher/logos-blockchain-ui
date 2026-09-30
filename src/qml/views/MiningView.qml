pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../amounts.js" as Amounts

// Proof-of-Work mining and claiming — fork-native (mirrors the official app's
// MiningView with this fork's control vocabulary: StatTile / CtaButton /
// GhostButton / LogosSwitch / LogosText).
//
// The one number that tells an operator whether claiming is working is the
// claimable ticket count and whether it MOVES: mining searches for tickets,
// unclaimed tickets expire, and auto-claim runs unattended and reports its
// failures only to the node log. Tickets climbing while nothing claims them is
// the failure this view exists to make visible (logos-blockchain-module#86).
//
// Presentational: the parent binds every property from the backend's Layer A PoW
// state and turns the signals below into pow_* calls. The settled-reward TALLY
// (a mining-reward total + a chain-scanned claim history) is Layer B, deferred —
// see the backend .rep note and #136.
ColumnLayout {
    id: root
    spacing: Theme.spacing.large

    readonly property real _inset: Theme.spacing.xlarge

    // --- Public API (bound from the backend's Layer A PoW props) ---
    property bool nodeRunning: false
    // The node's PoW service answers nothing until the chain is Online, so nothing
    // here can be read or changed before then.
    property bool chainOnline: false

    property int claimableTickets: 0
    property int soonestExpirySlots: -1
    property int soonestExpiryCount: 0
    property bool claimableLoaded: false
    property string claimableError: ""

    property bool powActive: false
    property bool miningActive: false
    property bool powStatusKnown: false
    property bool powRewardsEnabled: false
    property bool autoClaimArmed: false
    property bool autoClaimSelfDisarmed: false
    property int autoClaimTick: 0
    property string autoClaimTickUnit: ""
    // Rows of { address, thresholdLepta, balanceLepta, balanceKnown, reached, noCap }.
    property var claimTargets: []

    property bool miningBusy: false
    property bool claimBusy: false
    property bool claimSuccess: false
    property string claimMessage: ""

    // The pow section read by getPowConfig, handed to the embedded PowConfigView.
    property var powConfigSection: null
    property bool configBusy: false

    signal startMiningRequested()
    signal stopMiningRequested()
    // Empty address lets the node pay whichever target is furthest below threshold.
    signal claimRequested(string addressHex)
    signal autoClaimToggled(bool enabled)
    signal configureRequested(string configJson)

    QtObject {
        id: d
        readonly property string expiryCaption: {
            if (!root.claimableLoaded || root.soonestExpirySlots < 0)
                return ""
            return qsTr("%1 expiring in %2 slots")
                       .arg(root.soonestExpiryCount).arg(root.soonestExpirySlots)
        }
        // Tickets piling up with nothing to claim them — the state where the
        // numbers look healthy and every ticket expires.
        readonly property bool miningIntoNothing:
            root.powStatusKnown && root.miningActive && !root.autoClaimArmed
            && root.claimableTickets > 0
        readonly property string autoClaimHint: {
            if (!root.nodeRunning)
                return ""
            if (!root.powStatusKnown && !root.chainOnline)
                return qsTr("Available once the node is online.")
            if (!root.powStatusKnown)
                return qsTr("This node's module does not report auto-claim's state, so the "
                            + "switch shows what was last asked for.")
            if (root.claimTargets.length === 0)
                return qsTr("No auto-claim targets configured — add them under "
                            + "pow.auto_claim.targets in the config, then restart the node.")
            if (root.autoClaimSelfDisarmed)
                return qsTr("Every target has reached the balance it stops at, so the node "
                            + "turns auto-claim off again as soon as it is switched on. Raise "
                            + "a threshold in the config's pow section to resume.")
            if (root.autoClaimArmed && !root.miningActive)
                return qsTr("On, but there is nothing to claim until mining is running.")
            return ""
        }
    }

    // ── Header: mining on/off ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        spacing: Theme.spacing.medium

        ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            LogosText {
                text: qsTr("Mining")
                color: Theme.palette.text
                font.pixelSize: Theme.typography.subtitleText
                font.weight: Theme.typography.weightMedium
            }
            LogosText {
                text: root.miningActive
                      ? (root.powActive ? qsTr("Mining — finding tickets")
                                        : qsTr("Mining — no ticket activity yet"))
                      : qsTr("Mining searches for tickets; unclaimed tickets expire.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }
        }
        Item { Layout.fillWidth: true }

        CtaButton {
            objectName: "miningToggleButton"
            compact: true
            enabled: root.nodeRunning && (root.chainOnline || root.powStatusKnown)
                     && !root.miningBusy && (root.powStatusKnown ? root.powRewardsEnabled : true)
            text: root.miningBusy
                  ? (root.miningActive ? qsTr("Stopping…") : qsTr("Starting…"))
                  : (root.miningActive ? qsTr("Stop mining") : qsTr("Start mining"))
            onClicked: root.miningActive ? root.stopMiningRequested()
                                         : root.startMiningRequested()
        }
    }

    // ── Ticket counters ──────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        spacing: Theme.spacing.medium

        StatTile {
            Layout.fillWidth: true
            objectName: "claimableTicketsTile"
            label: qsTr("Ready to claim")
            value: root.claimableLoaded ? String(root.claimableTickets) : "—"
            sub: d.expiryCaption
            flashOnChange: root.visible
        }
        StatTile {
            Layout.fillWidth: true
            objectName: "miningStateTile"
            label: qsTr("Mining")
            value: !root.nodeRunning ? qsTr("Off")
                   : root.miningActive ? qsTr("On") : qsTr("Off")
            sub: root.miningActive
                 ? (root.powActive ? qsTr("active") : qsTr("idle"))
                 : (root.powStatusKnown && !root.powRewardsEnabled
                    ? qsTr("no rewards on this chain") : "")
        }
        StatTile {
            Layout.fillWidth: true
            objectName: "autoClaimStateTile"
            label: qsTr("Auto-claim")
            value: root.autoClaimArmed ? qsTr("On") : qsTr("Off")
            sub: root.autoClaimTick > 0
                 ? (root.autoClaimTickUnit === "slots"
                    ? qsTr("every %1 slots").arg(root.autoClaimTick)
                    : qsTr("every %1 s").arg(root.autoClaimTick))
                 : ""
        }
    }

    // ── Notices ──────────────────────────────────────────────────────────────
    LogosText {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        objectName: "claimableErrorNotice"
        visible: root.claimableError.length > 0
        text: qsTr("Can't read claimable tickets: %1").arg(root.claimableError)
        color: Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosText {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        objectName: "miningIntoNothingNotice"
        visible: d.miningIntoNothing
        text: root.autoClaimSelfDisarmed
              ? qsTr("Nothing is claiming these tickets: auto-claim is off and every target "
                     + "has reached the balance it stops at. Tickets expire unclaimed until a "
                     + "threshold is raised or you claim by hand below.")
              : qsTr("Nothing is claiming these tickets: mining is on and auto-claim is off. "
                     + "Tickets expire unclaimed until auto-claim is switched on or you claim "
                     + "by hand below.")
        color: Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    LogosText {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        objectName: "powRewardsDisabledNotice"
        visible: root.powStatusKnown && !root.powRewardsEnabled
        text: qsTr("This chain pays no mining rewards: the node reports PoW rewards as "
                   + "disabled for this deployment, so mining here produces nothing to claim.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    // ── Auto-claim ───────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        spacing: Theme.spacing.small

        LogosText {
            text: qsTr("Auto-claim")
            color: Theme.palette.text
            font.pixelSize: Theme.typography.secondaryText
            font.weight: Theme.typography.weightMedium
        }
        Item { Layout.fillWidth: true }
        LogosSwitch {
            objectName: "autoClaimSwitch"
            checked: root.autoClaimArmed
            // With no target the node refuses to arm and the switch snaps back, so
            // it can only be turned off then. A module without pow_status reports no
            // targets, which is not the same as having none.
            enabled: root.nodeRunning && (root.chainOnline || root.powStatusKnown)
                     && (root.autoClaimArmed || !root.powStatusKnown
                         || root.claimTargets.length > 0)
            onToggled: root.autoClaimToggled(checked)
        }
    }

    LogosText {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        objectName: "autoClaimHint"
        visible: text.length > 0
        text: d.autoClaimHint
        color: Theme.palette.textTertiary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    // Auto-claim targets (read-only; editing them is a config-side follow-up).
    Repeater {
        model: root.claimTargets
        delegate: RowLayout {
            id: targetRow
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: root._inset
            Layout.rightMargin: root._inset
            spacing: Theme.spacing.small

            LogosText {
                objectName: "claimTargetAddress"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: targetRow.modelData.address
                elide: Text.ElideMiddle
                font.family: Theme.typography.mono
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            LogosText {
                objectName: "claimTargetReached"
                visible: targetRow.modelData.reached === true
                text: qsTr("threshold reached")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }
            LogosText {
                objectName: "claimTargetBalance"
                text: {
                    var bal = targetRow.modelData.balanceKnown
                              ? Amounts.precise(targetRow.modelData.balanceLepta) : qsTr("—")
                    return targetRow.modelData.noCap
                           ? qsTr("%1 · no cap").arg(bal)
                           : qsTr("%1 / %2").arg(bal)
                                            .arg(Amounts.precise(targetRow.modelData.thresholdLepta))
                }
                color: Theme.palette.text
                font.pixelSize: Theme.typography.secondaryText
            }
        }
    }

    // ── Manual claim ─────────────────────────────────────────────────────────
    LogosText {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        Layout.topMargin: Theme.spacing.small
        text: qsTr("Pays the tickets mined so far. The node pays whichever claim target is "
                   + "furthest below its threshold — the same choice auto-claim makes.")
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        spacing: Theme.spacing.small

        CtaButton {
            objectName: "claimNowButton"
            compact: true
            text: root.claimBusy ? qsTr("Claiming…") : qsTr("Claim now")
            enabled: root.nodeRunning && !root.claimBusy && root.claimableTickets > 0
            // Empty address → let the node choose (mirrors auto-claim's choice).
            onClicked: root.claimRequested("")
        }
        LogosText {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            objectName: "claimResultText"
            visible: root.claimMessage.length > 0
            text: root.claimMessage
            color: root.claimSuccess ? Theme.palette.success : Theme.palette.error
            font.pixelSize: Theme.typography.secondaryText
            wrapMode: Text.WordWrap
        }
    }

    // ── Mining settings (embedded PowConfigView) ─────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: root._inset
        Layout.rightMargin: root._inset
        Layout.topMargin: Theme.spacing.medium
        color: Theme.palette.backgroundSecondary
        radius: Theme.spacing.radiusLarge
        border.color: Theme.palette.border
        border.width: 1
        implicitHeight: configCol.implicitHeight + 2 * Theme.spacing.large

        ColumnLayout {
            id: configCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.large
            spacing: Theme.spacing.medium

            PowConfigView {
                id: powConfig
                Layout.fillWidth: true
                busy: root.configBusy
                Component.onCompleted: loadFrom(root.powConfigSection)
            }
            Connections {
                target: root
                function onPowConfigSectionChanged() { powConfig.loadFrom(root.powConfigSection) }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                Item { Layout.fillWidth: true }
                GhostButton {
                    objectName: "powApplyConfigButton"
                    text: root.configBusy ? qsTr("Applying…") : qsTr("Apply settings")
                    enabled: powConfig.valid && !root.configBusy
                    onClicked: root.configureRequested(powConfig.configJson())
                }
            }

            LogosText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: qsTr("Applied to the config now; the node reads them the next time its "
                           + "mining starts.")
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
                wrapMode: Text.WordWrap
            }
        }
    }

    Item { Layout.fillHeight: true }
}
