import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls
import "../src/qml/views" as V

// ── BLEND tab · wizard step 3 — ACTIVE (studio prototype) ───────────────────
// Synced to the shipped module's BlendView active view: one continuous dashboard-style
// tile grid (no section-label dividers), a Messages row (per-epoch), a Core-nodes table
// with API/Log/Bootstrap source tags, and the off-ramp. Honest copy — no "mixing" claim,
// all values neutral/white. Studio-driven mock data; no backend.
Item {
    id: root
    signal withdrawRequested()
    signal restartRequested()
    signal copyText(string t)

    // ── studio-driven state ──
    property string subState: "active"   // active | withdrawing | withdrawn
    property int nonce: 0
    property bool heartbeatOk: true
    property string natState: "reachable"   // reachable | unreachable
    property int createdEpoch: 44
    property int activeEpoch: 46
    property int withdrawAtEpoch: 48
    property int epoch: 46

    // ── provider record ──
    property string providerId: "601dcb79ef4986b5a7b786ac7d965562a065f1acc9dfa42ea8ecfd3e850802b5"
    property string zkId: "2ca45bc4fa5bfd02a4806229d3e7669a52e590ede065263d9ec7cd370cb33b13"
    property string stakeNote: "744a4b64918a3f0961b6808f8e19f7f2d73a5f331824785d2b4c949bf04c29"
    property string locator: "/ip4/88.19.213.99/udp/3400/quic-v1"

    // ── messages (per-epoch, from node logs in the real module) ──
    property string sendWindow: "0 sent · 1 processed · 1 cover"
    property int proposalsEpoch: 3
    property int directEpoch: 1
    property int connectedPeers: 3

    // ── core-node roster (real module merges API + node log; mock here) ──
    readonly property var corePeers: [
        ({ id: "12D3KooWSQc7CcGtvWDPF1yCbBthFnQjprfCVHmfmNDUrSmqQsU1", address: "/ip4/65.109.51.37/udp/50002/quic-v1", sources: ["API","Log","Bootstrap"], status: "Connected", self: false }),
        ({ id: "12D3KooWQXJavMDTRscjauFSgVAB1VLB6Rzpy2uY5SU9Tk7927tb", address: "/ip4/65.109.51.37/udp/3402/quic-v1",  sources: ["API","Log","Bootstrap"], status: "Connected", self: false }),
        ({ id: "12D3KooWKmoKQqLzfjLxdNyhDPQJwrx8KUahQ6p1Q6TDjqivL97U", address: "/ip4/178.238.235.164/udp/3400/quic-v1", sources: ["API","Log"], status: "Connected", self: false }),
        ({ id: "12D3KooWGHZf9ReRgfXSYYZjzhy5QJgk98fT2DUqnevvQ26iCnQ4", address: "/ip4/88.19.213.99/udp/3400/quic-v1",   sources: ["Log"], status: "In set", self: true }),
        ({ id: "12D3KooWJRGau8M1rjT7R5e4YYsgdFhsMX35nRDtMwCDjxQkXAHz", address: "/ip4/65.109.51.37/udp/3401/quic-v1",  sources: ["Log","Bootstrap"], status: "In set", self: false }),
        ({ id: "12D3KooWFzxpUHfox7sTYBfM5JBRknTGD3BXF3j2bzstPXxVz5a2", address: "/ip4/180.93.113.125/udp/3400/quic-v1", sources: ["Log"], status: "In set", self: false }),
        ({ id: "12D3KooWHsqZLW7PyTb8Bw58LYSepLD5DYx1hVUoCHEDn9ucCWQj", address: "/ip4/212.227.95.210/udp/3400/quic-v1", sources: ["Log"], status: "In set", self: false }),
        ({ id: "12D3KooWLSJaHwocWCq1M7zTdcvxYvGVafGv1ARWKFrFzq2TT2TG", address: "/ip4/152.53.157.210/udp/5/quic-v1",    sources: ["Log"], status: "Unreachable", self: false })
    ]

    readonly property bool live: subState === "active"
    readonly property bool natOk: natState === "reachable"
    readonly property bool activityAccepted: nonce > 0
    readonly property int _tileMin: 240
    readonly property int _mixed: Math.max(0, proposalsEpoch - directEpoch)
    function _elide(s) { return s.length > 24 ? s.substring(0, 12) + "…" + s.substring(s.length - 6) : s }
    function _openInfo(i) { if (i) { infoModal.info = i; infoModal.open() } }
    readonly property string _docsBlend: "https://docs.logos.co/nodes/blend-core"

    // (i) — 16×16 bordered "i", matching the dashboard tiles / the shipped module.
    component Info: Rectangle {
        id: ib
        signal clicked()
        readonly property bool hovered: ma.containsMouse
        width: 16; height: 16; radius: 8; color: "transparent"; border.width: 1
        border.color: hovered ? Theme.palette.text : Qt.rgba(Theme.palette.textTertiary.r, Theme.palette.textTertiary.g, Theme.palette.textTertiary.b, 0.35)
        LogosText { anchors.centerIn: parent; text: "i"; font.pixelSize: 9; color: ib.hovered ? Theme.palette.text : Theme.palette.textMuted }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }
    component CopyGlyph: Canvas {
        implicitWidth: 16; implicitHeight: 16
        property color stroke: Theme.palette.textMuted
        onPaint: {
            var ctx = getContext("2d"); ctx.reset();
            ctx.strokeStyle = stroke; ctx.lineWidth = 1.3; ctx.lineJoin = "round"; ctx.lineCap = "round";
            var r = 2, x = 1, y = 1, s = 9;
            ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + s, y, x + s, y + s, r); ctx.arcTo(x + s, y + s, x, y + s, r);
            ctx.arcTo(x, y + s, x, y, r); ctx.arcTo(x, y, x + s, y, r); ctx.closePath(); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(10, 5); ctx.lineTo(14 - r, 5); ctx.arcTo(14, 5, 14, 14, r);
            ctx.arcTo(14, 14, 5, 14, r); ctx.lineTo(5, 14); ctx.lineTo(5, 10); ctx.stroke();
        }
    }
    // Tile — faithful replica of the Node dashboard Block (label + (i) row / value / sub + copy).
    component Tile: LogosFrame {
        id: tile
        property string label: ""
        property string value: ""
        property string sub: ""
        property var info: null
        property string copyValue: ""
        property bool mono: false
        property string actionText: ""
        signal actionClicked()
        property bool _copied: false
        Timer { id: copiedTimer; interval: 1400; onTriggered: tile._copied = false }
        Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.minimumWidth: root._tileMin
        backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
        radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        implicitHeight: 108
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            RowLayout { Layout.fillWidth: true
                LogosText { text: tile.label; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                Item { Layout.fillWidth: true }
                Info { visible: tile.info != null; Layout.alignment: Qt.AlignTop; onClicked: root._openInfo(tile.info) } }
            RowLayout { Layout.fillWidth: true; spacing: 0
                LogosText { Layout.fillWidth: true; text: tile.value; color: Theme.palette.text; font.pixelSize: 24; font.weight: Theme.typography.weightBold
                            elide: Text.ElideRight; font.family: tile.mono ? "monospace" : Qt.application.font.family } }
            RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 16; spacing: Theme.spacing.small
                LogosText { visible: tile.sub.length > 0; text: tile.sub; color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; elide: Text.ElideRight; Layout.alignment: Qt.AlignVCenter }
                LogosText { visible: tile.actionText.length > 0; text: tile.actionText; color: Theme.palette.info; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter
                            TapHandler { onTapped: tile.actionClicked() } }
                CopyGlyph { visible: tile.copyValue.length > 0; Layout.alignment: Qt.AlignVCenter
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.copyText(tile.copyValue); tile._copied = true; copiedTimer.restart() } } }
                LogosText { visible: tile._copied; text: qsTr("Copied"); color: Theme.palette.success; font.pixelSize: Theme.typography.secondaryText; Layout.alignment: Qt.AlignVCenter }
                Item { Layout.fillWidth: true }
            }
        }
    }

    QQC.ScrollView {
        anchors.fill: parent; contentWidth: availableWidth; clip: true
        ColumnLayout {
            width: root.width - Theme.spacing.large * 2
            x: Theme.spacing.large
            spacing: Theme.spacing.large

            // ── one continuous dashboard-style tile grid (no section dividers, all values white) ──
            GridLayout {
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.large
                columns: Math.max(1, Math.min(4, Math.floor(width / (root._tileMin + Theme.spacing.large))))
                columnSpacing: Theme.spacing.large; rowSpacing: Theme.spacing.large

                Tile { label: qsTr("Blend Core"); value: root.activityAccepted ? qsTr("Active") : qsTr("Member")
                    sub: root.activityAccepted ? qsTr("Active provider · since epoch %1").arg(root.activeEpoch)
                        : qsTr("In the Core set since epoch %1 · collecting activity").arg(root.activeEpoch)
                    info: ({ "title": qsTr("Blend Core membership"), "what": qsTr("Whether your node is in the active Core set. 'Member' = in the set; 'Active' = accepted activity is also visible (the active epoch / nonce advanced past the baseline)."), "states": [{ "label": qsTr("Member"), "meaning": qsTr("In the Core set, collecting activity.") }, { "label": qsTr("Active"), "meaning": qsTr("In Core with accepted activity visible.") }], "docs": root._docsBlend }) }
                Tile { label: qsTr("Provider nonce"); value: "" + root.nonce; sub: qsTr("activity signal — not proof alone")
                    info: ({ "title": qsTr("Provider nonce"), "what": qsTr("An on-chain counter that advances with accepted activity. A rising nonce is one signal you're live, not sufficient alone — liveness = membership AND healthy peers AND recent activity."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Active heartbeat"); value: root.heartbeatOk ? qsTr("Sending") : qsTr("Not sending")
                    info: ({ "title": qsTr("Active heartbeat"), "what": qsTr("A periodic message the node emits to signal it's a live provider. Not work-verified in this release — declared + heartbeating + reachable, not proof of mixing."), "states": [{ "label": qsTr("Sending"), "meaning": qsTr("Node is heartbeating.") }, { "label": qsTr("Not sending"), "meaning": qsTr("Node down or stalled.") }], "docs": root._docsBlend }) }
                Tile { label: qsTr("Reachability (Blend port)"); value: root.natOk ? qsTr("Reachable") : qsTr("Not reachable")
                    sub: root.natOk ? qsTr("verified by external prober") : qsTr("prober could not reach the port — fix your forward")
                    actionText: qsTr("Check"); onActionClicked: {}
                    info: ({ "title": qsTr("Reachability (Blend port)"), "what": qsTr("Peers must be able to dial your Blend port (udp/3400). No built-in AutoNAT verdict, so this uses a live external prober, Core membership, a local listener, or your attestation. A prober 'Not reachable' overrides the membership inference."), "states": [], "docs": root._docsBlend }) }

                Tile { label: qsTr("Blend signing key"); value: root._elide(root.providerId); mono: true; copyValue: root.providerId; sub: qsTr("provider_id · the key that earns")
                    info: ({ "title": qsTr("Blend signing key (provider_id)"), "what": qsTr("Your node's on-chain Blend identity; the key that accrues activity and rewards."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("BlendZk key"); value: root._elide(root.zkId); mono: true; copyValue: root.zkId; sub: "zk_id"
                    info: ({ "title": qsTr("BlendZk key (zk_id)"), "what": qsTr("The zero-knowledge key published in your declaration; performs the private Blend proofs."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Service type"); value: "BN"
                    info: ({ "title": qsTr("Service type"), "what": qsTr("Marks this SDP declaration as a Blend Network provider (BN)."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Published address"); value: root._elide(root.locator); mono: true; copyValue: root.locator
                    info: ({ "title": qsTr("Published address (locator)"), "what": qsTr("The address peers dial to reach your Blend port — your public IP + the Blend Core port, written on-chain."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Created / active epoch"); value: root.createdEpoch + " / " + root.activeEpoch
                    info: ({ "title": qsTr("Created / active epoch"), "what": qsTr("created = the epoch your declaration was accepted. active = when it becomes eligible (created + 2)."), "states": [], "docs": root._docsBlend }) }
                Tile { visible: root.subState !== "active"; label: qsTr("Withdraw at epoch"); value: "" + root.withdrawAtEpoch
                    info: ({ "title": qsTr("Withdraw at epoch"), "what": qsTr("The epoch your withdrawal takes effect and the declaration is removed; stake unlocks ~2 epochs after."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Locked note"); value: root._elide(root.stakeNote); mono: true; copyValue: root.stakeNote; sub: qsTr("stake — returned ~2 epochs after withdrawal")
                    info: ({ "title": qsTr("Locked note"), "what": qsTr("The note bonded on-chain as your provider stake; locked while active, returned ~2 epochs after a withdrawal."), "states": [], "docs": root._docsBlend }) }

                Tile { label: qsTr("Last send window"); value: root.sendWindow
                    info: ({ "title": qsTr("Blend send window"), "what": qsTr("Each release window the Blend core reports messages emitted: data (real), processed (relayed for others), cover (dummy traffic). Source: node log (DEBUG)."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Proposals (epoch %1)").arg(root.epoch); value: "" + root.proposalsEpoch
                    sub: root.proposalsEpoch > 0 ? qsTr("%1 mixed · %2 direct").arg(root._mixed).arg(root.directEpoch) : qsTr("none yet this epoch")
                    info: ({ "title": qsTr("Proposals this epoch"), "what": qsTr("Blocks your node proposed this epoch, split into mixed (delivered through Blend for proposer privacy) vs direct (missed the delivery deadline, broadcast in the clear). Mixed = proposed − direct."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Delivery (epoch %1)").arg(root.epoch); value: root.directEpoch > 0 ? qsTr("%1 direct").arg(root.directEpoch) : qsTr("all mixed")
                    info: ({ "title": qsTr("Delivery deadline"), "what": qsTr("Block proposals are sent through Blend for proposer privacy; each must reappear on the broadcast channel within T_M = layers × (max per-hop hold + 2) rounds, else it's broadcast in the clear (loses privacy for that block). Misses usually mean too few reachable Core peers."), "states": [], "docs": root._docsBlend }) }
                Tile { label: qsTr("Connected peers"); value: root.connectedPeers + " / " + root.corePeers.length
                    info: ({ "title": qsTr("Connected Core peers"), "what": qsTr("Core peers you currently hold a healthy connection to, out of the full epoch membership. A message mixes through these nodes, so more reachable peers means more reliable delivery."), "states": [], "docs": root._docsBlend }) }
            }

            // ── Core nodes table (full roster; source-tagged) ──
            LogosFrame {
                Layout.fillWidth: true; backgroundColor: Theme.palette.surfaceRaised; borderColor: "transparent"
                radius: Theme.spacing.radiusMedium; padding: Theme.spacing.medium
                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    RowLayout { Layout.fillWidth: true; spacing: Theme.spacing.tiny
                        LogosText { text: qsTr("Core nodes"); color: Theme.palette.text; font.pixelSize: 11; font.weight: Theme.typography.weightBold }
                        LogosText { text: qsTr("this epoch's membership · API + log"); color: Theme.palette.textTertiary; font.pixelSize: 11 }
                        Info { Layout.alignment: Qt.AlignVCenter; onClicked: root._openInfo(({ "title": qsTr("Core nodes"), "what": qsTr("This epoch's Blend Core membership. Your messages mix through these nodes, so unreachable members reduce delivery reliability. Tags mark each row's source and status shows what we can prove."), "states": [{ "label": qsTr("API"), "meaning": qsTr("From live /blend/info — a peer you're connected to, with its health.") }, { "label": qsTr("Log"), "meaning": qsTr("From the node log's epoch membership roster (peer id + address).") }, { "label": qsTr("Bootstrap"), "meaning": qsTr("This peer id is one of your configured bootstrap nodes (initial_peers).") }, { "label": qsTr("Connected / Degraded"), "meaning": qsTr("The API health bool for a connected peer.") }, { "label": qsTr("Unreachable"), "meaning": qsTr("A real dial/delivery failure for this peer in the log.") }, { "label": qsTr("In set"), "meaning": qsTr("In the roster but not currently connected from here.") }], "docs": root._docsBlend })) }
                        Item { Layout.fillWidth: true }
                        LogosText { text: qsTr("%1 shown").arg(root.corePeers.length); color: Theme.palette.textTertiary; font.pixelSize: 11 } }
                    Repeater {
                        model: root.corePeers
                        delegate: RowLayout {
                            id: peerRow
                            required property var modelData
                            readonly property color _sc: peerRow.modelData.status === "Connected" ? Theme.palette.success
                                : peerRow.modelData.status === "Degraded" ? Theme.palette.warning
                                : peerRow.modelData.status === "Unreachable" ? Theme.palette.error : Theme.palette.textTertiary
                            Layout.fillWidth: true; Layout.minimumHeight: 30; spacing: Theme.spacing.small
                            Rectangle { Layout.alignment: Qt.AlignVCenter; width: 8; height: 8; radius: 4; color: peerRow._sc }
                            ColumnLayout { Layout.fillWidth: true; spacing: 1
                                RowLayout { spacing: 6
                                    LogosText { text: root._elide(peerRow.modelData.id); color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.family: "monospace" }
                                    Rectangle { visible: peerRow.modelData.self === true; radius: 3; color: Theme.palette.info; implicitHeight: 14; implicitWidth: youLabel.implicitWidth + 8
                                        LogosText { id: youLabel; anchors.centerIn: parent; text: qsTr("you"); color: Theme.palette.surfaceRaised; font.pixelSize: 10 } } }
                                LogosText { visible: ("" + peerRow.modelData.address).length > 0; Layout.fillWidth: true; text: peerRow.modelData.address; color: Theme.palette.textTertiary; font.pixelSize: 11; font.family: "monospace"; elide: Text.ElideRight } }
                            Row { Layout.alignment: Qt.AlignVCenter; spacing: 4
                                Repeater { model: peerRow.modelData.sources || []
                                    delegate: Rectangle { required property string modelData; radius: 3; color: Theme.palette.surface; implicitHeight: 15; implicitWidth: srcLabel.implicitWidth + 8
                                        LogosText { id: srcLabel; anchors.centerIn: parent; text: parent.modelData; color: Theme.palette.textSecondary; font.pixelSize: 10 } } } }
                            LogosText { Layout.alignment: Qt.AlignVCenter; text: peerRow.modelData.status; color: peerRow._sc; font.pixelSize: 11 }
                            CopyGlyph { Layout.alignment: Qt.AlignVCenter; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.copyText(peerRow.modelData.id) } }
                        }
                    }
                }
            }

            // ── off-ramp (withdraw) ──
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
                                : root.subState === "withdrawing" ? qsTr("You've stopped earning. Your note unlocks at epoch %1 (~2 epochs after the request).").arg(root.withdrawAtEpoch)
                                : qsTr("Stops the provider and stops earning. Sets withdraw_at; your locked note returns to your BlendZk key ~2 epochs later.")
                            color: Theme.palette.textTertiary; font.pixelSize: 11
                        }
                    }
                    LogosButton { visible: root.subState === "active"; text: qsTr("Withdraw stake"); onClicked: root.withdrawRequested() }
                    LogosButton { visible: root.subState === "withdrawn"; text: qsTr("Declare again"); variant: LogosButton.Variant.Primary; onClicked: root.restartRequested() }
                }
            }
        }
    }

    V.InfoModal { id: infoModal; onCopyText: (t) => root.copyText(t) }
}
