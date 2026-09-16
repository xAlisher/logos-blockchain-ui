import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"
import "../amounts.js" as Amounts
import "infoContent.js" as InfoContent

// Leader rewards: a fungible voucher POOL plus a permanent CLAIMS LEDGER.
//
// Deliberately not a board with a column per state. Vouchers are interchangeable
// (every one is worth the same reward), the operator moves nothing — the protocol
// does, on a timer — and the fact that matters most is a duration ("~2h to settle"),
// which columns cannot express. So: the pool is a quantity, and the state machine
// belongs to the CLAIM, which has identity, cost, duration and an outcome.
//
// Design and the evidence behind it: docs/VOUCHER-STATE-MAP.md
ColumnLayout {
    id: root
    spacing: Theme.spacing.large

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
    signal clearClaimsRequested()
    signal copyToClipboard(string text)

    // Structured (i) content + shared modal — same {title,what,calc,states,docs}
    // modal the dashboard tiles use, so the Rewards (i)s match the dashboard.
    readonly property var _rInfo: InfoContent.rewards
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }

    // --- epoch sidebar (Rewards page) ---
    property int currentEpoch: -1
    function _cEpoch(c) { var sl = (c && c.slot !== undefined) ? Number(c.slot) : NaN; return isNaN(sl) ? -1 : Math.floor(sl / 36000) }
    readonly property var _claimEpochs: {
        var seen = ({}), list = []
        for (var i = 0; i < claims.length; i++) { var e = _cEpoch(claims[i]); if (e >= 0 && !seen[e]) { seen[e] = 1; list.push(e) } }
        list.sort(function(a, b) { return b - a }); return list
    }
    // Claims per epoch, shown in the sidebar rows (epoch -> count).
    readonly property var _claimCounts: {
        var m = ({})
        for (var i = 0; i < claims.length; i++) { var e = _cEpoch(claims[i]); if (e >= 0) m[e] = (m[e] || 0) + 1 }
        return m
    }
    function _isLanded(c) { return c && (c.status === "settled" || c.status === "in_block") }
    // Only LANDED claims appear as rows — every row is real earnings, so no per-row
    // state label is needed. The not-landed count still surfaces in the summary line
    // above the list (#46), so the "are my claims landing" signal isn't lost.
    readonly property var filteredClaims: {
        var out = []
        for (var i = 0; i < claims.length; i++) {
            var c = claims[i]
            if (!_isLanded(c)) continue
            if (rewardsEpochNav.selected !== -1 && _cEpoch(c) !== rewardsEpochNav.selected) continue
            out.push(c)
        }
        return out
    }

    InfoModal { id: infoModal; onCopyText: (t) => root.copyToClipboard(t) }

    Dialog {
        id: clearConfirm
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(440, root.width - 2 * Theme.spacing.large)
        padding: Theme.spacing.large
        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: qsTr("Clear the claims list? The dashboard’s “Earned” tile and the “Earned by epoch” chart are calculated from this list, so they reset to empty too — until you claim again. The rows are archived, not deleted, and won’t reappear; your actual balance is unaffected.")
                font.pixelSize: Theme.typography.secondaryText
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: Theme.spacing.medium
                CtaButton { compact: true; text: qsTr("Cancel"); onClicked: clearConfirm.close() }
                CtaButton {
                    compact: true
                    text: qsTr("Clear log")
                    onClicked: { clearConfirm.close(); root.clearClaimsRequested() }
                }
            }
        }
    }

    // ---- verified-feed additions (#47) ----
    // Auto-claim owns the button: claims fire in the first minutes after each
    // epoch tick (the first moment a voucher's proof can land, and the moment
    // that costs no leadership — fee notes are already in this epoch's
    // eligibility snapshot). The manual button only returns if this is off.
    property bool autoClaim: true
    // Current chain slot, pushed by the parent's scheduler poll. Slots are
    // seconds since genesis; epochs are 36,000 slots (10 h), boundaries at
    // N*36000 — measured on this testnet (redteam 08-24, epoch 46 at 1,656,001).
    property real slotNow: -1
    readonly property real secsToTick: slotNow >= 0 ? (36000 - (slotNow % 36000)) : -1
    readonly property string nextTickText: {
        if (root.secsToTick < 0) return ""
        var h = Math.floor(root.secsToTick / 3600)
        var m = Math.floor((root.secsToTick % 3600) / 60)
        return h > 0 ? qsTr("~%1h %2m").arg(h).arg(m) : qsTr("~%1m").arg(m)
    }
    // Explorer-verified-absent claims. >=2 is the stale-wallet-state signature
    // (08-24 incident): the wallet is offering state the chain disagrees with,
    // and a rescan rebuilds it. Never alarmed on inference.
    readonly property int failedVerified: root.summary ? (root.summary.failedVerified || 0) : 0
    // Copy, not open: an unrequested browser launch from a desktop app is jarring,
    // and half the time the link is headed to a chat anyway (Alisher, 08-25).
    function explorerTxUrl(tx) {
        return "https://testnet.blockchain.logos.co/web/explorer/transactions/" + tx
    }

    function setLeaderClaimResult(text) {
        // "No claimable voucher found" is the benign empty-claim case: a claim ran
        // with zero vouchers (an auto-claim race where the cached count led the pool,
        // or a manual press at 0). "Ready to claim: 0" already says this, so don't
        // surface it as an error. Real claim failures still show.
        if (text && /no claimable voucher/i.test(text)) { root._lastResult = ""; return }
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
    // Most recent LANDED claim (in a block, settled or not) — the fee/reward are known
    // once it's in_block, so the fee % shows without waiting for settlement.
    readonly property real lastReward: {
        for (var i = 0; i < claims.length; ++i)
            if ((claims[i].status === "settled" || claims[i].status === "in_block") && claims[i].reward > 0)
                return claims[i].reward
        return 0
    }
    readonly property real lastFee: {
        for (var i = 0; i < claims.length; ++i)
            if ((claims[i].status === "settled" || claims[i].status === "in_block") && claims[i].fee > 0)
                return claims[i].fee
        return 0
    }

    readonly property var _proposals: safeParse(proposalsJson)
    readonly property int blocksLed: Array.isArray(root._proposals) ? root._proposals.length : 0
    // Oldest entry in the proposals log — the log accumulates and never expires,
    // so "blocks led" is lifetime, not a current-chain figure.
    readonly property string firstProposalDay: {
        if (!Array.isArray(root._proposals) || root._proposals.length === 0) return ""
        var oldest = root._proposals[root._proposals.length - 1]
        return String((oldest && oldest.time) || "").substring(0, 10)
    }

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

    // Pacing. Claims fired in a burst land at roughly half the rate of paced ones:
    // measured 13->6 and 12->5 submitted-to-settled when fired together, against
    // 47/47 and 4/4 with a couple of seconds between calls. The cause is not
    // isolated (contention over the same notes, propagation, mempool eviction are
    // all candidates), but the correlation is strong and the cost of waiting is
    // nil — so the button holds itself back rather than letting a burst happen.
    // This is the cheapest fix in #46 and the only one that prevents the confusing
    // state instead of explaining it.
    property bool claimCoolingDown: false
    Timer {
        id: claimCooldown
        interval: 2000
        onTriggered: root.claimCoolingDown = false
    }

    readonly property bool canClaim: vouchers.length > 0 && balance > 0
                                     && !claimInFlight && !claimCoolingDown
    readonly property string claimBlockedReason: {
        if (claimInFlight) return qsTr("Claim in flight — wait for it to be submitted.")
        if (claimCoolingDown) return qsTr("Pacing — claims land far more reliably a couple of seconds apart.")
        if (vouchers.length === 0) return qsTr("No vouchers ready to claim.")
        if (balance === 0) return qsTr("Not enough balance to pay the claim fee.")
        if (balance < 0) return qsTr("Waiting for the wallet balance…")
        return ""
    }
    // Called by the view when a claim is actually submitted.
    function startClaimCooldown() {
        root.claimCoolingDown = true
        claimCooldown.restart()
    }

    // Claims that never made it into a block. Counted, never linked to a voucher.
    readonly property int notIncludedCount: {
        var n = 0
        for (var i = 0; i < claims.length; ++i)
            if (claims[i].status === "failed") n++   // explorer-verified absent only
        return n
    }
    readonly property int landedCount: {
        var n = 0
        for (var i = 0; i < claims.length; ++i)
            if (claims[i].status === "settled") n++
        return n
    }

    // Bare number — for counts and slot numbers, which have no unit.
    function fmt(n) { return Amounts.preciseNum(n) }
    // With the ticker — for amounts. See amounts.js: the raw u64 IS LGO.
    function fmtLgo(n) { return Amounts.precise(n) }

    // Claim status → colour. NOTE: Theme.palette.orange does NOT exist on
    // DarkTheme (only overlayOrange does) — an undefined colour renders BLACK,
    // which is what made "Submitted" invisible. Only tokens defined in
    // DarkTheme.qml are used here.
    //   submitted #FEBC2E warning  — waiting, nothing wrong
    //   in_block  #ED7B58 primary  — moving, not yet final
    //   settled   #49F563 success  — done
    //   expired   #969696 tertiary — inert; a no-op, not an error, so NOT red
    //     (shown as "Didn't land": what expired is the node's RESERVATION,
    //      not the voucher. "Expired" made users ask if they had lost money.)
    // Vocabulary (#47, post 08-25 audit): a verdict is only ever an OBSERVATION.
    //   settled  -> "Paid"       (seen in a block, or explorer-verified)
    //   checking -> "Confirming" (pool inference suspects a miss; explorer will decide)
    //   failed   -> "Failed"     (explorer verified the tx absent). GRAY, not red
    //     (26 Aug): under fee-market movement a priced-out claim is EXPECTED
    //     behavior — nothing consumed, voucher released, no fee. Red made a
    //     healthy node look broken; the rescan banner is the only red left.
    //   expired  -> legacy rows, rendered as "Confirming" until re-verified
    function statusColor(st) {
        if (st === "settled")  return Theme.palette.success
        if (st === "in_block") return Theme.palette.primary
        if (st === "checking" || st === "expired" || st === "failed")
            return Theme.palette.textTertiary
        if (st === "error") return Theme.palette.error
        return Theme.palette.warning
    }
    function statusLabel(st) {
        if (st === "settled")  return qsTr("Paid")
        if (st === "in_block") return qsTr("In a block")
        if (st === "checking" || st === "expired") return qsTr("Confirming…")
        if (st === "failed" || st === "error") return qsTr("Failed")
        return qsTr("Claiming…")
    }

    // Vouchers summary spans the full width, ABOVE the [epoch sidebar | ledger]
    // row: it is global state (not per-epoch), so it sits over both columns.
    // ======================= VOUCHERS =======================
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false   // nested layouts default fillHeight=true; pin it so only the ledger row grows
            spacing: Theme.spacing.medium
            LogosText {
                text: qsTr("Vouchers")
                font.pixelSize: Theme.typography.subtitleText
                font.weight: Theme.typography.weightMedium
            }
            // Sized and styled like the header's "Fund the node". Sitting beside
            // the heading keeps the tiles pure stats, so the number stays centred
            // with nothing hanging off it.
            // The button is owned by the scheduler (#47): visible only when
            // auto-claim is off. With it on, the line below says when the next
            // claim window opens — there is nothing to press on a healthy node.
            CtaButton {
                Layout.alignment: Qt.AlignVCenter
                compact: true
                visible: !root.autoClaim
                enabled: root.canClaim
                text: root.claimInFlight ? qsTr("Claiming…") : qsTr("Claim")
                onClicked: {
                    root.claimInFlight = true
                    // Start the cooldown at the press, not at the reply: the burst we
                    // are preventing is press-to-press, and the reply can be seconds away.
                    root.startClaimCooldown()
                    root.claimLeaderRewardsRequested()
                }
            }
            LogosText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.autoClaim
                text: root.claimInFlight
                      ? qsTr("Claiming…")
                      : (root.nextTickText.length > 0
                         ? qsTr("Auto-claims at epoch start · next in %1").arg(root.nextTickText)
                         : qsTr("Auto-claims at epoch start"))
                color: Theme.palette.textTertiary
                font.pixelSize: Theme.typography.secondaryText
            }
            Item { Layout.fillWidth: true }
        }

        // ======================= ALARM (verified anomalies only) =======================
        // Appears ONLY when the explorer has confirmed >=2 claims absent from the
        // chain — the stale-wallet-state signature. Inference never alarms.
        Rectangle {
            visible: root.failedVerified >= 2
            Layout.fillWidth: true
            implicitHeight: alarmCol.implicitHeight + 2 * Theme.spacing.medium
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusMedium
            border.color: Theme.palette.error
            border.width: 1
            ColumnLayout {
                id: alarmCol
                anchors.fill: parent
                anchors.margins: Theme.spacing.medium
                spacing: Theme.spacing.small
                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: qsTr("%n claim(s) verified absent on chain.", "", root.failedVerified)
                          + " " + qsTr("Your node's wallet state may be stale — a rescan rebuilds it from the chain. Keys and balance are untouched (~40 min resync).")
                    color: Theme.palette.error
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosText {
                    text: qsTr("Open the rescan guide ↗")
                    color: Theme.palette.primary
                    font.pixelSize: Theme.typography.secondaryText
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally("https://github.com/xAlisher/logos-blockchain-ui/blob/master/docs/RESCAN.md")
                    }
                }
            }
        }

        // GridLayout, not RowLayout: a RowLayout cannot wrap, so at narrow widths
        // the tiles were squeezed until their contents overlapped and spilled past
        // the borders. Columns are derived from the available width against a
        // minimum tile size, so tiles drop to the next line instead.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false   // nested layouts default fillHeight=true → tiles ballooned; pin it
            columnSpacing: Theme.spacing.medium
            rowSpacing: Theme.spacing.medium
            columns: Math.max(1, Math.floor((width + columnSpacing) / (180 + columnSpacing)))

            StatTile {
                topAligned: true
                label: qsTr("Ready to claim")
                value: String(root.vouchers.length)
                infoData: root._rInfo.readyToClaim
                onInfoRequested: root._openInfo(infoData)
                // No value here: "Unclaimed" in Rewards already carries it.
                interactive: root.vouchers.length > 0
                onClicked: if (root.vouchers.length > 0) voucherDialog.open()
            }

            StatTile {
                topAligned: true
                // "Submitted" matches the status word used on the claim rows.
                label: qsTr("Submitted")
                value: String(root.claimingCount)
                infoData: root._rInfo.submitted
                onInfoRequested: root._openInfo(infoData)
            }
        }

        // Why the button is unavailable, stated rather than left to guess. Suppressed
        // in the no-vouchers case: the "Ready to claim: 0" tile already says it.
        LogosText {
            visible: !root.canClaim && root.claimBlockedReason.length > 0 && root.vouchers.length > 0
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

        // ======================= CLAIMS =======================
        // Full-width title (Clear + info) ABOVE the epoch rail + list.
        RowLayout {
            Layout.fillWidth: true
            LogosText {
                text: qsTr("Claims")
                font.pixelSize: Theme.typography.subtitleText
                font.weight: Theme.typography.weightMedium
            }
            Item { Layout.fillWidth: true }
            GhostButton {
                Layout.alignment: Qt.AlignVCenter
                visible: root.claims.length > 0
                text: qsTr("Clear")
                onClicked: clearConfirm.open()
            }
            Button {
                id: claimsInfoBtn
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 28; implicitHeight: 28
                display: AbstractButton.IconOnly
                flat: true; padding: 4
                background: Rectangle { color: "transparent" }
                icon.source: Qt.resolvedUrl("../icons/info.svg")
                icon.width: 18; icon.height: 18
                icon.color: claimsInfoBtn.hovered ? Theme.palette.primary : Theme.palette.textMuted
                onClicked: root._openInfo(root._rInfo.claims)
            }
        }
        // Landing-rate signal (#46) — kept as one line above the list even though the
        // list now shows only landed rows.
        LogosText {
            visible: root.notIncludedCount > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("%1 of %2 claims have landed. The other %3 weren't included in a block — nothing was consumed, and %4 vouchers are still ready. Claims land far more reliably a few seconds apart.")
                      .arg(root.fmt(root.landedCount))
                      .arg(root.fmt(root.landedCount + root.notIncludedCount))
                      .arg(root.fmt(root.notIncludedCount))
                      .arg(root.fmt(root.vouchers.length))
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }

        // The epoch sidebar filters the claims ledger; the page scrolls once it fills.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacing.large

            EpochNav {
                id: rewardsEpochNav
                Layout.fillHeight: true
                epochs: root._claimEpochs
                currentEpoch: root.currentEpoch
                counts: root._claimCounts
                total: root.claims.length
            }
            ScrollView {
                id: rewardsScroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth
            ColumnLayout {
                width: rewardsScroll.availableWidth
                spacing: Theme.spacing.large

        Item {
            Layout.fillWidth: true
            implicitHeight: claimsCol.implicitHeight

            ColumnLayout {
                id: claimsCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.small

                LogosText {
                    visible: root.filteredClaims.length === 0
                    text: qsTr("No claims yet.")
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }

                Repeater {
                    model: root.filteredClaims
                    delegate: Rectangle {
                        id: claimRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: rowCol.implicitHeight + 2 * Theme.spacing.small
                        // Match the info tiles: backgroundTertiary (#1C1C1C) is
                        // DARKER than backgroundSecondary (#262626), despite the
                        // names. No stroke either — the tiles carry none, and the
                        // fill alone already separates the rows.
                        color: Theme.palette.backgroundTertiary
                        radius: Theme.spacing.radiusMedium    // unified row-card radius
                        border.width: 0

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
                                // Every row is a landed claim → real earnings. Headline the
                                // net in white; reward/fees as a gray aside. No status label,
                                // no green — the amount is the point. Datestamp far right.
                                LogosText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: qsTr("Earned: %1").arg(root.fmtLgo(
                                              modelData.fee > 0 ? (modelData.reward - modelData.fee)
                                                                : modelData.reward))
                                    color: Theme.palette.text
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.weight: Theme.typography.weightMedium
                                }
                                LogosText {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData.fee > 0
                                        ? qsTr("(reward %1, fees %2)")
                                            .arg(root.fmt(modelData.reward))
                                            .arg(root.fmt(modelData.fee))
                                        : qsTr("(fees unknown)")
                                    color: Theme.palette.textTertiary
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                                Item { Layout.fillWidth: true }
                                LogosText {
                                    // ISO "2026-08-17T15:31:47" reads better without the T.
                                    Layout.alignment: Qt.AlignVCenter
                                    text: String(modelData.settledAt || modelData.submittedAt || "")
                                              .replace("T", " ")
                                    color: Theme.palette.textTertiary
                                    opacity: 0.65
                                    font.pixelSize: Theme.typography.secondaryText
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

                            // State the outcome in COUNTS, not voucher identity. We cannot say
                            // WHICH voucher came back -- leader_claim returns only a tx hash
                            // (module#69) and an unlanded claim leaves no chain event -- but we do
                            // not need to: the user asked whether anything was lost, and that is a
                            // question about counts. Counts are also the privacy-safe answer; a
                            // not-yet-published nullifier on screen is a linkable identifier.
                            // See #46.
                            LogosText {
                                visible: claimRow.st === "expired" || claimRow.st === "checking"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Not seen by this node's scan yet — being verified against the chain. No verdict until the chain answers.")
                                color: Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            LogosText {
                                visible: claimRow.st === "failed"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Verified absent from the chain. Nothing was consumed — the voucher was released and no fee was charged.")
                                color: Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            LogosText {
                                visible: claimRow.st === "settled" && modelData.verifiedBy === "explorer"
                                          && !(modelData.reward > 0)
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: qsTr("Verified paid on chain (amount not yet recovered by the local scan — the balance already includes it).")
                                color: Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                            }
                            LogosText {
                                id: explorerCopy
                                // Not on failed rows: verified-absent means the explorer
                                // has no page for this tx — the link could only 404.
                                visible: !!modelData.tx && (claimRow.st === "settled"
                                                            || claimRow.st === "in_block")
                                text: explorerCopyReset.running ? qsTr("Link copied ✓") : qsTr("Copy explorer link")
                                color: explorerCopyReset.running ? Theme.palette.success : Theme.palette.primary
                                font.pixelSize: Theme.typography.secondaryText
                                Timer { id: explorerCopyReset; interval: 1500 }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.copyToClipboard(root.explorerTxUrl(modelData.tx))
                                        explorerCopyReset.restart()
                                    }
                                }
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

        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            radius: Theme.spacing.radiusLarge
            border.color: Theme.palette.border
            border.width: 1
        }

        // Custom footer: Dialog's standardButtons draws a DialogButtonBox from the
        // Qt style, which is not theme-aware and rendered as a white bar with a
        // system-grey button. Close is a dismiss, not a primary action, so it is
        // a bordered ghost button rather than the orange CTA.
        footer: Rectangle {
            color: "transparent"
            implicitHeight: 56
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Theme.spacing.large
                implicitWidth: closeLabel.implicitWidth + 3 * Theme.spacing.large
                implicitHeight: 32
                radius: Theme.spacing.radiusLarge   // compact: rounded corners, not a pill
                color: closeMouse.containsMouse ? Theme.palette.backgroundHover
                                                : "transparent"
                border.color: Theme.palette.border
                border.width: 1
                LogosText {
                    id: closeLabel
                    anchors.centerIn: parent
                    text: qsTr("Close")
                    font.pixelSize: Theme.typography.secondaryText
                    font.weight: Theme.typography.weightMedium
                    color: Theme.palette.text
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: voucherDialog.close()
                }
            }
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
            // Without this the first card slides under the header as it scrolls.
            topPadding: Theme.spacing.small
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
    }

}
