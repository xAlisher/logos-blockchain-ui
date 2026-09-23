import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

// ── BLEND tab · wizard step 1 — DECLARATION (studio prototype) ──────────────
// CHECKS (gates) first — each with a structured (i) and, on failure, the key/
// address to act on (copyable) + a short fix. Then FIELDS in per-object blocks
// (Identity · Address · Stake), keys copyable. Reachability is a proper AutoNAT
// check (David, 2026-09-22). Two keys must be funded (BlendZk + SdpFunding, per the
// operator guide). Studio-driven; no backend. Spec: docs/blend-core-address-check-spec.md.
Item {
    id: root
    signal submitRequested()
    signal startNodeRequested()
    signal copyText(string t)

    // ── gate inputs (studio toggles these) ──
    property bool gSynced: true
    property bool gZkFunded: true    // BlendZk key funded — holds the note locked as your stake
    property bool gFunded: true      // SDP funding key funded — pays the declaration fee
    property bool gNetwork: true
    property bool slotFree: true
    property string natState: "reachable"   // checking | reachable | notlistening | unreachable
    property bool ipDynamic: false
    property string phase: "idle"           // idle | submitting | submitted | error
    property string errorText: ""
    property int nodeStatus: 2               // -1/0 not started · 1 starting · 2 running · 4 stopped · 5 error
    property string nodeError: ""
    readonly property bool nodeUp: nodeStatus === 2

    // ── declaration data ──
    property string ipAddr: "88.19.213.99"
    property int blendPort: 3400
    property string providerId: "601dcb79ef4986b5a7b786ac7d965562a065f1acc9dfa42ea8ecfd3e850802b5"
    property string zkId: "2ca45bc4fa5bfd02a4806229d3e7669a52e590ede065263d9ec7cd370cb33b13"
    property string sdpKey: "6c4665db63dc20197a32e3b063e45f5281f794db707dbfb5364640522438901b"
    property string stakeNote: "1836184b81376b385bbf0961b6808f8e19f7f2d73a5f331824785d2b4c949b05"
    property string stakeValue: "500 LGO"
    readonly property string locator: "/ip4/" + ipAddr + "/udp/" + blendPort + "/quic-v1"

    readonly property bool portOk: natState === "reachable"
    readonly property bool allGreen: gSynced && gZkFunded && gFunded && gNetwork && portOk && slotFree
    function _elide(s) { return s.length > 20 ? s.substring(0, 10) + "…" + s.substring(s.length - 6) : s }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }

    readonly property string _docsBlend: "https://docs.logos.co/nodes/blend-core"
    readonly property string _docsPort: "https://docs.logos.co/nodes/blend-port-forwarding"

    // ── checks (gates first). `addr`+`fix` drive the on-failure action row. ──
    readonly property var checks: {
        var natVal = natState === "checking" ? qsTr("checking…")
                   : natState === "reachable" ? qsTr("Reachable")
                   : natState === "notlistening" ? qsTr("Core not running")
                   : qsTr("Not reachable")
        var natFix = natState === "checking" ? qsTr("Asking other nodes to dial you back on udp/%1 (AutoNAT)…").arg(blendPort)
                   : natState === "notlistening" ? qsTr("Blend Core isn't bound to udp/%1 yet. Start Core — this is NOT a router problem.").arg(blendPort)
                   : qsTr("Forward inbound udp/%1 (your Blend port — not your 3000 blockchain port) to this machine, then re-check.").arg(blendPort)
        var g = [
        { ok: gSynced, label: qsTr("Node status"), pending: false, val: gSynced ? qsTr("Online") : qsTr("Bootstrapping"),
          fix: qsTr("Wait for the node to finish syncing before declaring."), addr: "", copyable: false,
          info: { title: qsTr("Node status"), what: qsTr("Declaring needs a running node that's caught up to the chain tip — it signs the declaration, binds the Blend port, and confirms reachability."),
                  states: [{ label: qsTr("Online"), meaning: qsTr("Synced — ready to declare.") }, { label: qsTr("Bootstrapping"), meaning: qsTr("Still catching up — wait.") }, { label: qsTr("Not running / Stopped"), meaning: qsTr("Start the node — declaration is unavailable until it's up.") }, { label: qsTr("Error"), meaning: qsTr("Resolve the node error first.") }], docs: _docsBlend } },
        { ok: gZkFunded, label: qsTr("BlendZk key funded"), pending: false, val: gZkFunded ? qsTr("Funded, 500 LGO — 1 note to lock") : qsTr("Not funded, 0 LGO"),
          fix: qsTr("Request test funds to your BlendZk key from the faucet — the declaration locks one of its notes as your stake."), addr: zkId, copyable: true,
          info: { title: qsTr("BlendZk key"), what: qsTr("Declaring locks one note held by your BlendZk key as your provider stake (Sybil resistance). Fund it so there's a note to lock — the note is returned when you withdraw."),
                  states: [{ label: qsTr("Funded"), meaning: qsTr("A note is lockable — good to go.") }, { label: qsTr("Not funded"), meaning: qsTr("Request test funds to the BlendZk key.") }], docs: _docsBlend } },
        { ok: gFunded, label: qsTr("SDP funding key funded"), pending: false, val: gFunded ? qsTr("Funded, 500 LGO") : qsTr("Not funded, 0 LGO"),
          fix: qsTr("Request test funds to your SDP funding key from the faucet — it pays the declaration fee."), addr: sdpKey, copyable: true,
          info: { title: qsTr("SDP funding key"), what: qsTr("Pays the fee to submit the declaration on-chain. Funded separately from the BlendZk key (both are required)."),
                  states: [{ label: qsTr("Funded"), meaning: qsTr("Fee payable — good to go.") }, { label: qsTr("Not funded"), meaning: qsTr("Request test funds to the SDP funding key.") }], docs: _docsBlend } },
        { ok: portOk, label: qsTr("UDP/%1 (AutoNAT)").arg(blendPort), pending: natState === "checking", val: natVal, fix: natFix, addr: locator, copyable: true,
          info: { title: qsTr("Reachability (AutoNAT)"), what: qsTr("Other nodes dial your Blend port back to confirm you're reachable from the internet. Your published address must be dialable, or you declare but never earn."),
                  states: [{ label: qsTr("checking…"), meaning: qsTr("AutoNAT probe in flight.") }, { label: qsTr("reachable"), meaning: qsTr("Peers confirmed they can reach you.") }, { label: qsTr("Core not running"), meaning: qsTr("Nothing bound to the port — start Blend Core, not the router.") }, { label: qsTr("not reachable"), meaning: qsTr("Forward udp/%1 (the Blend port, not 3000).").arg(blendPort) }], docs: _docsPort } },
        { ok: gNetwork, label: qsTr("Blend network size"), pending: false, val: gNetwork ? qsTr("4 providers") : qsTr("1 provider"),
          fix: qsTr("Needs at least 2 active providers on the network — wait for more to join."), addr: "", copyable: false,
          info: { title: qsTr("Blend network size"), what: qsTr("A mix needs a minimum number of active providers to form. Below it, Blend can't run."),
                  states: [{ label: qsTr("≥ 2 providers"), meaning: qsTr("A mix can form.") }, { label: qsTr("1 provider"), meaning: qsTr("Too small — wait.") }], docs: _docsBlend } }
        ]
        if (!slotFree)
            g.push({ ok: false, label: qsTr("Declaration slot free"), pending: false, val: qsTr("withdrawing"), addr: "", copyable: false,
                     fix: qsTr("A previous declaration is being withdrawn. A new one can't take until it clears and the staked note unlocks — re-declaring now is a no-op."),
                     info: { title: qsTr("Declaration slot"), what: qsTr("A node holds one Blend declaration at a time. While a previous one is withdrawing, a fresh declare is a no-op until it clears."),
                             states: [{ label: qsTr("free"), meaning: qsTr("You can declare.") }, { label: qsTr("withdrawing"), meaning: qsTr("Wait for it to clear, then re-declare.") }], docs: _docsBlend } })
        return g
    }

    // ── field blocks (one card per object) ──
    readonly property var identityRows: [
        { k: qsTr("Blend signing key"), sub: qsTr("provider_id · your referral identity — the key that earns"), v: _elide(providerId), copyValue: providerId, info: { title: qsTr("Blend signing key (provider_id)"), what: qsTr("Your node's Blend signing key. It is your on-chain identity and, in the referral program, the key that accrues points. Not funded."), states: [{ label: qsTr("published"), meaning: qsTr("Written into the declaration, publicly readable.") }], docs: _docsBlend } },
        { k: qsTr("BlendZk key"), sub: qsTr("zk_id · does the mixing and holds your stake"), v: _elide(zkId), copyValue: zkId, info: { title: qsTr("BlendZk key (zk_id)"), what: qsTr("Performs the private mixing (zero-knowledge) AND holds the note locked as your provider stake. Distinct from your signing key; must be funded."), states: [], docs: _docsBlend } },
        { k: qsTr("Service type"), sub: "", v: "BN", copyValue: "", info: { title: qsTr("Service type"), what: qsTr("Marks this SDP declaration as a Blend Network provider (BN)."), states: [], docs: _docsBlend } }
    ]
    readonly property var addressRows: [
        { k: qsTr("Address published on-chain (public)"), sub: qsTr("Blend Core port %1 — forward THIS, not your 3000 blockchain port").arg(blendPort), v: locator, copyValue: locator, pub: true, info: { title: qsTr("Published address (locator)"), what: qsTr("The address peers use to reach your Blend port — your public IP + the Blend Core port (%1), NOT the 3000 blockchain port. Written on-chain, world-readable.").arg(blendPort), states: [{ label: qsTr("reachable"), meaning: qsTr("Peers can dial it.") }, { label: qsTr("unreachable"), meaning: qsTr("Declared but no traffic reaches you — fix NAT / start Core.") }], docs: _docsPort } }
    ]
    readonly property var stakeRows: [
        { k: qsTr("Amount locked (not spent)"), sub: qsTr("returned when you withdraw"), v: stakeValue, copyValue: "", info: { title: qsTr("Stake"), what: qsTr("One note held by your BlendZk key, bonded as your provider stake. Locked, not spent — returned when you withdraw."), states: [{ label: qsTr("locked"), meaning: qsTr("Bonded for the life of the declaration.") }, { label: qsTr("unlocked"), meaning: qsTr("Returned ~2 epochs after withdrawal.") }], docs: _docsBlend } },
        { k: qsTr("Locked note"), sub: qsTr("held by your BlendZk key"), v: _elide(stakeNote), copyValue: stakeNote, info: null }
    ]

    // reusable structured (i) — matches the dashboard tiles
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

    // reusable copy button (visible glyph, like the (i))
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

    // reusable field row: label/sub (left) · value (right) · [copy] · (i)
    component FieldRow: RowLayout {
        property string k; property string sub; property string v
        property string copyValue: ""; property var info: null; property bool pub: false
        Layout.fillWidth: true; spacing: Theme.spacing.small
        ColumnLayout {
            spacing: 1; Layout.fillWidth: true
            LogosText { Layout.fillWidth: true; text: k; color: Theme.palette.textSecondary; font.pixelSize: 11 }
            LogosText { visible: sub.length > 0; text: sub; color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        LogosText { Layout.alignment: Qt.AlignVCenter; text: v; color: pub ? (root.portOk ? Theme.palette.success : Theme.palette.textTertiary) : Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
        CopyDot { value: copyValue }
        InfoDot { payload: info }
    }

    // reusable object block (a card with a title + rows)
    component FieldBlock: LogosFrame {
        property string title: ""; property string desc: ""; property var rows: []
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.tiny
                LogosText { text: title; color: Theme.palette.text; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosText { visible: desc.length > 0; text: desc; color: Theme.palette.textTertiary; font.pixelSize: 11 }
            }
            Repeater {
                model: rows
                delegate: FieldRow { required property var modelData; k: modelData.k; sub: modelData.sub; v: modelData.v; copyValue: modelData.copyValue; info: modelData.info; pub: modelData.pub || false }
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
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: root.nodeStatus === 5 ? Theme.palette.error : "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.large
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    LogosText {
                        text: root.nodeStatus === 5 ? qsTr("Node error") : root.nodeStatus === 1 ? qsTr("Node is starting…") : root.nodeStatus === 4 ? qsTr("Node is stopped") : qsTr("Node isn't running")
                        color: root.nodeStatus === 5 ? Theme.palette.error : Theme.palette.text
                        font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold
                    }
                    LogosText {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: root.nodeStatus === 5 ? qsTr("%1. Resolve it, then come back to declare Blend Core.").arg(root.nodeError.length ? root.nodeError : qsTr("The node reported an error"))
                            : root.nodeStatus === 1 ? qsTr("Declaration becomes available once the node is online — it needs a running node to sign the declaration, bind the Blend port, and confirm reachability.")
                            : qsTr("You can't declare Blend Core without a running node: declaring needs it to sign the declaration, bind the Blend port, and prove reachability. Start your node, then return here.")
                        color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosButton { visible: root.nodeStatus !== 1; text: qsTr("Start node"); variant: LogosButton.Variant.Primary; onClicked: root.startNodeRequested() }
                }
            }

            // ── CHECKS ──
            LogosText { visible: root.nodeUp; text: qsTr("CHECKS"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            ColumnLayout {
                visible: root.nodeUp
                Layout.fillWidth: true; spacing: Theme.spacing.small
                Repeater {
                    model: root.checks
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
                                border.color: modelData.ok ? Theme.palette.success : modelData.pending ? Theme.palette.textTertiary : Theme.palette.error
                                LogosText { anchors.centerIn: parent; visible: modelData.ok; text: "✓"; color: Theme.palette.surfaceRaised; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                                LogosText { anchors.centerIn: parent; visible: !modelData.ok && !modelData.pending; text: "!"; color: Theme.palette.error; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                                LogosText { anchors.centerIn: parent; visible: modelData.pending; text: "…"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true; spacing: Theme.spacing.tiny
                                    LogosText { text: modelData.label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                                    Item { Layout.fillWidth: true }
                                    LogosText { text: modelData.val; color: modelData.ok ? Theme.palette.success : modelData.pending ? Theme.palette.textTertiary : Theme.palette.error; font.pixelSize: Theme.typography.secondaryText }
                                    InfoDot { payload: modelData.info }
                                }
                                LogosText { visible: !modelData.ok; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: modelData.fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                // on-failure action: the key/address to act on, copyable
                                RowLayout {
                                    visible: !modelData.ok && modelData.copyable && modelData.addr.length > 0
                                    Layout.fillWidth: true; spacing: Theme.spacing.tiny
                                    LogosText { text: root._elide(modelData.addr); color: Theme.palette.textSecondary; font.pixelSize: 11; font.family: "monospace" }
                                    CopyDot { value: modelData.addr }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }
                }
                LogosText { visible: root.portOk && root.ipDynamic; Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: qsTr("⚠ Reachable now, but your IP looks dynamic — home connections can change it and your published address would go stale (you'd drop from Core). Consider a static IP or pinning external_address.")
                    color: Theme.palette.warning; font.pixelSize: 11 }
            }

            // ── FIELDS — one block per object ──
            LogosText { visible: root.nodeUp; text: qsTr("WHAT YOU'LL PUBLISH AND LOCK"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            FieldBlock { visible: root.nodeUp; title: qsTr("Identity"); rows: root.identityRows }
            FieldBlock { visible: root.nodeUp; title: qsTr("Address"); desc: qsTr("published on-chain, public"); rows: root.addressRows }
            FieldBlock { visible: root.nodeUp; title: qsTr("Stake"); desc: qsTr("locked, not spent"); rows: root.stakeRows }

            // ── footer ──
            RowLayout {
                visible: root.nodeUp
                Layout.fillWidth: true; Layout.bottomMargin: Theme.spacing.large
                LogosText {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.phase === "submitted" ? qsTr("Declaration submitted — activating in ~2 epochs.")
                        : root.phase === "submitting" ? qsTr("Submitting declaration…")
                        : root.phase === "error" ? root.errorText
                        : root.allGreen ? qsTr("All checks passed — ready to declare.")
                        : qsTr("Resolve the red checks above to declare.")
                    color: root.phase === "error" ? Theme.palette.error : (root.phase === "submitted" || root.allGreen) ? Theme.palette.success : Theme.palette.textTertiary
                    font.pixelSize: 11
                }
                LogosButton {
                    text: root.phase === "submitting" ? qsTr("Submitting…") : root.phase === "submitted" ? qsTr("Submitted") : qsTr("Submit declaration")
                    variant: LogosButton.Variant.Primary
                    enabled: root.allGreen && root.phase === "idle"
                    onClicked: root.submitRequested()
                }
            }
        }
    }

    V.InfoModal { id: infoModal; onCopyText: (t) => root.copyText(t) }
}
