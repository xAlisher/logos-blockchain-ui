import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import Logos.Theme
import Logos.Controls
// BlockchainStatus enum (NotStarted/Starting/Running/Stopping/Stopped/Error)
// declared in BlockchainBackend.rep — registered with QML by the replica
// factory plugin.
import Logos.BlockchainBackend 1.0

import "views"

Rectangle {
    id: root

    readonly property var backend: logos.module("logos_node_1click")
    // `ready` can't be a binding on logos.isViewModuleReady(): that's a
    // Q_INVOKABLE method, not a Q_PROPERTY, so the binding wouldn't refresh
    // when the replica transitions to Valid. Drive it from the bridge's
    // viewModuleReadyChanged signal instead.
    property bool ready: false

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "logos_node_1click") {
                root.ready = isReady && root.backend !== null
                if (root.ready) {
                    root.refreshPeerId()
                    root._applyInitialRoute()
                }
            }
        }
    }

    Component.onCompleted: {
        // Cover the case where the replica is already Valid by the time
        // we attach the Connections handler.
        root.ready = root.backend !== null && logos.isViewModuleReady("logos_node_1click")
        if (root.ready) {
            root.refreshPeerId()
            root._applyInitialRoute()
        }
    }

    // Graceful shutdown: if the window is closed while the node is running,
    // veto the close, stop the node, then close once it has stopped.
    property bool quitting: false

    function _nodeBusy() {
        return root.backend
            && (root.backend.status === BlockchainBackend.Running
                || root.backend.status === BlockchainBackend.Starting
                || root.backend.status === BlockchainBackend.Stopping)
    }

    Connections {
        target: root.Window.window
        enabled: root.Window.window !== null
        ignoreUnknownSignals: true
        function onClosing(close) {
            if (!root.quitting && root._nodeBusy()) {
                root.quitting = true
                close.accepted = false
                root.backend.stopBlockchain()
            }
        }
    }

    // Once the stop initiated above completes, finish closing the window.
    Connections {
        target: root.backend
        enabled: root.quitting && root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.quitting && !root._nodeBusy() && root.Window.window)
                root.Window.window.close()
        }
    }

    // Models live on the C++ backend and are auto-remoted by ui-host as
    // "<module>/<propertyName>". QML acquires them via logos.model(...).
    readonly property var accountsModel: logos.model("logos_node_1click", "accounts")
    readonly property var blockModel: logos.model("logos_node_1click", "blocks")

    // Clipboard must be handled here in the UI-host (GUI) process. The backend
    // .rep source runs in a separate, non-GUI ViewModuleHost subprocess where
    // QGuiApplication::clipboard() segfaults (process exits with code 11), so
    // we copy from QML via a hidden TextEdit instead of calling the backend.
    function copyText(text) {
        clipboardHelper.text = text || ""
        clipboardHelper.selectAll()
        clipboardHelper.copy()
        clipboardHelper.deselect()
        clipboardHelper.text = ""
    }

    TextEdit {
        id: clipboardHelper
        visible: false
    }

    // Confirm before wiping chain state (recovery for logos-blockchain#3171).
    // Destructive-but-recoverable: the chain re-downloads from genesis; wallet
    // keys and config are preserved by the backend. Uses the themed LogosDialog
    // so it matches the rest of the app.
    LogosDialog {
        id: resetConfirmDialog
        anchors.centerIn: parent
        width: 420
        title: qsTr("Reset chain state?")

        LogosText {
            width: resetConfirmDialog.availableWidth
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            text: qsTr("This deletes the local chain database and consensus state, "
                       + "then the node re-downloads the chain from scratch on the "
                       + "next Start. Your wallet keys and config are kept. Use this "
                       + "if the node is stuck on \"Starting…\" or \"call failed\".")
        }

        function _doReset() {
            resetConfirmDialog.close()
            if (!root.backend) return
            logos.watch(
                root.backend.resetChainState(),
                function(result) {
                    if (result.success) root.backend.clearBlocks()
                    else console.log("[BlockchainView] resetChainState failed:", result.error)
                },
                function(error) { console.log("[BlockchainView] resetChainState error:", error) }
            )
        }

        rightActions: [
            LogosButton {
                text: qsTr("Cancel")
                implicitWidth: 110
                implicitHeight: 40
                onClicked: resetConfirmDialog.close()
            },
            LogosButton {
                text: qsTr("Reset")
                implicitWidth: 110
                implicitHeight: 40
                onClicked: resetConfirmDialog._doReset()
            }
        ]
    }

    // Honest-error recovery modal (one-click UX #16). Blocks the UI when the
    // node hits an error, shows the honest cause, explains that a wipe keeps the
    // config, and offers one "wipe + start over" that cleans the store and
    // bootstraps back to green.
    function _honestError() {
        var e = ""
        if (root.cryptarchiaInfoError && root.cryptarchiaInfoError.length)
            e = root.cryptarchiaInfoError
        else if (root.backend && root.backend.lastErrorMessage && root.backend.lastErrorMessage.length)
            e = root.backend.lastErrorMessage
        if (e.indexOf("Error: ") === 0) e = e.substring(7)
        // Never blank: the log may be gone (a wipe removed logs/) or the reason
        // opaque — still tell the user something actionable.
        if (!e.length)
            return qsTr("The node stopped during startup. If this keeps happening, wipe the "
                        + "database and start over, or check your config and peers.")
        if (e.toLowerCase().indexOf("call failed") >= 0)
            return qsTr("The node stopped responding — its process ended, usually because the "
                        + "local chain database is in a bad state.")
        return e
    }

    // Start only when actually idle — avoids the "already running" error from a
    // double start (auto-start racing a manual/one-click start).
    function _startNode() {
        if (root.backend && root.backend.status !== BlockchainBackend.Running
            && root.backend.status !== BlockchainBackend.Starting)
            root.backend.startBlockchain()
    }

    // Recovery sequence (one-click UX #16): stop the node and CONFIRM it is
    // stopped (wiping while the process holds the DB leaves a torn store, ui#7),
    // wipe the chain store + leftovers, then start over with the same config but
    // a clean state. `_wipeStage` drives the live progress under the button.
    // The `status` property is optimistic — stopBlockchain()/startBlockchain() set
    // it to Stopped/Running around the module RPC, so it reads "Stopped" while the
    // node subprocess is still finishing a chain recovery. Gating the wipe on it
    // let us wipe/restart a still-running node → "already running" + an un-wiped DB.
    // The node's HTTP API is the ground truth: it answers while up, refuses once
    // genuinely down. So every step gates on a real liveness probe against :8080.
    property string _wipeStage: ""   // "", "stopping", "wiping", "starting"
    property string _wipeError: ""   // honest failure text; re-enables the buttons
    property int    _wipeTries: 0
    property int    _wipeAttempts: 0
    function _wipeAndStart() {
        if (!root.backend) return
        root._wipeError = ""
        root._wipeTries = 0
        root._wipeStage = "stopping"
        root.backend.stopBlockchain()
        wipeDownProbe.restart()
    }
    // Probe until the node is genuinely DOWN (connection refused), then — after a
    // grace so RocksDB fully closes its handles — wipe. Generous cap: a chain
    // recovery can take ~40s to unwind before the node actually stops.
    Timer {
        id: wipeDownProbe
        interval: 600; repeat: true
        onTriggered: {
            if (!root.backend) { wipeDownProbe.stop(); wipeGraceTimer.restart(); return }
            root._wipeTries += 1
            var tries = root._wipeTries
            // Liveness via the backend (QRO → module get_cryptarchia_info), NOT a
            // direct QML XHR: v0.2.3's ui_qml sandbox blocks network from QML. A
            // failed call (or transport error) == the node's API is down → wipe.
            logos.watch(
                root.backend.getCryptarchiaInfo(),
                function(result) {
                    if (!result.success) {              // node down
                        wipeDownProbe.stop()
                        wipeGraceTimer.restart()
                    } else if (tries > 100) {           // ~60s failsafe
                        wipeDownProbe.stop()
                        root._wipeStage = ""
                        root._wipeError = qsTr("Couldn't stop the node — please try again.")
                    }
                },
                function(error) {                       // transport error → treat as down
                    wipeDownProbe.stop()
                    wipeGraceTimer.restart()
                }
            )
        }
    }
    Timer { id: wipeGraceTimer; interval: 1200; onTriggered: root._doWipe() }

    // Wipe the store; confirm resetChainState actually succeeded, retry a few times,
    // and NEVER start on an unverified wipe (that was the un-wiped-DB bug).
    function _doWipe() {
        if (!root.backend) { root._wipeStage = ""; return }
        root._wipeAttempts = 0
        root._wipeStage = "wiping"
        root._resetChainState()
    }
    function _resetChainState() {
        logos.watch(
            root.backend.resetChainState(),
            function(result) {
                if (result.success) root._afterWipe()
                else if (root._wipeAttempts < 3) { root._wipeAttempts += 1; wipeRetryTimer.restart() }
                else { root._wipeStage = ""; root._wipeError = qsTr("Couldn't wipe the database — please try again.") }
            },
            function(error) {
                if (root._wipeAttempts < 3) { root._wipeAttempts += 1; wipeRetryTimer.restart() }
                else { root._wipeStage = ""; root._wipeError = qsTr("Couldn't wipe the database — please try again.") }
            }
        )
    }
    Timer { id: wipeRetryTimer; interval: 600; onTriggered: root._resetChainState() }

    function _afterWipe() {
        if (!root.backend) { root._wipeStage = ""; return }
        root.backend.clearBlocks()
        root._wipeStage = "starting"
        root._wipeTries = 0
        root._startNode()                 // node is confirmed down → no "already running"
        wipeUpProbe.restart()
    }
    // Probe until the node is back UP, then close the modal.
    Timer {
        id: wipeUpProbe
        interval: 600; repeat: true
        onTriggered: {
            if (!root.backend) return
            root._wipeTries += 1
            var tries = root._wipeTries
            // Backend liveness (QRO), not QML XHR — see wipeDownProbe.
            logos.watch(
                root.backend.getCryptarchiaInfo(),
                function(result) {
                    if (result.success || tries > 50) {  // node up, or ~30s failsafe
                        wipeUpProbe.stop()
                        root._wipeStage = ""
                        errorRecoveryDialog.close()
                    }
                },
                function(error) {                        // still down; only bail on failsafe
                    if (tries > 50) {
                        wipeUpProbe.stop()
                        root._wipeStage = ""
                        errorRecoveryDialog.close()
                    }
                }
            )
        }
    }

    function _wipeStageBase() {
        switch (root._wipeStage) {
        case "stopping": return qsTr("Stopping the node")
        case "wiping":   return qsTr("Wiping the database")
        case "starting": return qsTr("Starting with a clean state")
        default: return ""
        }
    }
    // Animated ellipsis so the disabled button clearly reads as working.
    property int _dotPhase: 0
    Timer {
        id: wipeDotTimer
        interval: 400; repeat: true
        running: root._wipeStage.length > 0
        onTriggered: root._dotPhase = (root._dotPhase + 1) % 4
    }
    function _wipeStageText() {
        var base = root._wipeStageBase()
        if (!base.length) return ""
        return base + ["", ".", "..", "..."][root._dotPhase]
    }

    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (!root.backend) return
            // A fresh Starting resets the liveness-confirm budget (issue #19).
            if (root.backend.status === BlockchainBackend.Starting) { root._startTries = 0; return }
            if (root.backend.status !== BlockchainBackend.Error) return
            // "already running" is benign (the node IS running) — don't nag.
            if ((root.backend.lastErrorMessage || "").toLowerCase().indexOf("already running") >= 0)
                return
            root._wipeError = ""
            errorRecoveryDialog.open()
        }
    }

    // ── Start liveness-confirm (issue #19) ──
    // The node's `start` RPC can return before its API is actually up (a slow
    // chain recovery outlives the RPC deadline), so a no-reply is NOT an error.
    // While Starting, poll :8080 until it answers → confirmRunning(); if the log
    // shows a real fatal error, or it never comes up (~60s) → confirmStartFailed().
    property int _startTries: 0
    Timer {
        id: startConfirmProbe
        interval: 1500; repeat: true
        running: root.ready && root.backend
                 && root.backend.status === BlockchainBackend.Starting
        onTriggered: {
            if (!root.backend) return
            root._startTries += 1
            var tries = root._startTries
            // Backend liveness (QRO), not QML XHR — see wipeDownProbe. The node's
            // API answering (get_cryptarchia_info succeeds) == it's really up.
            logos.watch(
                root.backend.getCryptarchiaInfo(),
                function(result) {
                    if (result.success) {
                        if (root.backend) root.backend.confirmRunning()
                    } else if (tries > 40) {   // ~60s and still no API → confirmed failure
                        if (root.backend) root.backend.confirmStartFailed()
                    }
                },
                function(error) {              // no reply yet; only fail on the ~60s cap
                    if (tries > 40) {
                        if (root.backend) root.backend.confirmStartFailed()
                    }
                }
            )
        }
    }

    LogosDialog {
        id: errorRecoveryDialog
        anchors.centerIn: parent
        width: 480
        title: qsTr("The node hit an error")
        closePolicy: Popup.CloseOnEscape
        // Darker scrim behind the modal (~3× the default dim).
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }

        // Content via contentItem (a default child lands in contentData and is not
        // rendered — that was the blank-body bug).
        contentItem: Column {
            width: errorRecoveryDialog.availableWidth
            spacing: Theme.spacing.medium
            LogosText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.palette.error
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
                text: root._honestError()
            }
            LogosText {
                width: parent.width
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                text: qsTr("“Wipe the database and start over” deletes the local chain "
                           + "database and restarts the node with the same config. Your wallet "
                           + "keys and config are kept; the node re-downloads the chain and "
                           + "bootstraps back to green.")
            }
            LogosText {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: root._wipeError.length > 0
                color: Theme.palette.error
                font.pixelSize: Theme.typography.secondaryText
                font.weight: Theme.typography.weightMedium
                text: root._wipeError
            }
        }

        rightActions: [
            LogosButton {
                text: qsTr("Dismiss")
                implicitWidth: 100; implicitHeight: 40
                enabled: root._wipeStage.length === 0
                onClicked: errorRecoveryDialog.close()
            },
            LogosButton {
                id: wipeActionBtn
                text: root._wipeStage.length > 0 ? root._wipeStageText()
                                                 : qsTr("Wipe the database and start over")
                implicitWidth: 260; implicitHeight: 40
                enabled: root._wipeStage.length === 0
                onClicked: root._wipeAndStart()
                // Gentle pulse while a stage runs, so it reads as working.
                SequentialAnimation on opacity {
                    running: root._wipeStage.length > 0
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.55; duration: 550; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0;  duration: 550; easing.type: Easing.InOutQuad }
                    onRunningChanged: if (!running) wipeActionBtn.opacity = 1
                }
            }
        ]
    }

    // ── Fund the node (auto-stake) via the cryptarchia web faucet (issue #22) ──
    // POST the node's public key to the faucet; it credits testnet funds that
    // auto-stake. The backend runs the POST via system curl — QML network is
    // blocked by v0.2.3's ui_qml sandbox (and Qt/QML HTTPS fails on this AppImage).
    property string _fundStage: ""    // "", "requesting", "success", "error"
    property string _fundResult: ""   // tx / response text, or the error text
    property int _fundDots: 0
    Timer {
        interval: 400; repeat: true; running: root._fundStage === "requesting"
        onTriggered: root._fundDots = (root._fundDots + 1) % 4
    }
    function _fundDotStr() { return ["", ".", "..", "..."][root._fundDots] }
    function _requestFunds() {
        if (!root.backend) return
        var pk = (root.backend.primaryAddress || "").trim()
        if (!pk.length) {
            root._fundStage = "error"
            root._fundResult = qsTr("No node key available yet — wait until the node is online.")
            return
        }
        // Qt/QML HTTPS fails on this AppImage — the backend runs it via system curl.
        root._fundStage = "requesting"; root._fundResult = ""
        root.backend.requestFaucetFunds(pk)
    }
    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onFaucetResult(ok, message) {
            if (ok) {
                var tx = message
                try { var j = JSON.parse(message); if (j && j.hash) tx = j.hash } catch (e) {}
                root._fundStage = "success"; root._fundResult = tx
            } else {
                root._fundStage = "error"; root._fundResult = message
            }
        }
    }

    LogosDialog {
        id: fundDialog
        anchors.centerIn: parent
        width: 480
        title: qsTr("Fund the node")
        closePolicy: Popup.CloseOnEscape
        // Darker scrim behind the modal (~3× the default dim).
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
        onOpened: { root._fundStage = ""; root._fundResult = "" }

        // Content MUST be set via contentItem — a default child lands in contentData
        // and LogosDialog does not render it (that was the blank-body bug).
        contentItem: Column {
            width: fundDialog.availableWidth
            spacing: Theme.spacing.medium

            LogosText {
                visible: root._fundStage === "" || root._fundStage === "requesting"
                width: parent.width; wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                text: qsTr("These are testnet funds — no real value. They auto-stake: your balance "
                           + "counts as stake, so your node starts winning leader slots proportional "
                           + "to it and proposes blocks on its own. It can take a little while to arrive.")
            }
            Column {
                visible: root._fundStage === "" || root._fundStage === "requesting"
                width: parent.width; spacing: 4
                LogosText {
                    text: qsTr("Destination — your node's public key")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
                Row {
                    width: parent.width; spacing: Theme.spacing.small
                    LogosText {
                        width: parent.width - 26
                        text: root.backend ? (root.backend.primaryAddress || "—") : "—"
                        font.pixelSize: Theme.typography.primaryText
                        font.family: Theme.typography.publicSans
                        color: Theme.palette.text
                        elide: Text.ElideMiddle
                    }
                    LogosText {
                        width: 18; text: "⧉"; font.pixelSize: 14
                        color: keyCopyM.containsMouse ? Theme.palette.text : Theme.palette.textSecondary
                        MouseArea {
                            id: keyCopyM; anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.backend) root.backend.copyToClipboard(root.backend.primaryAddress)
                        }
                    }
                }
            }
            LogosText {
                visible: root._fundStage === "success"
                width: parent.width; wrapMode: Text.WordWrap
                color: Theme.palette.success
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
                text: qsTr("Funds requested successfully — feel free to close this window.")
            }
            Row {
                visible: root._fundStage === "success" && root._fundResult.length > 0
                width: parent.width; spacing: Theme.spacing.small
                LogosText {
                    width: parent.width - 26
                    text: root._fundResult
                    font.pixelSize: Theme.typography.secondaryText
                    font.family: Theme.typography.publicSans
                    color: Theme.palette.textSecondary
                    elide: Text.ElideMiddle
                }
                LogosText {
                    width: 18; text: "⧉"; font.pixelSize: 14
                    color: txCopyM.containsMouse ? Theme.palette.text : Theme.palette.textSecondary
                    MouseArea {
                        id: txCopyM; anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.backend) root.backend.copyToClipboard(root._fundResult)
                    }
                }
            }
            LogosText {
                visible: root._fundStage === "error"
                width: parent.width; wrapMode: Text.WordWrap
                color: Theme.palette.error
                font.pixelSize: Theme.typography.secondaryText
                font.weight: Theme.typography.weightMedium
                text: root._fundResult
            }
        }

        rightActions: [
            LogosButton {
                text: root._fundStage === "success" ? qsTr("Close") : qsTr("Cancel")
                implicitWidth: 100; implicitHeight: 40
                enabled: root._fundStage !== "requesting"
                onClicked: fundDialog.close()
            },
            // Orange primary CTA (LogosButton has no colour variant → custom pill).
            Rectangle {
                id: reqFundsBtn
                visible: root._fundStage !== "success"
                implicitWidth: 180; implicitHeight: 40
                radius: Theme.spacing.radiusXlarge   // match Cancel (LogosButton)
                readonly property bool on: root._fundStage !== "requesting"
                readonly property color base: Theme.palette.primaryHover
                color: !on ? Qt.rgba(base.r, base.g, base.b, 0.5)
                       : (reqFundsM.pressed ? Qt.darker(base, 1.16)
                          : (reqFundsM.containsMouse ? Qt.darker(base, 1.08) : base))
                LogosText {
                    anchors.centerIn: parent
                    text: root._fundStage === "requesting" ? (qsTr("Requesting") + root._fundDotStr())
                          : (root._fundStage === "error" ? qsTr("Try again") : qsTr("Request funds"))
                    color: Theme.palette.text
                    font.pixelSize: Theme.typography.primaryText
                    font.weight: Theme.typography.weightMedium
                }
                MouseArea {
                    id: reqFundsM
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: reqFundsBtn.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (reqFundsBtn.on) root._requestFunds()
                }
            }
        ]
    }

    // Node balance (auto-staked) for the dashboard tile — polled while Online.
    property string nodeBalance: "—"
    Timer {
        id: balanceTimer
        interval: 5000; repeat: true; triggeredOnStart: true
        running: root.ready && root.backend
                 && root.backend.status === BlockchainBackend.Running
                 && (root.backend.primaryAddress || "").length > 0
        onTriggered: {
            if (!root.backend) return
            logos.watch(
                root.backend.getBalance(root.backend.primaryAddress),
                function(result) {
                    if (result.success && result.value !== undefined && result.value !== null)
                        root.nodeBalance = String(result.value)
                },
                function(error) { /* keep last known */ }
            )
        }
    }

    // Peer / connection counts via the backend (curl) — the app's QML XHR is
    // unreliable here, so the dashboard can't poll :8080 directly (issue #21).
    property int nodePeers: -1
    property int nodeConnections: -1
    Timer {
        interval: 4000; repeat: true; triggeredOnStart: true
        running: root.ready && root.backend
                 && root.backend.status === BlockchainBackend.Running
        onTriggered: {
            if (!root.backend) return
            logos.watch(
                root.backend.getNetworkInfo(),
                function(result) {
                    if (result && result.peers !== undefined) {
                        root.nodePeers = result.peers
                        root.nodeConnections = result.connections
                    }
                },
                function(error) { /* keep last known */ }
            )
        }
    }

    // Self libp2p peer id, derived from the selected user config (no running
    // node required). Refreshed when ready and whenever the config changes.
    property string peerId: ""

    // Open directly on the node view when a config already exists, instead of
    // re-walking the first-run chooser every launch (logos-blockchain-ui#36).
    // The backend restores userConfig from QSettings at construction, so the
    // path is populated by the time the module is ready. Routing only — the
    // operator still starts the node from the node view; the "Change" button
    // there is the path back to the chooser (page 0). One-shot, so it never
    // overrides a manual return to the chooser.
    function _applyInitialRoute() {
        if (_d.initialRouted || !root.ready || !root.backend)
            return
        _d.initialRouted = true
        if (root.backend.userConfig && root.backend.userConfig.length > 0) {
            // Config exists → straight to the node view and auto-start (#15).
            _d.currentPage = 1
            if (root.backend.status !== BlockchainBackend.Running
                && root.backend.status !== BlockchainBackend.Starting)
                root.backend.startBlockchain()
        } else {
            // First ever open (no config) → the one-click first-run screen (#10).
            _d.currentPage = 2
        }
    }

    function refreshPeerId() {
        if (!root.backend || !root.backend.userConfig) {
            root.peerId = ""
            return
        }
        logos.watch(
            root.backend.getPeerId(),
            function(result) { root.peerId = result.success ? result.value : "" },
            function(error) { root.peerId = "" }
        )
    }

    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onUserConfigChanged() { root.refreshPeerId() }
    }

    // Live Cryptarchia consensus state, polled while the node runs.
    property string cryptarchiaInfoJson: ""
    property string cryptarchiaInfoError: ""

    Timer {
        id: cryptarchiaTimer
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.ready && root.backend
                 && root.backend.status === BlockchainBackend.Running
        onTriggered: {
            if (!root.backend) return
            logos.watch(
                root.backend.getCryptarchiaInfo(),
                function(result) {
                    if (result.success) {
                        root.cryptarchiaInfoJson = result.value
                        root.cryptarchiaInfoError = ""
                    } else {
                        root.cryptarchiaInfoError = _d.errorText(result.error)
                    }
                },
                function(error) { root.cryptarchiaInfoError = _d.errorText(error) }
            )
        }
    }

    // Wallet's claimable ("pending") vouchers. Auto-refreshed on every incoming
    // block, and once when the node starts running.
    property string claimableVouchersJson: ""

    function refreshClaimableVouchers() {
        if (!root.backend || root.backend.status !== BlockchainBackend.Running)
            return
        logos.watch(
            root.backend.getClaimableVouchers(),
            function(result) { if (result.success) root.claimableVouchersJson = result.value },
            function(error) { /* keep last known list on transient errors */ }
        )
    }

    // Blocks this node proposed, parsed from the node's own log (getProposals) — the
    // authoritative "my proposals" (leadership is private on-chain). Refreshed with vouchers.
    property string proposalsJson: ""
    function refreshProposals() {
        if (!root.backend || root.backend.status !== BlockchainBackend.Running)
            return
        logos.watch(
            root.backend.getProposals(),
            function(result) { if (result.success) root.proposalsJson = result.value },
            function(error) { /* keep last known list on transient errors */ }
        )
    }

    // Count of claimable leadership vouchers (blocks led, rewards pending).
    readonly property int voucherCount: {
        try {
            var v = root.claimableVouchersJson && root.claimableVouchersJson.length > 0
                    ? JSON.parse(root.claimableVouchersJson) : null
            if (!v) return 0
            if (Array.isArray(v)) return v.length
            if (v.vouchers && Array.isArray(v.vouchers)) return v.vouchers.length
            return 0
        } catch (e) { return 0 }
    }

    // Incoming blocks arrive as row insertions on the remoted block model.
    Connections {
        target: root.blockModel
        enabled: root.blockModel !== null
        ignoreUnknownSignals: true
        function onRowsInserted() { root.refreshClaimableVouchers(); root.refreshProposals() }
    }

    // Initial load when the node reaches Running (before the next block).
    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.backend.status === BlockchainBackend.Running) {
                root.refreshClaimableVouchers()
                root.refreshProposals()
            }
        }
    }

    QtObject {
        id: _d
        function errorText(message) {
            return qsTr("Error: %1").arg(message)
        }

        function getStatusString(s) {
            switch(s) {
            case BlockchainBackend.NotStarted: return qsTr("Not Started")
            case BlockchainBackend.Starting: return qsTr("Starting...")
            case BlockchainBackend.Running: return qsTr("Running")
            case BlockchainBackend.Stopping: return qsTr("Stopping...")
            case BlockchainBackend.Stopped: return qsTr("Stopped")
            case BlockchainBackend.Error: return _d.errorText(root.backend.lastErrorMessage)
            default: return qsTr("Unknown")
            }
        }
        function getStatusColor(s) {
            switch(s) {
            case BlockchainBackend.Running: return Theme.palette.success
            case BlockchainBackend.Starting:
            case BlockchainBackend.Stopping: return Theme.palette.warning
            default: return Theme.palette.error
            }
        }
        property int currentPage: 0

        // Guards the one-time startup route (see root._applyInitialRoute):
        // it must fire once when the module first becomes ready, and never
        // fight the user's later navigation (e.g. the node view's "Change"
        // button, which deliberately returns to the chooser at page 0).
        property bool initialRouted: false

        // One-click "Run the node" (#10/#15): generate a default testnet config
        // with the known-good bootstrap peers, then start fresh. The backend's
        // startBlockchain() fills bootstrap.ibd.peers from these before starting.
        function runNodeOneClick() {
            if (!root.backend) return
            var peers = [
                "/ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWFrouXfmrR4nsLMtE7wu15DoMJ6VtoUtHinREZCvbWHar",
                "/ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWJRGau8M1rjT7R5e4YYsgdFhsMX35nRDtMwCDjxQkXAHz",
                "/ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWQXJavMDTRscjauFSgVAB1VLB6Rzpy2uY5SU9Tk7927tb",
                "/ip4/65.109.51.37/udp/50001/quic-v1/p2p/12D3KooWSQc7CcGtvWDPF1yCbBthFnQjprfCVHmfmNDUrSmqQsU1"
            ]
            logos.watch(
                root.backend.generateConfig("", peers, 0, 0, "", "", false, 0, "", ""),
                function(result) {
                    if (!result.success) return
                    root.backend.userConfig =
                        (result.value !== undefined && result.value !== "")
                            ? result.value : root.backend.generatedUserConfigPath
                    root.backend.useGeneratedConfig = true
                    _d.currentPage = 1
                    root.backend.startBlockchain()
                },
                function(error) {}
            )
        }
    }

    color: Theme.palette.background

    // Loading state before backend connects
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: 12
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connecting to blockchain backend...")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: !root.ready }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        currentIndex: _d.currentPage
        visible: root.ready

        // Page 1: Config choice
        ScrollView {
            id: configChoiceScrollView
            clip: true
            ConfigChoiceView {
                id: configChoiceView
                width: configChoiceScrollView.availableWidth
                userConfigPath: root.backend ? root.backend.userConfig : ""
                deploymentConfigPath: root.backend ? root.backend.deploymentConfig : ""
                generatedUserConfigPath: root.backend ? root.backend.generatedUserConfigPath : ""
                onUserConfigPathSelected: function(path) {
                    if (root.backend) root.backend.userConfig = path
                }
                onDeploymentConfigPathSelected: function(path) {
                    if (root.backend) root.backend.deploymentConfig = path
                }
                onSetPathToConfigsRequested: function() {
                    if (root.backend) root.backend.useGeneratedConfig = false
                    _d.currentPage = 1
                }
                onGenerateRequested: function(outputPath, initialPeers, netPort, blendPort, httpAddr, externalAddress, noPublicIpCheck, deploymentMode, deploymentConfigPath, statePath) {
                    if (!root.backend) return
                    console.log("[BlockchainView] generateRequested: outputPath=", outputPath,
                                "initialPeers=", JSON.stringify(initialPeers),
                                "netPort=", netPort, "blendPort=", blendPort,
                                "httpAddr=", httpAddr, "externalAddress=", externalAddress,
                                "noPublicIpCheck=", noPublicIpCheck, "deploymentMode=", deploymentMode,
                                "deploymentConfigPath=", deploymentConfigPath, "statePath=", statePath)
                    configChoiceView.generateResultSuccess = false
                    configChoiceView.generateResultMessage = ""
                    logos.watch(
                        root.backend.generateConfig(
                            outputPath, initialPeers, netPort, blendPort,
                            httpAddr, externalAddress, noPublicIpCheck,
                            deploymentMode, deploymentConfigPath, statePath),
                        function(result) {
                            console.log("[BlockchainView] generateConfig success callback: result=", JSON.stringify(result))
                            configChoiceView.generateResultSuccess = result.success
                            configChoiceView.generateResultMessage =
                                result.success
                                    ? qsTr("Config generated successfully.")
                                    : qsTr("Generate failed: %1").arg(result.error)
                            if (result.success) {
                                // The module writes the config and returns the
                                // absolute path it used; use that for start().
                                root.backend.userConfig =
                                    (result.value !== undefined && result.value !== "")
                                        ? result.value
                                        : (outputPath !== "" ? outputPath : root.backend.generatedUserConfigPath)
                                root.backend.deploymentConfig =
                                    (deploymentMode === 1 && deploymentConfigPath !== "")
                                        ? deploymentConfigPath : ""
                                root.backend.useGeneratedConfig = true
                                // Finalize: move to the "set path" window, now
                                // showing the resolved config path, ready for
                                // the user to continue and start the node.
                                configChoiceView.showSetConfigPath()
                            }
                        },
                        function(error) {
                            console.log("[BlockchainView] generateConfig error callback: error=", error)
                            configChoiceView.generateResultSuccess = false
                            configChoiceView.generateResultMessage =
                                qsTr("Generate failed: %1").arg(error)
                        }
                    )
                }
            }
        }

        // Page 2: Node information + Wallet operations (tabbed)
        ColumnLayout {
            id: opPage
            spacing: Theme.spacing.medium

            // Selected operation inside the Operations tab's sidebar nav.
            //   0 Accounts · 1 Transfer · 2 Leader Rewards · 3 Channel Deposit
            property int operationIndex: 0

            // When pinned, Accounts stays visible (stacked on top) even while a
            // different operation is selected.
            property bool accountsPinned: false

            readonly property bool nodeRunning: root.backend
                ? root.backend.status === BlockchainBackend.Running
                : false

            // Wallet operations require a running node. If the node stops while
            // the Operations tab is open, fall back to the Node tab so the user
            // isn't stranded on a disabled tab.
            onNodeRunningChanged: {
                if (!nodeRunning)
                    operationTabBar.currentIndex = 0
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.medium
                // Tabs size to content (compressed) so the stop-node control + gear fit.
                LogosTabBar {
                    id: operationTabBar
                    spacing: Theme.spacing.large   // more room between the tabs
                    LogosTabButton { text: qsTr("Node") }
                    LogosTabButton {
                        text: qsTr("Operations")
                        enabled: opPage.nodeRunning
                    }
                    LogosTabButton {
                        text: qsTr("Explorer")
                        enabled: opPage.nodeRunning
                    }
                }
                Item { Layout.fillWidth: true }   // push node control + gear to the right

                // Node run/stop — outlined pill with a white glyph, near settings.
                // The reminder label nudges users to stop cleanly before closing
                // Basecamp (a dirty shutdown is what forced the DB-recovery pain).
                Rectangle {
                    id: nodeCtlBtn
                    Layout.alignment: Qt.AlignVCenter
                    readonly property int st: root.backend ? root.backend.status : -1
                    readonly property bool running: st === BlockchainBackend.Running
                    // Disabled mid-transition so a second start can't fire (#18).
                    readonly property bool busy: st === BlockchainBackend.Starting
                                                 || st === BlockchainBackend.Stopping
                    enabled: root.backend && !busy
                    opacity: busy ? 0.5 : 1
                    implicitHeight: 28
                    implicitWidth: nodeCtlRow.implicitWidth + 22
                    radius: 14
                    color: nodeCtlM.pressed ? Qt.rgba(1, 1, 1, 0.10)
                           : (nodeCtlM.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                    border.width: 1
                    border.color: nodeCtlM.containsMouse ? Theme.palette.text : Theme.palette.border
                    RowLayout {
                        id: nodeCtlRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.small
                        // white stop square (running) / play triangle (idle); none while busy
                        Rectangle {
                            visible: nodeCtlBtn.running
                            Layout.alignment: Qt.AlignVCenter
                            width: 9; height: 9; radius: 1
                            color: Theme.palette.text
                        }
                        LogosText {
                            visible: !nodeCtlBtn.running && !nodeCtlBtn.busy
                            Layout.alignment: Qt.AlignVCenter
                            text: "▶"
                            color: Theme.palette.text
                            font.pixelSize: 11
                        }
                        LogosText {
                            text: nodeCtlBtn.st === BlockchainBackend.Starting ? qsTr("Starting…")
                                  : nodeCtlBtn.st === BlockchainBackend.Stopping ? qsTr("Stopping…")
                                  : nodeCtlBtn.running ? qsTr("Stop node before closing Basecamp")
                                  : qsTr("Run node")
                            color: Theme.palette.text
                            font.pixelSize: Theme.typography.secondaryText
                            font.weight: Theme.typography.weightMedium
                        }
                    }
                    MouseArea {
                        id: nodeCtlM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.backend || nodeCtlBtn.busy) return
                            if (nodeCtlBtn.running) root.backend.stopBlockchain()
                            else root.backend.startBlockchain()
                        }
                    }
                }

                // Fund the node (auto-stake) — orange-accented CTA. Always visible;
                // greyed + non-interactive until the node is Online (issue #22).
                Rectangle {
                    id: fundBtn
                    Layout.alignment: Qt.AlignVCenter
                    readonly property bool online: root.backend
                        && root.backend.status === BlockchainBackend.Running
                    readonly property bool ready: online && root.backend
                        && (root.backend.primaryAddress || "").length > 0
                    enabled: ready
                    opacity: ready ? 1 : 0.4
                    implicitHeight: 28
                    implicitWidth: fundRow.implicitWidth + 22
                    radius: 14
                    readonly property color accent: Theme.palette.primaryHover
                    color: fundM.pressed ? Qt.rgba(accent.r, accent.g, accent.b, 0.20)
                           : (fundM.containsMouse && ready ? Qt.rgba(accent.r, accent.g, accent.b, 0.12)
                                                           : "transparent")
                    border.width: 1
                    border.color: ready ? accent : Theme.palette.border
                    ToolTip.visible: fundM.containsMouse && !fundBtn.ready
                    ToolTip.text: qsTr("Fund the node once it's online")
                    RowLayout {
                        id: fundRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.small
                        LogosText {
                            Layout.alignment: Qt.AlignVCenter
                            text: "＋"
                            color: fundBtn.ready ? fundBtn.accent : Theme.palette.textSecondary
                            font.pixelSize: 14
                            font.weight: Theme.typography.weightMedium
                        }
                        LogosText {
                            text: qsTr("Fund the node")
                            color: fundBtn.ready ? fundBtn.accent : Theme.palette.textSecondary
                            font.pixelSize: Theme.typography.secondaryText
                            font.weight: Theme.typography.weightMedium
                        }
                    }
                    MouseArea {
                        id: fundM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: fundBtn.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (fundBtn.ready) fundDialog.open()
                    }
                }

                // Settings gear (→ config; becomes the #12 modal).
                LogosText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: Theme.spacing.small
                    text: "⚙"
                    font.pixelSize: 18
                    color: gearMouse.containsMouse ? Theme.palette.text : Theme.palette.textSecondary
                    MouseArea {
                        id: gearMouse
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: _d.currentPage = 0
                    }
                }
            }

            StackLayout {
                id: operationStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: operationTabBar.currentIndex

                // ---- Tab 0: dashboard + Blocks/Proposals, one page (no split handle) ----
                ColumnLayout {
                    spacing: Theme.spacing.large

                    // One-click UX #13 — status-first node dashboard.
                    NodeDashboardView {
                        Layout.fillWidth: true
                        statusEnum: root.backend ? root.backend.status : -1
                        statusText: root.backend
                            ? _d.getStatusString(root.backend.status)
                            : qsTr("Not Connected")
                        statusColor: root.backend
                            ? _d.getStatusColor(root.backend.status)
                            : Theme.palette.error
                        isRunning: opPage.nodeRunning
                        errorText: (root.cryptarchiaInfoError && root.cryptarchiaInfoError.length)
                            ? root.cryptarchiaInfoError
                            : ((root.backend && root.backend.status === BlockchainBackend.Error)
                                ? root.backend.lastErrorMessage : "")
                        peerId: root.peerId
                        infoJson: root.cryptarchiaInfoJson
                        balanceText: root.nodeBalance
                        peerCount: root.nodePeers
                        connectionCount: root.nodeConnections

                        onCopyText: (text) => root.copyText(text)
                        onStartRequested: if (root.backend) root.backend.startBlockchain()
                        onStopRequested: if (root.backend) root.backend.stopBlockchain()
                    }

                    // Small, left-aligned Blocks / Proposals tabs.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        LogosTabBar {
                            id: blocksTabBar
                            LogosTabButton { text: qsTr("Blocks"); width: implicitWidth + 24 }
                            LogosTabButton { text: qsTr("Proposals"); width: implicitWidth + 24 }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    StackLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: blocksTabBar.currentIndex

                        BlocksView {
                            blockModel: root.blockModel
                            myKey: root.backend ? (root.backend.primaryAddress || "") : ""
                            onClearRequested: if (root.backend) root.backend.clearBlocks()
                            onCopyToClipboard: (text) => root.copyText(text)
                        }

                        // Proposals (#14) — blocks proposed by this node (parsed from the node log).
                        ProposalsView {
                            proposalsJson: root.proposalsJson
                            voucherCount: root.voucherCount
                            onCopyToClipboard: (text) => root.copyText(text)
                        }
                    }
                }

                // ---- Tab 1: Wallet operations (sidebar nav + panels) ----
                // Anchor-based (not a Layout): StackLayout force-fills this Item,
                // and anchors give the SplitView explicit geometry. The panels
                // have ~zero implicit height, so a plain Layout would collapse
                // them — anchors + SplitView.fillHeight avoid that.
                Item {
                    // Sidebar navigation
                    ColumnLayout {
                        id: opSidebar
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 180
                        spacing: Theme.spacing.small

                        NavItem { label: qsTr("Accounts"); index: 0; pinnable: true }
                        NavItem { label: qsTr("Transfer"); index: 1 }
                        NavItem { label: qsTr("Leader Rewards"); index: 2 }
                        NavItem { label: qsTr("Channel Deposit"); index: 3 }

                        Item { Layout.fillHeight: true }
                    }

                    Rectangle {
                        id: opDivider
                        anchors.left: opSidebar.right
                        anchors.leftMargin: Theme.spacing.large
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Theme.palette.borderSecondary
                    }

                    // Operation panels. Accounts lives outside the stack so it
                    // can stay pinned on top while another operation is shown;
                    // a vertical SplitView keeps both visible and resizable.
                    SplitView {
                        anchors.left: opDivider.right
                        anchors.leftMargin: Theme.spacing.large
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        orientation: Qt.Vertical

                        AccountsView {
                            id: accountsView
                            visible: opPage.operationIndex === 0 || opPage.accountsPinned
                            // Fills when it's the sole panel; when pinned beside
                            // an operation it's a resizable 260px strip on top
                            // (the operation below is the SplitView filler).
                            SplitView.fillHeight: opPage.operationIndex === 0
                            SplitView.preferredHeight: 260
                            SplitView.minimumHeight: 120

                            accountsModel: root.accountsModel

                            onGetBalanceRequested: function(addressHex) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.getBalance(addressHex),
                                    function(result) {
                                        if (result.success) {
                                            accountsView.lastBalanceErrorAddress = ""
                                            accountsView.lastBalanceError = ""
                                        } else {
                                            accountsView.lastBalanceErrorAddress = addressHex
                                            accountsView.lastBalanceError = _d.errorText(result.error)
                                        }
                                    },
                                    function(error) {
                                        accountsView.lastBalanceErrorAddress = addressHex
                                        accountsView.lastBalanceError = _d.errorText(error)
                                    }
                                )
                            }
                            onRefreshAccountsRequested: if (root.backend) root.backend.refreshAccounts()
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }

                        // Transfer / Leader Rewards / Channel Deposit.
                        // operationIndex 1,2,3 maps to stack index 0,1,2.
                        StackLayout {
                            id: otherOpsStack
                            SplitView.fillHeight: true
                            SplitView.minimumHeight: 150
                            visible: opPage.operationIndex !== 0
                            currentIndex: Math.max(0, opPage.operationIndex - 1)

                        TransferView {
                            id: transferView
                            accountsModel: root.accountsModel

                            onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.transferFunds(fromKeyHex, toKeyHex, amount),
                                    function(result) {
                                        if (result.success) {
                                            transferView.setTransferResult(result.value)
                                        } else {
                                            transferView.setTransferResult(_d.errorText(result.error))
                                        }
                                    },
                                    function(error) { transferView.setTransferResult(_d.errorText(error)) }
                                )
                            }
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }

                        LeaderRewardsView {
                            id: leaderRewardsView
                            vouchersJson: root.claimableVouchersJson

                            onClaimLeaderRewardsRequested: function() {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.claimLeaderRewards(),
                                    function(result) {
                                        if (result.success) {
                                            leaderRewardsView.setLeaderClaimResult(result.value)
                                        } else {
                                            leaderRewardsView.setLeaderClaimResult(_d.errorText(result.error))
                                        }
                                        // Reflect the claim in the pending list.
                                        root.refreshClaimableVouchers()
                                    },
                                    function(error) { leaderRewardsView.setLeaderClaimResult(_d.errorText(error)) }
                                )
                            }
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }

                        ChannelDepositView {
                            id: channelDepositView
                            accountsModel: root.accountsModel
                            nodeRunning: opPage.nodeRunning

                            onGetNotesRequested: function(addressHex, optionalTipHex) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.getNotes(addressHex, optionalTipHex),
                                    function(result) {
                                        if (result.success)
                                            channelDepositView.setNotes(result.value)
                                        else
                                            channelDepositView.setNotesError(_d.errorText(result.error))
                                    },
                                    function(error) { channelDepositView.setNotesError(_d.errorText(error)) }
                                )
                            }
                            onSubmitRequested: function(channelIdHex, inputNoteIdHexes, metadataBase58, changePublicKeyHex, fundingPublicKeyHexes, maxTxFee, optionalTipHex) {
                                if (!root.backend) return
                                logos.watch(
                                    root.backend.channelDepositWithNotes(
                                        channelIdHex, inputNoteIdHexes, metadataBase58,
                                        changePublicKeyHex, fundingPublicKeyHexes, maxTxFee, optionalTipHex),
                                    function(result) {
                                        if (result.success)
                                            channelDepositView.setSubmitResult(true, result.value)
                                        else
                                            channelDepositView.setSubmitResult(false, _d.errorText(result.error))
                                    },
                                    function(error) { channelDepositView.setSubmitResult(false, _d.errorText(error)) }
                                )
                            }
                            onCopyToClipboard: (text) => {
                                root.copyText(text)
                            }
                        }
                        }
                    }
                }

                // ---- Tab 2: Explorer (block / transaction lookup) ----
                ExplorerView {
                    id: explorerView
                    nodeRunning: opPage.nodeRunning

                    // Auto-detect the id kind. The node can't fetch a mined
                    // transaction by hash (its tx store is mempool-only, pruned
                    // ~10 min after inclusion), so resolve a tx in this order:
                    //   1. loaded blocks — the blocks view already holds each
                    //      tx and its id, so a copied tx id resolves locally;
                    //   2. get_block — the id is a block header id;
                    //   3. get_transaction — a still-pending mempool tx.
                    onSearchRequested: function(id) {
                        if (!root.backend) return

                        // Every backend call is remoted through QtRO, so each
                        // must be resolved via logos.watch (even the local scan,
                        // whose search runs synchronously on the source side).

                        // Step 1: scan the loaded blocks for the tx by its id.
                        logos.watch(
                            root.backend.findTransactionInBlocks(id),
                            function(local) {
                                if (local.success) {
                                    explorerView.setTransactionResult(id, local.value, local.slot, local.blockId)
                                    return
                                }
                                // Step 2: block by header id.
                                logos.watch(
                                    root.backend.getBlock(id),
                                    function(blockResult) {
                                        if (blockResult.success) {
                                            explorerView.setBlockResult(id, blockResult.value)
                                            return
                                        }
                                        // Step 3: pending transaction via the node.
                                        logos.watch(
                                            root.backend.getTransaction(id),
                                            function(txResult) {
                                                if (txResult.success)
                                                    explorerView.setTransactionResult(id, txResult.value)
                                                else
                                                    explorerView.setNotFound(id)
                                            },
                                            function(error) { explorerView.setError(id, _d.errorText(error)) }
                                        )
                                    },
                                    function(error) { explorerView.setError(id, _d.errorText(error)) }
                                )
                            },
                            function(error) { explorerView.setError(id, _d.errorText(error)) }
                        )
                    }
                    onCopyToClipboard: (text) => root.copyText(text)
                }
            }

            // Sidebar nav entry used by the Operations tab. `pinnable` adds a
            // pin toggle on the right (used by Accounts) that keeps the panel
            // visible alongside other operations.
            component NavItem: Rectangle {
                property string label
                property int index
                property bool pinnable: false

                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: Theme.spacing.radiusSmall
                color: opPage.operationIndex === index
                    ? Theme.palette.backgroundTertiary
                    : (navMouse.containsMouse ? Theme.palette.backgroundSecondary : "transparent")

                // Background click selects the operation. Sits below the row so
                // the pin button on top captures its own clicks.
                MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: opPage.operationIndex = index
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.medium
                    anchors.rightMargin: Theme.spacing.small
                    spacing: Theme.spacing.small

                    LogosText {
                        Layout.fillWidth: true
                        text: label
                        elide: Text.ElideRight
                        font.pixelSize: Theme.typography.secondaryText
                        font.bold: opPage.operationIndex === index
                        color: opPage.operationIndex === index
                            ? Theme.palette.primary
                            : Theme.palette.text
                    }

                    // Pin toggle (Accounts only). A flat icon button matching
                    // the other SVG icons; the pin colours up when pinned. Its
                    // own click handling stops the nav-background MouseArea
                    // below from also selecting the item.
                    Button {
                        visible: pinnable
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        display: AbstractButton.IconOnly
                        flat: true
                        padding: 4
                        icon.source: Qt.resolvedUrl("icons/pin.svg")
                        icon.width: 18
                        icon.height: 18
                        icon.color: opPage.accountsPinned
                            ? Theme.palette.primary
                            : Theme.palette.textTertiary
                        onClicked: opPage.accountsPinned = !opPage.accountsPinned

                        ToolTip.visible: hovered
                        ToolTip.text: opPage.accountsPinned
                            ? qsTr("Unpin accounts") : qsTr("Pin accounts")
                    }
                }
            }
        }

        // Page 2: first-run one-click screen (#10); shown only when no config (#15).
        FirstRunView {
            onRunNodeRequested: _d.runNodeOneClick()
            onHaveConfigRequested: { configChoiceView.showSetConfigPath(); _d.currentPage = 0 }
            onGenerateCustomRequested: _d.currentPage = 0
        }
    }
}
