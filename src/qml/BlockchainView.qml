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

    // Incoming blocks arrive as row insertions on the remoted block model.
    Connections {
        target: root.blockModel
        enabled: root.blockModel !== null
        ignoreUnknownSignals: true
        function onRowsInserted() { root.refreshClaimableVouchers() }
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

            LogosTabBar {
                id: operationTabBar
                Layout.fillWidth: true
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

            StackLayout {
                id: operationStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: operationTabBar.currentIndex

                // ---- Tab 0: Node information (status + logs) ----
                SplitView {
                    orientation: Qt.Vertical

                    ColumnLayout {
                        SplitView.fillWidth: true
                        SplitView.minimumHeight: 120
                        spacing: Theme.spacing.large

                        StatusConfigView {
                            Layout.fillWidth: true
                            statusText: root.backend
                                ? _d.getStatusString(root.backend.status)
                                : qsTr("Not Connected")
                            statusColor: root.backend
                                ? _d.getStatusColor(root.backend.status)
                                : Theme.palette.error
                            userConfig: root.backend ? root.backend.userConfig : ""
                            deploymentConfig: root.backend ? root.backend.deploymentConfig : ""
                            useGeneratedConfig: root.backend ? root.backend.useGeneratedConfig : false
                            canStart: root.backend
                                      && !!root.backend.userConfig
                                      && root.backend.status !== BlockchainBackend.Starting
                                      && root.backend.status !== BlockchainBackend.Stopping
                            isRunning: opPage.nodeRunning

                            onStartRequested: if (root.backend) root.backend.startBlockchain()
                            onStopRequested: if (root.backend) root.backend.stopBlockchain()
                            onChangeConfigRequested: _d.currentPage = 0
                            onResetChainStateRequested: resetConfirmDialog.open()
                        }

                        NodeInfoView {
                            Layout.fillWidth: true
                            peerId: root.peerId
                            onCopyToClipboard: (text) => root.copyText(text)
                        }

                        CryptarchiaInfoView {
                            Layout.fillWidth: true
                            visible: opPage.nodeRunning
                            infoJson: root.cryptarchiaInfoJson
                            errorText: root.cryptarchiaInfoError
                            onCopyToClipboard: (text) => root.copyText(text)
                        }

                        Item {
                            Layout.preferredHeight: Theme.spacing.small
                        }
                    }

                    BlocksView {
                        SplitView.fillWidth: true
                        SplitView.minimumHeight: 150

                        blockModel: root.blockModel
                        onClearRequested: if (root.backend) root.backend.clearBlocks()
                        onCopyToClipboard: (text) => {
                            root.copyText(text)
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
    }
}
