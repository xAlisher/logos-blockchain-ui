import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Leader rewards: a fungible voucher POOL plus a permanent CLAIMS LEDGER.
//
// Deliberately not a board with a column per state. Vouchers are interchangeable
// (every one is worth the same reward), the operator moves nothing — the protocol
// does, on a timer — and the fact that matters most is a duration ("~2h to settle"),
// which columns cannot express. So: the pool is a quantity, and the state machine
// belongs to the CLAIM, which has identity, cost, duration and an outcome.
//
// Design and the evidence behind it: docs/VOUCHER-STATE-MAP.md
ScrollView {
    id: root
    clip: true

    // JSON from wallet_get_claimable_vouchers:
    //   { "tip": "<hex>", "vouchers": [ {commitment, nullifier}, ... ] }
    // NOTE: the node computes ClaimableVouchers { available, pending } and this
    // endpoint returns .available ONLY. These are vouchers that are READY — the
    // node's own "pending" (reserved, claim in flight) never reaches the UI.
    property string vouchersJson: ""

    // JSON from getLeaderClaims(): { claims: [...], summary: {...} }
    property string claimsJson: ""

    // Wallet balance in base units, for the claim gate. -1 = not yet known.
    property real balance: -1

    // True from the moment Claim is pressed until the call returns. Without this
    // the button stays live with no acknowledgement, and a second press spends a
    // second voucher and a second fee.
    property bool claimInFlight: false

    signal claimLeaderRewardsRequested()
    signal copyToClipboard(string text)

    function setLeaderClaimResult(text) {
        root._lastResult = text
    }
    property string _lastResult: ""

    // ---- parsed state ----
    function safeParse(s) {
        try { return s && s.length > 0 ? JSON.parse(s) : null } catch (e) { return null }
    }

    readonly property var _parsed: safeParse(vouchersJson)
    readonly property var vouchers: (_parsed && _parsed.vouchers)
        ? _parsed.vouchers
        : (Array.isArray(_parsed) ? _parsed : [])
    readonly property string tip: (_parsed && _parsed.tip) ? String(_parsed.tip) : ""

    readonly property var _ledger: safeParse(claimsJson)
    readonly property var claims: (_ledger && _ledger.claims) ? _ledger.claims : []
    readonly property var summary: (_ledger && _ledger.summary) ? _ledger.summary : null

    // Claims we submitted that have not settled. This counts CLAIMS from our own
    // ledger, not vouchers: the node's reserved-voucher list is never sent to us.
    readonly property int claimingCount: root.summary ? (root.summary.inFlight || 0) : 0

    // Reward per claim is read from ledger state at execution and CAN change, so
    // the pool's value is an estimate from the most recent settled claim.
    readonly property real lastReward: {
        for (var i = 0; i < claims.length; ++i)
            if (claims[i].status === "settled" && claims[i].reward > 0)
                return claims[i].reward
        return 0
    }
    readonly property real lastFee: {
        for (var i = 0; i < claims.length; ++i)
            if (claims[i].status === "settled" && claims[i].fee > 0)
                return claims[i].fee
        return 0
    }

    readonly property bool canClaim: vouchers.length > 0 && balance > 0 && !claimInFlight
    readonly property string claimBlockedReason: {
        if (claimInFlight) return qsTr("Claim in flight — wait for it to be submitted.")
        if (vouchers.length === 0) return qsTr("No vouchers ready to claim.")
        if (balance === 0) return qsTr("Not enough balance to pay the claim fee.")
        if (balance < 0) return qsTr("Waiting for the wallet balance…")
        return ""
    }

    function fmt(n) {
        if (n === undefined || n === null || isNaN(n)) return "—"
        return Number(n).toLocaleString(Qt.locale(), "f", 0)
    }

    // Claim status → colour. NOTE: Theme.palette.orange does NOT exist on
    // DarkTheme (only overlayOrange does) — an undefined colour renders BLACK,
    // which is what made "Submitted" invisible. Only tokens defined in
    // DarkTheme.qml are used here.
    //   submitted #FEBC2E warning  — waiting, nothing wrong
    //   in_block  #ED7B58 primary  — moving, not yet final
    //   settled   #49F563 success  — done
    //   expired   #969696 tertiary — inert; costs nothing, so NOT red
    // red (error) stays reserved for a claim that actually failed.
    function statusColor(st) {
        if (st === "settled")  return Theme.palette.success
        if (st === "in_block") return Theme.palette.primary
        if (st === "expired")  return Theme.palette.textTertiary
        if (st === "error")    return Theme.palette.error
        return Theme.palette.warning
    }
    function statusLabel(st) {
        if (st === "settled")  return qsTr("Settled")
        if (st === "in_block") return qsTr("In a block")
        if (st === "expired")  return qsTr("Expired")
        if (st === "error")    return qsTr("Failed")
        return qsTr("Submitted")
    }

    // The page outgrows the pane once the claims ledger fills, so the whole
    // thing scrolls. Same pattern as ChannelDepositView.
    ColumnLayout {
        width: root.availableWidth
        spacing: Theme.spacing.large

        // ======================= PAGE TITLE (outside the boxes) =======================
        LogosText {
            text: qsTr("Leader Rewards")
            font.pixelSize: Theme.typography.titleText
            font.weight: Theme.typography.weightMedium
        }

        // ======================= VOUCHERS =======================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: poolCol.implicitHeight + 2 * Theme.spacing.large
            color: Theme.palette.backgroundTertiary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1

            ColumnLayout {
                id: poolCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacing.large
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosText {
                        text: qsTr("Vouchers")
                        font.pixelSize: Theme.typography.secondaryText
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    InfoButton {
                        Layout.alignment: Qt.AlignVCenter
                        text: qsTr("Vouchers you earned by leading a block. \"Ready\" means provable at the current tip; the protocol picks which one a claim consumes. A claim is itself a transaction, so it costs a fee — you need a balance to claim. Claims are public: the claim carries your public key in the clear on chain.")
                    }
                }

                // "ready" is the node's `available`. "claiming" counts our own
                // submitted-but-unsettled claims — the node's reserved-voucher list
                // is never sent to the UI, so we cannot report its `pending`.
                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    text: root.claimingCount > 0
                        ? qsTr("%1 ready to claim, %2 claiming")
                            .arg(root.vouchers.length).arg(root.claimingCount)
                        : qsTr("%1 ready to claim").arg(root.vouchers.length)
                }

                LogosButton {
                    id: claimButton
                    Layout.topMargin: Theme.spacing.small
                    Layout.preferredWidth: 200
                    enabled: root.canClaim
                    text: root.claimInFlight ? qsTr("Claiming…") : qsTr("Claim one voucher")
                    onClicked: {
                        root.claimInFlight = true
                        root.claimLeaderRewardsRequested()
                    }
                }

                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                    text: root.lastReward > 0
                        ? qsTr("~%1 per voucher, ~%2 fee each — from the last settled claim.")
                            .arg(root.fmt(root.lastReward)).arg(root.fmt(root.lastFee))
                        : qsTr("Value per voucher is known after a claim settles.")
                }

                LogosText {
                    visible: !root.canClaim && root.claimBlockedReason.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root.claimBlockedReason
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                }

                LogosText {
                    visible: root._lastResult.length > 0 && root._lastResult.indexOf("Error") === 0
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: root._lastResult
                    color: Theme.palette.error
                    font.pixelSize: Theme.typography.secondaryText
                }

                LogosButton {
                    Layout.topMargin: Theme.spacing.small
                    Layout.preferredWidth: 200
                    visible: root.vouchers.length > 0
                    text: voucherDetail.visible ? qsTr("Hide vouchers") : qsTr("Show vouchers")
                    onClicked: voucherDetail.visible = !voucherDetail.visible
                }

                ColumnLayout {
                    id: voucherDetail
                    visible: false
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.small
                    spacing: Theme.spacing.small

                    LogosText {
                        visible: root.tip.length > 0
                        Layout.fillWidth: true
                        text: qsTr("at tip %1").arg(root.tip)
                        elide: Text.ElideMiddle
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textTertiary
                    }

                    // Each voucher is its own nested block, styled like the Node tab's
                    // cards, with the shared HashRow (24x24 BcCopyButton, same icons).
                    Repeater {
                        model: root.vouchers
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: vCol.implicitHeight + 2 * Theme.spacing.small
                            color: Theme.palette.backgroundSecondary
                            radius: Theme.spacing.radiusSmall
                            border.color: Theme.palette.border
                            border.width: 1

                            ColumnLayout {
                                id: vCol
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: Theme.spacing.small
                                spacing: Theme.spacing.tiny

                                LogosText {
                                    text: qsTr("Voucher %1").arg(index + 1)
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.bold: true
                                }
                                HashRow {
                                    label: qsTr("Commitment")
                                    labelWidth: 90
                                    value: modelData && modelData.commitment ? String(modelData.commitment) : ""
                                    onCopyRequested: function(t) { root.copyToClipboard(t) }
                                }
                                HashRow {
                                    label: qsTr("Nullifier")
                                    labelWidth: 90
                                    value: modelData && modelData.nullifier ? String(modelData.nullifier) : ""
                                    onCopyRequested: function(t) { root.copyToClipboard(t) }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ======================= LIFETIME =======================
        Rectangle {
            Layout.fillWidth: true
            visible: root.summary && root.summary.settled > 0
            Layout.preferredHeight: lifeCol.implicitHeight + 2 * Theme.spacing.large
            color: Theme.palette.backgroundTertiary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1

            ColumnLayout {
                id: lifeCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacing.large
                spacing: Theme.spacing.tiny

                LogosText {
                    text: qsTr("Rewards claimed")
                    font.pixelSize: Theme.typography.secondaryText
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.large
                    Repeater {
                        model: root.summary ? [
                            { k: qsTr("Claims"),  v: root.fmt(root.summary.settled) },
                            { k: qsTr("Claimed"), v: root.fmt(root.summary.claimed) },
                            { k: qsTr("Fees"),    v: root.summary.feesComplete
                                                      ? root.fmt(root.summary.fees)
                                                      : qsTr("≥ %1").arg(root.fmt(root.summary.fees)) },
                            { k: qsTr("Net"),     v: root.summary.feesComplete
                                                      ? qsTr("+%1").arg(root.fmt(root.summary.net))
                                                      : qsTr("≤ +%1").arg(root.fmt(root.summary.net)) }
                        ] : []
                        delegate: ColumnLayout {
                            spacing: 0
                            LogosText {
                                text: modelData.k
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            LogosText {
                                text: modelData.v
                                font.pixelSize: Theme.typography.primaryText
                                font.weight: Theme.typography.weightMedium
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // Never present a partial scan as a lifetime total.
                LogosText {
                    visible: root.summary && (!root.summary.scanCaughtUp || root.summary.historyFromSlot > 0)
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                    text: {
                        if (!root.summary) return ""
                        if (!root.summary.scanCaughtUp)
                            return qsTr("Still scanning the chain (slot %1 of %2) — totals are partial.")
                                .arg(root.fmt(root.summary.lastScannedSlot))
                                .arg(root.fmt(root.summary.libSlot))
                        return qsTr("History scanned from slot %1, not from genesis.")
                            .arg(root.fmt(root.summary.historyFromSlot))
                    }
                }
                LogosText {
                    visible: root.summary && root.summary.settled > 0 && !root.summary.feesComplete
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText
                    text: qsTr("Some fees are unknown: a fee is the spent note minus the change, and notes spent before this ledger existed cannot be priced.")
                }
            }
        }

        // ======================= CLAIMS LEDGER =======================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: claimsCol.implicitHeight + 2 * Theme.spacing.large
            color: Theme.palette.backgroundTertiary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1

            ColumnLayout {
                id: claimsCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.spacing.large
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    LogosText {
                        text: qsTr("Claims")
                        font.pixelSize: Theme.typography.secondaryText
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    InfoButton {
                        text: qsTr("Every claim you have made, kept permanently. A claim is recorded the moment it is submitted, then reconciled against the chain: Submitted → In a block → Settled. Only blocks below the last irreversible block count as settled, so a chain reorg moves a claim back rather than un-settling it.")
                    }
                }

                LogosText {
                    visible: root.claims.length === 0
                    text: qsTr("No claims yet.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }

                Repeater {
                    model: root.claims
                    delegate: Rectangle {
                        id: claimRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: rowCol.implicitHeight + 2 * Theme.spacing.small
                        color: Theme.palette.backgroundSecondary
                        radius: Theme.spacing.radiusSmall
                        border.color: Theme.palette.border
                        border.width: 1

                        readonly property string st: modelData.status || "submitted"

                        ColumnLayout {
                            id: rowCol
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: Theme.spacing.small
                            spacing: Theme.spacing.tiny

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.small
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: root.statusColor(claimRow.st)
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                LogosText {
                                    text: root.statusLabel(claimRow.st)
                                    color: root.statusColor(claimRow.st)
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.weight: Theme.typography.weightMedium
                                }
                                LogosText {
                                    text: modelData.settledAt || modelData.submittedAt || ""
                                    color: Theme.palette.textTertiary
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                                Item { Layout.fillWidth: true }
                                LogosText {
                                    visible: claimRow.st === "settled"
                                    text: modelData.fee > 0
                                        ? qsTr("+%1 − %2 = +%3")
                                            .arg(root.fmt(modelData.reward))
                                            .arg(root.fmt(modelData.fee))
                                            .arg(root.fmt(modelData.reward - modelData.fee))
                                        : qsTr("+%1 (fee unknown)").arg(root.fmt(modelData.reward))
                                    color: Theme.palette.success
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.weight: Theme.typography.weightMedium
                                }
                            }

                            HashRow {
                                label: qsTr("Transaction")
                                labelWidth: 90
                                value: modelData.tx || ""
                                onCopyRequested: function(t) { root.copyToClipboard(t) }
                            }
                            HashRow {
                                visible: !!modelData.voucherNf
                                label: qsTr("Nullifier")
                                labelWidth: 90
                                value: modelData.voucherNf || ""
                                onCopyRequested: function(t) { root.copyToClipboard(t) }
                            }

                            // Say plainly when a status is inferred rather than seen,
                            // and when a row came from the chain rather than from us.
                            LogosText {
                                visible: claimRow.st === "expired"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Not seen on chain — the voucher was returned to the pool and no fee was charged. Inferred: an unlanded claim leaves nothing to observe.")
                                color: Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            LogosText {
                                visible: claimRow.st === "submitted"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Waiting to be included in a block, then to finalize. Finalization runs well behind the chain tip.")
                                color: Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            LogosText {
                                visible: !!modelData.backfilled
                                text: qsTr("recovered from the chain")
                                color: Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                        }
                    }
                }
            }
        }
    }
}
