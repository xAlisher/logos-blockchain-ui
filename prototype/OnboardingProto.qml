import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// ── NODE ONBOARDING — prototype (studio only) ──────────────────────────────
// A first-run flow for a fresh Logos node, prototyped ahead of the real UI.
// Maps to onboarding-map.md: it surfaces the steps the module/CLI API already
// supports but the shipped UI never shows — the keystore-backup step (#5/#12)
// and the participation step (#11) are the design-value screens here.
// Self-contained mock state; no backend. Emits finished()/exitRequested().
Item {
    id: root
    signal finished(bool keysBackedUp)           // → dashboard; banner shows unless keys were backed up
    signal exitRequested()

    // ── flow state (mock) ──
    // Default path is ONE CLICK: "Start node" with defaults. The steps below only
    // appear under "Advanced". Only USER ACTIONS are steps — start / sync / aging are
    // node-driven and live on the dashboard lifecycle lane, not here.
    property bool   advanced: false              // false = one-click landing; true = the stepper
    property int    step: 0
    readonly property var stepNames: [qsTr("Setup"), qsTr("Network"), qsTr("Keys"), qsTr("Fund")]
    property string mode: ""                     // "generate" | "existing"
    property string deployment: "default"        // "default" | "custom"
    property bool   keysSaved: false             // ticked the backup box in the Keys step
    property bool   funded: false
    property string fundBalance: ""

    // real keystore identities the generator creates (cli/config/keystore.rs)
    readonly property var keystore: [
        { name: "NetworkSwarm",  role: qsTr("libp2p peer identity"),        hex: "ed25519:8f2a…c41d" },
        { name: "BlendSigning",  role: qsTr("Blend message signing"),       hex: "ed25519:1b90…7e02" },
        { name: "BlendZk",       role: qsTr("Blend zero-knowledge key"),    hex: "zk:44c8…a1f3" },
        { name: "LeaderFunding", role: qsTr("Funds block proposing"),       hex: "zk:9d17…be55" },
        { name: "SdpFunding",    role: qsTr("Funds service declaration"),   hex: "zk:2f6e…08ab" },
        { name: "PoWClaim",      role: qsTr("Claims mining rewards"),        hex: "zk:73aa…d290" },
        { name: "VaucherMaster", role: qsTr("Wallet master key"),           hex: "zk:c05b…1147" },
        { name: "Stake",         role: qsTr("Stake / consensus eligibility"),hex: "zk:e8f1…6632" }
    ]

    function _canContinue() {
        switch (step) {
        case 0: return mode.length > 0
        case 2: return keysSaved
        default: return true          // Network + Fund always advanceable (Fund is skippable)
        }
    }
    function _startDefault() { root.finished(false) }              // one click: defaults → node, banner will nag for backup
    function _openAdvanced()  { root.mode = "generate"; root.step = 0; root.advanced = true }
    function _next() {
        if (step < 3) { step += 1 }
        else root.finished(root.keysSaved)   // "Start node" from advanced; backed up ⇒ no banner
    }
    function _back() { if (step > 0) step -= 1; else root.advanced = false }   // step 0 back ⇒ landing

    Timer { id: fundSeq; interval: 1600; onTriggered: { root.funded = true; root.fundBalance = "1 000 LGO" } }

    // ── selectable card used on the Setup / Network screens ──
    component ChoiceCard: LogosFrame {
        id: cc
        property string heading: ""
        property string body: ""
        property bool selected: false
        property bool recommended: false
        property bool arrow: false        // landing cards route on click → show "→", no radio
        signal picked()
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: selected ? Theme.palette.primary : Theme.palette.border
        radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        contentItem: RowLayout {
            spacing: Theme.spacing.medium
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                RowLayout {
                    spacing: Theme.spacing.small
                    LogosText { text: cc.heading; color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                    LogosBadge { visible: cc.recommended; text: qsTr("Recommended"); color: Theme.palette.success }
                }
                LogosText { text: cc.body; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            }
            LogosText {
                visible: cc.arrow; text: "→"; color: Theme.palette.textSecondary
                font.pixelSize: 20; Layout.alignment: Qt.AlignVCenter
            }
            Rectangle {
                visible: !cc.arrow
                width: 22; height: 22; radius: 11; Layout.alignment: Qt.AlignVCenter
                color: cc.selected ? Theme.palette.primary : "transparent"
                border.color: cc.selected ? Theme.palette.primary : Theme.palette.border; border.width: 2
                LogosText { anchors.centerIn: parent; visible: cc.selected; text: "✓"; color: "#FFFFFF"; font.pixelSize: 13; font.weight: Theme.typography.weightBold }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cc.picked() }
    }

    // ── layout: header (progress) · body (screens) · footer (nav) ──
    ColumnLayout {
        anchors.fill: parent; anchors.margins: Theme.spacing.xlarge; spacing: Theme.spacing.large

        // header: title + exit + step rail
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
            LogosButton { visible: root.advanced; text: qsTr("Exit setup"); onClicked: root.exitRequested() }
        }

        // step rail — only in the advanced flow
        RowLayout {
            visible: root.advanced
            Layout.fillWidth: true; spacing: Theme.spacing.small
            Repeater {
                model: root.stepNames
                delegate: ColumnLayout {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true; spacing: 4
                    Rectangle {
                        Layout.fillWidth: true; height: 4; radius: 2
                        color: index <= root.step ? Theme.palette.primary : Theme.palette.border
                    }
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

                    // ── LANDING (one click) — options route on click, no radios ──
                    ColumnLayout {
                        spacing: Theme.spacing.medium
                        LogosText { text: qsTr("How do you want to start?"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                        ChoiceCard {
                            heading: qsTr("Quick start"); recommended: true; arrow: true
                            body: qsTr("Generate a default testnet config and start the node. Back up your keys right after.")
                            onPicked: root._startDefault()
                        }
                        ChoiceCard {
                            heading: qsTr("Advanced setup"); arrow: true
                            body: qsTr("Choose your config, network and peers, and back up your keys during setup.")
                            onPicked: root._openAdvanced()
                        }
                    }

                    // ── ADVANCED (the stepper) ──
                    StackLayout {
                        width: parent.width
                        currentIndex: root.step

                    // 0 · SETUP ────────────────────────────────────────────
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
                            body: qsTr("Point at a user config and keystore you already have (e.g. moving to a new machine).")
                            selected: root.mode === "existing"; onPicked: root.mode = "existing"
                        }
                        // point-to-your-files — only when using an existing config
                        ColumnLayout {
                            visible: root.mode === "existing"
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.small
                            LogosText { text: qsTr("Point to your files"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacing.medium
                                LogosText { text: qsTr("User config"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
                                LogosTextField { Layout.fillWidth: true; text: "~/.logos/node/user_config.yaml" }
                                LogosButton { text: qsTr("Browse") }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: Theme.spacing.medium
                                LogosText { text: qsTr("Keystore"); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.preferredWidth: 90 }
                                LogosTextField { Layout.fillWidth: true; text: "~/.logos/node/keystore.yaml" }
                                LogosButton { text: qsTr("Browse") }
                            }
                            LogosText { text: qsTr("Your keys stay where they are — the node reads them from this path."); color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        }
                    }

                    // 1 · NETWORK ──────────────────────────────────────────
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
                        LogosText { text: qsTr("Bootstrap peers"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium; Layout.topMargin: Theme.spacing.small }
                        LogosText { text: qsTr("The node dials these on start to find the chain (one multiaddr per line)."); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                        LogosTextArea {
                            Layout.fillWidth: true; Layout.preferredHeight: 84
                            text: "/ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWQ8v9…bootstrap"
                        }
                    }

                    // 2 · KEYS (the backup gap) ────────────────────────────
                    ColumnLayout {
                        spacing: Theme.spacing.medium
                        LogosText { text: qsTr("Back up your node keys"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                        LogosNotice {
                            Layout.fillWidth: true; severity: LogosNotice.Warning
                            title: qsTr("Shown once")
                            message: qsTr("Generating your config created a keystore of 8 keys. They control your node's identity, stake, and rewards. Save them now — there is no way to recover them later.")
                        }
                        LogosFrame {
                            Layout.fillWidth: true
                            backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing.small
                                Repeater {
                                    model: root.keystore
                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true; spacing: Theme.spacing.medium
                                        ColumnLayout {
                                            Layout.preferredWidth: 180; spacing: 0
                                            LogosText { text: modelData.name; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                                            LogosText { text: modelData.role; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                        }
                                        LogosText { text: modelData.hex; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace"; Layout.fillWidth: true; elide: Text.ElideRight }
                                        LogosCopyButton { value: modelData.hex }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.spacing.medium
                            LogosButton { text: qsTr("Download keystore.yaml") }
                            Item { Layout.fillWidth: true }
                        }
                        LogosCheckbox {
                            text: qsTr("I've backed up my keys somewhere safe")
                            checked: root.keysSaved
                            onToggled: root.keysSaved = checked
                        }
                    }

                    // 3 · FUND ─────────────────────────────────────────────
                    ColumnLayout {
                        spacing: Theme.spacing.medium
                        LogosText { text: qsTr("Fund your node"); color: Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                            text: qsTr("A node needs stake before it can propose blocks. On testnet you request test funds for your funding key.")
                        }
                        LogosFrame {
                            Layout.fillWidth: true
                            backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                            contentItem: RowLayout {
                                spacing: Theme.spacing.medium
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    LogosText { text: qsTr("LeaderFunding key"); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                    LogosText { text: "zk:9d17…be55"; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
                                }
                                LogosCopyButton { value: "zk:9d17be55" }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: Theme.spacing.medium
                            LogosButton {
                                text: root.funded ? qsTr("Funds received") : qsTr("Request test funds")
                                variant: LogosButton.Variant.Primary; enabled: !root.funded
                                onClicked: fundSeq.restart()
                            }
                            LogosText { visible: root.funded; text: qsTr("Balance: %1").arg(root.fundBalance); color: Theme.palette.success; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                            Item { Layout.fillWidth: true }
                        }
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textTertiary; font.pixelSize: 11
                            text: qsTr("Optional: you can skip and fund later from the dashboard.")
                        }
                        LogosNotice {
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; severity: LogosNotice.Info
                            title: qsTr("What happens after Start")
                            message: qsTr("Starting hands off to the dashboard. The node syncs, then your stake ages ~2 epochs before it can propose — automatic on testnet. The lifecycle lane tracks it.")
                        }
                    }
                    }
                }
            }
        }

        // footer nav — advanced flow only (landing routes on click)
        RowLayout {
            visible: root.advanced
            Layout.fillWidth: true; spacing: Theme.spacing.medium
            LogosButton { text: qsTr("Back"); onClicked: root._back() }   // step 0 → returns to landing
            Item { Layout.fillWidth: true }
            LogosText {
                visible: !root._canContinue()
                color: Theme.palette.textTertiary; font.pixelSize: 11; Layout.alignment: Qt.AlignVCenter
                text: root.step === 2 ? qsTr("Confirm you saved your keys to continue") : ""
            }
            LogosButton {
                text: root.step === 3 ? qsTr("Start node") : qsTr("Continue")
                variant: LogosButton.Variant.Primary
                enabled: root._canContinue()
                onClicked: root._next()
            }
        }
    }
}
