import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

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

    // number formatting helpers
    function fmtK(n) { return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") }
    function fmtHMS(s) { var t = Math.floor(s); var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), ss = t % 60; function p(x) { return x < 10 ? "0" + x : x } return h + ":" + p(m) + ":" + p(ss) }

    // ── the single source of mock state (NUMERIC backing; strings are computed) ──
    QtObject {
        id: st
        property int status: -1            // -1 not connected · 0 NotStarted · 1 Starting · 2 Running · 4 Stopped · 5 Error
        property bool recovering: false
        property string err: ""
        property string mode: ""           // "Online" once the node reports
        property real tip: 0               // node chain tip (slot)
        property real head: 0              // network head (current_slot); head-tip>3 ⇒ bootstrapping
        property string peerId: ""
        property string blend: "none"
        property string validation: ""
        property int epochsToActivate: 0
        property string stake: "—"
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
        readonly property string proposed: proposedN >= 0 ? (proposedN + " Blocks") : "—"
        readonly property string peers: peersN >= 0 ? String(peersN) : "—"
        readonly property string connections: connN >= 0 ? (connN + " connections") : ""
        readonly property string cpu: cpuN >= 0 ? (Math.round(cpuN) + "%") : "—"
        readonly property string cpuCap: cpuN >= 0 ? (cpuCapN >= 0 ? ("Cap: " + cpuCapN + "%") : qsTr("Cap not set")) : ""
        readonly property string ram: ramN >= 0 ? (ramN.toFixed(1) + "GB") : "—"
        readonly property string ramCap: ramN >= 0 ? (ramCapSet ? qsTr("Cap set") : qsTr("Cap not set")) : ""
        readonly property string earned: earnedN >= 0 ? (win.fmtK(earnedN) + " LGO") : "—"
        readonly property string fee: feeN >= 0 ? (feeN + "%") : ""
        readonly property string uptime: upSecs >= 0 ? win.fmtHMS(upSecs) : ""

        readonly property string infoJson: mode.length
            ? JSON.stringify({ mode: mode, slot: Math.round(tip), height: Math.round(tip),
                               lib: "0x71bd39c4f0a17e2b8c4d5e6f9a0b1c2d3e4f5a6b9e4a", tip: "0x8a3f10d2e5c7b9a0f1e2d3c4b5a6978877665544c012" })
            : ""
        readonly property string timeInfoJson: mode.length
            ? JSON.stringify({ current_slot: Math.round(head), slot_duration_ms: 2000 }) : ""
        readonly property bool running: status === 2
        readonly property bool synced: running && mode === "Online" && (head - tip) <= 3
    }

    // ── scenario presets (numeric) ────────────────────────────────────────────
    function _reset(p) {
        st.status = ("status" in p) ? p.status : -1
        st.recovering = p.recovering || false
        st.err = p.err || ""
        st.mode = p.mode || ""
        st.tip = p.tip || 0
        st.head = p.head || 0
        st.peerId = p.peerId || ""
        st.blend = p.blend || "none"
        st.validation = p.validation || ""
        st.epochsToActivate = p.epochsToActivate || 0
        st.stake = p.stake || "—"; st.addr = p.addr || ""
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
    }
    readonly property var _peer: "12D3KooWQ8s...abkEwLz"
    readonly property var scenarios: [
        { key: "Fresh (not started)",     val: { status: 0 } },
        { key: "Starting",                val: { status: 1 } },
        { key: "Bootstrapping",           val: { status: 2, mode: "Online", tip: 148000, head: 148600, peerId: win._peer,
                                                  peers: 22, conn: 27, cpu: 14, cpuCap: 30, ram: 1.1, ramCapSet: false } },
        { key: "Online",                  val: { status: 2, mode: "Online", tip: 148905, head: 148905, upSecs: 12 * 3600 + 4 * 60 + 37, peerId: win._peer, epoch: 172, epochElapsed: 200,
                                                  peers: 38, conn: 43, cpu: 9, cpuCap: 30, ram: 1.2, ramCapSet: false } },
        { key: "Funded — aging",          val: { status: 2, mode: "Online", tip: 150000, head: 150000, upSecs: 1 * 3600 + 12 * 60, peerId: win._peer,
                                                  funded: true,                       // mining finished (stopped at 100%); wallet funded, notes now aging
                                                  proposed: 0, validation: "inactive", epochsToActivate: 2, epoch: 173, epochElapsed: 500,
                                                  peers: 40, conn: 46, cpu: 10, cpuCap: 30, ram: 1.3, ramCapSet: false, stake: "5T LGO", addr: "0x71bd…9e4a" } },
        { key: "Validating",              val: { status: 2, mode: "Online", tip: 151548, head: 151548, upSecs: 345 * 3600 + 43 * 60 + 23, peerId: win._peer, funded: true,
                                                  blend: "core", epoch: 174, epochElapsed: 372, proposed: 234, validation: "active", peers: 83, conn: 87,
                                                  empowering: true, empoweringMined: 2500, empoweringTarget: 5000, cpu: 12, cpuCap: 30, ram: 1.4, ramCapSet: false,
                                                  stake: "5T LGO", addr: "0x71bd…9e4a", earned: 1530, fee: 56 } },
        { key: "Error",                   val: { status: 5, err: "Node error: connection refused (rpc :3000)" } }
    ]

    // ── live tick: advance ONLY what fits the current state ─────────────────────
    // Running: network head advances; tip catches up while bootstrapping, then
    // moves in lockstep once synced (Slot/Height climb → the tiles flash green).
    // Metrics jitter only when present (i.e., only in states where they fit).
    Timer {
        id: live; interval: 1200; repeat: true; running: st.running
        onTriggered: {
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

    readonly property bool _grabMode: Qt.application.arguments.indexOf("--grab") >= 0
    readonly property int _grabScenario: { var i = Qt.application.arguments.indexOf("--scenario"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : 4 }
    readonly property int _grabTab: { var i = Qt.application.arguments.indexOf("--tab"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : 0 }
    Component.onCompleted: { win._reset(win.scenarios[_grabMode ? _grabScenario : 3].val); if (_grabMode) studioTabs.currentIndex = _grabTab }

    // ── layout: dashboard (left) + control panel (right) ──────────────────────
    RowLayout {
        anchors.fill: parent; spacing: 0

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0

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
                LogosButton {
                    // Fund opens the modal; once running it becomes a hard Stop (resets progress) — start again re-opens the modal
                    text: st.empoweringActive ? qsTr("Stop funding") : qsTr("Fund")
                    enabled: st.running; Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        if (st.empoweringActive) { st.empoweringActive = false; st.empoweringMined = -1; st.empoweringTarget = -1 }
                        else empoweringModal.open()
                    }
                }
                LogosButton {
                    text: st.running ? qsTr("Stop Node") : qsTr("Start Node")
                    variant: LogosButton.Variant.Primary; Layout.alignment: Qt.AlignVCenter
                    onClicked: st.running ? win._reset({ status: 4 }) : win.playStart()
                }
            }

            // tab bar chrome (mirrors BlockchainView; only Dashboard is live in the studio)
            LogosTabBar {
                id: studioTabs
                Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large
                currentIndex: 0
                LogosTabButton { text: qsTr("Dashboard") }
                LogosTabButton { text: qsTr("Blocks") }
                LogosTabButton { text: qsTr("Rewards") }
                LogosTabButton { text: qsTr("Explorer") }
                LogosTabButton { text: qsTr("Wallet") }        // groups Accounts · Transfer · Channel Deposit (pages TBD)
                LogosTabButton { text: qsTr("Settings") }
            }

            StackLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: studioTabs.currentIndex     // tab-aligned: 0 Dashboard … 5 Settings
                V.NodeDashboardView {
                status: st.status
                nodeRecovering: st.recovering
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
                peers: st.peers
                connections: st.connections
                empoweringActive: st.empoweringActive
                empoweringMined: st.empoweringMined
                empoweringTarget: st.empoweringTarget
                funded: st.funded
                cpu: st.cpu; cpuCap: st.cpuCap
                ram: st.ram; ramCap: st.ramCap
                stakeStr: st.stake; foundingAddr: st.addr
                earnedStr: st.earned; feePct: st.fee
                uptime: st.uptime
                }
                // placeholders for tabs without a prototype page (index-aligned)
                LogosText { text: qsTr("Blocks — not in this prototype"); color: Theme.palette.textTertiary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                LogosText { text: qsTr("Rewards — not in this prototype"); color: Theme.palette.textTertiary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                LogosText { text: qsTr("Explorer — not in this prototype"); color: Theme.palette.textTertiary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                LogosText { text: qsTr("Wallet — not in this prototype"); color: Theme.palette.textTertiary; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                V.SettingsView { onCopyText: (t) => {} }
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

                    // live actions
                    LogosText { text: "INTERACTIONS"; color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold; Layout.leftMargin: Theme.spacing.large }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large; spacing: Theme.spacing.small
                        LogosButton { Layout.fillWidth: true; text: "▶ Play Start → Online"; variant: LogosButton.Variant.Primary; onClicked: win.playStart() }
                        LogosButton { Layout.fillWidth: true; text: "Toggle Blend: " + st.blend
                            onClicked: st.blend = st.blend === "none" ? "edge" : st.blend === "edge" ? "core" : "none" }
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

    // Start Empowering modal — set a target, then mining climbs toward it
    V.EmpoweringModal {
        id: empoweringModal
        onStartRequested: (t) => { st.empoweringActive = true; st.empoweringTarget = t; st.empoweringMined = 0 }
    }

    // offscreen proof: grab a frame + quit (only with --grab; interactive runs stay open)
    readonly property int _grabDelay: { var i = Qt.application.arguments.indexOf("--grabdelay"); return (i >= 0 && i + 1 < Qt.application.arguments.length) ? parseInt(Qt.application.arguments[i + 1]) : 1800 }
    Timer {
        interval: win._grabDelay; repeat: false; running: win._grabMode
        onTriggered: win.contentItem.grabToImage(function(r){ r.saveToFile("/extra/tmp/bcui-iter/proto.png"); Qt.callLater(Qt.quit) })
    }
}
