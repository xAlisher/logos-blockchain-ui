import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../amounts.js" as Amounts

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

    // JSON array from getProposals() — blocks THIS node led. Leadership is private
    // on chain, so this comes from the node's own log; it is the source of every
    // voucher, which is what closes the loop led -> earned -> claimed -> unclaimed.
    property string proposalsJson: ""

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

    readonly property var _proposals: safeParse(proposalsJson)
    readonly property int blocksLed: Array.isArray(root._proposals) ? root._proposals.length : 0

    // Money still on the table. An ESTIMATE: the reward is read from ledger state
    // at execution and does change (9,517 then 9,535 observed on this chain), so
    // this is "vouchers x the most recent settled reward", never a promise.
    readonly property real unclaimedEst: root.vouchers.length * root.lastReward
    // What a claim costs as a share of what it pays. At ~44% this is the single
    // most decision-relevant number here, and nothing else surfaces it.
    readonly property int feePct: (root.lastReward > 0 && root.lastFee > 0)
        ? Math.round(root.lastFee * 100 / root.lastReward) : -1
    readonly property real netPerClaim: (root.lastReward > 0 && root.lastFee > 0)
        ? root.lastReward - root.lastFee : 0

    readonly property var _lastSettled: {
        for (var i = 0; i < claims.length; ++i)
            if (claims[i].status === "settled") return claims[i]
        return null
    }
    readonly property int feesKnown: {
        var n = 0
        for (var i = 0; i < claims.length; ++i)
            if (claims[i].status === "settled" && claims[i].fee > 0) n++
        return n
    }

    readonly property bool canClaim: vouchers.length > 0 && balance > 0 && !claimInFlight
    readonly property string claimBlockedReason: {
        if (claimInFlight) return qsTr("Claim in flight — wait for it to be submitted.")
        if (vouchers.length === 0) return qsTr("No vouchers ready to claim.")
        if (balance === 0) return qsTr("Not enough balance to pay the claim fee.")
        if (balance < 0) return qsTr("Waiting for the wallet balance…")
        return ""
    }

    // Bare number — for counts and slot numbers, which have no unit.
    function fmt(n) { return Amounts.plain(n) }
    // With the ticker — for amounts. See amounts.js: the raw u64 IS LGO.
    function fmtLgo(n) { return Amounts.exact(n) }

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
        LogosText {
            text: qsTr("Vouchers")
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.medium

            StatTile {
                label: qsTr("Ready to claim")
                value: String(root.vouchers.length)
                sub: root.lastReward > 0 ? qsTr("~%1").arg(root.fmtLgo(root.unclaimedEst)) : ""
                interactive: root.vouchers.length > 0
                tip: root.vouchers.length > 0 ? qsTr("Open the voucher list") : ""
                onClicked: if (root.vouchers.length > 0) voucherDialog.open()

                LogosButton {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 150
                    enabled: root.canClaim
                    text: root.claimInFlight ? qsTr("Claiming…") : qsTr("Claim voucher")
                    onClicked: {
                        root.claimInFlight = true
                        root.claimLeaderRewardsRequested()
                    }
                }
            }

            StatTile {
                label: qsTr("Claiming")
                value: String(root.claimingCount)
                sub: root.claimingCount > 0 ? qsTr("awaiting settlement") : qsTr("none in flight")
                tip: qsTr("Claims submitted but not yet final. Counted from this ledger — the node never sends the UI its own reserved-voucher list.")
            }
        }

        // Why the button is unavailable, stated rather than left to guess.
        LogosText {
            visible: !root.canClaim && root.claimBlockedReason.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.claimBlockedReason
            color: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            text: root.lastReward <= 0
                ? qsTr("Value per voucher is known after a claim settles.")
                : root.lastFee > 0
                    ? qsTr("~%1 per voucher, ~%2 fee each — from the last settled claim.")
                        .arg(root.fmtLgo(root.lastReward)).arg(root.fmtLgo(root.lastFee))
                    : qsTr("~%1 per voucher — from the last settled claim. The fee is not known yet; a claim is a transaction and does cost one.")
                        .arg(root.fmtLgo(root.lastReward))
        }
        LogosText {
            visible: root._lastResult.length > 0 && root._lastResult.indexOf("Error") === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root._lastResult
            color: Theme.palette.error
            font.pixelSize: Theme.typography.secondaryText
        }

        // ======================= REWARDS =======================
        LogosText {
            visible: root.summary && root.summary.settled > 0
            text: qsTr("Rewards")
            font.pixelSize: Theme.typography.subtitleText
            font.weight: Theme.typography.weightMedium
        }

        Item {
            Layout.fillWidth: true
            visible: root.summary && root.summary.settled > 0
            implicitHeight: lifeCol.implicitHeight

            ColumnLayout {
                id: lifeCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.small

                // Operator-facing figures. The previous version spent two of four
                // tiles on "Fees ≥ 0" and "Net ≤ +N" — bounds that are honest but
                // carry no information. These answer what an operator actually
                // asks: is money sitting unclaimed, is claiming worth it, am I
                // still winning slots.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.medium
                    Repeater {
                        model: root.summary ? [
                            {
                                k: qsTr("Claimed"),
                                v: root.fmtLgo(root.summary.claimed),
                                sub: qsTr("%1 claims").arg(root.fmt(root.summary.settled))
                            },
                            {
                                // The actionable one: value still on the table.
                                k: qsTr("Unclaimed"),
                                v: root.lastReward > 0
                                    ? qsTr("~%1").arg(root.fmtLgo(root.unclaimedEst))
                                    : "—",
                                sub: qsTr("%1 vouchers ready").arg(root.vouchers.length)
                            },
                            {
                                // Claiming burns a large share of the reward; an
                                // operator should see that before pressing again.
                                k: qsTr("Cost to claim"),
                                v: root.feePct >= 0
                                    ? qsTr("%1  %2%").arg(root.fmtLgo(root.lastFee)).arg(root.feePct)
                                    : qsTr("not known yet"),
                                sub: root.feePct >= 0
                                    ? qsTr("net +%1 per claim").arg(root.fmt(root.netPerClaim))
                                    : qsTr("of a %1 reward").arg(root.fmtLgo(root.lastReward))
                            },
                            {
                                // Recency: a node that stopped winning slots shows here.
                                k: qsTr("Blocks led"),
                                v: root.blocksLed > 0 ? root.fmt(root.blocksLed) : "—",
                                sub: qsTr("%1 vouchers earned").arg(root.fmt(root.blocksLed))
                            },
                            {
                                k: qsTr("Last claim"),
                                v: root._lastSettled
                                    ? String(root._lastSettled.settledAt || "").replace("T", " ").substring(11, 16)
                                    : "—",
                                sub: root._lastSettled
                                    ? qsTr("+%1").arg(root.fmtLgo(root._lastSettled.reward))
                                    : ""
                            }
                        ] : []
                        delegate: StatTile {
                            label: modelData.k
                            value: modelData.v
                            sub: modelData.sub || ""
                        }
                    }
                }

                // One caveat line, not three. It states only what is actually
                // uncertain right now and disappears entirely once the scan has
                // caught up and every fee is priced.
                LogosText {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.tiny
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textTertiary
                    opacity: 0.65
                    font.pixelSize: Theme.typography.secondaryText
                    visible: text.length > 0
                    text: {
                        if (!root.summary) return ""
                        var parts = []
                        if (!root.summary.scanCaughtUp)
                            parts.push(qsTr("still scanning the chain (slot %1 of %2) — totals are partial")
                                .arg(root.fmt(root.summary.lastScannedSlot))
                                .arg(root.fmt(root.summary.libSlot)))
                        else if (root.summary.historyFromSlot > 0)
                            parts.push(qsTr("history from slot %1, not genesis")
                                .arg(root.fmt(root.summary.historyFromSlot)))
                        if (root.summary.settled > 0 && !root.summary.feesComplete)
                            parts.push(qsTr("fees known for %1 of %2 claims")
                                .arg(root.feesKnown).arg(root.summary.settled))
                        return parts.join(" · ")
                    }
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
                                // No status dot: the label already carries the colour,
                                // so the dot repeated the same information twice.
                                LogosText {
                                    text: root.statusLabel(claimRow.st)
                                    color: root.statusColor(claimRow.st)
                                    Layout.alignment: Qt.AlignVCenter
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.weight: Theme.typography.weightMedium
                                }
                                LogosText {
                                    // ISO "2026-08-17T15:31:47" reads better without the T.
                                    // Held back so the status and the amount lead:
                                    // the timestamp is context, not the headline.
                                    text: String(modelData.settledAt || modelData.submittedAt || "")
                                              .replace("T", " ")
                                    Layout.alignment: Qt.AlignVCenter
                                    color: Theme.palette.textTertiary
                                    opacity: 0.65
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                                Item { Layout.fillWidth: true }
                                LogosText {
                                    visible: claimRow.st === "settled"
                                    text: modelData.fee > 0
                                        ? qsTr("+%1 − %2 = +%3 LGO")
                                            .arg(root.fmt(modelData.reward))
                                            .arg(root.fmt(modelData.fee))
                                            .arg(root.fmt(modelData.reward - modelData.fee))
                                        : qsTr("+%1 (fee unknown)").arg(root.fmtLgo(modelData.reward))
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
    // Voucher detail lives in a modal rather than inline: vouchers are fungible,
    // so the LIST is reference material while the COUNT is the headline. Keeping
    // 13 hex pairs out of the main flow is what lets the page stay scannable.
    Dialog {
        id: voucherDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(720, root.width - 2 * Theme.spacing.large)
        height: Math.min(560, root.height - 2 * Theme.spacing.large)
        padding: Theme.spacing.large
        standardButtons: Dialog.Close

        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1
        }

        header: ColumnLayout {
            spacing: 2
            LogosText {
                Layout.margins: Theme.spacing.large
                Layout.bottomMargin: 0
                text: qsTr("Ready to claim: %1").arg(root.vouchers.length)
                font.pixelSize: Theme.typography.subtitleText
                font.weight: Theme.typography.weightMedium
            }
            LogosText {
                Layout.margins: Theme.spacing.large
                Layout.topMargin: 0
                Layout.fillWidth: true
                visible: root.tip.length > 0
                text: qsTr("at tip %1").arg(root.tip)
                elide: Text.ElideMiddle
                color: Theme.palette.textTertiary
                opacity: 0.65
                font.pixelSize: Theme.typography.secondaryText
            }
        }

        contentItem: ScrollView {
            id: voucherScroll
            clip: true
            ColumnLayout {
                width: voucherScroll.availableWidth
                spacing: Theme.spacing.small

                Repeater {
                    model: root.vouchers
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: vCol.implicitHeight + 2 * Theme.spacing.small
                        color: Theme.palette.backgroundTertiary
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

}
