import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

// ── BLEND tab · wizard step 2 — ACTIVATION (studio prototype) ───────────────
// The declaration is on-chain but dormant. It activates automatically at
// created + 2 epochs, PROVIDED the node stays reachable and keeps sending Active
// heartbeats. This step is a monitored wait, not an input form. Honest caveat:
// in 0.2.x the Active heartbeat is NOT work-verified — "active" means declared +
// heartbeating + reachable, not provably mixing. Studio-driven; no backend.
Item {
    id: root
    signal cancelRequested()
    signal startNodeRequested()
    signal copyText(string t)

    // ── studio-driven state ──
    property string subState: "activating"   // activating | stalled | done
    property real progress: 0.45             // 0..1 toward active
    property string etaText: qsTr("~1h 10m")
    property int createdEpoch: 151730
    property int activeEpoch: 151732
    property bool heartbeatOk: true
    property string heartbeatAge: qsTr("11s ago")
    property string natState: "reachable"    // reachable | unreachable
    property int nodeStatus: 2
    property string nodeError: ""
    readonly property bool nodeUp: nodeStatus === 2

    // ── declaration record (carried from step 1) ──
    property string declId: "8f2a1c47declaration90ee0044ab77c1b6d3e5f0a2b8c9d1e4f6072a3b5c8d9e1"
    property string txHash: "0x7c1b6d3e5f0a2b8c9d1e4f6072a3b5c8d9e1a4f6b8c0d2e5f7091a3c5e7092bd"
    property string locator: "/ip4/88.19.213.99/udp/3400/quic-v1"

    readonly property bool natOk: natState === "reachable"
    readonly property bool healthy: heartbeatOk && natOk && nodeUp
    function _elide(s) { return s.length > 24 ? s.substring(0, 12) + "…" + s.substring(s.length - 6) : s }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }
    readonly property string _docsBlend: "https://docs.logos.co/nodes/blend-core"

    component InfoDot: QQC.Button {
        property var payload: null
        visible: payload !== null
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 24; implicitHeight: 24
        display: QQC.AbstractButton.IconOnly; flat: true; padding: 3
        background: Rectangle { color: "transparent" }
        icon.source: Qt.resolvedUrl("../src/qml/icons/info.svg")
        icon.width: 16; icon.height: 16
        icon.color: hovered ? Theme.palette.primary : Theme.palette.textMuted
        onClicked: root._openInfo(payload)
    }
    component CopyDot: QQC.Button {
        property string value: ""
        visible: value.length > 0
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 24; implicitHeight: 24
        display: QQC.AbstractButton.IconOnly; flat: true; padding: 3
        background: Rectangle { color: "transparent" }
        icon.source: Qt.resolvedUrl("../src/qml/icons/copy.svg")
        icon.width: 16; icon.height: 16
        icon.color: hovered ? Theme.palette.primary : Theme.palette.textSecondary
        onClicked: root.copyText(value)
    }
    // label (left) · value (right, mono) · [copy] · (i)
    component KV: RowLayout {
        property string k; property string v; property string copyValue: ""; property var info: null
        property color valColor: Theme.palette.text
        Layout.fillWidth: true; spacing: Theme.spacing.small
        LogosText { Layout.fillWidth: true; text: k; color: Theme.palette.textSecondary; font.pixelSize: 11 }
        LogosText { Layout.alignment: Qt.AlignVCenter; text: v; color: valColor; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
        CopyDot { value: copyValue }
        InfoDot { payload: info }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: root.width - Theme.spacing.large * 2
            x: Theme.spacing.large
            spacing: Theme.spacing.large

            // ── node-not-running gate (dropping the node here stalls activation) ──
            LogosFrame {
                visible: !root.nodeUp
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.error
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.large
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    LogosText { text: root.nodeStatus === 5 ? qsTr("Node error — activation paused") : qsTr("Node isn't running — activation paused")
                        color: Theme.palette.error; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: root.nodeStatus === 5 ? qsTr("%1. Your declaration stays on-chain, but it can't activate while the node is down — no heartbeats are being sent. Resolve it soon.").arg(root.nodeError.length ? root.nodeError : qsTr("The node reported an error"))
                            : qsTr("Your declaration stays on-chain, but it can't activate while the node is down — no heartbeats are being sent. Start the node before the activation window passes.")
                        color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                    LogosButton { text: qsTr("Start node"); variant: LogosButton.Variant.Primary; onClicked: root.startNodeRequested() }
                }
            }

            // ── on-chain confirmation ──
            LogosText { text: qsTr("ON-CHAIN"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spacing.small
                        LogosText { text: "✓"; color: Theme.palette.success; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                        LogosText { Layout.fillWidth: true; text: qsTr("Declaration accepted on-chain"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                    }
                    KV { k: qsTr("Declaration ID"); v: root._elide(root.declId); copyValue: root.declId
                         info: { "title": qsTr("Declaration ID"), "what": qsTr("The on-chain record of your Blend provider declaration. Look it up in the explorer to see its state."), "states": [], "docs": root._docsBlend } }
                    KV { k: qsTr("Transaction"); v: root._elide(root.txHash); copyValue: root.txHash }
                    KV { k: qsTr("Created at epoch"); v: root.createdEpoch.toString(); copyValue: "" }
                    KV { k: qsTr("Service type"); v: "BN"; copyValue: "" }
                }
            }

            // ── activation progress ──
            LogosText { text: qsTr("ACTIVATION"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: root.subState === "stalled" ? Theme.palette.error : "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    RowLayout {
                        Layout.fillWidth: true; spacing: Theme.spacing.tiny
                        LogosText {
                            text: root.subState === "stalled" ? qsTr("Activation at risk") : qsTr("Activating…")
                            color: root.subState === "stalled" ? Theme.palette.error : Theme.palette.text
                            font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium
                        }
                        Item { Layout.fillWidth: true }
                        LogosText {
                            text: root.subState === "stalled" ? qsTr("paused") : qsTr("active at epoch %1 · %2 left").arg(root.activeEpoch).arg(root.etaText)
                            color: root.subState === "stalled" ? Theme.palette.error : Theme.palette.textTertiary; font.pixelSize: 11
                        }
                        InfoDot { payload: { "title": qsTr("Activation window"), "what": qsTr("A new declaration becomes active at created + 2 epochs (~2h on testnet). During the wait your node must stay reachable and keep sending Active heartbeats — miss either and the timer doesn't complete."), "states": [{ "label": qsTr("activating"), "meaning": qsTr("Counting down; node healthy.") }, { "label": qsTr("at risk"), "meaning": qsTr("Heartbeat missed or unreachable — fix before the window passes.") }], "docs": root._docsBlend } }
                    }
                    // progress track
                    Rectangle {
                        Layout.fillWidth: true; height: 6; radius: 3
                        color: Theme.palette.backgroundTertiary
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.progress)); height: parent.height; radius: 3
                            color: root.subState === "stalled" ? Theme.palette.error : Theme.palette.primary
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosText { text: qsTr("epoch %1 (created)").arg(root.createdEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                        Item { Layout.fillWidth: true }
                        LogosText { text: qsTr("epoch %1 (active)").arg(root.activeEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                    }
                }
            }

            // ── liveness the window depends on ──
            LogosText { text: qsTr("WHILE YOU WAIT — KEEP THESE GREEN"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            ColumnLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                Repeater {
                    model: [
                        { "ok": root.heartbeatOk, "label": qsTr("Active heartbeat"),
                          "val": root.heartbeatOk ? qsTr("Sending · last %1").arg(root.heartbeatAge) : qsTr("Missed"),
                          "fix": qsTr("The node sends periodic Active messages to prove it's still up. If they stop, the activation window won't complete. Keep the node running."),
                          "info": { "title": qsTr("Active heartbeat"), "what": qsTr("A periodic message the node emits to signal it's still an active provider. Required through the activation window and for the whole life of the declaration."), "states": [{ "label": qsTr("Sending"), "meaning": qsTr("Node is heartbeating normally.") }, { "label": qsTr("Missed"), "meaning": qsTr("Node down or stalled — activation pauses.") }], "docs": root._docsBlend } },
                        { "ok": root.natOk, "label": qsTr("Reachability (AutoNAT)"),
                          "val": root.natOk ? qsTr("Reachable") : qsTr("Dropped"),
                          "fix": qsTr("Peers must still be able to dial your Blend port. If your IP changed or the forward broke, fix it before the window passes."),
                          "info": { "title": qsTr("Reachability (AutoNAT)"), "what": qsTr("Peers keep dialing your published address to confirm you're reachable. If it drops during activation, you'll declare but never go active."), "states": [{ "label": qsTr("Reachable"), "meaning": qsTr("Peers can reach you.") }, { "label": qsTr("Dropped"), "meaning": qsTr("Re-check NAT / IP.") }], "docs": root._docsBlend } }
                    ]
                    delegate: LogosFrame {
                        required property var modelData
                        Layout.fillWidth: true
                        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                        radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                        contentItem: RowLayout {
                            spacing: Theme.spacing.medium
                            Rectangle {
                                Layout.alignment: Qt.AlignTop; width: 18; height: 18; radius: 9
                                color: modelData.ok ? Theme.palette.success : "transparent"; border.width: 2
                                border.color: modelData.ok ? Theme.palette.success : Theme.palette.error
                                LogosText { anchors.centerIn: parent; visible: modelData.ok; text: "✓"; color: Theme.palette.surfaceRaised; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                                LogosText { anchors.centerIn: parent; visible: !modelData.ok; text: "!"; color: Theme.palette.error; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.spacing.tiny
                                    LogosText { text: modelData.label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                                    Item { Layout.fillWidth: true }
                                    LogosText { text: modelData.val; color: modelData.ok ? Theme.palette.success : Theme.palette.error; font.pixelSize: Theme.typography.secondaryText }
                                    InfoDot { payload: modelData.info }
                                }
                                LogosText { visible: !modelData.ok; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                            }
                        }
                    }
                }
            }

            // ── honest caveat ──
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: LogosText {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: qsTr("Note: in this release the Active heartbeat is not work-verified. \"Active\" means declared, heartbeating and reachable — not proof that your node is mixing traffic. Verified work is planned for a later version.")
                    color: Theme.palette.textTertiary; font.pixelSize: 11
                }
            }

            // ── footer ──
            RowLayout {
                Layout.fillWidth: true; Layout.bottomMargin: Theme.spacing.large
                LogosText {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.subState === "stalled" ? qsTr("Activation paused — resolve the red item above.")
                        : qsTr("No action needed. This advances to Active once the network admits your node as Core (after the ~2-epoch window), not on the clock alone.")
                    color: root.subState === "stalled" ? Theme.palette.error : Theme.palette.textTertiary
                    font.pixelSize: 11
                }
                LogosButton { text: qsTr("Cancel declaration"); onClicked: root.cancelRequested() }
            }
        }
    }

    V.InfoModal { id: infoModal; onCopyText: (t) => root.copyText(t) }
}
