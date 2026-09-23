import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
// BlendStatus enum (Off/WaitingForOnline/Edge/Core/Broadcast/…/Activating).
import Logos.BlockchainBackend 1.0
import "../controls"

// ── BLEND tab — ENABLE / MANAGE BLEND CORE, wired to the real backend ───────
// The Blend tab: the shipped BlendCoreProgress evidence strip on top (fed by the
// real lifecycle reducer via `controller`), then the enable/manage flow as a
// phase-driven wizard. Same phase machine as the former modal (epic #89, #90-#96):
//   gates → enabling → activated  |  core → disabling → disabled
// Gates + stages mirror the declaration proven on sneg (fund sdp funding_pk →
// POST /blend/join {locator, locked_note_id} → declaration → active at created+2
// epochs → Mode::Core). Disable requests withdrawal. This REPLACES EnableBlendCoreModal
// (#119) and the Node-page block (#118) + header button (#120). DS controls only.
Item {
    id: root

    property var backend: null
    // The blend lifecycle reducer/controller (BlockchainView owns the instance).
    property var controller: null
    // Ask the shell to switch to the Wallet tab (Fund the keys there).
    signal openWallet()
    // The owner binds this to QtRO readiness, not merely replica existence.
    property bool backendReady: false
    onBackendReadyChanged: if (!backendReady) _mutationUnknown(qsTr("Connection lost"))
    onBackendChanged: _mutationUnknown(qsTr("Backend changed"))
    property bool requestBusy: false
    readonly property bool mutationBusy: requestBusy || faucetBusy
    property int _mutationGeneration: 0
    property string _mutationReturnPhase: "gates"

    Timer {
        id: mutationDeadline
        interval: 20000
        onTriggered: root._mutationUnknown(qsTr("Request timed out"))
    }
    function _mutationUnknown(reason) {
        if (!requestBusy) return
        ++_mutationGeneration
        mutationDeadline.stop()
        requestBusy = false
        phase = _mutationReturnPhase
        errorText = qsTr("%1 — outcome unknown. Check chain evidence before retrying; this request will not be retried automatically.").arg(String(reason))
    }
    function _mutate(call, completed) {
        requestBusy = true
        _mutationReturnPhase = phase === "disabling" ? "core" : "gates"
        var token = ++_mutationGeneration
        mutationDeadline.restart()
        function failed(e) {
            if (token !== root._mutationGeneration) return
            root._mutationUnknown(e)
        }
        try {
            logos.watch(call(), function(r) {
                if (token !== root._mutationGeneration) return
                ++root._mutationGeneration
                mutationDeadline.stop()
                root.requestBusy = false
                completed(r)
            }, failed)
        } catch (e) { failed(e) }
    }

    // ── phase machine (identical to the prototype) ──
    // gates | enabling | activated | core | disabling | disabled
    property string phase: "gates"
    property int step: 0               // enabling sub-step: 0 submit · 1 in-block · 2 activating
    property string errorText: ""      // enable/disable failure surfaced verbatim from the node
    property string txId: ""           // declaration id returned by /blend/join
    property int coreEpoch: -1         // the epoch our declaration activates (mineActive)
    property int withdrawEpoch: -1     // if our declaration is withdraw-pending, the epoch it clears (mineWithdrawAt)
    property string faucetMsg: ""      // funded-gate faucet feedback (requesting / result / why-nothing)
    property bool   faucetBusy: false  // a faucet request is in flight

    // ── real gate state (populated by the backend polls) ──
    property string sdpKey: ""
    property real   sdpBalance: -1     // lepta on the sdp funding key; <0 = unknown
    property int    noteCount: -1      // lockable notes on a node key; <0 = unknown
    property string lockNoteId: ""     // the note id we'll stake (largest available)
    property int    blendPort: 3400
    property string locator: ""
    property string publicIp: ""
    property bool   portListening: false   // a local listener holds udp/<blendPort>
    property bool   portAttested: false    // operator confirmed the router port-forward
    // external reachability probe (epic #124): "" | reachable | unreachable | unknown
    property bool   reachChecking: false
    property string reachVerdict: ""
    property string reachDetail: ""
    property int    netCount: -1          // active BN declarations on the network
    // our existing on-chain declaration, for the "declaration slot free" gate
    property string mineId: ""             // our declaration id on-chain ("" = none)
    property bool   mineLive: false        // our declaration is is_active this epoch
    property int    mineInactiveSince: -1  // epoch our declaration went/goes inactive (active + 2)
    property int    nowEpoch: -1           // current epoch (from the declarations poll)
    // Full on-chain record of our declaration (Activation/Active pages). All real.
    property int    createdEpoch: -1       // record.created
    property int    recNonce: -1           // record.nonce (liveness signal — not proof alone)
    property string recNote: ""            // record.locked_note_id (staked note)
    property string recProvider: ""        // record.provider_id (Blend signing key)
    property string recZk: ""              // record.zk_id (BlendZk key)
    property string recLocator: ""         // record.locators[0] (published address)
    // Config identity (for the pre-declare "what you'll publish" block).
    property string identProvider: ""      // non_ephemeral_signing_key_id
    property string identZk: ""            // blend.core.zk secret_key_kms_id
    // node run state for the node-not-running gate (BlockchainStatus enum)
    readonly property int nodeStatus: (backend && typeof backend.status === "number") ? backend.status : -1
    readonly property bool nodeUp: nodeStatus === BlockchainBackend.Running
    // Node time info (current_slot / slot_duration_ms), plumbed from BlockchainView like the
    // Epoch tile (#132). Lets the activation bar show real TIME across created→active epochs.
    property string timeInfoJson: ""
    readonly property var _time: {
        try { return timeInfoJson ? JSON.parse(timeInfoJson) : null } catch (e) { return null }
    }
    readonly property int _epochLenSlots: 36000                        // testnet const, like the dash
    readonly property real _slotDurS: (_time && _time.slot_duration_ms) ? Number(_time.slot_duration_ms) / 1000 : 0
    readonly property int _nowSlot: (_time && _time.current_slot !== undefined) ? Number(_time.current_slot) : -1
    // Time-based fraction created→active (0..1); falls back to epoch counts when no slot data.
    readonly property real activationProgress: {
        if (createdEpoch < 0 || coreEpoch <= createdEpoch) return 0
        if (_nowSlot >= 0)
            return Math.max(0, Math.min(1, (_nowSlot - createdEpoch * _epochLenSlots) / ((coreEpoch - createdEpoch) * _epochLenSlots)))
        if (nowEpoch >= 0) return Math.max(0, Math.min(1, (nowEpoch - createdEpoch) / (coreEpoch - createdEpoch)))
        return 0
    }
    // Human "time left" until active (e.g. "1h 20m left"); falls back to "~N epoch(s) left".
    readonly property string activationTimeLeft: {
        if (coreEpoch < 0) return ""
        if (_nowSlot >= 0 && _slotDurS > 0) {
            var leftSlots = coreEpoch * _epochLenSlots - _nowSlot
            if (leftSlots <= 0) return qsTr("due now")
            var secs = leftSlots * _slotDurS
            var h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
            return (h > 0 ? h + "h " : "") + m + "m left"
        }
        var e = (nowEpoch >= 0) ? Math.max(0, coreEpoch - nowEpoch) : -1
        return e > 0 ? qsTr("~%1 epoch(s) left").arg(e) : ""
    }
    function _elide(s) { s = "" + s; return s.length > 22 ? s.substring(0,12) + "…" + s.substring(s.length-6) : s }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }

    // ── derived gates ──
    readonly property bool gSynced: backend
        && (backend.blendStatus === BlockchainBackend.Edge
            || backend.blendStatus === BlockchainBackend.Core
            || backend.blendStatus === BlockchainBackend.Broadcast
            || backend.blendStatus === BlockchainBackend.Activating)
    readonly property bool gFunded: sdpBalance > 0
    readonly property bool gStakeNote: noteCount > 0 && lockNoteId.length > 0
    readonly property bool gPort: portListening || portAttested
    readonly property bool gNetwork: netCount >= 2
    // Declaration slot: a fresh declare only TAKES when no on-chain declaration for our key is still
    // present — /blend/join returns the EXISTING id otherwise, so re-declaring is a silent no-op. A
    // stale declaration blocks either because it's withdrawing (wait for it to clear) or aged-out and
    // never withdrawn (withdraw it first). A LIVE declaration means we're already declared (the modal
    // is in its "core" phase then, not gates), so it doesn't block here.
    readonly property bool _declBlocks: mineId.length > 0 && !mineLive
    readonly property bool gSlotFree: !_declBlocks
    readonly property bool allGreen: gSynced && gFunded && gStakeNote && gPort && gNetwork && gSlotFree
    // ── manage-view state (drive off the declaration facts, not just blendStatus, which can lag) ──
    readonly property bool _isCore: backend && backend.blendStatus === BlockchainBackend.Core
    // pre-active window: declared + live on-chain, but activation epoch is still ahead
    readonly property bool _maturing: mineLive && coreEpoch > 0 && nowEpoch >= 0 && nowEpoch < coreEpoch
    // declared + live but not (yet) mixing in this epoch's Core set — the "no need to re-declare" state
    readonly property bool _declaredNotMixing: (backend && backend.blendStatus === BlockchainBackend.CoreDeclaredEdge) || (mineLive && !_isCore)

    readonly property string docsUrl: "https://docs.logos.co/blockchain/blend/join-the-blend-network-as-a-core-node"

    // ── open/close ──
    function open() {
        if (mutationBusy) return
        root.errorText = ""
        root.portAttested = false
        root.txId = ""
        root.faucetMsg = ""
        root.faucetBusy = false
        var bs = backend ? backend.blendStatus : 0
        root.step = (bs === BlockchainBackend.Activating) ? 2 : 0
        // CoreDeclaredEdge = declared + active on-chain but running Edge this epoch → show the Core
        // view (with a "not active this epoch" caveat), NOT the enabling/Activating view (activation
        // is long done); the stake is locked, so re-declaring here would be a mistake.
        root.phase = (bs === BlockchainBackend.Core || bs === BlockchainBackend.CoreDeclaredEdge) ? "core"
                   : (bs === BlockchainBackend.Activating) ? "enabling" : "gates"
        root._refreshGates()
    }
    // In a tab the StackLayout owns visibility; entering the tab (re)initialises the flow.
    onVisibleChanged: if (visible && !mutationBusy) open()
    function close() { /* no-op: the Blend tab is not a dismissable modal */ }

    function _enable() {
        if (mutationBusy || !allGreen || phase !== "gates" || !backend || !backendReady) return
        if (root.mineLive) { root.phase = "core"; return }   // already declared — never re-declare
        root.errorText = ""
        root.step = 0
        root.phase = "enabling"
        // locator "" → the backend builds it from the resolved public IP + blend port.
        root._mutate(
            function() { return backend.declareBlendCore(root.locator, root.lockNoteId) },
            function(r) {
                if (r && r.ok) {
                    root.txId = r.tx || ""
                    root.step = 1                 // submitted / heading into a block
                } else {
                    root.errorText = (r && r.error) ? r.error : qsTr("The declaration was rejected.")
                    root.phase = "gates"
                }
            }
        )
    }

    function _disable() {
        if (mutationBusy || withdrawEpoch >= 0 || phase !== "core" || !backend || !backendReady) return
        root.errorText = ""
        root.phase = "disabling"
        root._mutate(
            function() { return backend.withdrawBlendCore() },
            function(r) {
                if (r && r.ok) {
                    root.phase = "disabled"
                } else {
                    // Surface the node's own reason (e.g. WithdrawalWhileLocked — the
                    // staked note is still inside its lock period), not a generic failure.
                    root.errorText = (r && r.error) ? r.error : qsTr("The withdrawal was rejected.")
                    root.phase = "core"
                }
            }
        )
    }

    function _done() { root.close() }

    // ── gate polling (real backend) ──
    function _refreshGates() {
        if (!backend || !backendReady) return
        // 1) SDP funding key + locator (config-derived; also gives the blend port).
        logos.watch(
            backend.getSdpFundingKey(),
            function(r) {
                if (!r) return
                root.sdpKey = r.key || ""
                root.blendPort = r.blendPort || 3400
                root.locator = r.locator || ""
                root.publicIp = r.publicIp || ""
                root._refreshFunded()
            },
            function(e) {}
        )
        // 2) lockable stake note (a note owned by the leader/node key).
        var noteKey = backend.leaderKey || backend.primaryAddress || ""
        if (noteKey.length > 0) {
            logos.watch(
                backend.getNotes(noteKey, ""),
                function(r) {
                    if (!r || !r.success) return
                    try {
                        var o = JSON.parse(r.value)
                        var notes = (o && o.notes) ? o.notes : []
                        root.noteCount = notes.length
                        // Stake the largest note (most headroom over min-stake).
                        var bestId = "", bestVal = -1
                        for (var i = 0; i < notes.length; ++i) {
                            var v = Number(notes[i].value)
                            if (!isNaN(v) && v > bestVal) { bestVal = v; bestId = notes[i].id }
                        }
                        root.lockNoteId = bestId || ""
                    } catch (e) { root.noteCount = 0; root.lockNoteId = "" }
                },
                function(e) {}
            )
        }
        // 3) local udp/<blendPort> listener (best-effort).
        logos.watch(
            backend.checkBlendPortReachable(),
            function(r) { if (r) root.portListening = !!r.listening },
            function(e) {}
        )
        // 4) network size + our declaration's activation epoch.
        logos.watch(
            backend.getBlendDeclarations(),
            function(r) {
                if (!r) return
                root.netCount = (r.count !== undefined) ? r.count : -1
                if (r.mineActive !== undefined && r.mineActive >= 0) root.coreEpoch = r.mineActive
                root.withdrawEpoch = (r.mineWithdrawAt !== undefined && r.mineWithdrawAt >= 0) ? r.mineWithdrawAt : -1
                root.mineId = (r.mineId !== undefined) ? String(r.mineId) : ""
                root.mineLive = (r.mineLive === true)
                root.mineInactiveSince = (r.mineInactiveSince !== undefined) ? r.mineInactiveSince : -1
                root.nowEpoch = (r.nowEpoch !== undefined) ? r.nowEpoch : -1
                // Full record fields for the Activation/Active pages (provider record + stake).
                root.createdEpoch = (r.mineCreated !== undefined) ? r.mineCreated : -1
                root.recNonce = (r.mineNonce !== undefined) ? r.mineNonce : -1
                root.recNote = (r.mineNote !== undefined) ? String(r.mineNote) : ""
                root.recProvider = (r.mineProvider !== undefined) ? String(r.mineProvider) : ""
                root.recZk = (r.mineZk !== undefined) ? String(r.mineZk) : ""
                root.recLocator = (r.mineLocator !== undefined) ? String(r.mineLocator) : ""
                // We already have a LIVE declaration on-chain → we're declared, not eligible to declare
                // again. Leave the gates checklist for the manage view (guards against a stale blendStatus
                // that still reads Edge during the pre-active maturing window, epoch < active).
                if (root.mineLive && root.phase === "gates") root.phase = "core"
            },
            function(e) {}
        )
        // 5) config identity (provider_id / zk_id) for the pre-declare "what you'll publish".
        logos.watch(
            backend.getBlendIdentity(),
            function(r) {
                if (!r) return
                root.identProvider = r.providerId || ""
                root.identZk = r.zkId || ""
            },
            function(e) {}
        )
    }
    // External reachability probe (epic #124): responder + hosted prober → real verdict.
    function _checkReach() {
        if (!backend || !backendReady || root.reachChecking) return
        root.reachChecking = true; root.reachVerdict = ""
        root.reachDetail = qsTr("Asking the prober to dial your Blend port…")
        var nonce = ""
        for (var i = 0; i < 16; ++i) nonce += "0123456789abcdef"[Math.floor(Math.random() * 16)]
        logos.watch(
            backend.checkBlendReachable(nonce),
            function(r) {
                root.reachChecking = false
                if (r && r.ok === true) { root.reachVerdict = r.reachable ? "reachable" : "unreachable"; root.reachDetail = r.detail || "" }
                else { root.reachVerdict = "unknown"; root.reachDetail = (r && r.detail) ? r.detail : qsTr("Prober unavailable — attest the forward instead.") }
            },
            function(e) { root.reachChecking = false; root.reachVerdict = "unknown"; root.reachDetail = qsTr("Reachability check failed to run.") }
        )
    }
    function _refreshFunded() {
        if (!backend || !backendReady || root.sdpKey.length === 0) return
        logos.watch(
            backend.getBalance(root.sdpKey),
            function(r) {
                if (r && r.success && r.value !== undefined && r.value !== null) {
                    var n = Number(r.value)
                    root.sdpBalance = isNaN(n) ? -1 : n
                }
            },
            function(e) {}
        )
    }

    // Poll the gates while the checklist is showing.
    Timer {
        interval: 4000; repeat: true
        running: root.visible && root.phase === "gates"
        triggeredOnStart: true
        onTriggered: root._refreshGates()
    }
    // While enabling: watch the declaration land, then activate to Core. Real
    // activation is ~2 epochs (hours) — "safe to close"; this advances the stages
    // for as long as the window stays open.
    Timer {
        interval: 5000; repeat: true
        running: root.visible && root.phase === "enabling"
        onTriggered: {
            if (!root.backend || !root.backendReady) return
            logos.watch(
                root.backend.getBlendDeclarations(),
                function(r) {
                    if (r && r.mineId && String(r.mineId).length > 0) {
                        if (root.step < 2) root.step = 2         // on-chain → activating
                        if (r.mineActive !== undefined && r.mineActive >= 0) root.coreEpoch = r.mineActive
                        root.withdrawEpoch = (r.mineWithdrawAt !== undefined && r.mineWithdrawAt >= 0) ? r.mineWithdrawAt : -1
                    }
                },
                function(e) {}
            )
            // Positive Core proof comes through blendStatus (refreshBlendStatus reads
            // /blend/info on the dashboard timer). When it flips to Core, we're activated.
            if (root.backend.blendStatus === BlockchainBackend.Core) root.phase = "activated"
        }
    }

    // Faucet the SDP funding key (funded-gate action). Re-polls the balance on result.
    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onFaucetResult(ok, message) {
            root.faucetBusy = false
            root.faucetMsg = ok ? qsTr("Funds requested — the balance updates in a moment.")
                                : (message && message.length ? message : qsTr("Faucet request failed. You can also fund the key manually (copy it above)."))
            if (root.visible && root.phase === "gates") root._refreshFunded()
        }
    }

    function _gateAction(kind) {
        if (mutationBusy) return
        if (kind === "faucet") {
            if (!backend || !backendReady) return
            // No key yet = the click would silently no-op; tell the operator why instead.
            if (root.sdpKey.length === 0) {
                root.faucetMsg = qsTr("Funding key not ready yet — wait for the node to finish starting, then try again.")
                return
            }
            root.faucetBusy = true
            root.faucetMsg = qsTr("Requesting test funds…")
            backend.requestFaucetFunds(root.sdpKey)
        } else if (kind === "attest") {
            root.portAttested = true
        } else if (kind === "withdraw") {
            root._withdrawStale()
        }
    }

    // Withdraw a stale (aged-out, never-withdrawn) declaration from the gates phase so the operator
    // can clear the slot and re-declare. Stays in gates and re-polls; withdraw_at then appears and the
    // gate switches to the "wait until it clears" message.
    function _withdrawStale() {
        if (mutationBusy || withdrawEpoch >= 0 || !backend || !backendReady || root.mineId.length === 0) return
        root.errorText = ""
        root._mutate(
            function() { return backend.withdrawBlendCore() },
            function(r) {
                if (!(r && r.ok))
                    root.errorText = (r && r.error) ? r.error : qsTr("The withdrawal was rejected.")
                root._refreshGates()
            }
        )
    }

    // Human-readable LGO from raw lepta (decimals = 9), for the funded gate value.
    function _lgo(lepta) {
        if (lepta < 0) return qsTr("unknown")
        return (lepta / 1e9).toFixed(lepta > 0 && lepta < 1e7 ? 4 : 0) + " LGO"
    }

    // ── gate model (rebuilt from the real state) ──
    readonly property var gates: {
        var g = [
        { ok: gSynced,    label: qsTr("Node status"),
          val: gSynced ? qsTr("Online") : qsTr("Bootstrapping"),
          fix: qsTr("Wait for the node to finish syncing before declaring."), action: "", docs: "", kind: "", addr: "",
          info: ({ "title": qsTr("Node status"), "what": qsTr("Declaring needs a running, synced node — it signs the declaration, binds the Blend port and proves reachability."), "states": [{ "label": qsTr("Online"), "meaning": qsTr("Synced — ready to declare.") }, { "label": qsTr("Bootstrapping"), "meaning": qsTr("Still catching up — wait.") }], "docs": docsUrl }) },
        { ok: gFunded,    label: qsTr("SDP funding key funded"),
          val: gFunded ? _lgo(sdpBalance) : (sdpBalance === 0 ? qsTr("0 LGO") : qsTr("checking…")),
          fix: qsTr("The declaration pays a small fee from your SDP funding key."),
          action: qsTr("Request test funds"), docs: "", kind: "faucet", addr: sdpKey,
          info: ({ "title": qsTr("SDP funding key"), "what": qsTr("Pays the fee to submit the declaration on-chain. Funded from the faucet or any wallet."), "states": [], "docs": docsUrl }) },
        { ok: gStakeNote, label: qsTr("Lockable stake note"),
          val: gStakeNote ? qsTr("%1 note(s) available").arg(noteCount) : (noteCount === 0 ? qsTr("none") : qsTr("checking…")),
          fix: qsTr("Fund a node key so there's a note to lock as your provider stake."), action: "", docs: "", kind: "", addr: lockNoteId,
          info: ({ "title": qsTr("Lockable stake note"), "what": qsTr("Declaring locks one of your node's notes as the provider stake — bonded, not spent, and returned when you withdraw."), "states": [{ "label": qsTr("available"), "meaning": qsTr("A note is lockable.") }, { "label": qsTr("none"), "meaning": qsTr("Fund a node key.") }], "docs": docsUrl }) },
        { ok: gPort,      label: qsTr("UDP %1 forwarded").arg(blendPort),
          val: gPort ? (portAttested && !portListening ? qsTr("confirmed") : qsTr("open")) : qsTr("needs your confirmation"),
          fix: qsTr("The node only opens udp/%1 once it's a Core provider, so this can't be auto-checked yet — that's expected. Make sure udp/%1 is forwarded to this machine on your router (see the guide), then mark it below.").arg(blendPort),
          action: qsTr("I've forwarded this port"), docs: docsUrl, kind: "attest", addr: locator,
          info: ({ "title": qsTr("Reachability (Blend port)"), "what": qsTr("Peers must be able to dial your Blend port. The node only opens udp/%1 once it's a Core provider, so it can't be auto-verified before then — confirm the router forward yourself.").arg(blendPort), "states": [{ "label": qsTr("open"), "meaning": qsTr("A local listener holds the port.") }, { "label": qsTr("confirmed"), "meaning": qsTr("You attested the router forward.") }], "docs": docsUrl }) },
        { ok: gNetwork,   label: qsTr("Blend network size"),
          val: netCount >= 0 ? qsTr("%1 provider(s)").arg(netCount) : qsTr("checking…"),
          fix: qsTr("Needs at least 2 active providers on the network."), action: "", docs: "", kind: "", addr: "",
          info: ({ "title": qsTr("Blend network size"), "what": qsTr("A mix needs a minimum number of active providers to form. Below it, Blend can't run."), "states": [{ "label": qsTr("≥ 2 providers"), "meaning": qsTr("A mix can form.") }], "docs": docsUrl }) }
        ]
        // Only surfaced when a stale declaration actually blocks a fresh declare — no noise on a
        // first-time enable. Two honest sub-states: withdrawing (wait for it to clear) vs aged-out
        // and never withdrawn (withdraw it first). Both make /blend/join a no-op until cleared.
        if (_declBlocks) {
            g.push({ ok: false, label: qsTr("Declaration slot free"),
              val: withdrawEpoch >= 0
                    ? qsTr("withdrawing → clears epoch %1").arg(withdrawEpoch)
                    : (mineInactiveSince >= 0 ? qsTr("inactive since epoch %1").arg(mineInactiveSince) : qsTr("stale declaration on-chain")),
              fix: withdrawEpoch >= 0
                    ? qsTr("Your previous declaration is being withdrawn. A new one can't take until it clears at epoch %1 and the staked note unlocks — re-declare after that. Re-declaring now is a no-op.").arg(withdrawEpoch)
                    : qsTr("A stale declaration is still on-chain and makes a fresh declare a no-op. Withdraw it first, then re-declare once it clears (~2 epochs)."),
              action: withdrawEpoch >= 0 ? "" : qsTr("Withdraw stale declaration"),
              docs: "", kind: withdrawEpoch >= 0 ? "" : "withdraw", addr: mineId,
              info: ({ "title": qsTr("Declaration slot"), "what": qsTr("A node holds one Blend declaration at a time. While a previous one is withdrawing or stale, a fresh declare is a no-op until it clears."), "states": [{ "label": qsTr("free"), "meaning": qsTr("You can declare.") }, { "label": qsTr("withdrawing"), "meaning": qsTr("Wait for it to clear.") }], "docs": docsUrl }) })
        }
        return g
    }

    // Structured (i) → the shared InfoModal (what / states / docs), like the dashboard tiles.
    InfoModal { id: infoModal }

    // Privacy consent for the external reachability check (epic #124): it shares the node's
    // public IP with a third-party prober. Temporary, optional — gated behind explicit consent.
    QQC.Dialog {
        id: reachConfirm
        parent: QQC.Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: Math.min(480, (parent ? parent.width : 480) - 24)
        closePolicy: QQC.Popup.CloseOnEscape
        background: Rectangle { color: Theme.palette.surface; radius: Theme.spacing.radiusLarge; border.color: Theme.palette.border; border.width: 1 }
        QQC.Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.6) }
        header: LogosText { text: qsTr("Check reachability?"); padding: 20; color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            LogosText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                text: qsTr("This asks a third-party prober service (sequencer.logos.live) to dial your node's public IP on udp/%1 and report whether it's reachable. Your node's public IP is briefly shared with that third party.").arg(root.blendPort)
            }
            LogosText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textTertiary; font.pixelSize: 11
                text: qsTr("Temporary and optional: the node has no built-in reachability verdict yet, so this convenience check stands in for it. You can skip it and confirm your router's port-forward manually instead.")
            }
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
                Item { Layout.fillWidth: true }
                LogosButton { text: qsTr("Cancel"); onClicked: reachConfirm.close() }
                LogosButton { text: qsTr("Check reachability"); variant: LogosButton.Variant.Primary
                              onClicked: { reachConfirm.close(); root._checkReach() } }
            }
        }
    }
    component InfoDot: QQC.Button {
        property var payload: null
        visible: payload !== null
        Layout.alignment: Qt.AlignVCenter; implicitWidth: 22; implicitHeight: 22
        display: QQC.AbstractButton.IconOnly; flat: true; padding: 3
        background: Rectangle { color: "transparent" }
        icon.source: Qt.resolvedUrl("../icons/info.svg"); icon.width: 15; icon.height: 15
        icon.color: hovered ? Theme.palette.primary : Theme.palette.textMuted
        onClicked: if (payload) { infoModal.info = payload; infoModal.open() }
    }
    // label/sub (left) · value (right, mono) · [copy] · (i)
    component KV: RowLayout {
        property string k; property string sub: ""; property string v; property string copyValue: ""
        property var info: null; property color valColor: Theme.palette.text
        Layout.fillWidth: true; spacing: Theme.spacing.small
        ColumnLayout {
            spacing: 1; Layout.fillWidth: true
            LogosText { Layout.fillWidth: true; text: k; color: Theme.palette.textSecondary; font.pixelSize: 11 }
            LogosText { visible: sub.length > 0; Layout.fillWidth: true; text: sub; color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap }
        }
        LogosText { Layout.alignment: Qt.AlignVCenter; text: v; color: valColor; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
        BcCopyButton { visible: (""+copyValue).length > 0; Layout.alignment: Qt.AlignVCenter; Layout.preferredHeight: 22; Layout.preferredWidth: 22
                       onCopyText: if (root.backend) root.backend.copyToClipboard(copyValue) }
        InfoDot { payload: info }
    }
    // a titled card (white title + gray desc) with KV rows
    component FieldBlock: LogosFrame {
        property string title: ""; property string desc: ""; property var rows: []
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.tiny
                LogosText { text: title; color: Theme.palette.text; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosText { visible: desc.length > 0; text: desc; color: Theme.palette.textTertiary; font.pixelSize: 11 }
            }
            Repeater { model: rows
                delegate: KV { required property var modelData; k: modelData.k; sub: modelData.sub || ""; v: modelData.v; copyValue: modelData.copyValue || ""; info: modelData.info || null; valColor: modelData.valColor || Theme.palette.text } }
        }
    }
    // node-not-running gate (shared by Declaration + Activation)
    component NodeGate: LogosFrame {
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: root.nodeStatus === BlockchainBackend.Error ? Theme.palette.error : "transparent"
        radius: Theme.spacing.radiusMedium; padding: Theme.spacing.large
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText {
                text: root.nodeStatus === BlockchainBackend.Error ? qsTr("Node error")
                    : root.nodeStatus === BlockchainBackend.Starting ? qsTr("Node is starting…")
                    : root.nodeStatus === BlockchainBackend.Stopped ? qsTr("Node is stopped") : qsTr("Node isn't running")
                color: root.nodeStatus === BlockchainBackend.Error ? Theme.palette.error : Theme.palette.text
                font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold
            }
            LogosText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap
                text: root.nodeStatus === BlockchainBackend.Error ? qsTr("%1. Resolve it, then come back to Blend Core.").arg(root.backend && root.backend.lastErrorMessage ? root.backend.lastErrorMessage : qsTr("The node reported an error"))
                    : root.nodeStatus === BlockchainBackend.Starting ? qsTr("Blend Core becomes available once the node is Online — it signs the declaration, binds the Blend port, and proves reachability.")
                    : qsTr("You can't declare or activate Blend Core without a running node. Start it, then return here.")
                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
            }
            LogosButton { visible: root.nodeStatus !== BlockchainBackend.Starting; text: qsTr("Start node")
                          variant: LogosButton.Variant.Primary
                          onClicked: if (root.backend) root.backend.startBlockchain() }
        }
    }

    // a liveness row (green tick / amber ? / red !) with a fix line
    component LivenessRow: LogosFrame {
        id: lrRoot
        property bool ok: false
        property bool warn: false
        property string label: ""
        property string okText: ""
        property string badText: ""
        property string fix: ""
        property var info: null         // optional (i) → InfoModal, right side
        property string action: ""      // optional attest/act link shown when !ok
        signal acted()
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
        contentItem: RowLayout {
            spacing: Theme.spacing.medium
            Rectangle {
                Layout.alignment: Qt.AlignTop; width: 18; height: 18; radius: 9
                color: ok ? Theme.palette.success : "transparent"; border.width: 2
                border.color: ok ? Theme.palette.success : warn ? Theme.palette.warning : Theme.palette.error
                LogosText { anchors.centerIn: parent; visible: ok; text: "✓"; color: Theme.palette.surfaceRaised; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosText { anchors.centerIn: parent; visible: !ok; text: warn ? "?" : "!"; color: warn ? Theme.palette.warning : Theme.palette.error; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    LogosText { Layout.fillWidth: true; text: label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                    LogosText { text: ok ? okText : badText; color: ok ? Theme.palette.success : warn ? Theme.palette.warning : Theme.palette.error; font.pixelSize: Theme.typography.secondaryText }
                    InfoDot { payload: lrRoot.info }
                }
                LogosText { visible: !ok && fix.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                LogosText { visible: !lrRoot.ok && lrRoot.action.length > 0; text: lrRoot.action; font.pixelSize: 11
                            color: Theme.palette.info
                            TapHandler { onTapped: lrRoot.acted() } }
            }
        }
    }

    // ── the tab: the shipped evidence strip on top, then the enable/manage wizard ──
    QQC.ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width - Theme.spacing.large * 2
            x: Theme.spacing.large
            spacing: Theme.spacing.medium

            // Real lifecycle evidence strip + tone status (moved here from the Node page, #118).
            BlendCoreProgress {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.large
                implicitWidth: 0
                lifecycle: root.controller ? root.controller.lifecycle : ({})
                busy: root.controller ? root.controller.busy : false
                backendReady: root.backendReady
                loading: root.controller ? root.controller.loading : false
                recoveryBusy: root.controller ? root.controller.recoveryBusy : false
                recoveryNeedsRead: root.controller ? root.controller.recoveryNeedsRead : false
                recoveryLocked: root.controller ? root.controller.recoveryLocked : false
                recoveryResultText: root.controller ? root.controller.recoveryResultText : ""
                recoveryResultError: root.controller ? root.controller.recoveryResultError : false
                resultText: root.controller ? root.controller.resultText : ""
                resultError: root.controller ? root.controller.resultError : false
                onRecoverRequested: if (root.controller) root.controller.startRecovery()
                onPauseRecoveryRequested: if (root.controller) root.controller.pauseRecovery()
                onResumeRecoveryRequested: if (root.controller) root.controller.resumeRecovery()
                onDismissRecoveryRequested: if (root.controller) root.controller.dismissRecovery()
                onManageRequested: if (root.controller) root.controller.refresh(true)
                onRepairRequested: if (root.controller) root.controller.repair()
                onRefreshRequested: if (root.controller) root.controller.refresh(true)
            }

            // (header + step indicator removed — the strip above carries state/context)

            // ── node-not-running gate (shared across Declaration/Activation) ──
            NodeGate { visible: !root.nodeUp && root.phase !== "activated" }

            // ── gates checklist (phase: gates) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "gates" && root.nodeUp
                LogosText { text: qsTr("CHECKS"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                Repeater {
                    model: root.gates
                    delegate: LogosFrame {
                        required property var modelData
                        Layout.fillWidth: true
                        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                        radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                        contentItem: RowLayout {
                            spacing: Theme.spacing.medium
                            Rectangle {
                                // "attest" gates (the port forward) that aren't confirmed are amber
                                // "needs your action", not alarm-red — they can't be auto-verified.
                                readonly property color _pend: modelData.kind === "attest" ? Theme.palette.warning : Theme.palette.error
                                Layout.alignment: Qt.AlignTop; width: 18; height: 18; radius: 9
                                color: modelData.ok ? Theme.palette.success : "transparent"
                                border.color: modelData.ok ? Theme.palette.success : _pend; border.width: 2
                                // OK: a checkmark knocked out of the green disc (drawn in the row's own
                                // background colour so it reads as a transparent cut-out), pixel-centred.
                                // Not-OK: a centred "!" in the pending colour.
                                Canvas {
                                    id: _chk; visible: modelData.ok; anchors.fill: parent; antialiasing: true
                                    readonly property color _stroke: Theme.palette.surfaceRaised
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.reset()
                                        var w = width, h = height
                                        ctx.strokeStyle = _stroke; ctx.lineWidth = 2.2
                                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                                        ctx.beginPath()
                                        ctx.moveTo(w * 0.30, h * 0.52)
                                        ctx.lineTo(w * 0.44, h * 0.66)
                                        ctx.lineTo(w * 0.72, h * 0.36)
                                        ctx.stroke()
                                    }
                                    onVisibleChanged: if (visible) requestPaint()
                                    Component.onCompleted: requestPaint()
                                }
                                LogosText { visible: !modelData.ok; anchors.centerIn: parent; text: "!"; color: parent._pend
                                            font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                RowLayout {
                                    Layout.fillWidth: true
                                    LogosText { text: modelData.label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                                    Item { Layout.fillWidth: true }
                                    LogosText { text: modelData.val; color: modelData.ok ? Theme.palette.success : Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText }
                                    InfoDot { payload: modelData.info || null }
                                }
                                LogosText { visible: !modelData.ok; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: modelData.fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                // on-failure copyable key/address (not for the faucet gate, which shows its key below)
                                RowLayout {
                                    visible: !modelData.ok && (modelData.addr || "").length > 0 && modelData.kind !== "faucet"
                                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny; spacing: Theme.spacing.small
                                    LogosText { Layout.fillWidth: true; text: root._elide(modelData.addr || ""); color: Theme.palette.textSecondary; font.pixelSize: 11; font.family: "monospace" }
                                    BcCopyButton { Layout.alignment: Qt.AlignVCenter; Layout.preferredHeight: 22; Layout.preferredWidth: 22
                                                   onCopyText: if (root.backend) root.backend.copyToClipboard(modelData.addr || "") }
                                }
                                // SDP funding key — shown on the funded gate so the operator can
                                // send test LGO here from any wallet (manual alternative to the faucet).
                                ColumnLayout {
                                    visible: modelData.kind === "faucet" && root.sdpKey.length > 0
                                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny; spacing: 1
                                    LogosText { text: qsTr("Funding key — send test LGO here from any wallet:")
                                                color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: Theme.spacing.small
                                        LogosText { Layout.fillWidth: true; text: root.sdpKey
                                                    color: Theme.palette.textSecondary; font.pixelSize: 11
                                                    font.family: "monospace"; elide: Text.ElideMiddle }
                                        BcCopyButton { Layout.alignment: Qt.AlignVCenter; Layout.preferredHeight: 24; Layout.preferredWidth: 24
                                                       onCopyText: if (root.backend) root.backend.copyToClipboard(root.sdpKey) }
                                    }
                                }
                                // docs link (copies the URL) + an action link — local controls only.
                                RowLayout {
                                    visible: !modelData.ok && (modelData.docs || "").length > 0
                                    Layout.fillWidth: true; spacing: Theme.spacing.small
                                    LogosText { Layout.fillWidth: true; text: modelData.docs || ""; font.pixelSize: 11; elide: Text.ElideRight
                                                color: Theme.palette.info
                                                TapHandler { onTapped: if (root.backend) root.backend.copyToClipboard(modelData.docs || "") } }
                                    BcCopyButton { Layout.alignment: Qt.AlignVCenter; Layout.preferredHeight: 24; Layout.preferredWidth: 24
                                                   onCopyText: if (root.backend) root.backend.copyToClipboard(modelData.docs || "") }
                                }
                                // action link (faucet / port attestation)
                                LogosText { visible: !modelData.ok && (modelData.action || "").length > 0
                                            text: modelData.action; font.pixelSize: 11
                                            color: (root.backendReady && !root.mutationBusy) ? Theme.palette.info : Theme.palette.textTertiary
                                            TapHandler { enabled: root.backendReady && !root.mutationBusy; onTapped: root._gateAction(modelData.kind) } }
                                // faucet feedback — requesting / result / why-nothing (the click
                                // used to no-op silently; now it always says what happened).
                                LogosText { visible: modelData.kind === "faucet" && root.faucetMsg.length > 0
                                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: root.faucetMsg
                                            color: root.faucetBusy ? Theme.palette.textSecondary : Theme.palette.text
                                            font.pixelSize: 11 }
                            }
                        }
                    }
                }
                // enable/gates error (e.g. a rejected declaration bounced us back here)
                LogosText { visible: root.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.errorText; color: Theme.palette.error; font.pixelSize: 11 }
            }

            // ── WHAT YOU'LL PUBLISH AND LOCK (phase: gates) ──
            ColumnLayout {
                visible: root.phase === "gates" && root.nodeUp
                Layout.fillWidth: true; spacing: Theme.spacing.small
                LogosText { text: qsTr("WHAT YOU'LL PUBLISH AND LOCK"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                FieldBlock {
                    title: qsTr("Identity")
                    rows: [
                        ({ "k": qsTr("Blend signing key"), "sub": qsTr("provider_id · your on-chain identity — the key that earns"), "v": root._elide(root.identProvider), "copyValue": root.identProvider,
                           "info": ({ "title": qsTr("Blend signing key (provider_id)"), "what": qsTr("Your node's on-chain Blend identity; in the referral program it's the key that accrues points."), "states": [], "docs": root.docsUrl }) }),
                        ({ "k": qsTr("BlendZk key"), "sub": qsTr("zk_id · does the private mixing"), "v": root._elide(root.identZk), "copyValue": root.identZk,
                           "info": ({ "title": qsTr("BlendZk key (zk_id)"), "what": qsTr("Performs the zero-knowledge mixing. Published in the declaration."), "states": [], "docs": root.docsUrl }) }),
                        ({ "k": qsTr("Service type"), "v": "BN", "copyValue": "",
                           "info": ({ "title": qsTr("Service type"), "what": qsTr("Marks this SDP declaration as a Blend Network provider (BN)."), "states": [], "docs": root.docsUrl }) })
                    ]
                }
                FieldBlock {
                    title: qsTr("Address"); desc: qsTr("published on-chain, public")
                    rows: [
                        ({ "k": qsTr("Published address (locator)"), "sub": qsTr("forward THIS udp/%1 — not your 3000 blockchain port").arg(root.blendPort),
                           "v": root._elide(root.locator), "copyValue": root.locator, "valColor": Theme.palette.info,
                           "info": ({ "title": qsTr("Published address (locator)"), "what": qsTr("The address peers use to reach your Blend port — your public IP + the Blend Core port (%1), written on-chain.").arg(root.blendPort), "states": [], "docs": root.docsUrl }) })
                    ]
                }
                FieldBlock {
                    title: qsTr("Stake"); desc: qsTr("locked, not spent")
                    rows: [
                        ({ "k": qsTr("Note to lock"), "sub": qsTr("one of your node's notes — returned when you withdraw"),
                           "v": root.lockNoteId.length ? root._elide(root.lockNoteId) : qsTr("none yet"), "copyValue": root.lockNoteId,
                           "info": ({ "title": qsTr("Stake"), "what": qsTr("Declaring bonds one note as your provider stake (Sybil resistance). Locked, not spent — returned ~2 epochs after you withdraw."), "states": [], "docs": root.docsUrl }) })
                    ]
                }
            }

            // ── ACTIVATION (phase enabling, or declared-but-maturing) ──
            ColumnLayout {
                readonly property bool show: root.phase === "enabling" || (root.phase === "core" && root._declaredNotMixing)
                visible: show && root.nodeUp
                Layout.fillWidth: true; spacing: Theme.spacing.medium

                // (old headline/subtitle removed — the strip above carries the state)
                LogosText { visible: root.mineId.length > 0; text: qsTr("ON-CHAIN"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame {
                    visible: root.mineId.length > 0
                    Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.small
                            LogosText { text: "✓"; color: Theme.palette.success; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                            LogosText { Layout.fillWidth: true; text: qsTr("Declaration accepted on-chain"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium } }
                        KV { k: qsTr("Declaration ID"); v: root._elide(root.mineId); copyValue: root.mineId
                             info: ({ "title": qsTr("Declaration ID"), "what": qsTr("The on-chain record of your Blend provider declaration."), "states": [], "docs": root.docsUrl }) }
                        // Transaction is only known at declare time (txId); the on-chain SDP record
                        // doesn't carry the creating tx hash, so this row is shown only when we have it.
                        KV { visible: root.txId.length > 0; k: qsTr("Transaction"); v: root._elide(root.txId); copyValue: root.txId }
                        KV { visible: root.createdEpoch >= 0; k: qsTr("Created at epoch"); v: "" + root.createdEpoch; copyValue: "" }
                        KV { k: qsTr("Service type"); v: "BN"; copyValue: "" }
                    }
                }

                LogosText { visible: root.coreEpoch >= 0; text: qsTr("ACTIVATION"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame {
                    visible: root.coreEpoch >= 0
                    Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.tiny
                            LogosText { text: qsTr("Activating…"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                            Item { Layout.fillWidth: true }
                            LogosText { text: root.activationTimeLeft.length ? qsTr("active at epoch %1 · %2").arg(root.coreEpoch).arg(root.activationTimeLeft) : qsTr("active at epoch %1").arg(root.coreEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                            InfoDot { payload: ({ "title": qsTr("Activation window"), "what": qsTr("A new declaration becomes active at created + 2 epochs, provided the node stays reachable and keeps sending Active heartbeats. Membership, not the clock alone, decides."), "states": [], "docs": root.docsUrl }) } }
                        Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: Theme.palette.backgroundTertiary
                            Rectangle { width: parent.width * root.activationProgress; height: parent.height; radius: 3; color: Theme.palette.text } }
                        RowLayout { Layout.fillWidth: true
                            LogosText { text: qsTr("epoch %1 (created)").arg(root.createdEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            LogosText { text: qsTr("epoch %1 (active)").arg(root.coreEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 } }
                    }
                }

                LogosText { text: qsTr("WHILE YOU WAIT — KEEP THESE GREEN"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LivenessRow {
                    ok: root.backend && (root.backend.blendStatus === BlockchainBackend.Edge || root.backend.blendStatus === BlockchainBackend.Core || root.backend.blendStatus === BlockchainBackend.CoreDeclaredEdge)
                    label: qsTr("Active heartbeat"); okText: qsTr("Sending"); badText: qsTr("Not sending")
                    fix: qsTr("The node emits periodic Active messages while it's up. If they stop, activation won't complete — keep the node running.")
                    info: ({ "title": qsTr("Active heartbeat"), "what": qsTr("A periodic message the node emits to signal it's a live provider. Required through the activation window and for the life of the declaration. Not work-verified in this release — it means declared + heartbeating + reachable, not proof of mixing."), "states": [{ "label": qsTr("Sending"), "meaning": qsTr("Node is heartbeating.") }, { "label": qsTr("Not sending"), "meaning": qsTr("Node down or stalled — activation pauses.") }], "docs": root.docsUrl })
                }
                LivenessRow {
                    // Real external verdict from the prober (epic #124), plus honest fallbacks:
                    // Core membership implies peers reach you; a local listener holds the port; else
                    // attest. A real "unreachable" prober verdict is red; unconfirmed is amber.
                    readonly property bool _core: root.backend && root.backend.blendStatus === BlockchainBackend.Core
                    readonly property bool _verified: root.reachVerdict === "reachable"
                    readonly property bool _failed: root.reachVerdict === "unreachable"
                    ok: _verified || _core || root.portListening || root.portAttested
                    warn: !ok && !_failed     // amber unless a real unreachable verdict → red
                    label: qsTr("Reachability (Blend port)")
                    okText: _verified ? qsTr("Reachable") : _core ? qsTr("Reachable") : root.portListening ? qsTr("Listening") : qsTr("Confirmed")
                    badText: root.reachChecking ? qsTr("Checking…") : _failed ? qsTr("Not reachable") : qsTr("Needs confirmation")
                    fix: root.reachChecking ? root.reachDetail
                        : _failed ? qsTr("The prober couldn't reach udp/%1 — fix your router's port-forward, then re-check.").arg(root.blendPort)
                        : qsTr("Have the prober dial your Blend port for a real verdict, or attest the forward if it can't reach you.")
                    action: root.reachChecking ? "" : (root.reachVerdict === "unknown" ? qsTr("I've forwarded this port") : qsTr("Check reachability"))
                    onActed: { if (root.reachVerdict === "unknown") root.portAttested = true; else reachConfirm.open() }
                    info: ({ "title": qsTr("Reachability (Blend port)"), "what": qsTr("Peers must be able to dial your Blend port (udp/%1) or you declare but never earn. The node has no built-in AutoNAT verdict for it, so this uses Core membership, a local listener, an external prober (with your consent), or your attestation.").arg(root.blendPort), "states": [{ "label": qsTr("Reachable (verified)"), "meaning": qsTr("An external prober dialed your port and got the nonce back.") }, { "label": qsTr("Reachable"), "meaning": qsTr("You're a current Core member, so peers reach you.") }, { "label": qsTr("Needs confirmation"), "meaning": qsTr("Not verified yet — run the check or attest the forward.") }, { "label": qsTr("Not reachable"), "meaning": qsTr("The prober couldn't reach the port — fix the forward.") }], "docs": root.docsUrl })
                }

                LogosText { visible: root.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.errorText; color: Theme.palette.error; font.pixelSize: 11 }
            }

            // ── ACTIVE / mixing (phase core mixing, or the brief activated flash) ──
            ColumnLayout {
                readonly property bool show: (root.phase === "core" && !root._declaredNotMixing) || root.phase === "activated"
                visible: show && root.nodeUp
                Layout.fillWidth: true; spacing: Theme.spacing.medium

                LogosFrame { Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: Theme.palette.success; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.large
                    contentItem: RowLayout { spacing: Theme.spacing.medium
                        Rectangle { Layout.alignment: Qt.AlignVCenter; width: 40; height: 40; radius: 20; color: Theme.palette.success
                            LogosText { anchors.centerIn: parent; text: "✓"; color: Theme.palette.surfaceRaised; font.pixelSize: 18; font.weight: Theme.typography.weightBold } }
                        ColumnLayout { Layout.fillWidth: true; spacing: 2
                            LogosText { text: qsTr("Blend Core active"); color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                            LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.coreEpoch >= 0 ? qsTr("Current Core member · active since epoch %1").arg(root.coreEpoch) : qsTr("Current Core member — mixing your proposals"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText } } } }

                LogosText { text: qsTr("LIVENESS"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame { Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: ColumnLayout { spacing: Theme.spacing.small
                        KV { k: qsTr("Provider nonce"); sub: qsTr("one signal of activity — read with membership, not proof alone"); v: root.recNonce >= 0 ? "" + root.recNonce : "—"; valColor: Theme.palette.success
                             info: ({ "title": qsTr("Provider nonce"), "what": qsTr("An on-chain counter that advances with accepted activity. A rising nonce is one signal you're live, not sufficient alone — liveness = membership AND healthy peers AND recent activity."), "states": [], "docs": root.docsUrl }) }
                        KV { k: qsTr("Active heartbeat"); v: qsTr("Sending"); valColor: Theme.palette.success }
                        KV { k: qsTr("Reachability (Blend port)")
                             v: (root.backend && root.backend.blendStatus === BlockchainBackend.Core) ? qsTr("Reachable")
                                : root.portListening ? qsTr("Listening") : root.portAttested ? qsTr("Confirmed") : qsTr("Needs confirmation")
                             valColor: ((root.backend && root.backend.blendStatus === BlockchainBackend.Core) || root.portListening || root.portAttested) ? Theme.palette.success : Theme.palette.warning }
                    }
                }

                LogosText { text: qsTr("PROVIDER RECORD"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame { Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: ColumnLayout { spacing: Theme.spacing.small
                        KV { k: qsTr("Blend signing key"); sub: qsTr("provider_id · the key that earns"); v: root._elide(root.recProvider || root.identProvider); copyValue: root.recProvider || root.identProvider }
                        KV { k: qsTr("BlendZk key"); sub: "zk_id"; v: root._elide(root.recZk || root.identZk); copyValue: root.recZk || root.identZk }
                        KV { k: qsTr("Service type"); v: "BN"; copyValue: "" }
                        KV { k: qsTr("Published address"); v: root.recLocator.length ? root._elide(root.recLocator) : root._elide(root.locator); copyValue: root.recLocator.length ? root.recLocator : root.locator; valColor: Theme.palette.success }
                        KV { visible: root.createdEpoch >= 0; k: qsTr("Created / active epoch"); v: root.createdEpoch + " / " + (root.coreEpoch >= 0 ? root.coreEpoch : "—"); copyValue: "" }
                        KV { visible: root.withdrawEpoch >= 0; k: qsTr("Withdraw at epoch"); v: "" + root.withdrawEpoch; copyValue: "" }
                    }
                }

                LogosText { text: qsTr("STAKE"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame { Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: KV { k: qsTr("Locked note"); sub: qsTr("bonded as your provider stake — returned ~2 epochs after withdrawal"); v: root._elide(root.recNote); copyValue: root.recNote } }

                LogosText { visible: root.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.errorText; color: Theme.palette.error; font.pixelSize: 11 }
            }

            // ── WITHDRAWAL (phases disabling, disabled) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "disabling" || root.phase === "disabled"
                LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; text: root.phase === "disabling" ? qsTr("Submitting withdrawal…") : qsTr("Withdrawal requested — awaiting confirmation")
                            color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightMedium }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.phase === "disabling" ? qsTr("Requesting withdrawal; inclusion and stake release must be verified.")
                                : (root.withdrawEpoch >= 0 ? qsTr("Request acknowledged. Your stake unlocks at epoch %1 (~2 epochs). Not proof of removal until confirmed on-chain.").arg(root.withdrawEpoch)
                                                           : qsTr("Request acknowledged, not proof of removal or unlocked stake. Check the strip for the scheduled epoch and chain evidence."))
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            }

            // ── footer ──
            RowLayout {
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
                LogosText {
                    visible: root.phase === "gates"
                    text: root.allGreen ? qsTr("All checks passed — ready to enable.") : qsTr("Resolve the red checks above to enable.")
                    color: root.allGreen ? Theme.palette.success : Theme.palette.textTertiary; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter
                }
                Item { Layout.fillWidth: true }
                // Fund the declaration keys (Wallet tab) — shortcut while resolving gates.
                LogosButton { visible: root.phase === "gates" && !root.allGreen; text: qsTr("Fund keys"); onClicked: root.openWallet() }
                // Enable (gates)
                LogosButton { visible: root.phase === "gates"; variant: LogosButton.Variant.Primary
                    text: root.withdrawEpoch >= 0 ? qsTr("Re-declare after epoch %1").arg(root.withdrawEpoch) : qsTr("Enable Blend Core")
                    enabled: root.backendReady && root.allGreen && !root.mutationBusy; onClicked: root._enable() }
                // Cancel while maturing (withdraw the just-made declaration)
                LogosButton { visible: root.phase === "core" && root._declaredNotMixing; enabled: root.backendReady && !root.mutationBusy && root.withdrawEpoch < 0
                    text: qsTr("Cancel declaration"); onClicked: root._disable() }
                // Withdraw while actively mixing
                LogosButton { visible: root.phase === "core" && !root._declaredNotMixing; enabled: root.backendReady && !root.mutationBusy && root.withdrawEpoch < 0
                    text: qsTr("Withdraw stake"); onClicked: root._disable() }
                // Declare again after a completed withdrawal
                LogosButton { visible: root.phase === "disabled"; variant: LogosButton.Variant.Primary
                    text: qsTr("Declare again"); onClicked: { root.phase = "gates"; root._refreshGates() } }
            }
        }
    }
}
