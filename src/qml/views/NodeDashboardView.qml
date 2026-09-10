import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import Logos.BlockchainBackend 1.0

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

    // ── derived from JSON; "—" when the node hasn't reported (no fake fallbacks) ──
    function _parse(s) { try { return (s && s.length) ? JSON.parse(s) : null } catch (e) { return null } }
    function _short(s) { return (s && s.length > 14) ? (s.substring(0, 6) + "…" + s.substring(s.length - 4)) : (s || "—") }
    readonly property var _info: _parse(infoJson)
    readonly property var _time: _parse(timeInfoJson)
    function _field(k) { if (!_info) return undefined; if (_info.cryptarchia_info && _info.cryptarchia_info[k] !== undefined) return _info.cryptarchia_info[k]; return _info[k] }
    readonly property string mode: (_info && _info.mode) ? String(_info.mode) : ""
    readonly property string slot: (_time && _time.current_slot !== undefined) ? String(_time.current_slot)
                                   : (_field("slot") !== undefined ? String(_field("slot")) : "—")
    readonly property string heightStr: _field("height") !== undefined ? String(_field("height")) : "—"
    readonly property string lib: _field("lib") ? _short(String(_field("lib"))) : "—"
    readonly property string tip: _field("tip") ? _short(String(_field("tip"))) : "—"
    readonly property string peerIdShort: (peerId && peerId.length) ? _short(peerId) : "—"

    // ── NOT wired (no API yet) — honest placeholders, overridable for design mocks ──
    property string blendState: "none"                       // #58 none|edge|core (NOT in 0.3 API)
    property string epoch: "—"
    property string proposed: "—"                            // #61
    property string validation: ""                           // active|inactive|""
    property int epochsToActivate: 0
    property string peers: "—"                               // #62 (curl)
    property string connections: ""
    property string empowering: "—"                          // #64 (#85)
    property string empoweringAmount: ""
    property string cpu: "—"                                 // #65 (#89)
    property string cpuCap: ""
    property string ram: "—"                                 // #66 (#89)
    property string ramCap: ""
    property string stakeStr: "—"                            // #59
    property string foundingAddr: ""
    property string earnedStr: "—"                           // #60
    property string feePct: ""
    property string uptime: ""
    property string replayProgress: ""
    property string bootCountdown: ""
    property bool bootOverran: false

    // sync-rate + ETA engine (ported from NodeStatusCard, #57) → real bootstrapping countdown
    onInfoJsonChanged: sync.sampleRate(sync.tipSlot)
    QtObject {
        id: sync
        readonly property var tipSlot: root._field("slot") !== undefined ? Number(root._field("slot")) : undefined
        readonly property var currentSlot: (root._time && root._time.current_slot !== undefined) ? Number(root._time.current_slot) : undefined
        readonly property var slotDurationMs: (root._time && root._time.slot_duration_ms !== undefined) ? Number(root._time.slot_duration_ms) : undefined
        readonly property var remaining: (tipSlot === undefined || currentSlot === undefined) ? undefined : Math.max(0, currentSlot - tipSlot)
        readonly property int syncedSlack: 3
        readonly property bool synced: root.mode === "Online" && remaining !== undefined && remaining <= syncedSlack
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
        onTriggered: if (root._bootSecs < root._bootTotal + 3) root._bootSecs += 1
        onRunningChanged: if (!running) root._bootSecs = 0
    }

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    // ── Status hero → {label, sub, color} ──
    // label = base text (no ellipsis); d = animate a reserved-width "…" (transitional states)
    readonly property var _st:
        (!nodeConnected)
            ? ({ label: qsTr("Not connected"), sub: "", c: Theme.palette.textSecondary, copy: false, d: false })
      : status === BlockchainBackend.Error
            ? ({ label: qsTr("Error"), sub: (lastErrorMessage.length ? lastErrorMessage : qsTr("Node error.")), c: Theme.palette.error, copy: lastErrorMessage.length > 0, d: false })
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
    readonly property string _proposedSub: validation === "active" ? qsTr("Validation active")
                                : validation === "inactive" ? (epochsToActivate > 0 ? qsTr("Validation inactive, %1 more epoch to activate").arg(epochsToActivate) : qsTr("Validation inactive"))
                                : ""

    // Node lifecycle — HONEST: a stage only lights when we can truly detect it.
    // Today only Started + Online have real signals; Empowered/Aged/Proposing/
    // Earning stay dim (not-yet-reached) until their backend fields land
    // (#64/#85, #59-#61). Values: 0 = todo (dim), 1 = current (yellow, in
    // progress), 2 = done (green).
    readonly property var _lifeSteps: [qsTr("Started"), qsTr("Online"), qsTr("Empowered"), qsTr("Aged"), qsTr("Proposing"), qsTr("Earning")]
    readonly property var _lifeStates: {
        var s = [0, 0, 0, 0, 0, 0]
        if (!nodeConnected) return s
        if (status === BlockchainBackend.Starting) { s[0] = 1; return s }   // starting up → Started in progress
        if (status === BlockchainBackend.Running || nodeRecovering) {
            s[0] = 2                                                        // Started done
            if (status === BlockchainBackend.Running && sync.synced) {
                s[1] = 2                                                    // Online done
                if (empowering === "Active") s[2] = 2                       // Empowered (only if a real signal)
                if (validation === "active") s[4] = 2                       // Proposing (only if reported active)
                if (earnedStr !== "—" && earnedStr !== "" && earnedStr !== "0") s[5] = 2  // Earning
            } else {
                s[1] = 1                                                    // bootstrapping/replaying → Online in progress
            }
        }
        return s
    }

    component Lifecycle: Item {
        property var steps: []
        property var stepStates: []                // NB: 'states' is a built-in Item property — don't shadow it
        implicitHeight: 46
        readonly property int n: steps.length
        readonly property real padX: 10
        readonly property real cy: 12
        function xOf(i) { return n <= 1 ? padX : padX + i * ((width - 2 * padX) / (n - 1)) }
        onStepStatesChanged: cv.requestPaint()
        onWidthChanged: cv.requestPaint()
        Component.onCompleted: cv.requestPaint()
        Canvas {
            id: cv; anchors.fill: parent
            onAvailableChanged: if (available) requestPaint()
            onPaint: {
                var ctx = getContext("2d"); ctx.reset()
                var green = Theme.palette.success, yellow = Theme.palette.warning, track = Theme.palette.borderTertiary
                for (var s = 0; s < n - 1; s++) {
                    var right = stepStates[s + 1], left = stepStates[s], col = track, w = 2
                    if (right === 2)      { col = green;  w = 3 }
                    else if (right === 1) { col = yellow; w = 3 }
                    else if (left === 1)  { col = yellow; w = 3 }
                    ctx.strokeStyle = col; ctx.lineWidth = w; ctx.lineCap = "round"
                    ctx.beginPath(); ctx.moveTo(xOf(s), cy); ctx.lineTo(xOf(s + 1), cy); ctx.stroke()
                }
                for (var i = 0; i < n; i++) {
                    var x = xOf(i), st = stepStates[i]; ctx.beginPath()
                    if (st === 2) { ctx.fillStyle = green; ctx.arc(x, cy, 7, 0, Math.PI * 2); ctx.fill() }
                    else if (st === 1) {
                        ctx.fillStyle = Theme.palette.surfaceRaised; ctx.arc(x, cy, 7.5, 0, Math.PI * 2); ctx.fill()
                        ctx.beginPath(); ctx.strokeStyle = yellow; ctx.lineWidth = 3; ctx.arc(x, cy, 7.5, 0, Math.PI * 2); ctx.stroke()
                    } else { ctx.fillStyle = track; ctx.arc(x, cy, 4, 0, Math.PI * 2); ctx.fill() }
                }
            }
        }
        Repeater {
            model: steps
            LogosText {
                required property int index
                required property string modelData
                text: modelData; font.pixelSize: 12
                color: stepStates[index] === 2 ? Theme.palette.success
                      : stepStates[index] === 1 ? Theme.palette.warning
                      : Theme.palette.textTertiary
                x: xOf(index) - width / 2; y: cy + 12
            }
        }
    }

    component Info: Rectangle {
        width: 15; height: 15; radius: 8; color: "transparent"
        border.width: 1; border.color: Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.35)
        LogosText { anchors.centerIn: parent; text: "i"; font.pixelSize: 9; color: Theme.palette.textMuted }
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
        property string label: ""
        property string value: "—"
        property string sub: ""
        property color accent: Theme.palette.text
        property color tint: Theme.palette.surfaceRaised
        property bool copyable: false
        property bool hero: false
        property bool dots: false                 // animate a reserved-width "…" after the value
        property bool flash: !hero                // flash green on value change (live grid tiles)
        readonly property int _vsize: hero ? 32 : 24
        backgroundColor: hero ? Qt.rgba(tint.r, tint.g, tint.b, 0.12) : Theme.palette.surfaceRaised
        borderColor: "transparent"; radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        implicitHeight: hero ? 124 : 108
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout { Layout.fillWidth: true
                LogosText { text: label; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                Item { Layout.fillWidth: true }
                Info {} }
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                LogosText {
                    id: fv
                    Layout.fillWidth: !dots; text: value
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
                Item { Layout.fillWidth: dots }
            }
            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 16; spacing: Theme.spacing.small
                LogosText { visible: sub.length > 0; text: sub; color: Theme.palette.textTertiary
                            font.pixelSize: Theme.typography.secondaryText; elide: Text.ElideRight }
                CopyGlyph { visible: copyable && sub.length > 0; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true } }
        }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth
        ColumnLayout {
            width: root.width; spacing: Theme.spacing.large
            ColumnLayout {
                Layout.fillWidth: true; Layout.margins: Theme.spacing.xlarge; spacing: Theme.spacing.large
                // ---- lifecycle strip (top summary; only truly-detectable stages light up) ----
                LogosFrame {
                    Layout.fillWidth: true
                    backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                    radius: Theme.spacing.radiusLarge; padding: Theme.spacing.xlarge
                    contentItem: Lifecycle {
                        steps: root._lifeSteps
                        stepStates: root._lifeStates
                    }
                }
                GridLayout {
                    Layout.fillWidth: true; columns: Math.max(1, Math.min(2, Math.floor(width / (root._heroMin + Theme.spacing.large)))); columnSpacing: Theme.spacing.large; rowSpacing: Theme.spacing.large
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; hero: true; label: qsTr("Status"); value: root._st.label; sub: root._st.sub; accent: root._st.c; tint: root._st.c; copyable: root._st.copy; dots: root._st.d }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; hero: true; label: qsTr("Blend"); value: root._blend.label; sub: root.epoch !== "—" ? qsTr("Epoch ") + root.epoch : ""; accent: root._blend.c; tint: root._blend.c; copyable: root.epoch !== "—" }
                }
                GridLayout {
                    Layout.fillWidth: true; columns: Math.max(1, Math.min(4, Math.floor(width / (root._minCard + Theme.spacing.large)))); columnSpacing: Theme.spacing.large; rowSpacing: Theme.spacing.large
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Stake"); value: root.stakeStr; sub: root.foundingAddr; copyable: root.foundingAddr.length > 0 }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Earned"); value: root.earnedStr; sub: root.feePct.length ? qsTr("Fees this epoch: ") + root.feePct : "" }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Proposed in epoch"); value: root.proposed; sub: root._proposedSub }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Peers"); value: root.peers; sub: root.connections }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Peer ID"); value: root.peerIdShort; sub: root.foundingAddr; copyable: root.peerIdShort !== "—" }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Empowering"); value: root.empowering; sub: root.empoweringAmount }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("CPU"); value: root.cpu; sub: root.cpuCap }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("RAM"); value: root.ram; sub: root.ramCap }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Slot"); value: root.slot }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("Height"); value: root.heightStr }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("LiB"); value: root.lib }
                    Block { Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._minCard; label: qsTr("TiP"); value: root.tip }
                }
            }
            // Blocks table moved to its own top-level "Blocks" tab (BlockchainView).
        }
    }
}
