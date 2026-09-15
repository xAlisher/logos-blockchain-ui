import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import Logos.BlockchainBackend 1.0
import "infoContent.js" as InfoContent
import "../amounts.js" as Amounts

// Dashboard CONTENT (epic #56): Status/Blend hero pair + 4×3 metric grid + real Blocks table.
// Header + top-tab nav live in BlockchainView (persist across tabs). HONEST: fields with no real
// backend value show "—"; only wired data (status, slot/height/tip/lib, peerId) is real. Blocks are
// real (blockModel). Blend/Peers/CPU/RAM/Empowering/Proposed/Stake/Earned have no API yet → "—".
Item {
    id: root
    implicitWidth: 1040
    implicitHeight: 760
    // Min card width drives the grid's column count. The longest primary value
    // (Earned, in full lepta precision) DEFINES the floor: once a value no longer
    // fits a 210px card, _minCard grows to fit it so the grid drops to fewer
    // columns (cards rearrange) instead of clipping the number. Stake abbreviates
    // itself, so only the non-abbreviated Earned value needs to widen the card.
    readonly property int _minCard: Math.max(210, Math.ceil(_earnedTM.advanceWidth) + 2 * Theme.spacing.large + 16)
    TextMetrics { id: _earnedTM; font.pixelSize: 24; font.weight: Theme.typography.weightBold; text: root.earnedStr }
    readonly property int _heroMin: 340

    // ── WIRED (real backend, fed by BlockchainView) ──
    property int status: -1                                  // backend.status (-1 = not connected)
    property bool autoPaused: false                          // node stopped by a resource-cap breach
    property string autoPauseReason: ""                      // e.g. "CPU cap of 95%"
    property bool nodeRecovering: false
    property string lastErrorMessage: ""
    property string infoJson: ""                             // get_cryptarchia_info
    property string timeInfoJson: ""                         // get_time_info
    property string peerId: ""                               // getPeerId
    property var blockModel: null                            // real blocks
    property bool nodeRunning: false
    property string blocksEmptyText: qsTr("Start the node to see blocks arrive.")
    signal clearBlocksRequested()
    signal copyText(string t)

    // Version footer. This fork ships ONE module version — the /release in-UI guard
    // (CMakeLists) greps this literal and requires it to equal metadata.json. The
    // core/UI/testnet split is kept as API for the official build; empty core/testnet
    // ⇒ the footer honestly shows just "Module v<x>".
    property string moduleVersion: "0.2.23"
    property string coreVersion: ""
    property string uiVersion: moduleVersion
    property string testnetVersion: ""
    readonly property string _versionLine: (coreVersion.length && testnetVersion.length)
        ? qsTr("core %1 • UI %2 • testnet %3").arg(coreVersion).arg(uiVersion).arg(testnetVersion)
        : qsTr("Module v%1").arg(moduleVersion)
    readonly property var _infoData: InfoContent.data          // (i) tooltip content per tile
    readonly property var _rewardsInfo: InfoContent.rewards    // (i) content for the claim/rewards tiles (separate object)

    // ── derived from JSON; "—" when the node hasn't reported (no fake fallbacks) ──
    function _parse(s) { try { return (s && s.length) ? JSON.parse(s) : null } catch (e) { return null } }
    function _short(s) { return (s && s.length > 14) ? (s.substring(0, 6) + "…" + s.substring(s.length - 4)) : (s || "—") }
    function _fmtK(n) { return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") }   // thousands with thin spaces
    // Numeric value of a formatted amount ("0 LGO" → 0, "12.5 LGO" → 12.5, "—" → 0).
    function _amt(s) { var m = String(s).match(/-?[0-9][0-9.,]*/); return m ? parseFloat(m[0].replace(/,/g, "")) : 0 }
    // Width-responsive amount: keep the full number if it fits maxChars, else step up
    // magnitude (K→M→B→T) to the most precise form that fits. Suffix (e.g. " LGO") kept.
    function _tierNum(v) { return v >= 100 ? String(Math.round(v)) : (v >= 10 ? v.toFixed(0) : v.toFixed(1)) }
    function _abbrevFit(s, maxChars) {
        if (!s || s.length <= maxChars) return s
        var m = String(s).match(/^\s*(-?\d[\d,]*(?:\.\d+)?)(.*)$/)
        if (!m) return s                                   // non-numeric → leave (elide handles it)
        var n = parseFloat(m[1].replace(/,/g, "")); var suf = m[2] || ""
        if (!isFinite(n)) return s
        var tiers = [[1, ""], [1e3, "K"], [1e6, "M"], [1e9, "B"], [1e12, "T"]]
        var cands = []
        for (var i = 0; i < tiers.length; i++) { var v = n / tiers[i][0]; if (i === 0 || v >= 1) cands.push(_tierNum(v) + tiers[i][1] + suf) }
        for (var j = 0; j < cands.length; j++) if (cands[j].length <= maxChars) return cands[j]
        return cands[cands.length - 1]                     // even T doesn't fit → shortest we have
    }
    readonly property var _info: _parse(infoJson)
    readonly property var _time: _parse(timeInfoJson)
    function _field(k) { if (!_info) return undefined; if (_info.cryptarchia_info && _info.cryptarchia_info[k] !== undefined) return _info.cryptarchia_info[k]; return _info[k] }
    // The node's sync state. Accept whichever key this build exposes: `mode` (IPC
    // get_cryptarchia_info), or `state` / nested cryptarchia_info.state (HTTP-shaped).
    readonly property string mode: {
        if (!_info) return ""
        if (_info.mode) return String(_info.mode)
        if (_info.state) return String(_info.state)
        if (_info.cryptarchia_info && _info.cryptarchia_info.state) return String(_info.cryptarchia_info.state)
        return ""
    }
    readonly property string slot: (_time && _time.current_slot !== undefined) ? String(_time.current_slot)
                                   : (_field("slot") !== undefined ? String(_field("slot")) : "—")
    readonly property string heightStr: _field("height") !== undefined ? String(_field("height")) : "—"
    readonly property string lib: _field("lib") ? _short(String(_field("lib"))) : "—"
    readonly property string tip: _field("tip") ? _short(String(_field("tip"))) : "—"
    readonly property string _libFull: _field("lib") ? String(_field("lib")) : ""
    readonly property string _tipFull: _field("tip") ? String(_field("tip")) : ""
    readonly property string peerIdShort: (peerId && peerId.length) ? _short(peerId) : "—"
    // Epoch progress (prototype calc): epoch = floor(slot / epochLen); slot-in-epoch × slot
    // duration gives elapsed. PREVIEW: epochLen is a testnet-measured const (~36000 slots ≈ 10h)
    // until the node exposes it — verified consistent (596k/36000 ≈ epoch 16).
    readonly property int _epochLenSlots: 36000
    readonly property string _epochSub: {
        if (!_time || _time.current_slot === undefined || _time.slot_duration_ms === undefined) return ""
        var dur = Number(_time.slot_duration_ms) / 1000            // seconds per slot
        if (!(dur > 0)) return ""
        var inEpoch = Number(_time.current_slot) % _epochLenSlots
        var elapsedM = Math.floor(inEpoch * dur / 60)
        var lenH = Math.round(_epochLenSlots * dur / 3600)
        var h = Math.floor(elapsedM / 60), m = elapsedM % 60
        return (h > 0 ? h + "h " : "") + m + "m of " + lenH + "h"
    }

    // ── NOT wired (no API yet) — honest placeholders, overridable for design mocks ──
    property string blendState: "none"                       // #58 none|edge|core (NOT in 0.3 API)
    property string epoch: "—"
    property string epochProgress: ""                        // e.g. "6h of 10h" — needs epoch length + slot-in-epoch from the node
    property string proposed: "—"                            // #61
    property string validation: ""                           // active|inactive|""
    property int epochsToActivate: 0
    // Real eligibility signal: the node's /leader/aged-notes `count` (#61). A note can
    // lead exactly 2 epochs after it is minted (stake snapshot = start of the previous
    // epoch). -1 = the node version doesn't report it (pre-0.3, e.g. this 0.2.4 line →
    // 404), 0 = funded but not yet aged, >0 = eligible to propose now.
    property int eligibleNoteCount: -1
    property int vouchersSubmitted: -1                       // claims in flight (submitted, awaiting settle); -1 = n/a
    property int vouchersReady: -1                           // claimable vouchers ready; -1 = n/a
    property string peers: "—"                               // #62 (curl)
    property string connections: ""
    property bool empoweringActive: false                    // #64 (#85) — mining currently on (drives the tile)
    property real empoweringMined: -1                        // LGO mined toward target; <0 = no data
    property real empoweringTarget: -1                       // auto-claim threshold / target balance
    property bool funded: false                              // wallet has stake/notes (persists after mining stops) — the lifecycle "Funded" signal
    property string cpu: "—"                                 // #65 (#89)
    property string cpuCap: ""
    property string ram: "—"                                 // #66 (#89)
    property string ramCap: ""
    property string disk: "—"                                // node data-dir footprint (#89)
    property string diskCap: ""
    property string diskPruneNote: ""                        // transient, shown on the Disk tile after a disk-cap prune
    property string stakeStr: "—"                            // #59
    property string foundingAddr: ""
    property string earnedStr: "—"                           // #60
    property var earnedByEpoch: []                           // [{epoch, lepta}] net earned per epoch (chart)
    property string feePct: ""
    property string uptime: ""
    property string replayProgress: ""
    property string bootCountdown: ""
    property bool bootOverran: false

    // Stall / crash detection. Catches a DEAD node (crashed / IBD wedged) that the
    // backend still reports as Running — those stay frozen for hours. Threshold is
    // deliberately generous (10 min): a live bootstrap legitimately advances Height only
    // every few minutes during peer churn, so a tight window false-fires on slow sync.
    property bool nodeStalled: false
    readonly property int _stallMs: 600000        // 10 min of ZERO height progress ⇒ actually stuck
    property double _heightAdvancedAt: 0
    property string _heightSeen: ""
    onHeightStrChanged: {
        if (heightStr !== "—" && heightStr !== _heightSeen) {
            _heightSeen = heightStr
            _heightAdvancedAt = Date.now()
            nodeStalled = false
        }
    }

    // sync-rate + ETA engine (ported from NodeStatusCard, #57) → real bootstrapping countdown
    onInfoJsonChanged: sync.sampleRate(sync.tipSlot)
    QtObject {
        id: sync
        readonly property var tipSlot: root._field("slot") !== undefined ? Number(root._field("slot")) : undefined
        readonly property var currentSlot: (root._time && root._time.current_slot !== undefined) ? Number(root._time.current_slot) : undefined
        readonly property var slotDurationMs: (root._time && root._time.slot_duration_ms !== undefined) ? Number(root._time.slot_duration_ms) : undefined
        readonly property var remaining: (tipSlot === undefined || currentSlot === undefined) ? undefined : Math.max(0, currentSlot - tipSlot)
        readonly property int syncedSlack: 3   // (retained for the ETA engine below; NOT used to gate `synced`)
        // Trust the node's own sync state. It only reports "Online" once it's caught up
        // and following the chain; a slot-gap check here false-fired on this sparse chain,
        // where the tip legitimately trails wall-clock by tens of slots between blocks —
        // which made the hero flap Online↔Bootstrapping every time a block landed.
        readonly property bool synced: root.mode === "Online"
        property real emaRate: NaN
        property real lastTip: NaN
        property real lastAt: 0
        readonly property real smoothing: 0.15
        readonly property real etaEnterRate: 0.05
        readonly property real etaExitRate: 0.0
        property bool etaHolding: false
        readonly property real headRate: (slotDurationMs !== undefined && slotDurationMs > 0) ? 1000 / slotDurationMs : NaN
        function sampleRate(tip) {
            if (tip === undefined) return
            const now = Date.now() / 1000
            if (!isNaN(lastTip) && now > lastAt) {
                const instant = (tip - lastTip) / (now - lastAt)
                if (instant < 0) emaRate = NaN
                else emaRate = isNaN(emaRate) ? instant : smoothing * instant + (1 - smoothing) * emaRate
            }
            lastTip = tip; lastAt = now
            const closing = emaRate - headRate
            if (!isNaN(closing)) {
                if (!etaHolding && closing > etaEnterRate) etaHolding = true
                else if (etaHolding && closing <= etaExitRate) etaHolding = false
            }
        }
        readonly property real closingRate: (isNaN(emaRate) || isNaN(headRate)) ? NaN : emaRate - headRate
        readonly property var etaSeconds: {
            if (!(root.status === BlockchainBackend.Running) || synced || remaining === undefined || remaining <= 0) return undefined
            if (!etaHolding || isNaN(closingRate) || closingRate <= 0) return undefined
            return remaining / closingRate
        }
        function formatEta(seconds) {
            const total = Math.round(seconds); const h = Math.floor(total / 3600); const m = Math.floor((total % 3600) / 60); const s = total % 60
            const pad = (n) => (n < 10 ? "0" + n : String(n))
            return h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (m + ":" + pad(s))
        }
        // Calm, honest bootstrap sub: no growing counter/ETA (the node may not be converging, which
        // makes both "slots behind" and remaining/rate grow). Progress lives in the Height tile
        // (blocks applied, monotonic). A real %-complete needs a backend sync-progress field.
        readonly property string syncLabel: qsTr("Syncing…")
    }

    // Bootstrap countdown: bootstrap runs ~1h, so count DOWN from 60:00 (client-side elapsed —
    // no backend sync-progress field exists). On overrun → "Takes a bit longer." (mockup #57).
    readonly property bool _bootstrapping: status === BlockchainBackend.Running && !sync.synced
    property int _bootSecs: 0
    readonly property int _bootTotal: 3600
    function _fmtSecs(s) { var m = Math.floor(s / 60); var ss = s % 60; return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss }
    Timer {
        interval: 1000; repeat: true; running: root._bootstrapping
        onTriggered: {
            if (root._bootSecs < root._bootTotal + 3) root._bootSecs += 1
            // Height hasn't advanced for _stallMs while bootstrapping ⇒ the node is
            // wedged or has crashed (the backend still says Running). Surface it.
            root.nodeStalled = root._heightAdvancedAt > 0
                && (Date.now() - root._heightAdvancedAt > root._stallMs)
        }
        onRunningChanged: if (!running) { root._bootSecs = 0; root.nodeStalled = false }
    }

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    // ── Status hero → {label, sub, color} ──
    // label = base text (no ellipsis); d = animate a reserved-width "…" (transitional states)
    readonly property var _st:
        autoPaused
            ? ({ label: qsTr("Node auto-paused"), sub: qsTr("Node hit %1").arg(autoPauseReason.length ? autoPauseReason : qsTr("a resource cap")), c: Theme.palette.warning, copy: false, d: false })
      : (!nodeConnected)
            ? ({ label: qsTr("Not connected"), sub: "", c: Theme.palette.textSecondary, copy: false, d: false })
      : status === BlockchainBackend.Error
            ? ({ label: qsTr("Error"), sub: (lastErrorMessage.length ? lastErrorMessage : qsTr("Node error.")), c: Theme.palette.error, copy: lastErrorMessage.length > 0, d: false })
      : nodeStalled
            ? ({ label: qsTr("Sync stalled"), sub: qsTr("No block progress — the node may have stopped or lost peers. Try stopping and starting it again."), c: Theme.palette.error, copy: false, d: false })
      : nodeRecovering
            ? ({ label: qsTr("Replaying blocks"), sub: replayProgress, c: Theme.palette.warning, copy: false, d: true })
      : status === BlockchainBackend.Starting
            ? ({ label: qsTr("Starting"), sub: qsTr("Checking configuration"), c: Theme.palette.warning, copy: false, d: true })
      : (status === BlockchainBackend.Running && !sync.synced)
            ? ({ label: qsTr("Bootstrapping"), sub: (_bootTotal - _bootSecs > 0) ? ("~" + _fmtSecs(_bootTotal - _bootSecs)) : qsTr("Takes a bit longer."), c: Theme.palette.warning, copy: false, d: true })
      : status === BlockchainBackend.Running
            ? ({ label: qsTr("Online"), sub: (uptime.length ? qsTr("Uptime: ") + uptime : qsTr("Following the chain")), c: Theme.palette.success, copy: uptime.length > 0, d: false })
      : ({ label: qsTr("Not started"), sub: "", c: Theme.palette.textSecondary, copy: false, d: false })
    readonly property bool nodeConnected: status >= 0
    readonly property var _blend: blendState === "core" ? ({ label: qsTr("Core"), c: Theme.palette.info })
                                : blendState === "edge" ? ({ label: qsTr("Edge"), c: Theme.palette.info })
                                : ({ label: qsTr("Not active"), c: Theme.palette.text })
    readonly property string _blendSub: blendState === "none" ? qsTr("Proposals not mixed") : qsTr("Proposals mixed")
    // Blend state is only meaningful once the node is Online (following the chain).
    // While stopped / starting / replaying / bootstrapping, show "—" and no sub
    // rather than a misleading "Not active · Proposals not mixed".
    readonly property bool _blendKnown: status === BlockchainBackend.Running && sync.synced
    // While the node is Aging (funded, not yet eligible to propose — lane stage 2),
    // the Proposed card reflects that dedicated state instead of a bare "—".
    // Eligible once the node has aged/led a block; the per-epoch count (value) can be
    // 0 at epoch start without meaning "not eligible" — the sub carries that state.
    readonly property string _proposedSub: _lifeReached >= 3 ? (_amt(proposed) > 0 ? qsTr("Proposing") : qsTr("Eligible"))
                                : _lifeReached === 2 ? (eligibleNoteCount === 0 ? qsTr("Aging") : qsTr("Aging, eligibility not reported."))
                                : validation === "inactive" ? (epochsToActivate > 0 ? qsTr("Activates in %1 %2").arg(epochsToActivate).arg(epochsToActivate === 1 ? qsTr("epoch") : qsTr("epochs")) : qsTr("Validation inactive"))
                                : ""

    // Node lifecycle — HONEST: a stage only counts as reached when we can truly
    // detect it. Today only Started + Online have real signals; Empowered/Aged/
    // Proposing/Earning are reached only once their backend fields land
    // (#64/#85, #59-#61). Progress is expressed as a single frontier index
    // (furthest reached) plus a transitioning flag (moving Started→Online).
    readonly property var _lifeSteps: [qsTr("Started"), qsTr("Online"), qsTr("Funded"), qsTr("Aged"), qsTr("Proposing"), qsTr("Earning")]
    // Furthest reached stage (-1 = none). Monotonic: a later confirmed stage
    // implies every earlier one (you can't propose without having aged/empowered).
    readonly property int _lifeReached: {
        if (!nodeConnected || status === BlockchainBackend.NotStarted) return -1
        if (status === BlockchainBackend.Starting) return -1                    // Started itself is in progress (live, unchecked)
        if (nodeRecovering) return 0                                            // replaying → Started done, syncing
        if (status === BlockchainBackend.Running && !sync.synced) return 0
        if (status !== BlockchainBackend.Running) return -1
        var r = 1                                                               // Online (Running + synced)
        if (funded || _amt(stakeStr) > 0) r = Math.max(r, 2)                    // Funded — wallet actually holds stake
        if (eligibleNoteCount > 0) r = Math.max(r, 3)                           // Aged — a note is in the aged UTXO snapshot (#61)
        if (validation === "active") r = Math.max(r, 4)                         // Proposing implies Aged (#61)
        if (_amt(earnedStr) > 0) r = Math.max(r, 5)                             // Earning — a POSITIVE reward, not "0 LGO" (#60)
        return r
    }
    // Actively moving from the frontier toward the next stage. Two detectable
    // transitions: Started→Online (starting/replaying/bootstrapping), and
    // Funded→Aged (funded notes waiting ~2 epochs to become eligible to lead —
    // "aged" is the real Cryptarchia term; queryable via get_leader_aged_notes,
    // not yet wired: logos-blockchain-module#61).
    readonly property bool _lifeTransitioning:
        status === BlockchainBackend.Starting || nodeRecovering
        || (status === BlockchainBackend.Running && !sync.synced)                              // → Online (bootstrapping)
        || (status === BlockchainBackend.Running && sync.synced && empoweringActive && !funded) // → Funded (mining)
        || _lifeReached === 2                                                                   // → Aged (aging)

    // Chevron/pipeline lane. green = LIVE (the one accented segment); done = gray
    // segment + green check; transitioning = the live segment goes yellow (animated
    // fill pulse); future = darkest segments.
    component Lifecycle: Item {
        id: lane
        property var steps: []
        property int reached: -1
        property bool transitioning: false
        property bool stalled: false                   // live stage wedged (no progress) → red, not pulsing
        property real flow: 0
        implicitHeight: 30
        readonly property int n: steps.length
        readonly property real gap: 2                  // clearance from a chevron's tip to the next's notch
        readonly property real inset: 0                // lane fills to the card padding → equal gap on both sides
        readonly property real dpth: Math.min(14, height * 0.5)   // point/notch depth
        // interlocking: each chevron overlaps the next by (dpth - gap) so the tip sits `gap` px from the notch
        readonly property real segW: (width - 2 * inset + (n - 1) * (dpth - gap)) / Math.max(1, n)
        function segLeft(i) { return inset + i * (segW - dpth + gap) }
        function segRight(i) { return segLeft(i) + segW }
        function labelCenter(i) {   // center within the readable area (between the notch and the point)
            var l = segLeft(i) + (i > 0 ? dpth : 0)
            var r = segRight(i) - (i < n - 1 ? dpth : 0)
            return (l + r) / 2
        }
        onReachedChanged: cv.requestPaint()
        onTransitioningChanged: cv.requestPaint()
        onStalledChanged: cv.requestPaint()
        onWidthChanged: cv.requestPaint()
        onFlowChanged: cv.requestPaint()
        Component.onCompleted: cv.requestPaint()
        // breathe: ease up, then ease back down. Was a sawtooth (0→1 then a hard snap
        // back to 0) which read as a sharp, fast drop from filled to transparent.
        SequentialAnimation on flow {
            running: lane.transitioning; loops: Animation.Infinite
            NumberAnimation { from: 0; to: 1; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1; to: 0; duration: 1400; easing.type: Easing.InOutSine }
        }
        Canvas {
            id: cv; anchors.fill: parent
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                var ctx = getContext("2d"); ctx.reset()
                var green = Theme.palette.success, yellow = Theme.palette.warning, red = Theme.palette.error
                var h = height, r = 3, dpth = lane.dpth
                // trace a polygon with rounded corners (arcTo from each edge midpoint)
                function roundPoly(pts) {
                    var m = pts.length
                    ctx.beginPath()
                    var s = pts[m - 1], b = pts[0]
                    ctx.moveTo((s[0] + b[0]) / 2, (s[1] + b[1]) / 2)
                    for (var k = 0; k < m; k++) {
                        var cur = pts[k], nxt = pts[(k + 1) % m]
                        ctx.arcTo(cur[0], cur[1], nxt[0], nxt[1], r)
                    }
                    ctx.closePath()
                }
                for (var i = 0; i < n; i++) {
                    var x0 = lane.segLeft(i), x1 = lane.segRight(i)
                    var first = (i === 0), last = (i === n - 1)
                    // while transitioning, the LIVE (pulsing) stage is the NEXT one being worked
                    // toward (e.g. aging → Aged), and the frontier itself is done (checked).
                    var liveIdx = transitioning ? reached + 1 : reached   // Starting: reached=-1 → live is Started(0)
                    var isLive = (i === liveIdx && liveIdx >= 0 && liveIdx < n)
                    var isDone = (reached >= 0 && i <= reached && i !== liveIdx)
                    var fill
                    if (isLive && lane.stalled) fill = Qt.rgba(red.r, red.g, red.b, 0.22)
                    else if (isLive && transitioning) fill = Qt.rgba(yellow.r, yellow.g, yellow.b, 0.14 + 0.14 * flow)
                    else if (isLive) fill = Qt.rgba(green.r, green.g, green.b, 0.20)
                    else if (isDone) fill = Theme.palette.surface
                    else fill = Theme.palette.surfaceRecessed
                    var pts = [[x0, 0]]
                    if (last) { pts.push([x1, 0], [x1, h]) }
                    else { pts.push([x1 - dpth, 0], [x1, h / 2], [x1 - dpth, h]) }
                    pts.push([x0, h])
                    if (!first) pts.push([x0 + dpth, h / 2])   // concave notch seats the previous chevron's point
                    roundPoly(pts)
                    ctx.fillStyle = fill; ctx.fill()
                }
            }
        }
        // per-segment label (+ green check for done), centered in the chevron
        Repeater {
            model: lane.steps
            Row {
                required property int index
                required property string modelData
                readonly property int _liveIdx: lane.transitioning ? lane.reached + 1 : lane.reached
                readonly property bool _live: index === _liveIdx && _liveIdx >= 0 && _liveIdx < lane.n
                readonly property bool _done: lane.reached >= 0 && index <= lane.reached && index !== _liveIdx
                spacing: 4
                x: lane.labelCenter(index) - width / 2
                y: (lane.height - height) / 2
                LogosText { visible: parent._done; text: "✓"; color: Theme.palette.success; font.pixelSize: 12; font.weight: Theme.typography.weightBold; anchors.verticalCenter: parent.verticalCenter }
                LogosText {
                    // a transitioning-live stage shows the in-progress verb (Online→Syncing…, Aged→Aging)
                    text: (parent._live && lane.stalled && index === 1) ? qsTr("Stalled")
                        : (parent._live && lane.transitioning && index === 1) ? qsTr("Syncing…")
                        : (parent._live && lane.transitioning && index === 3) ? qsTr("Aging")
                        : parent.modelData
                    font.pixelSize: 12
                    color: parent._live ? (lane.stalled ? Theme.palette.error : (lane.transitioning ? Theme.palette.warning : Theme.palette.success))
                          : parent._done ? Theme.palette.textSecondary : Theme.palette.textTertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    component Info: Rectangle {
        id: ib
        signal clicked()
        readonly property bool hovered: ma.containsMouse
        width: 16; height: 16; radius: 8; color: "transparent"
        border.width: 1
        border.color: hovered ? Theme.palette.text : Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.35)
        LogosText { anchors.centerIn: parent; text: "i"; font.pixelSize: 9; color: ib.hovered ? Theme.palette.text : Theme.palette.textMuted }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }
    component CopyGlyph: Canvas {
        implicitWidth: 16; implicitHeight: 16
        property color stroke: Theme.palette.textMuted
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            ctx.strokeStyle = stroke; ctx.lineWidth = 1.3; ctx.lineJoin = "round"; ctx.lineCap = "round";
            var r = 2, x = 1, y = 1, s = 9;
            ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + s, y, x + s, y + s, r); ctx.arcTo(x + s, y + s, x, y + s, r);
            ctx.arcTo(x, y + s, x, y, r); ctx.arcTo(x, y, x + s, y, r); ctx.closePath(); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(10, 5); ctx.lineTo(14 - r, 5); ctx.arcTo(14, 5, 14, 14, r);
            ctx.arcTo(14, 14, 5, 14, r); ctx.lineTo(5, 14); ctx.lineTo(5, 10); ctx.stroke();
        }
    }
    component Block: LogosFrame {
        id: blk
        property var info: null                   // {title, what, calc, states, docs} for the (i) modal
        signal infoRequested()
        property string label: ""
        property string value: "—"
        property string sub: ""
        property color accent: Theme.palette.text
        property color tint: Theme.palette.surfaceRaised
        property color subColor: Theme.palette.textTertiary   // sub-line color (overridable, e.g. yellow while Aging)
        property bool copyable: false
        property string copyValue: ""            // if set, the sub row is just a copy button (copies this full value)
        signal copyRequested(string t)
        property bool _copied: false
        Timer { id: copiedTimer; interval: 1400; onTriggered: blk._copied = false }
        property bool hero: false
        property bool dots: false                 // animate a reserved-width "…" after the value
        property bool flash: !hero                // flash green on value change (live grid tiles)
        property bool showLane: false             // embed the lifecycle lane at the bottom (merged Status card)
        property var laneSteps: []
        property int laneReached: -1
        property bool laneTransitioning: false
        property bool abbreviate: false           // width-responsive number abbreviation (e.g. Stake)
        readonly property int _vsize: hero ? 32 : 24
        // Measure the ACTUAL rendered width of the full value (letters + space included, not
        // a digit estimate) so we abbreviate the moment it no longer fits the card, with a
        // small breathing-room margin. _chPx (a digit width) only sizes the shorter tiers.
        TextMetrics { id: _valTM; font.pixelSize: blk._vsize; font.weight: Theme.typography.weightBold; text: blk.value }
        TextMetrics { id: _chTM; font.pixelSize: blk._vsize; font.weight: Theme.typography.weightBold; text: "0000000000" }
        readonly property real _chPx: _chTM.advanceWidth > 0 ? _chTM.advanceWidth / 10 : 12
        readonly property real _valAvail: blk.width - 2 * Theme.spacing.large - (dots ? 34 : 0) - 12
        readonly property string _fitValue: {
            if (!abbreviate) return value
            if (_valTM.advanceWidth > 0 && _valTM.advanceWidth <= _valAvail) return value
            return root._abbrevFit(value, Math.max(5, Math.floor(_valAvail / _chPx)))
        }
        backgroundColor: Theme.palette.surfaceRaised     // no state tint — the colored value carries the state; flat surfaces avoid a color wash
        borderColor: "transparent"; radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        implicitHeight: showLane ? 118 : (hero ? 124 : 108)
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout { Layout.fillWidth: true
                visible: label.length > 0        // collapse the label line when there's no label (e.g. the Status hero)
                LogosText { text: label; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                Item { Layout.fillWidth: true }
                Info { visible: blk.info != null; onClicked: blk.infoRequested() } }
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                LogosText {
                    id: fv
                    Layout.fillWidth: false; text: blk._fitValue
                    property color restColor: accent
                    color: restColor                       // binding; flashAnim overrides on change
                    font.pixelSize: _vsize; font.weight: Theme.typography.weightBold; elide: Text.ElideRight
                    onTextChanged: if (flash) flashAnim.restart()
                    SequentialAnimation {
                        id: flashAnim
                        ColorAnimation { target: fv; property: "color"; to: Theme.palette.success; duration: 160; easing.type: Easing.OutQuad }
                        ColorAnimation { target: fv; property: "color"; to: fv.restColor; duration: 1100; easing.type: Easing.InOutQuad }
                    }
                }
                Row {   // reserved-width animated ellipsis (only opacity animates → no jump)
                    visible: dots; spacing: 0
                    Repeater { model: 3
                        LogosText {
                            text: "."; color: accent; font.pixelSize: _vsize; font.weight: Theme.typography.weightBold
                            opacity: 0.25
                            SequentialAnimation on opacity {
                                running: dots; loops: Animation.Infinite
                                PauseAnimation { duration: index * 260 }
                                NumberAnimation { to: 1.0; duration: 180 }
                                NumberAnimation { to: 0.25; duration: 180 }
                                PauseAnimation { duration: (2 - index) * 260 + 520 }
                            }
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                // merged hero: uptime/countdown pinned to the card's upper-right corner
                LogosText {
                    visible: showLane && sub.length > 0
                    text: sub; color: subColor; font.pixelSize: Theme.typography.secondaryText
                    Layout.alignment: Qt.AlignTop
                }
                Info { visible: showLane && blk.info != null; Layout.alignment: Qt.AlignTop; Layout.leftMargin: Theme.spacing.small; onClicked: blk.infoRequested() }
            }
            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 16; spacing: Theme.spacing.small
                visible: !showLane        // (stacked below the value only when the lane isn't sharing the card)
                // normal sub text (hidden when the row is a copy-only button)
                LogosText { visible: copyValue.length === 0 && sub.length > 0; text: sub; color: subColor
                            font.pixelSize: Theme.typography.secondaryText; elide: Text.ElideRight }
                // short display text alongside a full-value copy (e.g. Stake address)
                LogosText { visible: copyValue.length > 0 && sub.length > 0; text: sub; color: subColor
                            font.pixelSize: Theme.typography.secondaryText; elide: Text.ElideRight }
                // copy button — copies copyValue (full) or the sub; flashes "Copied" to its right
                CopyGlyph {
                    visible: copyValue.length > 0 || (copyable && sub.length > 0)
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { blk.copyRequested(copyValue.length > 0 ? copyValue : sub); blk._copied = true; copiedTimer.restart() }
                    }
                }
                LogosText { visible: blk._copied; text: qsTr("Copied"); color: Theme.palette.success; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true } }
            Lifecycle {
                visible: showLane
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.large    // equal gap to the value line, matching the card padding
                steps: laneSteps; reached: laneReached; transitioning: laneTransitioning
                stalled: root.nodeStalled
            }
        }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth
        ColumnLayout {
            width: root.width; spacing: Theme.spacing.large
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: Theme.spacing.xlarge; spacing: Theme.spacing.large
                // ---- Node hero: full-width Status headline + journey lane merged ----
                Block {
                    Layout.fillWidth: true; hero: true; label: ""      // no "Status" label — the value is the headline
                    value: root._st.label; sub: root._st.sub; accent: root._st.c; copyable: false; dots: root._st.d
                    showLane: true; laneSteps: root._lifeSteps; laneReached: root._lifeReached; laneTransitioning: root._lifeTransitioning
                    info: root._infoData.status; onInfoRequested: root._openInfo(info)
                }
                GridLayout {
                    Layout.fillWidth: true; columns: Math.max(1, Math.min(4, Math.floor(width / (root._minCard + Theme.spacing.large)))); columnSpacing: Theme.spacing.large; rowSpacing: Theme.spacing.large
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Stake"); value: root.stakeStr; abbreviate: true; sub: root.foundingAddr.length > 0 ? root._short(root.foundingAddr) : ""; copyValue: root.foundingAddr; onCopyRequested: (t) => root.copyText(t); info: root._infoData.stake; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Earned"); value: root.earnedStr; sub: root.feePct.length ? qsTr("Last claim fee: %1% of reward").arg(root.feePct) : ""; info: root._infoData.earned; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Blend"); value: root._blendKnown ? root._blend.label : "—"; sub: root._blendKnown ? root._blendSub : ""; accent: root._blendKnown ? root._blend.c : Theme.palette.text; info: root._infoData.blend; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Epoch"); value: root.epoch; sub: root.epochProgress.length ? root.epochProgress : root._epochSub; info: root._infoData.epoch; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Blocks proposed in epoch"); value: root.proposed; sub: root._proposedSub; subColor: root._lifeReached === 2 ? Theme.palette.warning : root._lifeReached >= 3 ? (root._amt(root.proposed) > 0 ? Theme.palette.textTertiary : Theme.palette.success) : Theme.palette.textTertiary; info: root._infoData.proposed; onInfoRequested: root._openInfo(info) }
                    // Vouchers — the two honest numbers the Rewards tab shows:
                    // "Ready to claim" (claimable now) headlines; "Submitted" = claims in flight.
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Ready to claim"); value: root.vouchersReady >= 0 ? String(root.vouchersReady) : "—"; sub: root.vouchersSubmitted >= 0 ? qsTr("Submitted: %1").arg(root.vouchersSubmitted) : ""; info: root._rewardsInfo.readyToClaim; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Peers"); value: root.peers; sub: root.connections; info: root._infoData.peers; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Peer ID"); value: root.peerIdShort; copyValue: root.peerId; onCopyRequested: (t) => root.copyText(t); info: root._infoData.peerId; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Mining")
                            // dashboard shows PROGRESS of mining (%, mined/target), not raw token totals; "—" when not started
                            value: (root.empoweringActive && root.empoweringTarget > 0) ? (Math.min(100, Math.round(root.empoweringMined / root.empoweringTarget * 100)) + "%") : "—"
                            sub: (root.empoweringActive && root.empoweringTarget > 0) ? (root._fmtK(root.empoweringMined) + " / " + root._fmtK(root.empoweringTarget) + " LGO") : ""; info: root._infoData.mining; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("CPU"); value: root.cpu; sub: root.cpuCap; info: root._infoData.cpu; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("RAM"); value: root.ram; sub: root.ramCap; info: root._infoData.ram; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Disk"); value: root.disk; sub: root.diskPruneNote.length ? root.diskPruneNote : root.diskCap; info: root._infoData.disk; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Slot"); value: root.slot; copyValue: root.slot !== "—" ? root.slot : ""; onCopyRequested: (t) => root.copyText(t); info: root._infoData.slot; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Height"); value: root.heightStr; copyValue: root.heightStr !== "—" ? root.heightStr : ""; onCopyRequested: (t) => root.copyText(t); info: root._infoData.height; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("LiB"); value: root.lib; copyValue: root._libFull; onCopyRequested: (t) => root.copyText(t); info: root._infoData.lib; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("TiP"); value: root.tip; copyValue: root._tipFull; onCopyRequested: (t) => root.copyText(t); info: root._infoData.tip; onInfoRequested: root._openInfo(info) }
                }
                // ---- Earned by epoch (experimental) — full-width chart below the grid ----
                // Shown only once there's a first earning to plot (empty until then).
                LogosFrame {
                    Layout.fillWidth: true
                    visible: root.earnedByEpoch && root.earnedByEpoch.length > 0
                    backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                    radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { text: qsTr("Earned by epoch (LGO)"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                            Item { Layout.fillWidth: true }
                            // (i) — the SAME circled-i the metric tiles use; opens the shared InfoModal.
                            Info { Layout.alignment: Qt.AlignVCenter; onClicked: root._openInfo(root._infoData.earnedByEpoch) }
                        }
                        Item {
                            Layout.fillWidth: true; Layout.preferredHeight: 180
                            Canvas {
                                id: earnChart
                                anchors.fill: parent
                                readonly property var series: root.earnedByEpoch
                                // Geometry shared with the hover hit-test. padT leaves room for
                                // the hovered value drawn above the bars. No Y labels → tiny padL.
                                readonly property int padL: 6
                                readonly property int padR: 6
                                readonly property int padT: 22
                                readonly property int padB: 8        // no x-axis labels → small bottom pad, taller bars
                                readonly property int minSlot: 5     // px per bar+gap; lets bars go ~3-4px wide when packed
                                // Width-adaptive: draw only the most recent epochs that fit at minSlot each.
                                // Epoch labels are hidden (they'd crowd once bars go thin); the epoch + value
                                // reveal on hover instead. hoverIdx indexes into `vis`, not the full series.
                                readonly property var vis: {
                                    var d = series || []
                                    var pw = Math.max(1, width - padL - padR)
                                    var maxN = Math.max(1, Math.floor(pw / minSlot))
                                    return d.length > maxN ? d.slice(-maxN) : d
                                }
                                property int hoverIdx: -1
                                onSeriesChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onHoverIdxChanged: requestPaint()
                                onAvailableChanged: if (available) requestPaint()
                                Component.onCompleted: requestPaint()
                                function niceMax(v) {
                                    if (v <= 0) return 1
                                    var exp = Math.floor(Math.log(v) / Math.LN10)
                                    var base = Math.pow(10, exp)
                                    var f = v / base
                                    var nf = f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10
                                    return nf * base
                                }
                                onPaint: {
                                    var ctx = getContext("2d"); ctx.reset()
                                    var W = width, H = height
                                    var white = Theme.palette.text
                                    if ((series || []).length === 0) {
                                        ctx.font = "10px sans-serif"; ctx.fillStyle = Theme.palette.textTertiary
                                        ctx.textAlign = "center"; ctx.textBaseline = "middle"
                                        ctx.fillText(qsTr("No earnings yet — claim a reward to see it here."), W / 2, H / 2)
                                        return
                                    }
                                    var d = vis                                  // width-adaptive: the most recent epochs that fit
                                    // Y auto-scaled to the visible data (meaningful for tiny rewards); no labels.
                                    var maxLGO = 0
                                    for (var i = 0; i < d.length; i++) maxLGO = Math.max(maxLGO, Math.max(0, Number(d[i].lepta) / 1e9))
                                    var top = niceMax(maxLGO)
                                    var pw = Math.max(1, W - padL - padR), ph = Math.max(1, H - padT - padB)
                                    var baseY = padT + ph
                                    // faint baseline
                                    ctx.strokeStyle = Theme.palette.border; ctx.globalAlpha = 0.4; ctx.lineWidth = 1
                                    ctx.beginPath(); ctx.moveTo(padL, baseY); ctx.lineTo(W - padR, baseY); ctx.stroke(); ctx.globalAlpha = 1
                                    // Bars (white), FIXED width, packed from the LEFT (progress-style) — not
                                    // stretched to fill the width. Empty space stays on the right until history
                                    // grows into it; once it fills, `vis` shows a rolling window of the most recent.
                                    // slot = minSlot (bar + 1px gap); no x-axis labels — epoch + value show on hover.
                                    var slot = minSlot, bw = slot - 1
                                    for (var j = 0; j < d.length; j++) {
                                        var v = Math.max(0, Number(d[j].lepta) / 1e9)
                                        var cx = padL + slot * (j + 0.5)
                                        var bh = top > 0 ? (v / top) * ph : 0
                                        ctx.fillStyle = white; ctx.globalAlpha = (j === hoverIdx) ? 1.0 : 0.8
                                        ctx.fillRect(cx - bw / 2, baseY - bh, bw, bh); ctx.globalAlpha = 1
                                    }
                                    // Hover: "Epoch N: X LGO" above the bar, clamped so the label stays on-canvas.
                                    if (hoverIdx >= 0 && hoverIdx < d.length) {
                                        var hv = qsTr("Epoch %1: %2 LGO").arg(d[hoverIdx].epoch).arg(Amounts.preciseNum(Number(d[hoverIdx].lepta)))
                                        ctx.font = "11px sans-serif"; ctx.fillStyle = white
                                        ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
                                        var tw = ctx.measureText(hv).width
                                        var hx = padL + slot * (hoverIdx + 0.5)
                                        hx = Math.max(padL + tw / 2, Math.min(W - padR - tw / 2, hx))
                                        ctx.fillText(hv, hx, padT - 7)
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent; hoverEnabled: true
                                    onPositionChanged: {
                                        var d = earnChart.vis
                                        if (!d || d.length === 0) { earnChart.hoverIdx = -1; return }
                                        // Same fixed, left-packed geometry as onPaint.
                                        var idx = Math.floor((mouseX - earnChart.padL) / earnChart.minSlot)
                                        earnChart.hoverIdx = (idx >= 0 && idx < d.length) ? idx : -1
                                    }
                                    onExited: earnChart.hoverIdx = -1
                                }
                            }
                        }
                    }
                }

                // ---- footer: version line (+ copy) · legal disclaimer (modal) ----
                RowLayout {
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.small
                    LogosText { text: root._versionLine; color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText }
                    CopyGlyph {
                        Layout.alignment: Qt.AlignVCenter
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.copyText(root._versionLine) }
                    }
                    Item { Layout.fillWidth: true }
                    LogosLink { text: qsTr("Legal disclaimer"); font.pixelSize: Theme.typography.secondaryText
                                linkColor: Theme.palette.textTertiary; hoverColor: Theme.palette.textSecondary; underline: false
                                onActivated: legalModal.open() }
                }
            }
            // Blocks table moved to its own top-level "Blocks" tab (BlockchainView).
        }
    }

    LegalDisclaimerModal { id: legalModal }
    InfoModal { id: infoModal }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }
}
