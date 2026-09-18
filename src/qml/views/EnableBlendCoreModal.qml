import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
// BlendStatus enum (Off/WaitingForOnline/Edge/Core/Broadcast/…/Activating).
import Logos.BlockchainBackend 1.0

// ── ENABLE / MANAGE BLEND CORE — real modal (epic #89, #90-#96) ─────────────
// Ported from design/node-dashboard/prototype/EnableBlendCoreProto.qml, but fed by
// REAL backend calls instead of mock toggles. Full Blend provider lifecycle as one
// phase machine:
//   gates → enabling → activated →(Done)  |  core → disabling → disabled →(Done)
// Gates + stages mirror the declaration proven end-to-end on sneg (fund sdp funding_pk
// → POST /blend/join {locator, locked_note_id} → declaration → active at created+2
// epochs → Mode::Core). Disable = POST /sdp/withdrawal (unlocks the staked note).
//
// Overlay Item: parent sets anchors.fill; open()/close() toggle visibility. Uses the
// global `logos` context property for logos.watch, and `backend` (the .rep replica)
// injected by BlockchainView. DS controls only.
Item {
    id: root
    visible: false

    property var backend: null

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
    property int    netCount: -1          // active BN declarations on the network
    // our existing on-chain declaration, for the "declaration slot free" gate
    property string mineId: ""             // our declaration id on-chain ("" = none)
    property bool   mineLive: false        // our declaration is is_active this epoch
    property int    mineInactiveSince: -1  // epoch our declaration went/goes inactive (active + 2)
    property int    nowEpoch: -1           // current epoch (from the declarations poll)

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

    readonly property string docsUrl: "https://docs.logos.co/blockchain/blend/join-the-blend-network-as-a-core-node"

    // ── open/close ──
    function open() {
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
        root.visible = true
        root._refreshGates()
    }
    function close() { root.visible = false }

    function _enable() {
        if (!allGreen || phase !== "gates" || !backend) return
        root.errorText = ""
        root.step = 0
        root.phase = "enabling"
        // locator "" → the backend builds it from the resolved public IP + blend port.
        logos.watch(
            backend.declareBlendCore(root.locator, root.lockNoteId),
            function(r) {
                if (r && r.ok) {
                    root.txId = r.tx || ""
                    root.step = 1                 // submitted / heading into a block
                } else {
                    root.errorText = (r && r.error) ? r.error : qsTr("The declaration was rejected.")
                    root.phase = "gates"
                }
            },
            function(e) {
                root.errorText = qsTr("Couldn't submit the declaration — %1").arg(String(e))
                root.phase = "gates"
            }
        )
    }

    function _disable() {
        if (phase !== "core" || !backend) return
        root.errorText = ""
        root.phase = "disabling"
        logos.watch(
            backend.withdrawBlendCore(),
            function(r) {
                if (r && r.ok) {
                    root.phase = "disabled"
                } else {
                    // Surface the node's own reason (e.g. WithdrawalWhileLocked — the
                    // staked note is still inside its lock period), not a generic failure.
                    root.errorText = (r && r.error) ? r.error : qsTr("The withdrawal was rejected.")
                    root.phase = "core"
                }
            },
            function(e) {
                root.errorText = qsTr("Couldn't submit the withdrawal — %1").arg(String(e))
                root.phase = "core"
            }
        )
    }

    function _done() { root.close() }

    // ── gate polling (real backend) ──
    function _refreshGates() {
        if (!backend) return
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
            },
            function(e) {}
        )
    }
    function _refreshFunded() {
        if (!backend || root.sdpKey.length === 0) return
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
            if (!root.backend) return
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
        if (kind === "faucet") {
            if (!backend) return
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
        if (!backend || root.mineId.length === 0) return
        root.errorText = ""
        logos.watch(
            backend.withdrawBlendCore(),
            function(r) {
                if (!(r && r.ok))
                    root.errorText = (r && r.error) ? r.error : qsTr("The withdrawal was rejected.")
                root._refreshGates()
            },
            function(e) { root.errorText = qsTr("Couldn't submit the withdrawal — %1").arg(String(e)) }
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
        { ok: gSynced,    label: qsTr("Node synced"),
          val: gSynced ? qsTr("Online") : qsTr("Bootstrapping"),
          fix: qsTr("Wait for the node to finish syncing before declaring."), action: "", docs: "", kind: "" },
        { ok: gFunded,    label: qsTr("SDP funding key funded"),
          val: gFunded ? _lgo(sdpBalance) : (sdpBalance === 0 ? qsTr("0 LGO") : qsTr("checking…")),
          fix: qsTr("The declaration pays a small fee from your SDP funding key."),
          action: qsTr("Request test funds"), docs: "", kind: "faucet" },
        { ok: gStakeNote, label: qsTr("Lockable stake note"),
          val: gStakeNote ? qsTr("%1 note(s) available").arg(noteCount) : (noteCount === 0 ? qsTr("none") : qsTr("checking…")),
          fix: qsTr("Fund a node key so there's a note to lock as your provider stake."), action: "", docs: "", kind: "" },
        { ok: gPort,      label: qsTr("UDP %1 forwarded").arg(blendPort),
          val: gPort ? (portAttested && !portListening ? qsTr("confirmed") : qsTr("open")) : qsTr("needs your confirmation"),
          fix: qsTr("The node only opens udp/%1 once it's a Core provider, so this can't be auto-checked yet — that's expected. Make sure udp/%1 is forwarded to this machine on your router (see the guide), then mark it below.").arg(blendPort).arg(blendPort),
          action: qsTr("I've forwarded this port"), docs: docsUrl, kind: "attest" },
        { ok: gNetwork,   label: qsTr("Blend network size"),
          val: netCount >= 0 ? qsTr("%1 provider(s)").arg(netCount) : qsTr("checking…"),
          fix: qsTr("Needs at least 2 active providers on the network."), action: "", docs: "", kind: "" }
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
              docs: "", kind: withdrawEpoch >= 0 ? "" : "withdraw" })
        }
        return g
    }

    // ── backdrop ──
    Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    // ── the modal card ──
    LogosFrame {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 480)
        backgroundColor: Theme.palette.surface; borderColor: Theme.palette.border
        radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        MouseArea { anchors.fill: parent; z: -1 }   // swallow card clicks (behind content)

        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium

            // header
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 2
                    LogosText { text: (root.phase === "core" || root.phase === "activated" || root.phase === "disabling" || root.phase === "disabled") ? qsTr("Blend Core") : qsTr("Enable Blend Core")
                                color: Theme.palette.text; font.pixelSize: Theme.typography.titleText; font.weight: Theme.typography.weightBold }
                    LogosText { text: qsTr("Become a Blend Network core provider — mixes your proposals for proposer privacy.");
                                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
                Item {   // close — icon button, not a big square
                    Layout.alignment: Qt.AlignTop; implicitWidth: 28; implicitHeight: 28
                    LogosText { anchors.centerIn: parent; text: "✕"; font.pixelSize: 15
                                color: closeMa.containsMouse ? Theme.palette.text : Theme.palette.textSecondary }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
                }
            }

            // ── gates checklist (phase: gates) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "gates"
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
                                }
                                LogosText { visible: !modelData.ok; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: modelData.fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
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
                                        LogosCopyButton { value: root.sdpKey; Layout.alignment: Qt.AlignVCenter }
                                    }
                                }
                                // docs link (copies the URL, like InfoModal's DOCS link) + an action link
                                RowLayout {
                                    visible: !modelData.ok && (modelData.docs || "").length > 0
                                    Layout.fillWidth: true; spacing: Theme.spacing.small
                                    LogosLink { Layout.fillWidth: true; text: modelData.docs; font.pixelSize: 11; elide: Text.ElideRight; onActivated: gcb.copy() }
                                    LogosCopyButton { id: gcb; value: modelData.docs || ""; Layout.alignment: Qt.AlignVCenter }
                                }
                                // action link (faucet / port attestation)
                                LogosLink { visible: !modelData.ok && (modelData.action || "").length > 0
                                            text: modelData.action; font.pixelSize: 11; onActivated: root._gateAction(modelData.kind) }
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

            // ── enabling progress (phase: enabling) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "enabling"
                LogosText { text: root.withdrawEpoch >= 0 ? qsTr("Previous declaration still withdrawing")
                                 : root.step === 0 ? qsTr("Submitting declaration…")
                                 : root.step === 1 ? qsTr("Included in a block")
                                 : (root.coreEpoch > 0 ? qsTr("Activating — Core at epoch %1").arg(root.coreEpoch)
                                                       : qsTr("Activating — Core in ~2 epochs"))
                            color: root.withdrawEpoch >= 0 ? Theme.palette.warning : Theme.palette.text
                            font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightMedium }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.withdrawEpoch >= 0 ? qsTr("Your key can't re-declare until the previous declaration clears at epoch %1 and its stake unlocks. Re-declare after that.").arg(root.withdrawEpoch)
                                 : root.step === 0 ? qsTr("Signing the declaration from your node's blend keys.")
                                 : root.step === 1 ? (root.txId.length > 0 ? qsTr("Declaration is on-chain (id %1…).").arg(root.txId.substring(0, 8)) : qsTr("Declaration is on-chain."))
                                 : qsTr("You can safely close this window — activation continues in the background (~2 epochs).")
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny; spacing: Theme.spacing.small
                    Repeater { model: 3
                        delegate: Rectangle { required property int index
                            Layout.fillWidth: true; height: 4; radius: 2
                            color: index <= root.step ? Theme.palette.primary : Theme.palette.border } }
                }
            }

            // ── activated success (phase: activated) ──
            LogosText {
                visible: root.phase === "activated"; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                Layout.topMargin: Theme.spacing.medium; Layout.bottomMargin: Theme.spacing.medium
                text: qsTr("You're a Blend Core provider ✦"); color: "#d9a521"
                font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold
            }

            // ── core manage (phase: core) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "core"
                LogosFrame {
                    Layout.fillWidth: true
                    backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: RowLayout {
                        spacing: Theme.spacing.medium
                        Rectangle { Layout.alignment: Qt.AlignVCenter; width: 18; height: 18; radius: 9
                            color: (root.backend && root.backend.blendStatus === BlockchainBackend.CoreDeclaredEdge) ? Theme.palette.info : "#d9a521" }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            LogosText { text: (root.backend && root.backend.blendStatus === BlockchainBackend.CoreDeclaredEdge)
                                            ? qsTr("Core declared — not active this epoch")
                                            : qsTr("Active — mixing your proposals")
                                        color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                            LogosText { text: (root.backend && root.backend.blendStatus === BlockchainBackend.CoreDeclaredEdge)
                                            ? qsTr("running as Edge · not in this epoch's Core set")
                                            : (root.backend && root.backend.lastBlendEvent.length > 0) ? root.backend.lastBlendEvent : qsTr("emitting the active heartbeat"); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                        }
                    }
                }
                // declared-but-Edge: explain the honest state + head off a re-declare (stake is locked)
                LogosText { visible: root.backend && root.backend.blendStatus === BlockchainBackend.CoreDeclaredEdge
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: qsTr("Your Core declaration is active on-chain and your stake is locked — you don't need to declare again. The node is running as Edge and isn't in this epoch's Core mixing set. It may rejoin at the next epoch. If it keeps missing epochs, the node reports a Blend membership issue (blend_tsi_outage) worth raising with the team.")
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                LogosText { visible: !(root.backend && root.backend.blendStatus === BlockchainBackend.CoreDeclaredEdge)
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: qsTr("Disabling withdraws your Blend declaration and unlocks the note you staked. You stop mixing and revert to Edge at the next epoch — rewards you already earned are unaffected.")
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                // withdrawal error (e.g. the staked note is still inside its lock period)
                LogosText { visible: root.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.errorText; color: Theme.palette.error; font.pixelSize: 11 }
            }

            // ── disabling / disabled (phases: disabling, disabled) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "disabling" || root.phase === "disabled"
                LogosText { text: root.phase === "disabling" ? qsTr("Submitting withdrawal…") : qsTr("Left the Blend Network — back to Edge")
                            color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightMedium }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.phase === "disabling" ? qsTr("Removing your declaration and unlocking the staked note.")
                                                             : qsTr("Your staked note is unlocked. The node reverts to Edge at the next epoch.")
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
                // Close (mid-flow) / Done (terminal)
                LogosButton { visible: root.phase === "enabling" || root.phase === "disabling"; text: qsTr("Close"); onClicked: root.close() }
                LogosButton { visible: root.phase === "activated" || root.phase === "disabled"; text: qsTr("Done"); onClicked: root._done() }
                // Enable / Disable actions
                LogosButton { visible: root.phase === "gates"; variant: LogosButton.Variant.Primary
                    text: root.withdrawEpoch >= 0 ? qsTr("Re-declare after epoch %1").arg(root.withdrawEpoch) : qsTr("Enable Blend Core")
                    enabled: root.allGreen; onClicked: root._enable() }
                LogosButton { visible: root.phase === "core"; text: qsTr("Disable Blend Core"); onClicked: root._disable() }
            }
        }
    }
}
