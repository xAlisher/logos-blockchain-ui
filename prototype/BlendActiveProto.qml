import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

// ── BLEND tab · wizard step 3 — ACTIVE (studio prototype) ───────────────────
// Steady state: the node is an active Blend provider. Shows the live provider
// record (nonce increments = the on-chain liveness proof), the referral tie-in
// (provider_id is the key that earns), and the off-ramp: Withdraw stake sets
// withdraw_at; the locked note unlocks ~2 epochs later. Studio-driven; no backend.
Item {
    id: root
    signal withdrawRequested()
    signal restartRequested()
    signal copyText(string t)

    // ── studio-driven state ──
    property string subState: "active"   // active | withdrawing | withdrawn
    property int nonce: 47
    property string nonceAge: qsTr("just now")
    property bool heartbeatOk: true
    property string natState: "reachable"
    property string upSince: qsTr("2h 40m")
    property int createdEpoch: 151730
    property int activeEpoch: 151732
    property int withdrawAtEpoch: 151760

    // ── provider record ──
    property string providerId: "601dcb79ef4986b5a7b786ac7d965562a065f1acc9dfa42ea8ecfd3e850802b5"
    property string zkId: "2ca45bc4fa5bfd02a4806229d3e7669a52e590ede065263d9ec7cd370cb33b13"
    property string stakeNote: "1836184b81376b385bbf0961b6808f8e19f7f2d73a5f331824785d2b4c949b05"
    property string stakeValue: "500 LGO"
    property string locator: "/ip4/88.19.213.99/udp/3400/quic-v1"

    readonly property bool live: subState === "active"
    readonly property bool natOk: natState === "reachable"
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
    component KV: RowLayout {
        property string k; property string sub: ""; property string v; property string copyValue: ""; property var info: null
        property color valColor: Theme.palette.text
        Layout.fillWidth: true; spacing: Theme.spacing.small
        ColumnLayout {
            spacing: 1; Layout.fillWidth: true
            LogosText { Layout.fillWidth: true; text: k; color: Theme.palette.textSecondary; font.pixelSize: 11 }
            LogosText { visible: sub.length > 0; Layout.fillWidth: true; text: sub; color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap }
        }
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

            // ── big status ──
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: root.live ? Theme.palette.success : "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.large
                contentItem: RowLayout {
                    spacing: Theme.spacing.medium
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter; width: 40; height: 40; radius: 20
                        color: root.live ? Theme.palette.success : root.subState === "withdrawing" ? Theme.palette.warning : Theme.palette.backgroundTertiary
                        LogosText { anchors.centerIn: parent; text: root.live ? "✓" : root.subState === "withdrawing" ? "↩" : "—"; color: root.live ? Theme.palette.surfaceRaised : Theme.palette.text; font.pixelSize: 18; font.weight: Theme.typography.weightBold }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        LogosText {
                            text: root.live ? qsTr("Blend Core active") : root.subState === "withdrawing" ? qsTr("Withdrawing") : qsTr("Withdrawn")
                            color: Theme.palette.text; font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold
                        }
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.live ? qsTr("Mixing for %1 · active since epoch %2").arg(root.upSince).arg(root.activeEpoch)
                                : root.subState === "withdrawing" ? qsTr("Stopped mixing · note unlocks at epoch %1").arg(root.withdrawAtEpoch)
                                : qsTr("Note returned to your BlendZk key")
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                        }
                    }
                }
            }

            // ── liveness ──
            LogosText { visible: root.subState !== "withdrawn"; text: qsTr("LIVENESS"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            LogosFrame {
                visible: root.subState !== "withdrawn"
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    KV {
                        k: qsTr("Provider nonce"); sub: qsTr("one signal of activity — not proof on its own; read it with peers + membership below")
                        v: root.nonce.toString(); valColor: root.live ? Theme.palette.success : Theme.palette.text
                        info: { "title": qsTr("Provider nonce"), "what": qsTr("An on-chain counter that advances with accepted activity. A rising nonce is one signal you're live, but it is not sufficient by itself — liveness = current Core membership AND healthy peers AND recent accepted activity, read together."), "states": [{ "label": qsTr("rising"), "meaning": qsTr("Activity being accepted.") }, { "label": qsTr("stalled"), "meaning": qsTr("No recent accepted activity — check membership and peers.") }], "docs": root._docsBlend } }
                    KV { k: qsTr("Last update"); v: root.nonceAge; copyValue: "" }
                    KV { k: qsTr("Active heartbeat"); v: root.heartbeatOk ? qsTr("Sending") : qsTr("Missed"); valColor: root.heartbeatOk ? Theme.palette.success : Theme.palette.error }
                    KV { k: qsTr("Reachability (AutoNAT)"); v: root.natOk ? qsTr("Reachable") : qsTr("Dropped"); valColor: root.natOk ? Theme.palette.success : Theme.palette.error }
                }
            }

            // ── provider record ──
            LogosText { text: qsTr("PROVIDER RECORD"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    KV { k: qsTr("Blend signing key"); sub: qsTr("provider_id · the key that earns referral points"); v: root._elide(root.providerId); copyValue: root.providerId
                         info: { "title": qsTr("Blend signing key (provider_id)"), "what": qsTr("Your on-chain provider identity. In the referral program this is the key that accrues points while you stay active."), "states": [], "docs": root._docsBlend } }
                    KV { k: qsTr("BlendZk key"); sub: qsTr("zk_id · does the mixing and holds your stake"); v: root._elide(root.zkId); copyValue: root.zkId }
                    KV { k: qsTr("Service type"); v: "BN"; copyValue: "" }
                    KV { k: qsTr("Published address"); v: root.locator; copyValue: root.locator; valColor: root.natOk ? Theme.palette.success : Theme.palette.textTertiary }
                    KV { k: qsTr("Created / active epoch"); v: root.createdEpoch + " / " + root.activeEpoch; copyValue: "" }
                    KV { visible: root.subState !== "active"; k: qsTr("Withdraw at epoch"); v: root.withdrawAtEpoch.toString(); copyValue: ""
                         info: { "title": qsTr("withdraw_at"), "what": qsTr("The epoch at which your withdrawal takes effect. Until then you're winding down; after it the staked note unlocks."), "states": [], "docs": root._docsBlend } }
                }
            }

            // ── stake ──
            LogosText { text: qsTr("STAKE"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    KV { k: root.subState === "withdrawn" ? qsTr("Amount unlocked") : qsTr("Amount locked (not spent)")
                         sub: root.subState === "withdrawn" ? qsTr("returned to your BlendZk key") : qsTr("returned when you withdraw")
                         v: root.stakeValue; valColor: root.subState === "withdrawn" ? Theme.palette.success : Theme.palette.text
                         info: { "title": qsTr("Stake"), "what": qsTr("One note held by your BlendZk key, bonded for the life of the declaration. Locked, not spent — returned ~2 epochs after you withdraw."), "states": [{ "label": qsTr("locked"), "meaning": qsTr("Bonded while active.") }, { "label": qsTr("unlocked"), "meaning": qsTr("Returned after withdrawal.") }], "docs": root._docsBlend } }
                    KV { k: qsTr("Locked note"); sub: qsTr("held by your BlendZk key"); v: root._elide(root.stakeNote); copyValue: root.stakeNote }
                }
            }

            // ── off-ramp ──
            LogosFrame {
                Layout.fillWidth: true; Layout.bottomMargin: Theme.spacing.large
                backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: RowLayout {
                    spacing: Theme.spacing.medium
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        LogosText {
                            text: root.subState === "withdrawn" ? qsTr("Declaration closed") : root.subState === "withdrawing" ? qsTr("Withdrawal in progress") : qsTr("Withdraw your stake")
                            color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium
                        }
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.subState === "withdrawn" ? qsTr("Your note is unlocked. Declare again to rejoin Blend Core.")
                                : root.subState === "withdrawing" ? qsTr("You've stopped mixing and stopped earning. Your note unlocks at epoch %1 (~2 epochs after the request).").arg(root.withdrawAtEpoch)
                                : qsTr("Stops mixing and stops earning. Sets withdraw_at; your locked note returns to your BlendZk key ~2 epochs later.")
                            color: Theme.palette.textTertiary; font.pixelSize: 11
                        }
                    }
                    LogosButton {
                        visible: root.subState === "active"
                        text: qsTr("Withdraw stake"); onClicked: root.withdrawRequested()
                    }
                    LogosButton {
                        visible: root.subState === "withdrawn"
                        text: qsTr("Declare again"); variant: LogosButton.Variant.Primary; onClicked: root.restartRequested()
                    }
                }
            }
        }
    }

    V.InfoModal { id: infoModal; onCopyText: (t) => root.copyText(t) }
}
