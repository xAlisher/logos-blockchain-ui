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

import "controls"
import "views"

Rectangle {
    id: root

    readonly property var backend: logos.module("blockchain_ui")
    // `ready` can't be a binding on logos.isViewModuleReady(): that's a
    // Q_INVOKABLE method, not a Q_PROPERTY, so the binding wouldn't refresh
    // when the replica transitions to Valid. Drive it from the bridge's
    // viewModuleReadyChanged signal instead.
    property bool ready: false

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "blockchain_ui") {
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
        root.ready = root.backend !== null && logos.isViewModuleReady("blockchain_ui")
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
    readonly property var accountsModel: logos.model("blockchain_ui", "accounts")
    readonly property var blockModel: logos.model("blockchain_ui", "blocks")

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
        if (root.backend.userConfig && root.backend.userConfig.length > 0)
            _d.currentPage = 1
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

    // Live Cryptarchia consensus state, polled while the node runs. This poll
    // is our *status monitor*, not a liveness verdict: a failed call means "the
    // status RPC didn't answer", not "the node is dead" (the node also pushes
    // blocks over a separate event channel, so it can be perfectly alive while a
    // request/reply call times out). So a failure never stops the node — we
    // retry with backoff, and if that is exhausted we simply *pause monitoring*
    // and let the user (or the next incoming block) resume it.
    property string cryptarchiaInfoJson: ""
    property string cryptarchiaInfoError: ""
    // Consensus clock, polled alongside the chain info. Its current_slot is what
    // the At Headslot tile measures the chain tip against.
    property string timeInfoJson: ""

    // UI status overrides driven by the poll loop, taking precedence over the
    // backend's own status in the status tag:
    //  - `statusUnresponsive`: set while we're backing off after failed status
    //    calls (the node is still Running but the status RPC isn't answering);
    //  - `monitoringPaused`: set once the backoff is exhausted — monitoring is
    //    paused (the node is left untouched). Cleared by an incoming block or
    //    the user's Resume action.
    property bool statusUnresponsive: false
    property bool monitoringPaused: false

    // Whether the node is Running per the backend state machine. Kept separate
    // from `statusPollActive` so leaving Running can clear a paused-monitoring
    // state (a fresh start re-monitors from scratch).
    readonly property bool nodeRunning:
        root.ready && root.backend
        && root.backend.status === BlockchainBackend.Running

    onNodeRunningChanged: {
        if (!nodeRunning) {
            root.monitoringPaused = false
            root.cryptarchiaInfoJson = ""
            root.timeInfoJson = ""
        }
    }

    // Poll cadence / backoff. Healthy cadence is `statusPollBaseMs`; after a
    // failed call we retry at `statusRetryMs`, doubling it on each further
    // failure up to `statusPollMaxMs` (2^6 seconds). Once at the cap we retry
    // there up to `statusMaxRetries` times before giving up. `statusRetryMs === 0`
    // means "healthy — use the base cadence".
    readonly property int statusPollBaseMs: 2000
    readonly property int statusPollMaxMs: 64 * 1000     // 2^6 seconds
    readonly property int statusMaxRetries: 3            // retries at the cap before giving up
    property int statusRetryMs: 0
    property int statusCapRetryCount: 0

    // Drives the poll loop on/off: the node is Running and monitoring hasn't
    // been paused. Kept as a property so its change handler can (re)start
    // polling from a clean state — including when Resume clears the pause.
    readonly property bool statusPollActive: root.nodeRunning && !root.monitoringPaused

    onStatusPollActiveChanged: {
        if (statusPollActive) {
            root.statusRetryMs = 0
            root.statusCapRetryCount = 0
            root.statusUnresponsive = false
            root.pollNodeStatus()          // immediate first poll
        } else {
            root.statusUnresponsive = false
            cryptarchiaTimer.stop()
        }
    }

    // Single-shot: each poll schedules the next one itself once its reply
    // arrives, so a slow/stuck call can't overlap the following request and the
    // backoff interval is honoured exactly. `interval` follows the backoff.
    Timer {
        id: cryptarchiaTimer
        repeat: false
        interval: root.statusRetryMs > 0 ? root.statusRetryMs : root.statusPollBaseMs
        onTriggered: root.pollNodeStatus()
    }

    function pollNodeStatus() {
        if (!root.statusPollActive || !root.backend)
            return
        logos.watch(
            root.backend.getCryptarchiaInfo(),
            function(result) {
                if (result.success)
                    root._onStatusPollSuccess(result.value)
                else
                    root._onStatusPollFailure(_d.errorText(result.error))
            },
            function(error) { root._onStatusPollFailure(_d.errorText(error)) }
        )
    }

    function _scheduleNextPoll() {
        // Guard against rescheduling after the node has left Running (e.g. the
        // user stopped it, or we gave up below).
        if (root.statusPollActive)
            cryptarchiaTimer.restart()
    }

    function _pollTimeInfo() {
        if (!root.backend)
            return
        logos.watch(
            root.backend.getTimeInfo(),
            function(result) { root.timeInfoJson = result.success ? result.value : "" },
            function(error) { root.timeInfoJson = "" }
        )
    }

    function _onStatusPollSuccess(value) {
        root.cryptarchiaInfoJson = value
        root._pollTimeInfo()
        root.cryptarchiaInfoError = ""
        root.statusRetryMs = 0             // recovered: back to the base cadence
        root.statusCapRetryCount = 0
        root.statusUnresponsive = false
        root.statusNextPollSeconds = 0
        root._scheduleNextPoll()
    }

    function _onStatusPollFailure(message) {
        root.cryptarchiaInfoError = message

        if (root.statusRetryMs >= root.statusPollMaxMs) {
            // Already at the cap: retry there a bounded number of times before
            // giving up.
            root.statusCapRetryCount += 1
            if (root.statusCapRetryCount >= root.statusMaxRetries) {
                // Out of retries: the status RPC won't answer. Do NOT touch the
                // node (it may well be alive — see the comment above). Just
                // pause monitoring; an incoming block or the Resume button will
                // bring it back.
                root.statusRetryMs = 0
                root.statusCapRetryCount = 0
                root.statusUnresponsive = false
                root.statusNextPollSeconds = 0
                root.monitoringPaused = true   // flips statusPollActive → stops the loop
                return
            }
            root.statusUnresponsive = true
            root.statusNextPollSeconds = Math.ceil(root.statusRetryMs / 1000)
            root._scheduleNextPoll()
            return
        }

        // Exponential backoff: 2s, 4s, 8s, … capped at 2^6 s.
        root.statusRetryMs = root.statusRetryMs === 0
            ? root.statusPollBaseMs
            : Math.min(root.statusRetryMs * 2, root.statusPollMaxMs)
        root.statusUnresponsive = true
        root.statusNextPollSeconds = Math.ceil(root.statusRetryMs / 1000)
        root._scheduleNextPoll()
    }

    // Live countdown to the next retry while backing off, purely for display.
    // Reset to the full backoff on each scheduled retry and ticked down once a
    // second; the actual poll is driven by `cryptarchiaTimer`, not this.
    property int statusNextPollSeconds: 0

    Timer {
        id: statusCountdownTimer
        interval: 1000
        repeat: true
        running: root.statusUnresponsive
        onTriggered: {
            if (root.statusNextPollSeconds > 0)
                root.statusNextPollSeconds -= 1
        }
    }

    // Resume the status monitor after it was paused (backoff exhausted). Clears
    // the pause, which flips `statusPollActive` back on and — via its change
    // handler — resets the backoff and fires an immediate poll. No-op if the
    // node isn't Running.
    function resumeMonitoring() {
        if (root.monitoringPaused && root.nodeRunning)
            root.monitoringPaused = false
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

    // Incoming blocks arrive as row insertions on the remoted block model. A
    // new block is proof the node is alive, so it also auto-resumes a paused
    // status monitor.
    Connections {
        target: root.blockModel
        enabled: root.blockModel !== null
        ignoreUnknownSignals: true
        function onRowsInserted() {
            root.resumeMonitoring()
            root.refreshClaimableVouchers()
        }
    }

    // Initial load when the node reaches Running (before the next block).
    Connections {
        target: root.backend
        enabled: root.backend !== null
        ignoreUnknownSignals: true
        function onStatusChanged() {
            if (root.backend.status === BlockchainBackend.Running)
                root.refreshClaimableVouchers()
        }
    }

    QtObject {
        id: _d
        function errorText(message) {
            return qsTr("Error: %1").arg(message)
        }

        property int currentPage: 0

        // Guards the one-time startup route (see root._applyInitialRoute):
        // it must fire once when the module first becomes ready, and never
        // fight the user's later navigation (e.g. the node view's "Change"
        // button, which deliberately returns to the chooser at page 0).
        property bool initialRouted: false
    }

    color: Theme.palette.background

    // Loading state before backend connects
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: Theme.spacing.medium
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Connecting to blockchain backend...")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        LogosSpinner { Layout.alignment: Qt.AlignHCenter; running: !root.ready }
    }

    StackLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.large
        currentIndex: _d.currentPage
        visible: root.ready

        // Page 1: Config choice
        LogosScrollView {
            id: configChoiceScrollView
            ConfigChoiceView {
                id: configChoiceView
                objectName: "configChoiceView"
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

        // Page 2: node dashboard, wallet operations and the explorer, behind a
        // left nav. Same idiom as basecamp's Settings/AppManager sidebars —
        // LogosListView + LogosItemDelegate; the design system has no packaged
        // sidebar component.
        ColumnLayout {
            id: opPage
            spacing: Theme.spacing.medium

            property int sectionIndex: 0
            readonly property bool nodeRunning: root.backend ? root.backend.status === BlockchainBackend.Running : false
            readonly property bool canStart: root.backend && !!root.backend.userConfig && (root.backend.status === BlockchainBackend.NotStarted || root.backend.status === BlockchainBackend.Stopped)
            readonly property bool canStop: root.backend && (root.backend.status === BlockchainBackend.Running || root.backend.status === BlockchainBackend.Error)
            // On stop, leave only the tabs that need a running node (wallet ops,
            // indices 2..6). Dashboard(0), Blocks(1) and Settings(7) stay put.
            onNodeRunningChanged: { if (!nodeRunning && sectionIndex >= 2 && sectionIndex <= 6) sectionIndex = 0 }

            // app header (was inside NodeDashboardView; hoisted so it persists across tabs)
            RowLayout {
                Layout.fillWidth: true; Layout.margins: Theme.spacing.large; spacing: Theme.spacing.medium
                Image {
                    source: Qt.resolvedUrl("icons/logos.svg")
                    sourceSize.width: 30; sourceSize.height: 30
                    Layout.preferredWidth: 30; Layout.preferredHeight: 30
                    Layout.alignment: Qt.AlignVCenter
                    fillMode: Image.PreserveAspectFit
                }
                LogosText { text: qsTr("Blockchain Node"); color: Theme.palette.text; font.pixelSize: 28; font.weight: Theme.typography.weightBold; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
                LogosButton { text: qsTr("Start Empowering"); enabled: opPage.nodeRunning; Layout.alignment: Qt.AlignVCenter }
                LogosButton {
                    text: opPage.nodeRunning ? qsTr("Stop Node") : qsTr("Start Node")
                    variant: LogosButton.Variant.Primary
                    Layout.alignment: Qt.AlignVCenter
                    enabled: opPage.nodeRunning ? opPage.canStop : opPage.canStart
                    onClicked: {
                        if (!root.backend) return
                        if (opPage.nodeRunning) root.backend.stopBlockchain()
                        else root.backend.startBlockchain()
                    }
                }
            }

            // top tab nav (replaces the left SectionNav; index-for-index with operationStack)
            LogosTabBar {
                id: sectionTabs
                Layout.fillWidth: true; Layout.leftMargin: Theme.spacing.large; Layout.rightMargin: Theme.spacing.large
                currentIndex: opPage.sectionIndex
                onCurrentIndexChanged: opPage.sectionIndex = currentIndex
                LogosTabButton { text: qsTr("Dashboard") }
                LogosTabButton { text: qsTr("Blocks") }
                LogosTabButton { text: qsTr("Accounts"); enabled: opPage.nodeRunning }
                LogosTabButton { text: qsTr("Rewards"); enabled: opPage.nodeRunning }
                LogosTabButton { text: qsTr("Explorer"); enabled: opPage.nodeRunning }
                LogosTabButton { text: qsTr("Transfer"); enabled: opPage.nodeRunning }
                LogosTabButton { text: qsTr("Channel Deposit"); enabled: opPage.nodeRunning }
                LogosTabButton { text: qsTr("Settings") }
            }

            StackLayout {
                id: operationStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: opPage.sectionIndex

                // ---- Section 0: Dashboard (blocks folded in) ----
                NodeDashboardView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    status: root.backend ? root.backend.status : -1
                    nodeRecovering: !!root.backend && root.backend.nodeRecovering
                    lastErrorMessage: root.cryptarchiaInfoError || (root.backend ? root.backend.lastErrorMessage : "")
                    infoJson: root.cryptarchiaInfoJson
                    timeInfoJson: root.timeInfoJson
                    peerId: root.peerId
                    nodeRunning: opPage.nodeRunning
                    blockModel: root.blockModel
                    blocksEmptyText: !opPage.nodeRunning
                                     ? qsTr("Start the node to see blocks arrive.")
                                     : root.cryptarchiaInfoJson.length === 0
                                       ? qsTr("Waiting for the node to report its state...")
                                       : qsTr("Waiting for the next block. Only blocks produced from now on are listed.")
                    onClearBlocksRequested: if (root.backend) root.backend.clearBlocks()
                    onCopyText: (t) => root.copyText(t)
                }

                // ---- Section 1: Blocks ----
                BlocksView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    blockModel: root.blockModel
                    emptyText: !opPage.nodeRunning
                               ? qsTr("Start the node to see blocks arrive.")
                               : root.cryptarchiaInfoJson.length === 0
                                 ? qsTr("Waiting for the node to report its state...")
                                 : qsTr("Waiting for the next block. Only blocks produced from now on are listed.")
                    onClearRequested: if (root.backend) root.backend.clearBlocks()
                    onCopyToClipboard: (t) => root.copyText(t)
                }

                // ---- wallet operations, one per nav entry ----
                AccountsView {
                    id: accountsView
                    accountsModel: root.accountsModel

                    onGetBalanceRequested: function(addressHex) {
                        if (!root.backend) {
                            accountsView.setBalanceResult(
                                addressHex, false, qsTr("Not connected to the module."))
                            return
                        }
                        logos.watch(
                            root.backend.getBalance(addressHex),
                            function(result) {
                                accountsView.setBalanceResult(
                                    addressHex, result.success,
                                    result.success ? "" : _d.errorText(result.error))
                            },
                            function(error) {
                                accountsView.setBalanceResult(
                                    addressHex, false, _d.errorText(error))
                            }
                        )
                    }
                    onRefreshAccountsRequested: if (root.backend) root.backend.refreshAccounts()
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

                // ---- Section 5: Explorer (block / transaction lookup) ----
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
                TransferView {
                    id: transferView
                    accountsModel: root.accountsModel

                    onTransferRequested: function(fromKeyHex, toKeyHex, amount) {
                        if (!root.backend) return
                        logos.watch(
                            root.backend.transferFunds(fromKeyHex, toKeyHex, amount),
                            function(result) {
                                if (result.success) {
                                    transferView.setTransferHash(result.value)
                                } else {
                                    transferView.setTransferError(_d.errorText(result.error))
                                }
                            },
                            function(error) { transferView.setTransferError(_d.errorText(error)) }
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

                // ---- Section 7: Settings ----
                // Surfaces the active configuration and the path back to the
                // chooser (page 0) — the redesigned dashboard dropped the old
                // NodeStatusCard "Change config" button, so this restores it.
                LogosScrollView {
                    id: settingsScrollView
                    ColumnLayout {
                        width: settingsScrollView.availableWidth
                        spacing: Theme.spacing.large

                        LogosFrame {
                            Layout.fillWidth: true
                            backgroundColor: Theme.palette.surfaceRaised
                            borderColor: "transparent"
                            radius: Theme.spacing.radiusLarge
                            padding: Theme.spacing.large
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing.medium
                                LogosText {
                                    text: qsTr("Configuration")
                                    color: Theme.palette.text
                                    font.pixelSize: 20
                                    font.weight: Theme.typography.weightBold
                                }
                                LogosText {
                                    text: qsTr("The node is started from the configuration below. Change it to point at a different config or regenerate one.")
                                    color: Theme.palette.textSecondary
                                    font.pixelSize: Theme.typography.secondaryText
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                // user config
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.medium
                                    LogosText {
                                        text: qsTr("User config")
                                        color: Theme.palette.textSecondary
                                        font.pixelSize: Theme.typography.secondaryText
                                        Layout.preferredWidth: 140
                                    }
                                    LogosText {
                                        text: (root.backend && root.backend.userConfig && root.backend.userConfig.length > 0)
                                              ? root.backend.userConfig : qsTr("—")
                                        color: Theme.palette.text
                                        font.pixelSize: Theme.typography.secondaryText
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }

                                // deployment config (only when set)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.medium
                                    visible: !!root.backend && !!root.backend.deploymentConfig && root.backend.deploymentConfig.length > 0
                                    LogosText {
                                        text: qsTr("Deployment config")
                                        color: Theme.palette.textSecondary
                                        font.pixelSize: Theme.typography.secondaryText
                                        Layout.preferredWidth: 140
                                    }
                                    LogosText {
                                        text: root.backend ? root.backend.deploymentConfig : ""
                                        color: Theme.palette.text
                                        font.pixelSize: Theme.typography.secondaryText
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.topMargin: Theme.spacing.small
                                    LogosButton {
                                        text: qsTr("Change configuration")
                                        variant: LogosButton.Variant.Primary
                                        enabled: !opPage.nodeRunning
                                        onClicked: _d.currentPage = 0
                                    }
                                    Item { Layout.fillWidth: true }
                                    LogosText {
                                        visible: opPage.nodeRunning
                                        text: qsTr("Stop the node to change its configuration.")
                                        color: Theme.palette.textTertiary
                                        font.pixelSize: Theme.typography.secondaryText
                                        Layout.alignment: Qt.AlignVCenter
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
