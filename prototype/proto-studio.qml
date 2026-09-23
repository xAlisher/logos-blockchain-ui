import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V
import "../src/qml/controls" as C
import "../src/qml/amounts.js" as Amounts

// Blockchain-node dashboard PROTOTYPE STUDIO.
// Drives the REAL NodeDashboardView with mock state — no node, no backend — so
// interactions and states (including features not built yet) can be prototyped.
// Left: the live dashboard + a header with a working Start/Stop. Right: a control
// panel — one-click scenario presets, live toggles, and a scripted Start→Online.
Window {
    id: win
    width: 1320; height: 860; visible: true
    color: Theme.palette.background
    title: "Blockchain Node — Prototype Studio"

    property bool _onboarding: false      // onboarding flow overlay (launched from the control panel)
    property bool _keysBackedUp: false    // false ⇒ show the "back up your keys" banner (Quick start leaves it false)
    property bool _dragExp: false         // drag-to-reorder tiles experiment overlay
    property bool _blendModal: false      // Enable-Blend-Core modal overlay (epic #89)
    property bool _blendPortOpen: false   // the hard gate (UDP 3400) — flip to demo green → Enable

    // number formatting helpers
    function fmtK(n) { return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") }
    function fmtHMS(s) { var t = Math.floor(s); var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), ss = t % 60; function p(x) { return x < 10 ? "0" + x : x } return h + ":" + p(m) + ":" + p(ss) }

    // ── the single source of mock state (NUMERIC backing; strings are computed) ──
    QtObject {
        id: st
        property int status: -1            // -1 not connected · 0 NotStarted · 1 Starting · 2 Running · 4 Stopped · 5 Error
        property bool recovering: false
        property bool autoPaused: false    // node stopped by a resource-cap breach → "Node auto-paused" hero
        property string autoPauseReason: ""
        property bool stalled: false       // no real progress → "Sync stalled" / (with prolonged phase) "Bootstrap stuck"
        property string phase: ""          // cryptarchia phase; "ProlongedBootstrapPeriod" ⇒ prolonged bootstrap
        property string err: ""
        property string mode: ""           // "Online" once the node reports
        property real tip: 0               // node chain tip (slot)
        property real head: 0              // network head (current_slot); head-tip>3 ⇒ bootstrapping
        property string peerId: ""
        property string blend: "none"
        property int blendWithdrawEpoch: -1    // >=0 ⇒ our declaration is withdrawing, clears at this epoch (blocks re-declare)
        property int blendMaturingEpoch: -1    // >=0 ⇒ declared + live on-chain but pre-active; activates at this epoch
        property string validation: ""
        property int epochsToActivate: 0
        property int eligibleNoteCount: -1     // 0.3 /leader/aged-notes count; -1 unknown, 0 aging, >0 eligible
        property real stakeLepta: -1     // raw lepta (decimals=9); Amounts.short → LGO
        property string addr: ""
        // numeric knobs for the not-yet-built metrics; <0 / false ⇒ "—"/absent
        property int epochN: -1
        property real epochElapsed: -1     // minutes into the current epoch
        property real epochLen: 600        // ~10h epoch (mock)
        readonly property string epochProgress: epochElapsed >= 0 ? (Math.floor(epochElapsed / 60) + "h of " + Math.floor(epochLen / 60) + "h") : ""
        property int proposedN: -1
        property int peersN: -1
        property int connN: -1
        property bool empoweringActive: false
        property real empoweringMined: -1     // LGO mined toward target
        property real empoweringTarget: -1    // target balance / auto-claim threshold
        property bool funded: false           // wallet funded (persists after mining stops at 100%)
        property real cpuN: -1
        property int cpuCapN: -1           // <0 ⇒ "Cap not set"
        property real ramN: -1
        property bool ramCapSet: false
        property real earnedN: -1
        property int feeN: -1
        property real upSecs: -1           // uptime seconds; <0 ⇒ none

        // computed strings the view consumes (honest "—"/"" when absent)
        readonly property string epoch: epochN >= 0 ? String(epochN) : "—"
        readonly property string proposed: proposedN >= 0 ? String(proposedN) : "—"
        readonly property string peers: peersN >= 0 ? String(peersN) : "—"
        readonly property string connections: connN >= 0 ? (connN + " connections") : ""
        readonly property string cpu: cpuN >= 0 ? (Math.round(cpuN) + "%") : "—"
        readonly property string cpuCap: cpuN >= 0 ? (cpuCapN >= 0 ? ("Cap: " + cpuCapN + "%") : qsTr("Cap not set")) : ""
        readonly property string ram: ramN >= 0 ? (ramN.toFixed(1) + "GB") : "—"
        readonly property string ramCap: ramN >= 0 ? (ramCapSet ? qsTr("Cap set") : qsTr("Cap not set")) : ""
        readonly property string earned: earnedN >= 0 ? Amounts.precise(earnedN) : "—"   // earnedN = raw lepta; precise → tiny rewards visible
        readonly property string fee: feeN >= 0 ? String(feeN) : ""   // bare number; view adds "%"
        readonly property string uptime: upSecs >= 0 ? win.fmtHMS(upSecs) : ""

        readonly property string infoJson: mode.length
            ? JSON.stringify({ mode: mode, slot: Math.round(tip), height: Math.round(tip), phase: phase,
                               lib: "0x71bd39c4f0a17e2b8c4d5e6f9a0b1c2d3e4f5a6b9e4a", tip: "0x8a3f10d2e5c7b9a0f1e2d3c4b5a6978877665544c012" })
            : ""
        readonly property string timeInfoJson: mode.length
            ? JSON.stringify({ current_slot: Math.round(head), slot_duration_ms: 2000 }) : ""
        readonly property bool running: status === 2
        readonly property bool synced: running && mode === "Online" && (head - tip) <= 3
    }

    // ── mock data for the ported operator pages (Rewards / Blocks / Proposals / Wallet) ──
    // Static snapshots so the real fork views render representative content in the studio.
    readonly property string mockProposalsJson: JSON.stringify([
        { id: "0x8a3f10d2e5c7b9a0f1e2d3c4b5a6978877665544c012", txs: 3, time: 1789480200, removed: false },
        { id: "0x71bd39c4f0a17e2b8c4d5e6f9a0b1c2d3e4f5a6b9e4a", txs: 1, time: 1789476600, removed: false },
        { id: "0x5c2e91a0b3d4f5061728394a5b6c7d8e9f0a1b2c3d4e", txs: 0, time: 1789473000, removed: false }
    ])
    readonly property string mockClaimsJson: JSON.stringify({
        claims: [
            { status: "settled", slot: 411500, reward: 5814, fee: 4173, tx: "6da7dc3948e976c3f1ee2e2616bb3dee1bfc63c1c2fbadb3f37796eab9a126af", voucherNf: "7d19c05c2ff04c4c9f5d159a9b1753abbc4b1d99819f005ea5a0abcbdedf1f04", settledAt: "2026-09-15T10:31:45", submittedAt: "2026-09-15T10:31:40" },
            { status: "settled", slot: 411180, reward: 5814, fee: 4173, tx: "e590c916644fb51cc7517db88cdab8d62d3ad6d0c39005320b4f0677339bf209", voucherNf: "606ee4daff2ffabbc2204fe07e1523c57bd11023da1def88975a99f543a4cc0a", settledAt: "2026-09-15T10:30:15", submittedAt: "2026-09-15T10:30:10" },
            { status: "settled", slot: 410900, reward: 5814, fee: 4173, tx: "ac67f25aee2db4413c048efeacc0c513d7bdb0b0b6805446d85454e7b3cdc406", voucherNf: "439f24635ed005129bb4f6937c6046085d8b709ee215e7e53e621c0ff77eee02", settledAt: "2026-09-15T10:30:45", submittedAt: "2026-09-15T10:30:40" },
            { status: "settled", slot: 396500, reward: 5720, fee: 4173, tx: "18973b6e76be6b6eefddaaf7ebf3107389b258f0590ddc39902ff9959034def3", voucherNf: "ad32c8e61b082d30183fc7fde8eb86c09edd158fe14adcc629c42da74a865930", settledAt: "2026-09-15T09:58:15", submittedAt: "2026-09-15T09:58:10" },
            { status: "settled", slot: 380000, reward: 5680, fee: 4102, tx: "b21c7fe0a4d9c8375e162b4c0d5a6978877665544c0129e3f4a5b6c7d8e9f0a1", voucherNf: "f0e1d2c3b4a5968778695a4b3c2d1e0fa9b8c7d6b5a4938271605f4e3d2c1b0a", settledAt: "2026-09-15T05:12:00", submittedAt: "2026-09-15T05:11:55" },
            { status: "in_block", slot: 412000, reward: 5814, fee: 4173, tx: "c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2", voucherNf: "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90", submittedAt: "2026-09-15T10:33:00" },
            { status: "failed", slot: 399000, submittedAt: "2026-09-15T10:05:00" },
            { status: "failed", slot: 378000, submittedAt: "2026-09-15T04:40:00" }
        ],
        summary: { claimed: 8215, settled: 5, inFlight: 0, feesComplete: true, scanCaughtUp: true }
    })
    readonly property string mockVouchersJson: JSON.stringify({
        vouchers: [
            { voucherNf: "0xa1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4", slot: 411700 },
            { voucherNf: "0xf0e1d2c3b4a5968778695a4b3c2d1e0fa9b8c7d6", slot: 411660 }
        ]
    })
    ListModel {
        id: mockBlockModel
        ListElement { height: 148905; epoch: 172; leader: "0x8a3f10d2e5c7b9a0f1"; slot: 411702; hash: "0x8a3f10d2e5c7b9a0f1e2d3c4b5a6978877665544c012"; txs: 3 }
        ListElement { height: 148904; epoch: 172; leader: "0x0000000000000000"; slot: 411701; hash: "0x71bd39c4f0a17e2b8c4d5e6f9a0b1c2d3e4f5a6b9e4a"; txs: 1 }
        ListElement { height: 148903; epoch: 172; leader: "0x0000000000000000"; slot: 411700; hash: "0x5c2e91a0b3d4f5061728394a5b6c7d8e9f0a1b2c3d4e"; txs: 0 }
    }
    ListModel {
        id: mockAccountsModel
        ListElement { address: "0x8a3f10d2e5c7b9a0f1e2d3c4b5a6978877665544c012"; balance: "5000000000" }
        ListElement { address: "0x71bd39c4f0a17e2b8c4d5e6f9a0b1c2d3e4f5a6b9e4a"; balance: "1200000000" }
    }
    // Wallet Accounts view = labelled keys grouped Spendable/Identity. Kept SEPARATE from
    // mockAccountsModel because Transfer/ChannelDeposit pickers must NOT list the identity
    // (signing) keys — only spendable keys can be a transfer source.
    ListModel {
        id: mockWalletAccounts
        ListElement { address: "3dbbbeed6cf8a8fac00d57edd1746034fa6ab6311fa78778dc07ddd4011dc726"; balance: "1,250.0 LGO"; label: "Wallet"; hint: "Your spendable balance — faucet funds land here"; group: "spendable"; fundable: true }
        ListElement { address: "5da62d70bdc0230b8a552d3f4e730658b2aef07c694eaed859f4e24aa4ccca0e"; balance: "3,000.0 LGO"; label: "Leader funding key"; hint: "Funds block proposals — fund this to earn"; group: "spendable"; fundable: true }
        ListElement { address: "6c4665db63dc20197a32e3b063e45f5281f794db707dbfb5364640522438901b"; balance: "500.0 LGO"; label: "SDP funding key"; hint: "Pays your Blend Core declaration fee"; group: "spendable"; fundable: true }
        ListElement { address: "2ca45bc4fa5bfd02a4806229d3e7669a52e590ede065263d9ec7cd370cb33b13"; balance: "500.0 LGO"; label: "BlendZk key"; hint: "Holds the note locked as your Blend Core stake"; group: "spendable"; fundable: true }
        ListElement { address: "601dcb79ef4986b5a7b786ac7d965562a065f1acc9dfa42ea8ecfd3e850802b5"; balance: ""; label: "Blend signing key"; hint: "Your node's Blend signing identity (provider_id) — matches the on-chain declaration and earns referral points"; group: "identity"; fundable: false }
        ListElement { address: "12D3KooWK6oQMAMZYFne1Mwtc1C7vvNfqLg42WDa8rQuDgR9uXRj"; balance: ""; label: "Network key"; hint: "Your node's peer identity on the network"; group: "identity"; fundable: false }
    }

    // ── scenario presets (numeric) ────────────────────────────────────────────
    function _reset(p) {
        st.status = ("status" in p) ? p.status : -1
        st.recovering = p.recovering || false
        st.autoPaused = p.autoPaused || false
        st.autoPauseReason = p.autoPauseReason || ""
        st.stalled = p.stalled || false
        st.phase = p.phase || ""
        st.err = p.err || ""
        st.mode = p.mode || ""
        st.tip = p.tip || 0
        st.head = p.head || 0
        st.peerId = p.peerId || ""
        st.blend = p.blend || "none"
        st.blendWithdrawEpoch = ("blendWithdrawEpoch" in p) ? p.blendWithdrawEpoch : -1
        st.blendMaturingEpoch = ("blendMaturingEpoch" in p) ? p.blendMaturingEpoch : -1
        st.validation = p.validation || ""
        st.epochsToActivate = p.epochsToActivate || 0
        st.eligibleNoteCount = ("eligibleNoteCount" in p) ? p.eligibleNoteCount : -1
        st.stakeLepta = ("stake" in p) ? p.stake : -1; st.addr = p.addr || ""
        st.epochN = ("epoch" in p) ? p.epoch : -1
        st.epochElapsed = ("epochElapsed" in p) ? p.epochElapsed : -1
        st.proposedN = ("proposed" in p) ? p.proposed : -1
        st.peersN = ("peers" in p) ? p.peers : -1
        st.connN = ("conn" in p) ? p.conn : -1
        st.empoweringActive = p.empowering || false
        st.empoweringMined = ("empoweringMined" in p) ? p.empoweringMined : -1
        st.empoweringTarget = ("empoweringTarget" in p) ? p.empoweringTarget : -1
        st.funded = p.funded || false
        st.cpuN = ("cpu" in p) ? p.cpu : -1
        st.cpuCapN = ("cpuCap" in p) ? p.cpuCap : -1
        st.ramN = ("ram" in p) ? p.ram : -1
        st.ramCapSet = p.ramCapSet || false
        st.earnedN = ("earned" in p) ? p.earned : -1
        st.feeN = ("fee" in p) ? p.fee : -1
        st.upSecs = ("upSecs" in p) ? p.upSecs : -1
        stallReassert.restart()   // re-apply the stall flag after the view's _recordProgress resets it
    }
    // The view zeroes nodeStalled on load; infoJson is static here, so re-assert the preset's
    // value once the load settles. Covers both the stalled presets (→ true) and clearing it (→ false).
    Timer { id: stallReassert; interval: 220; repeat: false
            onTriggered: if (typeof nodeDash !== "undefined") nodeDash.nodeStalled = st.stalled }
    readonly property var _peer: "12D3KooWQ8s...abkEwLz"
    readonly property var scenarios: [
        { key: "Fresh (not started)",     val: { status: 0 } },
        { key: "Starting",                val: { status: 1 } },
        { key: "Bootstrapping",           val: { status: 2, mode: "Online", tip: 148000, head: 148600, peerId: win._peer,
                                                  peers: 22, conn: 27, cpu: 14, cpuCap: 30, ram: 1.1, ramCapSet: false } },
        { key: "Online",                  val: { status: 2, mode: "Online", tip: 148905, head: 148905, upSecs: 12 * 3600 + 4 * 60 + 37, peerId: win._peer, epoch: 172, epochElapsed: 200,
                                                  peers: 38, conn: 43, cpu: 9, cpuCap: 30, ram: 1.2, ramCapSet: false } },
        { key: "Funded — aging",          val: { status: 2, mode: "Online", tip: 150000, head: 150000, upSecs: 1 * 3600 + 12 * 60, peerId: win._peer,
                                                  funded: true,                       // wallet funded, notes aging; node reports 0 aged notes yet
                                                  proposed: 0, eligibleNoteCount: 0, epoch: 173, epochElapsed: 500,
                                                  peers: 40, conn: 46, cpu: 10, cpuCap: 30, ram: 1.3, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        { key: "Aged — eligible",         val: { status: 2, mode: "Online", tip: 150800, head: 150800, upSecs: 22 * 3600, peerId: win._peer,
                                                  funded: true, eligibleNoteCount: 3,  // aged into the snapshot; eligible to propose (not yet won a slot)
                                                  proposed: 0, epoch: 175, epochElapsed: 120,
                                                  peers: 41, conn: 47, cpu: 10, cpuCap: 30, ram: 1.3, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        { key: "Validating",              val: { status: 2, mode: "Online", tip: 151548, head: 151548, upSecs: 345 * 3600 + 43 * 60 + 23, peerId: win._peer, funded: true,
                                                  blend: "core", epoch: 174, epochElapsed: 372, proposed: 234, validation: "active", eligibleNoteCount: 5, peers: 83, conn: 87,
                                                  empowering: true, empoweringMined: 2500, empoweringTarget: 5000, cpu: 12, cpuCap: 30, ram: 1.4, ramCapSet: false,
                                                  stake: 5000000000000, addr: "0x71bd…9e4a", earned: 1530000234000, fee: 56 } },
        // ── Blend spectrum (Online node, varying blend role) ────────────────────
        { key: "Blend — Edge",            val: { status: 2, mode: "Online", tip: 151600, head: 151600, upSecs: 40 * 3600, peerId: win._peer, funded: true,
                                                  blend: "edge", epoch: 175, epochElapsed: 240, proposed: 12, eligibleNoteCount: 3, peers: 60, conn: 66,
                                                  cpu: 10, cpuCap: 30, ram: 1.3, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        { key: "Blend — Core (mixing)",   val: { status: 2, mode: "Online", tip: 151640, head: 151640, upSecs: 60 * 3600, peerId: win._peer, funded: true,
                                                  blend: "core", epoch: 176, epochElapsed: 150, proposed: 40, eligibleNoteCount: 4, peers: 61, conn: 67,
                                                  cpu: 10, cpuCap: 30, ram: 1.3, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        { key: "Blend — declared, not mixing", val: { status: 2, mode: "Online", tip: 151700, head: 151700, upSecs: 60 * 3600, peerId: win._peer, funded: true,
                                                  blend: "coredeclared", epoch: 176, epochElapsed: 150, proposed: 40, eligibleNoteCount: 4, peers: 62, conn: 68,
                                                  cpu: 11, cpuCap: 30, ram: 1.4, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        // Declaration withdrawing → the modal's "Declaration slot free" gate blocks re-declare until it
        // clears (blend TYPE is honestly Edge meanwhile — a stale/withdrawing declaration doesn't mix).
        { key: "Blend — withdrawing",     val: { status: 2, mode: "Online", tip: 151720, head: 151720, upSecs: 60 * 3600, peerId: win._peer, funded: true,
                                                  blend: "edge", blendWithdrawEpoch: 35, epoch: 33, epochElapsed: 150, proposed: 40, eligibleNoteCount: 4, peers: 62, conn: 68,
                                                  cpu: 11, cpuCap: 30, ram: 1.4, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        // Declared + live on-chain but pre-active: the modal opens the manage view ("activating at epoch N")
        // and never invites a re-declare — the stake is already locked.
        { key: "Blend — declared, maturing", val: { status: 2, mode: "Online", tip: 151730, head: 151730, upSecs: 60 * 3600, peerId: win._peer, funded: true,
                                                  blend: "coredeclared", blendMaturingEpoch: 37, epoch: 35, epochElapsed: 150, proposed: 40, eligibleNoteCount: 4, peers: 62, conn: 68,
                                                  cpu: 11, cpuCap: 30, ram: 1.4, ramCapSet: false, stake: 5000000000000, addr: "0x71bd…9e4a" } },
        // ── recovery / trouble heroes ───────────────────────────────────────────
        { key: "Replaying blocks",        val: { status: 2, mode: "Online", recovering: true, tip: 149000, head: 151000, peerId: win._peer, peers: 30, conn: 35 } },
        { key: "Bootstrap stuck",         val: { status: 2, mode: "Online", stalled: true, phase: "ProlongedBootstrapPeriod", tip: 148600, head: 152000, peerId: win._peer, peers: 3, conn: 4 } },
        { key: "Sync stalled",            val: { status: 2, mode: "Online", stalled: true, tip: 148600, head: 152000, peerId: win._peer, peers: 6, conn: 8 } },
        { key: "Node auto-paused",        val: { status: 4, autoPaused: true, autoPauseReason: "CPU cap of 30%" } },
        { key: "Error",                   val: { status: 5, err: "Node error: connection refused (rpc :3000)" } }
    ]

    // ── live tick: advance ONLY what fits the current state ─────────────────────
    // Running: network head advances; tip catches up while bootstrapping, then
    // moves in lockstep once synced (Slot/Height climb → the tiles flash green).
    // Metrics jitter only when present (i.e., only in states where they fit).
    Timer {
        id: live; interval: 1200; repeat: true; running: st.running
        onTriggered: {
            // A stalled/stuck node's HEIGHT is frozen (that's the whole signal): let the network
            // head climb (so it visibly falls behind) but never advance tip — otherwise the view's
            // _recordProgress() sees height move and clears nodeStalled, hiding the hero.
            if (st.stalled) { st.head += 1; return }
            st.head += 1
            var behind = st.head - st.tip
            if (behind > 3) {
                st.tip = Math.min(st.head, st.tip + Math.max(60, Math.round(behind * 0.25)))   // converging bootstrap
            } else {
                st.tip = st.head                                                                // synced → lockstep
                if (st.upSecs < 0) st.upSecs = 0                                                // start uptime on first sync
                else st.upSecs += 2
            }
            if (st.cpuN >= 0) st.cpuN = 8 + Math.random() * 12
            if (st.ramN >= 0) st.ramN = 1.2 + Math.random() * 0.5
            if (st.peersN >= 0) {
                st.peersN = Math.max(1, st.peersN + (Math.floor(Math.random() * 4) - 1))
                if (st.connN >= 0) st.connN = st.peersN + 2 + Math.floor(Math.random() * 5)   // connections ≥ peers, always
            }
            if (st.proposedN >= 0 && st.validation === "active" && Math.random() < 0.4) st.proposedN += 1
            if (st.earnedN >= 0 && Math.random() < 0.3) st.earnedN += Math.floor(Math.random() * 3)
            // mining climbs toward the target; at 100% it STOPS and the wallet is funded
            if (st.empoweringActive && st.empoweringTarget > 0) {
                st.empoweringMined = Math.min(st.empoweringTarget, st.empoweringMined + Math.max(50, Math.round(st.empoweringTarget * 0.03)))
                if (st.empoweringMined >= st.empoweringTarget) {
                    st.funded = true                         // wallet funded
                    st.empoweringActive = false              // mining stops (not pause)
                    st.empoweringMined = -1; st.empoweringTarget = -1   // tile → "—"
                }
            }
            // aging: funded notes wait ~2 epochs before they can lead; count the epochs
            // down, then validation goes active (node starts proposing).
            if (st.validation === "inactive" && st.epochsToActivate > 0) {
                win._agingTicks++
                if (win._agingTicks % 5 === 0) {
                    st.epochsToActivate -= 1
                    if (st.epochsToActivate <= 0) { st.validation = "active"; st.proposedN = Math.max(st.proposedN, 0) }
                }
            }
            // epoch clock advances; at the end a new epoch begins
            if (st.epochElapsed >= 0) {
                st.epochElapsed += 3
                if (st.epochElapsed >= st.epochLen) { st.epochElapsed = 0; if (st.epochN >= 0) st.epochN += 1 }
            }
        }
    }
    property int _agingTicks: 0

    // ── scripted Start → Online: kick to bootstrapping, let the live tick converge ──
    property int _seqStep: 0
    Timer {
        id: seq; interval: 1400; repeat: true; running: false
        onTriggered: {
            win._seqStep++
            if (win._seqStep === 1) { win._reset({ status: 1 }) }                                                  // Starting
            else if (win._seqStep === 2) { win._reset({ status: 2, mode: "Online", tip: 148200, head: 148700, peerId: win._peer }) }  // Bootstrapping → live tick converges to Online
            else { seq.running = false; win._seqStep = 0 }
        }
    }
    function playStart() { win._reset({ status: 0 }); win._seqStep = 0; seq.running = true }

    // ── Blend wizard (tab 6): which step is showing ──
    property int blendStep: 1   // 1 Declaration · 2 Activation · 3 Active

    // The SHIPPED BlendCoreProgress reducer output, mapped from the wizard's
    // current evidence. Deliberately NOT a linear wizard readout: the strip
    // reflects independent evidence per stage (per the state-gallery critique).
    readonly property var _blendLifecycle: {
        function S(a, b, c, d, e, f) { return [
            { label: qsTr("Online"), state: a }, { label: qsTr("Declared"), state: b },
            { label: qsTr("Activated"), state: c }, { label: qsTr("Connected"), state: d },
            { label: qsTr("Activity"), state: e }, { label: qsTr("Maintaining"), state: f } ] }
        if (blendStep === 1) {
            if (!blendDecl.nodeUp)
                return { title: qsTr("Evidence unavailable — node offline"), tone: "warning", action: "refresh", actionLabel: qsTr("Refresh"),
                         detail: qsTr("The node isn't running, so Blend Core evidence can't be read. This is unknown, not \"not declared\"."),
                         evidence: qsTr("No current evidence; nothing inferred."), steps: S("current", "pending", "pending", "pending", "pending", "pending") }
            return { title: blendDecl.phase === "submitting" ? qsTr("Submitting declaration…") : !blendDecl.allGreen ? qsTr("Not declared — checks pending") : qsTr("Ready to declare"),
                     tone: blendDecl.phase === "submitting" ? "warning" : !blendDecl.allGreen ? "warning" : "success",
                     action: "refresh", actionLabel: qsTr("Refresh"),
                     detail: qsTr("Your node is online but not yet a Blend provider. Clear the checks below, then submit the declaration."),
                     evidence: qsTr("No declaration on-chain yet."),
                     steps: S("complete", "current", "pending", "pending", "pending", "pending") }
        }
        if (blendStep === 2) {
            var risk = blendAct.subState === "stalled"
            return { title: risk ? qsTr("Activation at risk") : qsTr("Activating — awaiting Core membership"),
                     tone: risk ? "error" : "warning", action: "refresh", actionLabel: qsTr("Refresh"),
                     detail: qsTr("Declared on-chain. \"Activated\" means the node is actually admitted as Core — not merely past created + 2 epochs. Keep it reachable and heartbeating."),
                     evidence: qsTr("Declared at epoch %1; current membership evidence pending.").arg(blendAct.createdEpoch),
                     steps: S("complete", "complete", risk ? "error" : "current", "pending", "pending", "pending") }
        }
        if (blendLive.subState === "withdrawn")
            return { title: qsTr("Withdrawn — not declared"), tone: "warning", action: "refresh", actionLabel: qsTr("Refresh"),
                     detail: qsTr("The declaration was withdrawn and the staked note unlocked. Declare again to rejoin Blend Core."),
                     evidence: qsTr("No current Core membership."), steps: S("complete", "pending", "pending", "pending", "pending", "pending") }
        if (blendLive.subState === "withdrawing")
            return { title: qsTr("Withdrawal scheduled"), tone: "warning", action: "manage", actionLabel: qsTr("Manage"),
                     detail: qsTr("Withdrawal requested. The node has stopped mixing; the staked note unlocks at epoch %1.").arg(blendLive.withdrawAtEpoch),
                     evidence: qsTr("Winding down; membership ending."), steps: S("complete", "complete", "complete", "complete", "complete", "current") }
        return { title: qsTr("Blend Core active"), tone: "success", action: "manage", actionLabel: qsTr("Manage"),
                 detail: qsTr("Current Blend Core member: healthy peers and recent accepted activity."),
                 evidence: qsTr("Membership + healthy peers + recent activity (nonce %1). Nonce alone is not proof.").arg(blendLive.nonce),
                 steps: S("complete", "complete", "complete", "complete", "complete", "complete") }
    }

    // ── Blend wizard state presets ──
    function _decl(p) {
        blendDecl.gSynced    = ("gSynced" in p)    ? p.gSynced    : true
        blendDecl.gFunded    = ("gFunded" in p)    ? p.gFunded    : true
        blendDecl.gZkFunded  = ("gZkFunded" in p)  ? p.gZkFunded  : true
        blendDecl.gNetwork   = ("gNetwork" in p)   ? p.gNetwork   : true
        blendDecl.slotFree   = ("slotFree" in p)   ? p.slotFree   : true
        blendDecl.natState   = p.natState || "reachable"
        blendDecl.ipDynamic  = p.ipDynamic || false
        blendDecl.phase      = p.phase || "idle"
        blendDecl.errorText  = p.errorText || ""
        win.blendStep = 1
        studioTabs.currentIndex = 6
    }
    function _activate(p) {
        blendAct.subState    = p.subState || "activating"
        blendAct.progress    = ("progress" in p) ? p.progress : 0.45
        blendAct.etaText     = p.etaText || qsTr("~1h 10m")
        blendAct.heartbeatOk = ("heartbeatOk" in p) ? p.heartbeatOk : true
        blendAct.natState    = p.natState || "reachable"
        win.blendStep = 2
        studioTabs.currentIndex = 6
    }
    function _live(p) {
        blendLive.subState    = p.subState || "active"
        blendLive.nonce       = ("nonce" in p) ? p.nonce : 47
        blendLive.heartbeatOk = ("heartbeatOk" in p) ? p.heartbeatOk : true
        blendLive.natState    = p.natState || "reachable"
        win.blendStep = 3
        studioTabs.currentIndex = 6
    }
    // submit → maturing → active lifecycle chain
    Timer { id: declSubmit;  interval: 1600; repeat: false; onTriggered: { blendDecl.phase = "submitted"; toActivate.restart() } }
    Timer { id: toActivate;  interval: 1100; repeat: false; onTriggered: win._activate({ subState: "activating", progress: 0.12, etaText: qsTr("~1h 50m") }) }
    Timer { id: blendWithdraw; interval: 1600; repeat: false; onTriggered: blendLive.subState = "withdrawn" }

    readonly property bool _grabMode: Qt.application.arguments.indexOf("--grab") >= 0
    readonly property int _grabScenario: { var i = Qt.application.arguments.indexOf("--scenario"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : 4 }
    readonly property int _grabTab: { var i = Qt.application.arguments.indexOf("--tab"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : 0 }
    readonly property bool _grabOnboarding: Qt.application.arguments.indexOf("--onboarding") >= 0
    readonly property int _grabObStep: { var i = Qt.application.arguments.indexOf("--ob-step"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : -1 }
    Component.onCompleted: {
        win._reset(win.scenarios[_grabMode ? _grabScenario : 3].val)
        if (_grabMode) studioTabs.currentIndex = _grabTab
        if (Qt.application.arguments.indexOf("--dragexp") >= 0) win._dragExp = true
        // --blendstep N: drive the Blend wizard to step N (2 = activation, 3 = active) for grabs
        var _bi = Qt.application.arguments.indexOf("--blendstep")
        if (_bi >= 0 && _bi + 1 < Qt.application.arguments.length) {
            var _bs = parseInt(Qt.application.arguments[_bi + 1])
            if (_bs === 2) win._activate({ subState: "activating", progress: 0.45 })
            else if (_bs === 3) win._live({ subState: "active" })
        }
        // Render the Enable-Blend-Core modal open (over the chosen scenario); --port opens UDP 3400.
        if (Qt.application.arguments.indexOf("--blendmodal") >= 0) {
            if (Qt.application.arguments.indexOf("--port") >= 0) win._blendPortOpen = true
            win._blendModal = true
        }
        if (_grabOnboarding) {
            win._onboarding = true
            if (_grabObStep >= 0) {
                onboardingFlow.advanced = true; onboardingFlow.step = _grabObStep
                onboardingFlow.mode = (Qt.application.arguments.indexOf("--ob-existing") >= 0) ? "existing" : "generate"
            }   // else: landing
        }
    }

    // ── layout: dashboard (left) + control panel (right) ──────────────────────
    RowLayout {
        anchors.fill: parent; spacing: 0

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

            // thin "back up your keys" banner — shows while the node is up and keys
            // aren't backed up yet. Quick start leaves keys unbacked (banner on);
            // Download in Settings, or backing up during Advanced setup, clears it.
            Rectangle {
                Layout.fillWidth: true
                visible: st.running && !win._keysBackedUp
                color: Theme.palette.error
                implicitHeight: bannerRow.implicitHeight + Theme.spacing.small * 2
                RowLayout {
                    id: bannerRow
                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spacing.large; anchors.rightMargin: Theme.spacing.large
                    spacing: Theme.spacing.medium
                    LogosText {
                        Layout.fillWidth: true; text: qsTr("Back up your keys. If you lose them, you lose access to this node.")
                        color: "#FFFFFF"; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium
                    }
                    LogosButton { text: qsTr("Back up"); onClicked: studioTabs.currentIndex = 5 }   // → Settings
                }
            }

            // header (prototype chrome — mirrors BlockchainView's real header)
            RowLayout {
                Layout.fillWidth: true; Layout.margins: Theme.spacing.large; spacing: Theme.spacing.medium
                Image {
                    source: Qt.resolvedUrl("../src/qml/icons/logos.svg")
                    sourceSize.width: 30; sourceSize.height: 30
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter; fillMode: Image.PreserveAspectFit
                }
                LogosText { text: "Blockchain Node"; color: Theme.palette.text; font.pixelSize: 28; font.weight: Theme.typography.weightBold; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                // Small header buttons (mirror the fork): Fund = small gray, Start/Stop = small orange.
                C.GhostButton {
                    // Fund/Pause toggle — starts/pauses background mining directly (no modal).
                    // The stake target is set in Settings → Mining. Pause keeps progress.
                    text: st.empoweringActive ? qsTr("Pause mining") : qsTr("Fund")
                    enabled: st.running; Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        if (st.empoweringActive) {
                            st.empoweringActive = false          // pause — keep mined progress
                        } else {
                            st.empoweringActive = true
                            if (st.empoweringTarget <= 0) st.empoweringTarget = 1000   // LGO default (editable in Settings)
                            if (st.empoweringMined < 0) st.empoweringMined = 330        // demo: 33% toward target
                        }
                    }
                }
                // Blend header action — matrix mirrors the fork: core → "Blend Core active" ·
                // declared (coredeclared) → "Blend Core declared" · edge → "Enable Core" · else Enable.
                C.GhostButton {
                    visible: st.running
                    text: st.blend === "core" ? qsTr("Blend Core active")
                          : st.blend === "coredeclared" ? qsTr("Blend Core declared")
                          : st.blend === "edge" ? qsTr("Enable Core")
                          : qsTr("Enable Blend Core")
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: win._blendModal = true
                }
                C.CtaButton {
                    compact: true
                    text: st.running ? qsTr("Stop") : qsTr("Start")
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: st.running ? win._reset({ status: 4 }) : win.playStart()
                }
            }

            // tab bar chrome (mirrors BlockchainView; only Dashboard is live in the studio)
            LogosTabBar {
                id: studioTabs
                Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large
                currentIndex: 0
                // Mirrors the fork nav (Explorer folded into Blocks; Rewards promoted).
                LogosTabButton { text: qsTr("Node") }
                LogosTabButton { text: qsTr("Rewards") }
                LogosTabButton { text: qsTr("Explorer") }
                LogosTabButton { text: qsTr("Proposals") }
                LogosTabButton { text: qsTr("Wallet") }        // groups Accounts · Transfer · Channel Deposit (pages TBD)
                LogosTabButton { text: qsTr("Settings") }
                LogosTabButton { text: qsTr("Blend") }
            }

            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.topMargin: Theme.spacing.large     // breathing room between the tab bar and the page title
                currentIndex: studioTabs.currentIndex     // tab-aligned: 0 Node … 5 Settings
                V.NodeDashboardView {
                id: nodeDash
                onEnableBlendRequested: win._blendModal = true   // Blend tile CTA → open the modal
                status: st.status
                nodeRecovering: st.recovering
                autoPaused: st.autoPaused
                autoPauseReason: st.autoPauseReason
                // nodeStalled is LIVE-computed in the view (a 10-min height-freeze timer) and its
                // _recordProgress() resets it to false on load, so we can't just bind it. infoJson
                // is static in the studio, so we re-assert the preset's stall flag once after load
                // settles (win.stallReassert) and it sticks.
                lastErrorMessage: st.err
                infoJson: st.infoJson
                timeInfoJson: st.timeInfoJson
                peerId: st.peerId
                nodeRunning: st.running
                blendState: st.blend
                epoch: st.epoch
                epochProgress: st.epochProgress
                proposed: st.proposed
                validation: st.validation
                epochsToActivate: st.epochsToActivate
                eligibleNoteCount: st.eligibleNoteCount
                peers: st.peers
                connections: st.connections
                empoweringActive: st.empoweringActive
                empoweringMined: st.empoweringMined
                empoweringTarget: st.empoweringTarget
                funded: st.funded
                cpu: st.cpu; cpuCap: st.cpuCap
                ram: st.ram; ramCap: st.ramCap
                stakeStr: st.stakeLepta >= 0 ? Amounts.short(st.stakeLepta) : "—"; foundingAddr: st.addr
                earnedStr: st.earned; feePct: st.fee
                uptime: st.uptime
                // Mock earnings so the (now gated) "Earned by epoch" chart renders in the studio.
                earnedByEpoch: st.running ? (function(){ var a=[]; for (var e=20; e<50; e++) a.push({ epoch: e, lepta: Math.round((0.5 + 0.45*Math.sin(e*0.7)) * 900000000) }); return a })() : []
                }
                // Real fork views driven with mock data (#99–#103), index-aligned to the tabs
                // Rewards (tab 1)
                V.LeaderRewardsView {
                    vouchersJson: win.mockVouchersJson
                    claimsJson: win.mockClaimsJson
                    proposalsJson: win.mockProposalsJson
                    balance: 5000000000
                    currentEpoch: 11
                    autoClaim: true
                    slotNow: 411800
                    claimInFlight: false
                    onClaimLeaderRewardsRequested: {}
                    onClearClaimsRequested: {}
                    onCopyToClipboard: (t) => {}
                }
                // Blocks (tab 2) — Explorer folded in
                V.BlocksView {
                    blockModel: mockBlockModel
                    myKey: "0x8a3f10d2e5c7b9a0f1"
                    currentEpoch: 11
                    nodeRunning: st.running
                    bootstrapping: false
                    onClearRequested: {}
                    onCopyToClipboard: (t) => {}
                    onSearchRequested: (id) => {}
                }
                // Proposals (tab 3)
                V.ProposalsView {
                    proposalsJson: win.mockProposalsJson
                    voucherCount: 2
                    currentEpoch: 11
                    onCopyToClipboard: (t) => {}
                    onOpenLeaderRewardsRequested: studioTabs.currentIndex = 1
                    onClearRequested: {}
                }
                // Wallet (tab 4) — left SIDEBAR (Accounts · Transfer · Channel Deposit) + content,
                // matching the fork's Wallet operations layout (anchor-based, not horizontal tabs).
                Item {
                    id: walletPage
                    property int walletNav: 0
                    ColumnLayout {
                        id: walletSidebar
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 180; spacing: Theme.spacing.tiny
                        Repeater {
                            model: [qsTr("Accounts"), qsTr("Transfer"), qsTr("Channel Deposit")]
                            delegate: Rectangle {
                                required property int index
                                required property string modelData
                                Layout.fillWidth: true; implicitHeight: 40
                                radius: Theme.spacing.radiusMedium
                                color: walletPage.walletNav === index ? Theme.palette.backgroundTertiary : "transparent"
                                LogosText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: Theme.spacing.medium
                                    text: modelData
                                    color: walletPage.walletNav === index ? Theme.palette.text : Theme.palette.textSecondary
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.weight: walletPage.walletNav === index ? Theme.typography.weightMedium : Theme.typography.weightRegular
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: walletPage.walletNav = index }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                    Rectangle {
                        id: walletDivider
                        anchors.left: walletSidebar.right; anchors.leftMargin: Theme.spacing.large
                        anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: 1; color: Theme.palette.borderSecondary
                    }
                    StackLayout {
                        anchors.left: walletDivider.right; anchors.leftMargin: Theme.spacing.large
                        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                        currentIndex: walletPage.walletNav
                        V.AccountsView { accountsModel: mockWalletAccounts; onGetBalanceRequested: (a) => {}; onFundRequested: (a) => {}; onRefreshAccountsRequested: () => {}; onCopyToClipboard: (t) => {} }
                        V.TransferView { accountsModel: mockAccountsModel; onTransferRequested: (f, to, a) => {}; onCopyToClipboard: (t) => {} }
                        V.ChannelDepositView { accountsModel: mockAccountsModel; nodeRunning: st.running; onGetNotesRequested: (a, b) => {}; onSubmitRequested: () => {}; onCopyToClipboard: (t) => {} }
                    }
                }
                V.SettingsView {
                    onCopyText: (t) => {}
                    onKeysBackedUp: win._keysBackedUp = true
                    // Mining card ↔ shared mock state (Fund/Pause button drives the same st)
                    miningEnabled: st.empoweringActive
                    miningTarget: st.empoweringTarget > 0 ? String(st.empoweringTarget) : "1000"
                    // Always show representative mined/progress in the studio (330 of 1000 = 33%),
                    // even before Fund is pressed, so the card demonstrates the states.
                    miningMined: st.empoweringMined >= 0 ? st.empoweringMined : 330
                    onMiningToggled: (on) => {
                        st.empoweringActive = on
                        if (on) {
                            if (st.empoweringTarget <= 0) st.empoweringTarget = 1000
                            if (st.empoweringMined < 0) st.empoweringMined = 330
                        }
                    }
                    onMiningTargetApplied: (t) => st.empoweringTarget = Number(t) || 1000
                }
                // Blend (tab 6) — enable-Blend-Core wizard. Top: the SHIPPED
                // BlendCoreProgress evidence strip + status (independent evidence,
                // not a wizard sequence), pinned. Below: the current wizard step,
                // which scrolls inside itself.
                ColumnLayout {
                    spacing: Theme.spacing.large
                    BlendCoreProgress {
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; Layout.topMargin: Theme.spacing.large
                        implicitWidth: 0
                        lifecycle: win._blendLifecycle
                        backendReady: true
                        onRefreshRequested: {}
                        onManageRequested: win.blendStep = 3
                        onRepairRequested: {}
                    }
                    StackLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        currentIndex: Math.max(0, Math.min(2, win.blendStep - 1))
                        BlendDeclarationProto {
                            id: blendDecl
                            nodeStatus: st.status
                            nodeError: st.err
                            onSubmitRequested: { blendDecl.phase = "submitting"; declSubmit.restart() }
                            onStartNodeRequested: win.playStart()
                            onCopyText: (t) => {}
                        }
                        BlendActivationProto {
                            id: blendAct
                            nodeStatus: st.status
                            nodeError: st.err
                            onCancelRequested: { win.blendStep = 1; blendDecl.phase = "idle"; blendDecl.slotFree = false }
                            onStartNodeRequested: win.playStart()
                            onCopyText: (t) => {}
                        }
                        BlendActiveProto {
                            id: blendLive
                            onWithdrawRequested: { blendLive.subState = "withdrawing"; blendWithdraw.restart() }
                            onRestartRequested: { win.blendStep = 1; blendDecl.phase = "idle"; blendDecl.slotFree = true }
                            onCopyText: (t) => {}
                        }
                    }
                }
            }
        }

        // ── control panel ──
        Rectangle {
            Layout.preferredWidth: 300; Layout.fillHeight: true
            color: Theme.palette.surface
            QQC.ScrollView {
                anchors.fill: parent; contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width; spacing: Theme.spacing.large
                    Layout.margins: Theme.spacing.large

                    LogosText { text: "Prototype Studio"; color: Theme.palette.text; font.pixelSize: 16; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large; Layout.topMargin: Theme.spacing.large }

                    // scenarios
                    LogosText { text: "SCENARIOS"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        Repeater {
                            model: win.scenarios
                            LogosButton {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData.key
                                onClicked: win._reset(modelData.val)
                            }
                        }
                    }

                    // flows (full-screen prototype journeys)
                    LogosText { text: "FLOWS"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        LogosButton { Layout.fillWidth: true; text: "▶ Start onboarding"; variant: LogosButton.Variant.Primary; onClicked: win._onboarding = true }
                        LogosButton { Layout.fillWidth: true; text: "▶ Enable Blend Core (modal)"; onClicked: win._blendModal = true }
                        LogosButton { Layout.fillWidth: true; text: "▶ Drag-reorder tiles (experiment)"; onClicked: win._dragExp = true }
                    }

                    // live actions
                    LogosText { text: "INTERACTIONS"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        LogosButton { Layout.fillWidth: true; text: "▶ Play Start → Online"; variant: LogosButton.Variant.Primary; onClicked: win.playStart() }
                        LogosButton { Layout.fillWidth: true; text: "Cycle Blend: " + st.blend
                            onClicked: st.blend = st.blend === "none" ? "edge" : st.blend === "edge" ? "coredeclared" : st.blend === "coredeclared" ? "core" : "none" }
                        LogosButton { Layout.fillWidth: true; text: "Blend modal: UDP 3400 " + (win._blendPortOpen ? "open ✓" : "closed ✕")
                            onClicked: win._blendPortOpen = !win._blendPortOpen }
                    }

                    // Blend wizard states (tab 6) — step 1 Declaration · step 2 Activation · step 3 Active
                    LogosText { text: "BLEND · STEP 1 DECLARATION"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        LogosButton { Layout.fillWidth: true; text: "▶ Run full lifecycle"; variant: LogosButton.Variant.Primary; onClicked: { win._decl({}); declSubmit.stop(); toActivate.stop(); blendDecl.phase = "submitting"; declSubmit.restart() } }
                        LogosButton { Layout.fillWidth: true; text: "✓ Ready (all pass)"; onClicked: win._decl({}) }
                        LogosButton { Layout.fillWidth: true; text: "Submitting…"; onClicked: win._decl({ phase: "submitting" }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Not synced"; onClicked: win._decl({ gSynced: false }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ BlendZk key unfunded"; onClicked: win._decl({ gZkFunded: false }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ SDP key unfunded"; onClicked: win._decl({ gFunded: false }) }
                        LogosButton { Layout.fillWidth: true; text: "◴ NAT: checking"; onClicked: win._decl({ natState: "checking" }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ NAT: Core not listening"; onClicked: win._decl({ natState: "notlistening" }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ NAT: unreachable"; onClicked: win._decl({ natState: "unreachable" }) }
                        LogosButton { Layout.fillWidth: true; text: "⚠ Reachable, IP dynamic"; onClicked: win._decl({ ipDynamic: true }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Network too small"; onClicked: win._decl({ gNetwork: false }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Slot blocked (withdrawing)"; onClicked: win._decl({ slotFree: false }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Submit error"; onClicked: win._decl({ phase: "error", errorText: "Declaration rejected: staked note already locked." }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Node not started"; onClicked: { win._reset({ status: 0 }); win.blendStep = 1; studioTabs.currentIndex = 6 } }
                        LogosButton { Layout.fillWidth: true; text: "✕ Node error"; onClicked: { win._reset({ status: 5, err: "Node error: connection refused (rpc :3000)" }); win.blendStep = 1; studioTabs.currentIndex = 6 } }
                    }

                    LogosText { text: "BLEND · STEP 2 ACTIVATION"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        LogosButton { Layout.fillWidth: true; text: "◴ Activating (maturing)"; onClicked: win._activate({ subState: "activating", progress: 0.45 }) }
                        LogosButton { Layout.fillWidth: true; text: "◴ Almost active (95%)"; onClicked: win._activate({ subState: "activating", progress: 0.95, etaText: "~5m" }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Heartbeat missed (at risk)"; onClicked: win._activate({ subState: "stalled", heartbeatOk: false }) }
                        LogosButton { Layout.fillWidth: true; text: "✕ Reachability dropped"; onClicked: win._activate({ subState: "stalled", natState: "unreachable" }) }
                    }

                    LogosText { text: "BLEND · STEP 3 ACTIVE"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        LogosButton { Layout.fillWidth: true; text: "✓ Active (mixing)"; onClicked: win._live({ subState: "active" }) }
                        LogosButton { Layout.fillWidth: true; text: "↩ Withdrawing"; onClicked: win._live({ subState: "withdrawing" }) }
                        LogosButton { Layout.fillWidth: true; text: "— Withdrawn"; onClicked: win._live({ subState: "withdrawn" }) }
                    }

                    LogosText {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large
                        text: "Edit design/node-dashboard/prototype presets to add states. This drives the real NodeDashboardView with mock data — no node."
                        color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // Onboarding prototype — full-window first-run flow, launched from the control panel.
    // "Start from it": takes over the window; Finish/Exit returns to the studio.
    Rectangle {
        anchors.fill: parent; visible: win._onboarding; z: 100
        color: Theme.palette.background
        OnboardingProto {
            id: onboardingFlow
            anchors.fill: parent
            onFinished: (keysBackedUp) => { win._onboarding = false; win._keysBackedUp = keysBackedUp; win.playStart() }
            onExitRequested: win._onboarding = false
        }
    }

    // Enable-Blend-Core modal (epic #89) — gated checklist → Enable → Enabling stages → Core.
    // The port gate (UDP 3400) starts red; flip it via the control panel to demo green → Enable.
    EnableBlendCoreProto {
        anchors.fill: parent; visible: win._blendModal; z: 200
        gPort: win._blendPortOpen
        blendState: st.blend
        withdrawEpoch: st.blendWithdrawEpoch
        maturingEpoch: st.blendMaturingEpoch
        onClosed: win._blendModal = false
        onDeclared: st.blend = "coredeclared"  // declaration submitted → declared, maturing (Edge meanwhile)
        onReachedCore: st.blend = "core"     // activated → Core
        onDisabled: st.blend = "edge"        // withdrawal → back to Edge
    }

    // Drag-reorder experiment — fixed Status hero on top, draggable metric tiles below.
    Rectangle {
        anchors.fill: parent; visible: win._dragExp; z: 100
        color: Theme.palette.background
        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.spacing.xlarge; spacing: Theme.spacing.large
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    LogosText { text: "Drag-reorder tiles"; color: Theme.palette.text; font.pixelSize: Theme.typography.titleText; font.weight: Theme.typography.weightBold }
                    LogosText { text: "Hover a lower card, grab the grip in its corner, drag it to a gap. The Status hero stays put."; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                }
                LogosButton { text: "Exit"; onClicked: win._dragExp = false }
            }
            // fixed Status hero (NOT draggable — the contrast the experiment is testing)
            LogosFrame {
                Layout.fillWidth: true; Layout.preferredHeight: 96
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
                contentItem: ColumnLayout {
                    spacing: 2
                    LogosText { text: "Online"; color: Theme.palette.success; font.pixelSize: 32; font.weight: Theme.typography.weightBold }
                    LogosText { text: "Status — fixed"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                }
            }
            DragGridExperiment { Layout.fillWidth: true; Layout.fillHeight: true }
        }
    }

    // Start Empowering modal — set a target, then mining climbs toward it
    V.EmpoweringModal {
        id: empoweringModal
        onStartRequested: (t) => { st.empoweringActive = true; st.empoweringTarget = t; st.empoweringMined = 0 }
    }

    // offscreen proof: grab a frame + quit (only with --grab; interactive runs stay open)
    readonly property int _grabDelay: { var i = Qt.application.arguments.indexOf("--grabdelay"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : 1800 }
    // Save target: --grabout <path> if given, else "proto.png" beside the run cwd (gitignored). Portable —
    // no machine-specific path, so a render works from any checkout of the fork.
    readonly property string _grabOut: { var i = Qt.application.arguments.indexOf("--grabout"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? Qt.application.arguments[i + 1] : "proto.png" }
    Timer {
        interval: win._grabDelay; repeat: false; running: win._grabMode
        onTriggered: win.contentItem.grabToImage(function(r){ r.saveToFile(win._grabOut); Qt.callLater(Qt.quit) })
    }
}
