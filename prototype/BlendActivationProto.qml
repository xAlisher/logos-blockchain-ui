import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

// ── BLEND tab · wizard step 2 — ACTIVATION (studio prototype) ───────────────
// Mirrors the shipped module's activation phase (BlendView): ON-CHAIN block
// (declaration accepted + id/tx/created/service), an ACTIVATION progress toward
// created+2 (time-based, white bar), then WHILE YOU WAIT — KEEP THESE GREEN:
// Active heartbeat + Reachability (attest/prober). In 0.2.x the Active heartbeat
// is NOT work-verified — "active" means declared + heartbeating + reachable, not
// proof of mixing. Studio-driven mock data; no backend. Handoff spec.
Item {
    id: root
    signal cancelRequested()
    signal startNodeRequested()
    signal copyText(string t)

    // ── studio-driven state ──
    property int createdEpoch: 44
    property int coreEpoch: 46                // active-at epoch (created + 2)
    property real activationProgress: 0.45   // 0..1 toward active
    property string activationTimeLeft: qsTr("~1h 10m")
    property bool heartbeatOk: true
    property string reachVerdict: "reachable"  // reachable | unreachable | unknown | ""
    property bool reachChecking: false
    property bool portListening: false
    property bool portAttested: true
    property int blendPort: 3400
    property int nodeStatus: 2
    property string nodeError: ""
    property string errorText: ""
    readonly property bool nodeUp: nodeStatus === 2

    // ── on-chain record ──
    property string mineId: "cdd5bdd7dc2fe4fb9dfb2205d67e6d2b58458d5e9f1691d15de43543f9bb27c3"
    property string txId: "c733a1646e5930b139af6a6a6b38944b1b5ce9e4e343e72b54f986329a853368"

    function _elide(s) { return s.length > 20 ? s.substring(0, 10) + "…" + s.substring(s.length - 6) : s }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }
    readonly property string docsUrl: "https://docs.logos.co/nodes/blend-core"

    component InfoDot: QQC.Button {
        property var payload: null
        visible: payload !== null
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 24; implicitHeight: 24
        display: QQC.AbstractButton.IconOnly; flat: true; padding: 3
        background: Rectangle { color: "transparent" }
        icon.source: Qt.resolvedUrl("../src/qml/icons/info.svg"); icon.width: 16; icon.height: 16
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
        icon.source: Qt.resolvedUrl("../src/qml/icons/copy.svg"); icon.width: 16; icon.height: 16
        icon.color: hovered ? Theme.palette.primary : Theme.palette.textSecondary
        onClicked: root.copyText(value)
    }
    // on-chain KV row (label · value mono · [copy] · (i))
    component KV: RowLayout {
        property string k; property string v; property string copyValue: ""; property var info: null
        Layout.fillWidth: true; Layout.minimumHeight: 22; spacing: Theme.spacing.small
        LogosText { Layout.fillWidth: true; text: k; color: Theme.palette.textSecondary; font.pixelSize: 11 }
        LogosText { Layout.alignment: Qt.AlignVCenter; text: v; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
        CopyDot { value: copyValue }
        InfoDot { payload: info }
    }
    // liveness row — mirrors BlendView.LivenessRow
    component LivenessRow: LogosFrame {
        id: lr
        property bool ok: false
        property bool warn: false
        property string label: ""
        property string okText: ""
        property string badText: ""
        property string fix: ""
        property var info: null
        property string action: ""
        signal acted()
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
        contentItem: RowLayout {
            spacing: Theme.spacing.medium
            Rectangle {
                Layout.alignment: Qt.AlignTop; width: 18; height: 18; radius: 9
                color: lr.ok ? Theme.palette.success : "transparent"; border.width: 2
                border.color: lr.ok ? Theme.palette.success : lr.warn ? Theme.palette.warning : Theme.palette.error
                LogosText { anchors.centerIn: parent; visible: lr.ok; text: "✓"; color: Theme.palette.surfaceRaised; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosText { anchors.centerIn: parent; visible: !lr.ok; text: lr.warn ? "?" : "!"; color: lr.warn ? Theme.palette.warning : Theme.palette.error; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    LogosText { Layout.fillWidth: true; text: lr.label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                    LogosText { text: lr.ok ? lr.okText : lr.badText; color: lr.ok ? Theme.palette.success : lr.warn ? Theme.palette.warning : Theme.palette.error; font.pixelSize: Theme.typography.secondaryText }
                    InfoDot { payload: lr.info }
                }
                LogosText { visible: !lr.ok && lr.fix.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: lr.fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                LogosText { visible: !lr.ok && lr.action.length > 0; text: lr.action; font.pixelSize: 11; color: Theme.palette.info
                            TapHandler { onTapped: lr.acted() } }
            }
        }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: root.width - Theme.spacing.large * 2
            x: Theme.spacing.large
            spacing: Theme.spacing.large

            // ── node-not-running gate ──
            LogosFrame {
                visible: !root.nodeUp
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.large
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: root.nodeStatus === 5 ? Theme.palette.error : "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.large
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    LogosText { text: root.nodeStatus === 5 ? qsTr("Node error") : root.nodeStatus === 1 ? qsTr("Node is starting…") : root.nodeStatus === 4 ? qsTr("Node is stopped") : qsTr("Node isn't running")
                                color: root.nodeStatus === 5 ? Theme.palette.error : Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap
                                text: qsTr("Activation pauses while the node is down — it must stay online and reachable through the window. Start your node, then return here.")
                                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                    LogosButton { visible: root.nodeStatus !== 1; text: qsTr("Start node"); variant: LogosButton.Variant.Primary; onClicked: root.startNodeRequested() }
                }
            }

            ColumnLayout {
                visible: root.nodeUp
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.large; spacing: Theme.spacing.medium

                // ── ON-CHAIN ──
                LogosText { text: qsTr("ON-CHAIN"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame {
                    Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.small
                            LogosText { text: "✓"; color: Theme.palette.success; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold }
                            LogosText { Layout.fillWidth: true; text: qsTr("Declaration accepted on-chain"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium } }
                        KV { k: qsTr("Declaration ID"); v: root._elide(root.mineId); copyValue: root.mineId
                             info: ({ "title": qsTr("Declaration ID"), "what": qsTr("The on-chain record of your Blend provider declaration."), "states": [], "docs": root.docsUrl }) }
                        KV { visible: root.txId.length > 0; k: qsTr("Transaction"); v: root._elide(root.txId); copyValue: root.txId }
                        KV { visible: root.createdEpoch >= 0; k: qsTr("Created at epoch"); v: "" + root.createdEpoch; copyValue: "" }
                        KV { k: qsTr("Service type"); v: "BN"; copyValue: "" }
                    }
                }

                // ── ACTIVATION ──
                LogosText { visible: root.coreEpoch >= 0; text: qsTr("ACTIVATION"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosFrame {
                    visible: root.coreEpoch >= 0
                    Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.tiny
                            LogosText { text: qsTr("Activating…"); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                            Item { Layout.fillWidth: true }
                            LogosText { text: root.activationTimeLeft.length ? qsTr("active at epoch %1 · %2").arg(root.coreEpoch).arg(root.activationTimeLeft) : qsTr("active at epoch %1").arg(root.coreEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                            InfoDot { payload: ({ "title": qsTr("Activation window"), "what": qsTr("A new declaration becomes active at created + 2 epochs, provided the node stays reachable and keeps sending Active heartbeats. Membership, not the clock alone, decides."), "states": [], "docs": root.docsUrl }) } }
                        Rectangle { Layout.fillWidth: true; height: 6; radius: 3; color: Theme.palette.backgroundTertiary
                            Rectangle { width: parent.width * root.activationProgress; height: parent.height; radius: 3; color: Theme.palette.text } }
                        RowLayout { Layout.fillWidth: true
                            LogosText { text: qsTr("epoch %1 (created)").arg(root.createdEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                            Item { Layout.fillWidth: true }
                            LogosText { text: qsTr("epoch %1 (active)").arg(root.coreEpoch); color: Theme.palette.textTertiary; font.pixelSize: 11 } }
                    }
                }

                // ── WHILE YOU WAIT — KEEP THESE GREEN ──
                LogosText { text: qsTr("WHILE YOU WAIT — KEEP THESE GREEN"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LivenessRow {
                    ok: root.heartbeatOk
                    label: qsTr("Active heartbeat"); okText: qsTr("Sending"); badText: qsTr("Not sending")
                    fix: qsTr("The node emits periodic Active messages while it's up. If they stop, activation won't complete — keep the node running.")
                    info: ({ "title": qsTr("Active heartbeat"), "what": qsTr("A periodic message the node emits to signal it's a live provider. Required through the activation window and for the life of the declaration. Not work-verified in this release — it means declared + heartbeating + reachable, not proof of mixing."), "states": [({ "label": qsTr("Sending"), "meaning": qsTr("Node is heartbeating.") }), ({ "label": qsTr("Not sending"), "meaning": qsTr("Node down or stalled — activation pauses.") })], "docs": root.docsUrl })
                }
                LivenessRow {
                    readonly property bool _verified: root.reachVerdict === "reachable"
                    readonly property bool _failed: root.reachVerdict === "unreachable"
                    ok: !_failed && (_verified || root.portListening || root.portAttested)
                    warn: !ok && !_failed
                    label: qsTr("Reachability (Blend port)")
                    okText: _verified ? qsTr("Reachable") : root.portListening ? qsTr("Listening") : qsTr("Confirmed")
                    badText: root.reachChecking ? qsTr("Checking…") : _failed ? qsTr("Not reachable") : qsTr("Needs confirmation")
                    fix: _failed ? qsTr("The prober couldn't reach udp/%1 — fix your router's port-forward, then re-check.").arg(root.blendPort)
                        : qsTr("Have the prober dial your Blend port for a real verdict, or attest the forward if it can't reach you.")
                    action: root.reachChecking ? "" : (root.reachVerdict === "unknown" ? qsTr("I've forwarded this port") : qsTr("Check reachability"))
                    onActed: { if (root.reachVerdict === "unknown") root.portAttested = true; else root.reachVerdict = "reachable" }
                    info: ({ "title": qsTr("Reachability (Blend port)"), "what": qsTr("Peers must be able to dial your Blend port (udp/%1) or you declare but never earn. The node has no built-in AutoNAT verdict for it, so this uses Core membership, a local listener, an external prober (with your consent), or your attestation.").arg(root.blendPort), "states": [({ "label": qsTr("Reachable (verified)"), "meaning": qsTr("An external prober dialed your port and got the nonce back.") }), ({ "label": qsTr("Reachable"), "meaning": qsTr("You're a current Core member, so peers reach you.") }), ({ "label": qsTr("Needs confirmation"), "meaning": qsTr("Not verified yet — run the check or attest the forward.") }), ({ "label": qsTr("Not reachable"), "meaning": qsTr("The prober couldn't reach the port — fix the forward.") })], "docs": root.docsUrl })
                }

                LogosText { visible: root.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.errorText; color: Theme.palette.error; font.pixelSize: 11 }

                // cancel (studio)
                RowLayout {
                    Layout.fillWidth: true; Layout.bottomMargin: Theme.spacing.large
                    Item { Layout.fillWidth: true }
                    LogosButton { text: qsTr("Cancel"); onClicked: root.cancelRequested() }
                }
            }
        }
    }

    V.InfoModal { id: infoModal; onCopyText: (t) => root.copyText(t) }
}
