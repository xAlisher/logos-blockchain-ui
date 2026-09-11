import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import Logos.BlockchainBackend 1.0
import "infoContent.js" as InfoContent

// Dashboard CONTENT (epic #56): Status/Blend hero pair + 4×3 metric grid + real Blocks table.
// Header + top-tab nav live in BlockchainView (persist across tabs). HONEST: fields with no real
// backend value show "—"; only wired data (status, slot/height/tip/lib, peerId) is real. Blocks are
// real (blockModel). Blend/Peers/CPU/RAM/Empowering/Proposed/Stake/Earned have no API yet → "—".
Item {
    id: root
    implicitWidth: 1040
    implicitHeight: 760
    readonly property int _minCard: 210     // min card width; cards wrap to next line below this
    readonly property int _heroMin: 340

    // ── WIRED (real backend, fed by BlockchainView) ──
    property int status: -1                                  // backend.status (-1 = not connected)
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
    property string moduleVersion: "0.2.20"
    property string coreVersion: ""
    property string uiVersion: moduleVersion
    property string testnetVersion: ""
    readonly property string _versionLine: (coreVersion.length && testnetVersion.length)
        ? qsTr("core %1 • UI %2 • testnet %3").arg(coreVersion).arg(uiVersion).arg(testnetVersion)
        : qsTr("Module v%1").arg(moduleVersion)
    readonly property var _infoData: InfoContent.data          // (i) tooltip content per tile

    // ── derived from JSON; "—" when the node hasn't reported (no fake fallbacks) ──
    function _parse(s) { try { return (s && s.length) ? JSON.parse(s) : null } catch (e) { return null } }
    function _short(s) { return (s && s.length > 14) ? (s.substring(0, 6) + "…" + s.substring(s.length - 4)) : (s || "—") }
    function _fmtK(n) { return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") }   // thousands with thin spaces
    // Numeric value of a formatted amount ("0 LGO" → 0, "12.5 LGO" → 12.5, "—" → 0).
    function _amt(s) { var m = String(s).match(/-?[0-9][0-9.,]*/); return m ? parseFloat(m[0].replace(/,/g, "")) : 0 }
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

    // ── NOT wired (no API yet) — honest placeholders, overridable for design mocks ──
    property string blendState: "none"                       // #58 none|edge|core (NOT in 0.3 API)
    property string epoch: "—"
    property string epochProgress: ""                        // e.g. "6h of 10h" — needs epoch length + slot-in-epoch from the node
    property string proposed: "—"                            // #61
    property string validation: ""                           // active|inactive|""
    property int epochsToActivate: 0
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
    property string stakeStr: "—"                            // #59
    property string foundingAddr: ""
    property string earnedStr: "—"                           // #60
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
        (!nodeConnected)
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
            ? ({ label: qsTr("Online"), sub: (uptime.length ? qsTr("Uptime: ") + uptime : qsTr("Validating")), c: Theme.palette.success, copy: uptime.length > 0, d: false })
      : ({ label: qsTr("Not started"), sub: "", c: Theme.palette.textSecondary, copy: false, d: false })
    readonly property bool nodeConnected: status >= 0
    readonly property var _blend: blendState === "core" ? ({ label: qsTr("Core"), c: Theme.palette.info })
                                : blendState === "edge" ? ({ label: qsTr("Edge"), c: Theme.palette.info })
                                : ({ label: qsTr("Not active"), c: Theme.palette.text })
    readonly property string _blendSub: blendState === "none" ? qsTr("Proposals not mixed") : qsTr("Proposals mixed")
    // While the node is Aging (funded, not yet eligible to propose — lane stage 2),
    // the Proposed card reflects that dedicated state instead of a bare "—".
    readonly property string _proposedSub: _lifeReached === 2 ? qsTr("Aging — eligible to propose in ~2 epochs")
                                : validation === "active" ? qsTr("Validation active")
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
        NumberAnimation on flow { running: lane.transitioning; from: 0; to: 1; duration: 1500; loops: Animation.Infinite }
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
        readonly property int _vsize: hero ? 32 : 24
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
                    Layout.fillWidth: false; text: value
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
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Stake"); value: root.stakeStr; sub: root.foundingAddr.length > 0 ? root._short(root.foundingAddr) : ""; copyValue: root.foundingAddr; onCopyRequested: (t) => root.copyText(t); info: root._infoData.stake; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Earned"); value: root.earnedStr; sub: root.feePct.length ? qsTr("Fees this epoch: ") + root.feePct : ""; info: root._infoData.earned; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Blend"); value: root._blend.label; sub: root._blendSub; accent: root._blend.c; info: root._infoData.blend; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Epoch"); value: root.epoch; sub: root.epochProgress; info: root._infoData.epoch; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Proposed in current epoch"); value: root.proposed; sub: root._proposedSub; subColor: root._lifeReached === 2 ? Theme.palette.warning : Theme.palette.textTertiary; info: root._infoData.proposed; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Peers"); value: root.peers; sub: root.connections; info: root._infoData.peers; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Peer ID"); value: root.peerIdShort; copyValue: root.peerId; onCopyRequested: (t) => root.copyText(t); info: root._infoData.peerId; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Mining")
                            // dashboard shows PROGRESS of mining (%, mined/target), not raw token totals; "—" when not started
                            value: (root.empoweringActive && root.empoweringTarget > 0) ? (Math.min(100, Math.round(root.empoweringMined / root.empoweringTarget * 100)) + "%") : "—"
                            sub: (root.empoweringActive && root.empoweringTarget > 0) ? (root._fmtK(root.empoweringMined) + " / " + root._fmtK(root.empoweringTarget) + " LGO") : ""; info: root._infoData.mining; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("CPU"); value: root.cpu; sub: root.cpuCap; info: root._infoData.cpu; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("RAM"); value: root.ram; sub: root.ramCap; info: root._infoData.ram; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Disk"); value: root.disk; sub: root.diskCap; info: root._infoData.disk; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Slot"); value: root.slot; info: root._infoData.slot; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Height"); value: root.heightStr; info: root._infoData.height; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("LiB"); value: root.lib; copyValue: root._libFull; onCopyRequested: (t) => root.copyText(t); info: root._infoData.lib; onInfoRequested: root._openInfo(info) }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("TiP"); value: root.tip; copyValue: root._tipFull; onCopyRequested: (t) => root.copyText(t); info: root._infoData.tip; onInfoRequested: root._openInfo(info) }
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
