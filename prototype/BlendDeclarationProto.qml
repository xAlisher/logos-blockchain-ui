import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

// ── BLEND tab · wizard step 1 — DECLARATION (studio prototype) ──────────────
// Mirrors the shipped module's `gates` phase (BlendView): CHECKS list rebuilt from
// state, each with a structured (i) and, on failure, the key/address to act on + a
// short fix + an action link (faucet / attest). Then WHAT YOU'LL PUBLISH AND LOCK
// (Identity · Address · Stake). Reachability uses the attest model (the node only
// binds udp/<port> once it's Core, so it can't be auto-verified before then).
// Studio-driven mock data; no backend. Handoff spec for the module implementation.
Item {
    id: root
    signal submitRequested()
    signal startNodeRequested()
    signal copyText(string t)

    // ── gate inputs (studio toggles) ──
    property bool gSynced: true
    property bool gFunded: true          // SDP funding key funded — pays the declaration fee
    property bool gStakeNote: true       // a node note is available to lock as stake
    property bool portListening: false   // a local listener holds the port
    property bool portAttested: true     // operator attested the router forward
    property bool gNetwork: true
    property bool slotFree: true
    property int withdrawEpoch: -1        // >=0 → a prior declaration is withdrawing
    property int mineInactiveSince: -1
    property string faucetMsg: ""
    property string phase: "idle"         // idle | submitting | submitted | error
    property string errorText: ""
    property int nodeStatus: 2            // -1/0 not started · 1 starting · 2 running · 4 stopped · 5 error
    property string nodeError: ""
    readonly property bool nodeUp: nodeStatus === 2

    // ── declaration data ──
    property string ipAddr: "88.19.213.99"
    property int blendPort: 3400
    property int noteCount: 1
    property int netCount: 4
    property string providerId: "601dcb79ef4986b5a7b786ac7d965562a065f1acc9dfa42ea8ecfd3e850802b5"
    property string zkId: "2ca45bc4fa5bfd02a4806229d3e7669a52e590ede065263d9ec7cd370cb33b13"
    property string sdpKey: "6c4665db63dc20197a32e3b063e45f5281f794db707dbfb5364640522438901b"
    property string lockNoteId: "1836184b81376b385bbf0961b6808f8e19f7f2d73a5f331824785d2b4c949b05"
    property string mineId: ""
    readonly property string locator: "/ip4/" + ipAddr + "/udp/" + blendPort + "/quic-v1"

    readonly property bool gPort: portListening || portAttested
    readonly property bool _declBlocks: !slotFree
    readonly property bool allGreen: gSynced && gFunded && gStakeNote && gPort && gNetwork && !_declBlocks
    function _elide(s) { return s.length > 20 ? s.substring(0, 10) + "…" + s.substring(s.length - 6) : s }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }
    function _gateAction(kind) {
        if (kind === "faucet") root.faucetMsg = qsTr("Requesting test funds…")
        else if (kind === "attest") root.portAttested = true
    }
    readonly property string docsUrl: "https://docs.logos.co/nodes/blend-core"

    // ── gate model — mirrors BlendView.gates ──
    readonly property var gates: {
        var g = [
        { ok: gSynced, label: qsTr("Node status"), val: gSynced ? qsTr("Online") : qsTr("Bootstrapping"),
          fix: qsTr("Wait for the node to finish syncing before declaring."), action: "", docs: "", kind: "", addr: "",
          info: ({ "title": qsTr("Node status"), "what": qsTr("Declaring needs a running, synced node — it signs the declaration, binds the Blend port and proves reachability."), "states": [({ "label": qsTr("Online"), "meaning": qsTr("Synced — ready to declare.") }), ({ "label": qsTr("Bootstrapping"), "meaning": qsTr("Still catching up — wait.") })], "docs": docsUrl }) },
        { ok: gFunded, label: qsTr("SDP funding key funded"), val: gFunded ? qsTr("500 LGO") : qsTr("0 LGO"),
          fix: qsTr("The declaration pays a small fee from your SDP funding key."), action: qsTr("Request test funds"), docs: "", kind: "faucet", addr: sdpKey,
          info: ({ "title": qsTr("SDP funding key"), "what": qsTr("Pays the fee to submit the declaration on-chain. Funded from the faucet or any wallet."), "states": [], "docs": docsUrl }) },
        { ok: gStakeNote, label: qsTr("Lockable stake note"), val: gStakeNote ? qsTr("%1 note(s) available").arg(noteCount) : qsTr("none"),
          fix: qsTr("Fund a node key so there's a note to lock as your provider stake."), action: "", docs: "", kind: "", addr: lockNoteId,
          info: ({ "title": qsTr("Lockable stake note"), "what": qsTr("Declaring locks one of your node's notes as the provider stake — bonded, not spent, and returned when you withdraw."), "states": [({ "label": qsTr("available"), "meaning": qsTr("A note is lockable.") }), ({ "label": qsTr("none"), "meaning": qsTr("Fund a node key.") })], "docs": docsUrl }) },
        { ok: gPort, label: qsTr("UDP %1 forwarded").arg(blendPort),
          val: gPort ? (portAttested && !portListening ? qsTr("confirmed") : qsTr("open")) : qsTr("needs your confirmation"),
          fix: qsTr("The node only opens udp/%1 once it's a Core provider, so this can't be auto-checked yet — that's expected. Make sure udp/%1 is forwarded to this machine on your router (see the guide), then mark it below.").arg(blendPort),
          action: qsTr("I've forwarded this port"), docs: docsUrl, kind: "attest", addr: locator,
          info: ({ "title": qsTr("Reachability (Blend port)"), "what": qsTr("Peers must be able to dial your Blend port. The node only opens udp/%1 once it's a Core provider, so it can't be auto-verified before then — confirm the router forward yourself.").arg(blendPort), "states": [({ "label": qsTr("open"), "meaning": qsTr("A local listener holds the port.") }), ({ "label": qsTr("confirmed"), "meaning": qsTr("You attested the router forward.") })], "docs": docsUrl }) },
        { ok: gNetwork, label: qsTr("Blend network size"), val: qsTr("%1 provider(s)").arg(netCount),
          fix: qsTr("Needs at least 2 active providers on the network."), action: "", docs: "", kind: "", addr: "",
          info: ({ "title": qsTr("Blend network size"), "what": qsTr("A mix needs a minimum number of active providers to form. Below it, Blend can't run."), "states": [({ "label": qsTr("≥ 2 providers"), "meaning": qsTr("A mix can form.") })], "docs": docsUrl }) }
        ]
        if (_declBlocks)
            g.push({ ok: false, label: qsTr("Declaration slot free"),
                val: withdrawEpoch >= 0 ? qsTr("withdrawing → clears epoch %1").arg(withdrawEpoch)
                    : (mineInactiveSince >= 0 ? qsTr("inactive since epoch %1").arg(mineInactiveSince) : qsTr("stale declaration on-chain")),
                fix: withdrawEpoch >= 0 ? qsTr("Your previous declaration is being withdrawn. A new one can't take until it clears at epoch %1 and the staked note unlocks — re-declare after that. Re-declaring now is a no-op.").arg(withdrawEpoch)
                    : qsTr("A stale declaration is still on-chain and makes a fresh declare a no-op. Withdraw it first, then re-declare once it clears (~2 epochs)."),
                action: withdrawEpoch >= 0 ? "" : qsTr("Withdraw stale declaration"), docs: "", kind: withdrawEpoch >= 0 ? "" : "withdraw", addr: mineId,
                info: ({ "title": qsTr("Declaration slot"), "what": qsTr("A node holds one Blend declaration at a time. While a previous one is withdrawing or stale, a fresh declare is a no-op until it clears."), "states": [({ "label": qsTr("free"), "meaning": qsTr("You can declare.") }), ({ "label": qsTr("withdrawing"), "meaning": qsTr("Wait for it to clear.") })], "docs": docsUrl }) })
        return g
    }

    // ── WHAT YOU'LL PUBLISH AND LOCK — Identity · Address · Stake ──
    readonly property var identityRows: [
        ({ "k": qsTr("Blend signing key"), "sub": qsTr("provider_id · your on-chain identity — the key that earns"), "v": _elide(providerId), "copyValue": providerId,
           "info": ({ "title": qsTr("Blend signing key (provider_id)"), "what": qsTr("Your node's on-chain Blend identity; in the referral program it's the key that accrues points."), "states": [], "docs": docsUrl }) }),
        ({ "k": qsTr("BlendZk key"), "sub": qsTr("zk_id · does the private mixing"), "v": _elide(zkId), "copyValue": zkId,
           "info": ({ "title": qsTr("BlendZk key (zk_id)"), "what": qsTr("Performs the zero-knowledge mixing. Published in the declaration."), "states": [], "docs": docsUrl }) }),
        ({ "k": qsTr("Service type"), "v": "BN", "copyValue": "",
           "info": ({ "title": qsTr("Service type"), "what": qsTr("Marks this SDP declaration as a Blend Network provider (BN)."), "states": [], "docs": docsUrl }) })
    ]
    readonly property var addressRows: [
        ({ "k": qsTr("Published address (locator)"), "sub": qsTr("forward THIS udp/%1 — not your 3000 blockchain port").arg(blendPort), "v": _elide(locator), "copyValue": locator, "pub": true,
           "info": ({ "title": qsTr("Published address (locator)"), "what": qsTr("The address peers use to reach your Blend port — your public IP + the Blend Core port (%1), written on-chain.").arg(blendPort), "states": [], "docs": docsUrl }) })
    ]
    readonly property var stakeRows: [
        ({ "k": qsTr("Note to lock"), "sub": qsTr("one of your node's notes — returned when you withdraw"), "v": lockNoteId.length ? _elide(lockNoteId) : qsTr("none yet"), "copyValue": lockNoteId,
           "info": ({ "title": qsTr("Stake"), "what": qsTr("Declaring bonds one note as your provider stake (Sybil resistance). Locked, not spent — returned ~2 epochs after you withdraw."), "states": [], "docs": docsUrl }) })
    ]

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
    component FieldRow: RowLayout {
        property string k; property string sub; property string v
        property string copyValue: ""; property var info: null; property bool pub: false
        Layout.fillWidth: true; spacing: Theme.spacing.small
        ColumnLayout {
            spacing: 1; Layout.fillWidth: true
            LogosText { Layout.fillWidth: true; text: k; color: Theme.palette.textSecondary; font.pixelSize: 11 }
            LogosText { visible: sub.length > 0; text: sub; color: Theme.palette.textTertiary; font.pixelSize: 11; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        }
        LogosText { Layout.alignment: Qt.AlignVCenter; text: v; color: pub ? Theme.palette.info : Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
        CopyDot { value: copyValue }
        InfoDot { payload: info }
    }
    component FieldBlock: LogosFrame {
        property string title: ""; property string desc: ""; property var rows: []
        Layout.fillWidth: true
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"; radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.tiny
                LogosText { text: title; color: Theme.palette.text; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                LogosText { visible: desc.length > 0; text: desc; color: Theme.palette.textTertiary; font.pixelSize: 11 } }
            Repeater { model: rows
                delegate: FieldRow { required property var modelData; k: modelData.k; sub: modelData.sub || ""; v: modelData.v; copyValue: modelData.copyValue || ""; info: modelData.info || null; pub: modelData.pub || false } }
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
                    LogosText {
                        text: root.nodeStatus === 5 ? qsTr("Node error") : root.nodeStatus === 1 ? qsTr("Node is starting…") : root.nodeStatus === 4 ? qsTr("Node is stopped") : qsTr("Node isn't running")
                        color: root.nodeStatus === 5 ? Theme.palette.error : Theme.palette.text
                        font.pixelSize: Theme.typography.primaryText; font.weight: Theme.typography.weightBold
                    }
                    LogosText {
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: root.nodeStatus === 1 ? qsTr("Declaration becomes available once the node is online — it needs a running node to sign the declaration, bind the Blend port, and confirm reachability.")
                            : qsTr("You can't declare Blend Core without a running node: declaring needs it to sign the declaration, bind the Blend port, and prove reachability. Start your node, then return here.")
                        color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosButton { visible: root.nodeStatus !== 1; text: qsTr("Start node"); variant: LogosButton.Variant.Primary; onClicked: root.startNodeRequested() }
                }
            }

            // ── CHECKS (gates) ──
            LogosText { visible: root.nodeUp; text: qsTr("CHECKS"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            ColumnLayout {
                visible: root.nodeUp
                Layout.fillWidth: true; spacing: Theme.spacing.small
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
                                readonly property color _pend: modelData.kind === "attest" ? Theme.palette.warning : Theme.palette.error
                                Layout.alignment: Qt.AlignTop; width: 18; height: 18; radius: 9
                                color: modelData.ok ? Theme.palette.success : "transparent"
                                border.color: modelData.ok ? Theme.palette.success : _pend; border.width: 2
                                Canvas {
                                    id: _chk; visible: modelData.ok; anchors.fill: parent; antialiasing: true
                                    readonly property color _stroke: Theme.palette.surfaceRaised
                                    onPaint: {
                                        var ctx = getContext("2d"); ctx.reset()
                                        var w = width, h = height
                                        ctx.strokeStyle = _stroke; ctx.lineWidth = 2.2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                                        ctx.beginPath(); ctx.moveTo(w * 0.30, h * 0.52); ctx.lineTo(w * 0.44, h * 0.66); ctx.lineTo(w * 0.72, h * 0.36); ctx.stroke()
                                    }
                                    onVisibleChanged: if (visible) requestPaint()
                                    Component.onCompleted: requestPaint()
                                }
                                LogosText { visible: !modelData.ok; anchors.centerIn: parent; text: "!"; color: parent._pend; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 1
                                RowLayout {
                                    Layout.fillWidth: true
                                    LogosText { text: modelData.label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium }
                                    Item { Layout.fillWidth: true }
                                    LogosText { text: modelData.val; color: modelData.ok ? Theme.palette.success : Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText }
                                    InfoDot { payload: modelData.info || null }
                                }
                                LogosText { visible: !modelData.ok; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: modelData.fix; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                // on-failure copyable key/address (not the faucet gate, which shows its key below)
                                RowLayout {
                                    visible: !modelData.ok && (modelData.addr || "").length > 0 && modelData.kind !== "faucet"
                                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny; spacing: Theme.spacing.small
                                    LogosText { Layout.fillWidth: true; text: root._elide(modelData.addr || ""); color: Theme.palette.textSecondary; font.pixelSize: 11; font.family: "monospace" }
                                    CopyDot { value: modelData.addr || "" }
                                }
                                // funding key shown on the faucet gate — send test LGO here from any wallet
                                ColumnLayout {
                                    visible: modelData.kind === "faucet" && root.sdpKey.length > 0
                                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny; spacing: 1
                                    LogosText { text: qsTr("Funding key — send test LGO here from any wallet:"); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                    RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.small
                                        LogosText { Layout.fillWidth: true; text: root.sdpKey; color: Theme.palette.textSecondary; font.pixelSize: 11; font.family: "monospace"; elide: Text.ElideMiddle }
                                        CopyDot { value: root.sdpKey } }
                                }
                                // docs link (copies the URL)
                                RowLayout {
                                    visible: !modelData.ok && (modelData.docs || "").length > 0
                                    Layout.fillWidth: true; spacing: Theme.spacing.small
                                    LogosText { Layout.fillWidth: true; text: modelData.docs || ""; font.pixelSize: 11; elide: Text.ElideRight; color: Theme.palette.info
                                                TapHandler { onTapped: root.copyText(modelData.docs || "") } }
                                    CopyDot { value: modelData.docs || "" }
                                }
                                // action link (faucet / attest / withdraw)
                                LogosText { visible: !modelData.ok && (modelData.action || "").length > 0; text: modelData.action; font.pixelSize: 11; color: Theme.palette.info
                                            TapHandler { onTapped: root._gateAction(modelData.kind) } }
                                // faucet feedback
                                LogosText { visible: modelData.kind === "faucet" && root.faucetMsg.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap
                                            text: root.faucetMsg; color: Theme.palette.text; font.pixelSize: 11 }
                            }
                        }
                    }
                }
                LogosText { visible: root.errorText.length > 0; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: root.errorText; color: Theme.palette.error; font.pixelSize: 11 }
            }

            // ── WHAT YOU'LL PUBLISH AND LOCK ──
            LogosText { visible: root.nodeUp; text: qsTr("WHAT YOU'LL PUBLISH AND LOCK"); color: Theme.palette.textTertiary; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
            FieldBlock { visible: root.nodeUp; title: qsTr("Identity"); rows: root.identityRows }
            FieldBlock { visible: root.nodeUp; title: qsTr("Address"); desc: qsTr("published on-chain, public"); rows: root.addressRows }
            FieldBlock { visible: root.nodeUp; title: qsTr("Stake"); desc: qsTr("locked, not spent"); rows: root.stakeRows }

            // ── footer: Fund keys + Submit ──
            RowLayout {
                visible: root.nodeUp
                Layout.fillWidth: true; Layout.bottomMargin: Theme.spacing.large; spacing: Theme.spacing.medium
                LogosText {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: root.phase === "submitted" ? qsTr("Declaration submitted — activating in ~2 epochs.")
                        : root.phase === "submitting" ? qsTr("Submitting declaration…")
                        : root.phase === "error" ? root.errorText
                        : root.allGreen ? qsTr("All checks passed — ready to declare.")
                        : qsTr("Resolve the checks above to declare.")
                    color: root.phase === "error" ? Theme.palette.error : (root.phase === "submitted" || root.allGreen) ? Theme.palette.success : Theme.palette.textTertiary
                    font.pixelSize: 11
                }
                LogosButton { visible: !root.allGreen; text: qsTr("Fund keys"); onClicked: root._gateAction("faucet") }
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
