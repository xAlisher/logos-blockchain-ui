import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// ── ENABLE / MANAGE BLEND CORE — prototype modal (studio only) ──────────────
// Full Blend provider lifecycle (epic #89) as a single local phase machine:
//   gates → enabling → activated →(Done: reachedCore)  |  core → disabling → disabled →(Done: disabled)
// Gates + stages mirror the real declaration proven on sneg. Self-contained mock
// state; no backend. Emits closed()/reachedCore()/disabled().
Item {
    id: root
    signal closed()
    signal declared()                  // enable submitted → node is "activating"
    signal reachedCore()
    signal disabled()

    property string blendState: "edge" // node lifecycle: edge | coredeclared | core (drives entry phase)
    property int withdrawEpoch: -1     // >=0 ⇒ our declaration is withdrawing, clears at this epoch

    // ── mock gate state (the studio toggles these to demo red/green) ──
    property bool gSynced: true
    property bool gFunded: true
    property bool gStakeNote: true
    property bool gPort: false          // the hard gate (port-forward) — red by default
    property bool gNetwork: true
    // A fresh declare only takes when no stale declaration is still on-chain — a withdrawing one makes
    // /blend/join a no-op until it clears. gSlotFree blocks Enable while that's true (mirrors the fork).
    readonly property bool _declBlocks: withdrawEpoch >= 0
    readonly property bool gSlotFree: !_declBlocks
    readonly property bool allGreen: gSynced && gFunded && gStakeNote && gPort && gNetwork && gSlotFree

    // ── single phase machine ──
    // gates | enabling | activated | core | disabling | disabled
    property string phase: "gates"
    property int step: 0               // enabling sub-step: 0 submit · 1 in-block · 2 activating
    property int _mockEpoch: 26

    // Every open starts clean and picks the entry phase from the node's lifecycle state.
    onVisibleChanged: if (visible) {
        root.step = 0
        // Core / declared-on-chain → the "core" manage view (declared reads Edge but is still on-chain);
        // otherwise the gates checklist (where the slot gate blocks re-declare while withdrawing).
        root.phase = (root.blendState === "core" || root.blendState === "coredeclared") ? "core" : "gates"
    }

    function _enable()  { if (allGreen && phase === "gates") { step = 0; phase = "enabling"; declared() } }
    function _disable() { if (phase === "core") phase = "disabling" }
    function _done()    { if (phase === "activated") reachedCore(); else if (phase === "disabled") disabled(); closed() }

    Timer {   // enable pacing (real activation is HOURS — 2 epochs — hence "safe to close")
        interval: 1400; repeat: true; running: root.phase === "enabling"
        onTriggered: { if (root.step < 2) root.step += 1; else root.phase = "activated" }
    }
    Timer {   // disable pacing
        interval: 1400; repeat: false; running: root.phase === "disabling"
        onTriggered: root.phase = "disabled"
    }

    readonly property var gates: {
        var g = [
        { ok: gSynced,    label: qsTr("Node synced"),            val: gSynced ? qsTr("Online") : qsTr("Bootstrapping"),
          fix: qsTr("Wait for the node to finish syncing before declaring."), action: "", docs: "" },
        { ok: gFunded,    label: qsTr("SDP funding key funded"), val: gFunded ? qsTr("1000 LGO") : qsTr("0 LGO"),
          fix: qsTr("The declaration pays a small fee from your SDP funding key."), action: qsTr("Request test funds"), docs: "" },
        { ok: gStakeNote, label: qsTr("Lockable stake note"),   val: gStakeNote ? qsTr("1 note ≥ min-stake") : qsTr("none"),
          fix: qsTr("Fund a node key so there's a note to lock as your provider stake."), action: "", docs: "" },
        { ok: gPort,      label: qsTr("UDP 3400 reachable"),    val: gPort ? qsTr("open") : qsTr("closed"),
          fix: qsTr("Forward inbound udp/3400 to this machine on your router. The app can't open it — see the guide."),
          action: qsTr("Port-forward guide"), docs: "https://docs.logos.co/nodes/blend-port-forwarding" },
        { ok: gNetwork,   label: qsTr("Blend network size"),    val: gNetwork ? qsTr("4 providers") : qsTr("1 provider"),
          fix: qsTr("Needs at least 2 active providers on the network."), action: "", docs: "" }
        ]
        // Only shown when a stale declaration actually blocks a fresh declare (here: withdrawing).
        if (_declBlocks)
            g.push({ ok: false, label: qsTr("Declaration slot free"),
                     val: qsTr("withdrawing → clears epoch %1").arg(withdrawEpoch),
                     fix: qsTr("Your previous declaration is being withdrawn. A new one can't take until it clears at epoch %1 and the staked note unlocks — re-declare after that. Re-declaring now is a no-op.").arg(withdrawEpoch),
                     action: "", docs: "" })
        return g
    }

    // ── backdrop ──
    Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
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
                    LogosText { text: (root.phase === "core" || root.phase === "activated" || root.phase === "disabling") ? qsTr("Blend Core") : qsTr("Enable Blend Core")
                                color: Theme.palette.text; font.pixelSize: Theme.typography.titleText; font.weight: Theme.typography.weightBold }
                    LogosText { text: qsTr("Become a Blend Network core provider — mixes your proposals for proposer privacy.");
                                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
                Item {   // close — icon button, not a big square
                    Layout.alignment: Qt.AlignTop; implicitWidth: 28; implicitHeight: 28
                    LogosText { anchors.centerIn: parent; text: "✕"; font.pixelSize: 15
                                color: closeMa.containsMouse ? Theme.palette.text : Theme.palette.textSecondary }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closed() }
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
                                Layout.alignment: Qt.AlignTop; width: 18; height: 18; radius: 9
                                color: modelData.ok ? Theme.palette.success : "transparent"
                                border.color: modelData.ok ? Theme.palette.success : Theme.palette.error; border.width: 2
                                // OK: a checkmark knocked out of the green disc (drawn in the row's own
                                // background colour → reads as a transparent cut-out), pixel-centred.
                                Canvas {
                                    visible: modelData.ok; anchors.fill: parent; antialiasing: true
                                    readonly property color _stroke: Theme.palette.surfaceRaised
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.reset()
                                        ctx.strokeStyle = _stroke; ctx.lineWidth = 2.2
                                        ctx.lineCap = "round"; ctx.lineJoin = "round"
                                        ctx.beginPath()
                                        ctx.moveTo(width * 0.30, height * 0.52)
                                        ctx.lineTo(width * 0.44, height * 0.66)
                                        ctx.lineTo(width * 0.72, height * 0.36)
                                        ctx.stroke()
                                    }
                                    onVisibleChanged: if (visible) requestPaint()
                                    Component.onCompleted: requestPaint()
                                }
                                LogosText { visible: !modelData.ok; anchors.centerIn: parent; text: "!"; color: Theme.palette.error; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
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
                                RowLayout {
                                    visible: !modelData.ok && (modelData.docs || "").length > 0
                                    Layout.fillWidth: true; spacing: Theme.spacing.small
                                    LogosLink { Layout.fillWidth: true; text: modelData.action || modelData.docs; font.pixelSize: 11; elide: Text.ElideRight; onActivated: gcb.copy() }
                                    LogosCopyButton { id: gcb; value: modelData.docs || ""; Layout.alignment: Qt.AlignVCenter }
                                }
                                LogosLink { visible: !modelData.ok && (modelData.docs || "").length === 0 && (modelData.action || "").length > 0
                                            text: modelData.action; font.pixelSize: 11; onActivated: {} }
                            }
                        }
                    }
                }
            }

            // ── enabling progress (phase: enabling) ──
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                visible: root.phase === "enabling"
                LogosText { text: root.step === 0 ? qsTr("Submitting declaration…")
                                 : root.step === 1 ? qsTr("Included in a block")
                                 : qsTr("Activating — Core at epoch %1 (~%2h)").arg(root._mockEpoch + 2).arg(20)
                            color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightMedium }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.step === 0 ? qsTr("Signing the declaration from your node's blend keys.")
                                 : root.step === 1 ? qsTr("Declaration is on-chain (tx a1b2…c3d4).")
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
                        Rectangle { Layout.alignment: Qt.AlignVCenter; width: 18; height: 18; radius: 9; color: "#d9a521" }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 1
                            LogosText { text: qsTr("Active — mixing your proposals"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                            LogosText { text: qsTr("3 core peers this epoch · emitting the active heartbeat"); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                        }
                    }
                }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: qsTr("Disabling withdraws your Blend declaration and unlocks the note you staked. You stop mixing and revert to Edge at the next epoch — rewards you already earned are unaffected.")
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
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
                LogosButton { visible: root.phase === "enabling" || root.phase === "disabling"; text: qsTr("Close"); onClicked: root.closed() }
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
