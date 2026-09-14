import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

import "../controls"

// Node onboarding, ported from the studio prototype and wired to the real backend.
// Default path is ONE CLICK (Quick start: generate a default config + start). The
// stepper (Setup · Network · Keys · Fund) only appears under Advanced. Only USER
// actions are steps — start/sync/aging are node-driven and live on the dashboard.
//
// This view owns the UI + step state; the HOST (BlockchainView) performs the
// backend work and feeds results back through the properties below. That mirrors
// the prototype's finished()/exitRequested() contract, extended for real actions.
Item {
    id: root

    // ── intents the host wires to the backend ──
    signal quickStartRequested()                                   // generate default config + start → dashboard
    signal generateConfigRequested(var initialPeers, int deploymentMode, string deploymentConfigPath)
    signal useExistingConfigRequested(string userConfigPath, string deploymentConfigPath)
    signal saveKeystoreRequested(string destPath)                 // copy keystore.yaml to a chosen path
    signal requestFundsRequested()                                // faucet the funding key
    signal startNodeRequested()                                   // start the node in the background (no navigation)
    signal finishRequested()                                      // start the node (if needed) → dashboard
    signal exitRequested()                                        // back to the welcome splash
    signal copyToClipboard(string text)
    signal browseUserConfig()                                     // host opens a file dialog, sets userConfigPath
    signal browseDeploymentConfig()

    // ── feedback the host sets ──
    property bool   configReady: false          // host flips true once generate/set-existing succeeds
    property string configError: ""             // host sets on a generate failure
    property bool   configPending: false        // host sets while generateConfig is in flight
    property string fundingKey: ""              // leader funding key (the one that stakes/proposes)
    property bool   nodeRunning: false
    property bool   synced: false               // node caught up (Online) — fund only makes sense then
    // Faucet feedback, mirrored from the dashboard fund flow (BlockchainView._fundStage):
    // "" (idle) | "requesting" | "success" | "error".
    property string fundStage: ""
    property string fundDetail: ""              // tx hash on success, error text on failure
    readonly property bool funded: fundStage === "success"
    property string keystoreResult: ""          // host sets after saveKeystore ("Saved to …" / "Error: …")
    property bool   keystoreExists: false       // host: keystore.yaml is present (true after generate)

    // ── local step state ──
    property bool   advanced: false
    property int    step: 0
    readonly property var stepNames: [qsTr("Setup"), qsTr("Network"), qsTr("Keys"), qsTr("Fund")]
    property string mode: ""                     // "generate" | "existing"
    property string deployment: "default"        // "default" | "custom"
    property string userConfigPath: ""           // for the "existing config" path (host-fed via browse)
    property string deploymentConfigPath: ""     // custom deployment YAML (both flows)
    property bool   keysSaved: false             // ticked the backup checkbox

    readonly property color ctaOrange: Theme.colors.orange400

    // The four testnet bootstrap peers, editable in the Network step.
    property alias peersText: peersArea.text
    property string defaultPeers: ""

    function _canContinue() {
        switch (step) {
        case 0: return mode === "generate" || (mode === "existing" && userConfigPath.length > 0)
        case 1: return !root.configPending          // Network → commits config; block while in flight
        case 2: return keysSaved
        default: return true
        }
    }

    // Advancing OUT of the Network step (step 1) commits the config: generate a new
    // one, or adopt the existing paths. We wait for the host to flip configReady
    // before moving to Keys, so the keystore exists for the backup step.
    function _commitConfigThenNext() {
        root.configError = ""
        if (root.mode === "existing") {
            root.useExistingConfigRequested(root.userConfigPath, root.deploymentConfigPath)
        } else {
            var peers = peersArea.text.split("\n").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
            var dmode = root.deployment === "custom" ? 1 : 0
            root.generateConfigRequested(peers, dmode, root.deployment === "custom" ? root.deploymentConfigPath : "")
        }
    }
    onConfigReadyChanged: if (configReady && advanced && step === 1) step = 2

    function _next() {
        if (!advanced) return
        if (step === 1 && !configReady) { _commitConfigThenNext(); return }   // commit, advance on configReady
        if (step < 3) { step += 1; return }
        root.finishRequested()                                                 // step 3 "Start node"
    }
    // Welcome is the landing now, so backing out of step 0 returns there.
    function _back() { if (step > 0) step -= 1; else root.exitRequested() }
    function _openAdvanced() { root.mode = "generate"; root.step = 0; root.advanced = true }

    // Entering the Fund step starts the node in the background so its wallet loads
    // and the funding address appears — without leaving the onboarding screen.
    onStepChanged: if (advanced && step === 3 && !nodeRunning) root.startNodeRequested()

    // ── selectable card (Setup / Network / landing) ──
    component ChoiceCard: LogosFrame {
        id: cc
        property string heading: ""
        property string body: ""
        property bool selected: false
        property bool recommended: false
        property bool arrow: false           // landing cards route on click → "→", no radio
        signal picked()
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: selected ? Theme.colors.orange400 : Theme.palette.border
        radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        contentItem: RowLayout {
            spacing: Theme.spacing.medium
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                RowLayout {
                    spacing: Theme.spacing.small
                    LogosText { text: cc.heading; color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                    Rectangle {
                        visible: cc.recommended
                        radius: Theme.spacing.radiusSmall; color: Qt.rgba(Theme.palette.success.r, Theme.palette.success.g, Theme.palette.success.b, 0.15)
                        implicitWidth: recLbl.implicitWidth + 2 * Theme.spacing.small; implicitHeight: recLbl.implicitHeight + Theme.spacing.tiny
                        LogosText { id: recLbl; anchors.centerIn: parent; text: qsTr("Recommended"); color: Theme.palette.success; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                    }
                }
                LogosText { text: cc.body; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
            LogosText { visible: cc.arrow; text: "→"; color: Theme.palette.textSecondary; font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter }
            Rectangle {
                visible: !cc.arrow
                width: 22; height: 22; radius: 11; Layout.alignment: Qt.AlignVCenter
                color: cc.selected ? Theme.colors.orange400 : "transparent"
                border.color: cc.selected ? Theme.colors.orange400 : Theme.palette.border; border.width: 2
                LogosText { anchors.centerIn: parent; visible: cc.selected; text: "✓"; color: "#FFFFFF"; font.pixelSize: 13; font.weight: Theme.typography.weightBold }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cc.picked() }
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.spacing.xlarge; spacing: Theme.spacing.large

        // header
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                LogosText { text: qsTr("Set up your node"); color: Theme.palette.text; font.pixelSize: Theme.typography.titleText; font.weight: Theme.typography.weightBold }
                LogosText {
                    text: root.advanced ? qsTr("Advanced setup — configure and secure your node.")
                                        : qsTr("Get your Logos node running, funded, and eligible to earn.")
                    color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                }
            }
            GhostButton { visible: root.advanced; text: qsTr("Exit setup"); onClicked: root.exitRequested() }
        }

        // step rail (advanced only)
        RowLayout {
            visible: root.advanced
            Layout.fillWidth: true; spacing: Theme.spacing.small
            Repeater {
                model: root.stepNames
                delegate: ColumnLayout {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true; spacing: 4
                    Rectangle { Layout.fillWidth: true; height: 4; radius: 2; color: index <= root.step ? Theme.colors.orange400 : Theme.palette.border }
                    LogosText {
                        text: (index + 1) + ". " + modelData
                        color: index === root.step ? Theme.palette.text : Theme.palette.textTertiary
                        font.pixelSize: 11; font.weight: index === root.step ? Theme.typography.weightBold : Theme.typography.weightRegular
                    }
                }
            }
        }

        // body
        LogosFrame {
            Layout.fillWidth: true; Layout.fillHeight: true
            backgroundColor: Theme.palette.surface; borderColor: "transparent"
            radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
            contentItem: QQC.ScrollView {
                contentWidth: availableWidth; clip: true
                StackLayout {
                    width: parent.width
                    currentIndex: root.advanced ? 1 : 0

                    // ── LANDING (one click) ──
                    ColumnLayout {
                        spacing: Theme.spacing.medium
                        LogosText { text: qsTr("How do you want to start?"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                        ChoiceCard {
                            heading: qsTr("Quick start"); recommended: true; arrow: true
                            body: qsTr("Generate a default testnet config and start the node. Back up your keys right after.")
                            onPicked: root.quickStartRequested()
                        }
                        ChoiceCard {
                            heading: qsTr("Advanced setup"); arrow: true
                            body: qsTr("Choose your config, network and peers, and back up your keys during setup.")
                            onPicked: root._openAdvanced()
                        }
                    }

                    // ── ADVANCED stepper ──
                    StackLayout {
                        width: parent.width
                        currentIndex: root.step

                        // 0 · SETUP
                        ColumnLayout {
                            spacing: Theme.spacing.medium
                            LogosText { text: qsTr("How do you want to start?"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                            ChoiceCard {
                                heading: qsTr("Generate a new node"); recommended: true
                                body: qsTr("Create a fresh config and keystore. Best if this is your first node.")
                                selected: root.mode === "generate"; onPicked: root.mode = "generate"
                            }
                            ChoiceCard {
                                heading: qsTr("Use an existing config")
                                body: qsTr("Point at a user config you already have (e.g. moving to a new machine). Your keystore stays beside it.")
                                selected: root.mode === "existing"; onPicked: root.mode = "existing"
                            }
                            ColumnLayout {
                                visible: root.mode === "existing"
                                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.small
                                LogosText { text: qsTr("Point to your files"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.spacing.medium
                                    LogosText { text: qsTr("User config"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
                                    LogosTextField { Layout.fillWidth: true; text: root.userConfigPath; placeholderText: qsTr("path to user_config.yaml"); onTextChanged: root.userConfigPath = text }
                                    LogosButton { text: qsTr("Browse"); onClicked: root.browseUserConfig() }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.spacing.medium
                                    LogosText { text: qsTr("Deployment"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
                                    LogosTextField { Layout.fillWidth: true; text: root.deploymentConfigPath; placeholderText: qsTr("optional — deployment YAML"); onTextChanged: root.deploymentConfigPath = text }
                                    LogosButton { text: qsTr("Browse"); onClicked: root.browseDeploymentConfig() }
                                }
                                LogosText { text: qsTr("Your keys stay where they are — the node reads them from this path."); color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            }
                        }

                        // 1 · NETWORK
                        ColumnLayout {
                            spacing: Theme.spacing.medium
                            LogosText { text: qsTr("Network"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                            ChoiceCard {
                                heading: qsTr("Default (public testnet)")
                                body: qsTr("Recommended. Uses the shipped deployment config and bootstrap peers.")
                                selected: root.deployment === "default"; onPicked: root.deployment = "default"
                            }
                            ChoiceCard {
                                heading: qsTr("Custom deployment file")
                                body: qsTr("Supply your own deployment YAML (private net or a pinned genesis).")
                                selected: root.deployment === "custom"; onPicked: root.deployment = "custom"
                            }
                            RowLayout {
                                visible: root.deployment === "custom"
                                Layout.fillWidth: true; spacing: Theme.spacing.medium
                                LogosTextField { Layout.fillWidth: true; text: root.deploymentConfigPath; placeholderText: qsTr("path to deployment YAML"); onTextChanged: root.deploymentConfigPath = text }
                                LogosButton { text: qsTr("Browse"); onClicked: root.browseDeploymentConfig() }
                            }
                            LogosText { text: qsTr("Bootstrap peers"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium; Layout.topMargin: Theme.spacing.small }
                            LogosText { text: qsTr("The node dials these on start to find the chain (one multiaddr per line)."); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            LogosTextArea { id: peersArea; Layout.fillWidth: true; Layout.preferredHeight: 96; text: root.defaultPeers }
                            LogosText { visible: root.configError.length > 0; text: root.configError; color: Theme.palette.error; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }

                        // 2 · KEYS
                        ColumnLayout {
                            spacing: Theme.spacing.medium
                            LogosText { text: qsTr("Back up your node keys"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                            LogosFrame {
                                Layout.fillWidth: true
                                backgroundColor: Theme.palette.backgroundSecondary; borderColor: Theme.palette.warning; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                                contentItem: ColumnLayout {
                                    spacing: 2
                                    LogosText { text: qsTr("Shown once"); color: Theme.palette.warning; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightBold }
                                    LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: qsTr("Your keystore holds the keys that control this node's identity, stake, and rewards. There is no way to recover them if lost — save the file somewhere safe now."); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                                }
                            }
                            // What the keystore contains (real key roles; the file holds the secrets).
                            LogosFrame {
                                Layout.fillWidth: true
                                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                                contentItem: ColumnLayout {
                                    spacing: Theme.spacing.small
                                    Repeater {
                                        model: [
                                            { name: qsTr("Network / peer identity"),   role: qsTr("libp2p peer id") },
                                            { name: qsTr("Blend signing + ZK"),         role: qsTr("proposer privacy") },
                                            { name: qsTr("Leader funding"),             role: qsTr("funds block proposing") },
                                            { name: qsTr("SDP funding"),                role: qsTr("service declaration") },
                                            { name: qsTr("Mining / PoW claim"),         role: qsTr("claims mining rewards") },
                                            { name: qsTr("Wallet master + stake"),      role: qsTr("balance + consensus eligibility") }
                                        ]
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true; spacing: Theme.spacing.medium
                                            LogosText { text: modelData.name; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium; Layout.preferredWidth: 200 }
                                            LogosText { text: modelData.role; color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; Layout.fillWidth: true }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacing.medium
                                CtaButton {
                                    text: qsTr("Download keystore.yaml")
                                    enabled: root.keystoreExists
                                    onClicked: keystoreSaveDialog.open()
                                }
                                LogosText {
                                    Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: text.length > 0
                                    text: root.keystoreResult
                                    color: root.keystoreResult.indexOf("Error") === 0 ? Theme.palette.error : Theme.palette.textTertiary
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                            }
                            LogosCheckbox {
                                text: qsTr("I've backed up my keys somewhere safe")
                                checked: root.keysSaved
                                onToggled: root.keysSaved = checked
                            }
                        }

                        // 3 · FUND
                        ColumnLayout {
                            spacing: Theme.spacing.medium
                            LogosText { text: qsTr("Fund your node"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                            LogosText {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                                text: qsTr("A node needs stake before it can propose blocks. On testnet you request test funds for your funding key; they auto-stake once the node processes them.")
                            }
                            LogosFrame {
                                Layout.fillWidth: true; visible: root.fundingKey.length > 0
                                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                                contentItem: RowLayout {
                                    spacing: Theme.spacing.medium
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 0
                                        LogosText { text: qsTr("Funding key (leader)"); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                        LogosText { text: root.fundingKey; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace"; elide: Text.ElideMiddle; Layout.fillWidth: true }
                                    }
                                    BcCopyButton { onCopyText: root.copyToClipboard(root.fundingKey) }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacing.medium
                                CtaButton {
                                    text: root.fundStage === "requesting" ? qsTr("Requesting…")
                                          : root.fundStage === "success" ? qsTr("Funds requested")
                                          : root.fundStage === "error" ? qsTr("Try again")
                                          : qsTr("Request test funds")
                                    // Only fundable once the node is synced (Online) — a request
                                    // sent while bootstrapping just queues and looks like nothing.
                                    enabled: root.synced && root.fundStage !== "requesting"
                                             && root.fundStage !== "success" && root.fundingKey.length > 0
                                    onClicked: root.requestFundsRequested()
                                }
                                Item { Layout.fillWidth: true }
                            }
                            // Stage feedback, mirroring the dashboard fund dialog.
                            LogosText {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap; visible: text.length > 0
                                text: {
                                    if (root.fundStage === "requesting") return qsTr("Requesting testnet funds…")
                                    if (root.fundStage === "success") return qsTr("Funds requested successfully — they auto-stake shortly. You can continue.")
                                    if (root.fundStage === "error") return root.fundDetail
                                    if (!root.synced) return qsTr("Waiting for the node to finish syncing before it can be funded…")
                                    if (root.fundingKey.length === 0) return qsTr("Preparing your keys…")
                                    return ""
                                }
                                color: root.fundStage === "success" ? Theme.palette.success
                                       : root.fundStage === "error" ? Theme.palette.error
                                       : Theme.palette.textTertiary
                                font.pixelSize: Theme.typography.secondaryText
                                font.weight: (root.fundStage === "success" || root.fundStage === "error") ? Theme.typography.weightMedium : Theme.typography.weightRegular
                            }
                            // Transaction hash (copyable) on success.
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacing.small
                                visible: root.fundStage === "success" && root.fundDetail.length > 0
                                LogosText {
                                    Layout.fillWidth: true; elide: Text.ElideMiddle
                                    text: root.fundDetail; font.family: "monospace"
                                    color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                                }
                                BcCopyButton { onCopyText: root.copyToClipboard(root.fundDetail) }
                            }
                            LogosText {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textTertiary; font.pixelSize: 11
                                text: qsTr("Optional — you can skip and fund later from the dashboard. The node is already starting in the background.")
                            }
                        }
                    }
                }
            }
        }

        // footer nav (advanced only; landing routes on click)
        RowLayout {
            visible: root.advanced
            Layout.fillWidth: true; spacing: Theme.spacing.medium
            GhostButton { text: qsTr("Back"); onClicked: root._back() }
            Item { Layout.fillWidth: true }
            LogosText {
                visible: !root._canContinue()
                color: Theme.palette.textTertiary; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter
                text: root.step === 2 ? qsTr("Confirm you saved your keys to continue") : ""
            }
            CtaButton {
                text: root.step === 3 ? qsTr("Go to dashboard")
                      : (root.step === 1 && root.configPending) ? qsTr("Preparing…")
                      : qsTr("Continue")
                enabled: root._canContinue()
                onClicked: root._next()
            }
        }
    }

    // "Download keystore.yaml" → native Save-As; host copies the real keystore.
    FileDialog {
        id: keystoreSaveDialog
        modality: Qt.NonModal
        fileMode: FileDialog.SaveFile
        nameFilters: ["YAML files (*.yaml *.yml)", "All files (*)"]
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        selectedFile: "keystore.yaml"
        onAccepted: {
            var p = selectedFile.toString()
            if (p.indexOf("file://") === 0) p = p.substring(7)
            root.saveKeystoreRequested(p)
        }
    }
}
