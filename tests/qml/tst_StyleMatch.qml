import QtQuick
import QtTest

// Measurement harness (verify, don't assert): loads the Blend tab and prints the ACTUAL
// rendered padding + title/value/label font sizes for the lifecycle strip and a tile, so
// strip-vs-card geometry is compared from real values, not from reading tokens.
TestCase {
    id: test
    name: "StyleMatch"
    width: 1200; height: 1200; visible: true
    when: windowShown
    property var view

    QtObject {
        id: backend
        property int blendStatus: 3
        property int status: 2
        property string leaderKey: ""
        property string primaryAddress: ""
        property string lastErrorMessage: ""
        function getSdpFundingKey() { return "read" }
        function getBalance(k) { return "read" }
        function getNotes(k, t) { return "read" }
        function checkBlendPortReachable() { return "read" }
        function getBlendDeclarations() { return "read" }
        function getBlendIdentity() { return "read" }
        function requestFaucetFunds(k) { return }
        function startBlockchain() { return }
        function copyToClipboard(t) { return }
    }
    QtObject { id: logos; function watch(c, ok, e) { return } }
    QtObject {
        id: controller
        property var lifecycle: ({ ok: true, state: "collecting", title: "Collecting Blend activity",
            detail: "d", tone: "neutral", action: "refresh", actionLabel: "Refresh",
            steps: ["Online","Declared","Activated","Connected","Activity","Maintaining"].map(function(l,i){ return {label:l, state: i<4?"complete":i===4?"current":"pending"} }),
            corePeers: [], messages: ({}) })
    }

    function init() {
        var c = Qt.createComponent("../../src/qml/views/BlendView.qml")
        compare(c.status, Component.Ready, c.errorString())
        view = c.createObject(test, {backend: backend, controller: controller, backendReady: true,
                                     width: 1200, height: 1200, phase: "core"})
        verify(view !== null); waitForRendering(view); wait(50)
    }
    function cleanup() { if (view) { view.destroy(); view = null } }

    function test_measure() {
        var strip = findChild(view, "blendStripCard")
        var title = findChild(view, "blendTitle")
        var tile = findChild(view, "blendTile")
        var tval = findChild(view, "blendTileValue")
        var tlab = findChild(view, "blendTileLabel")
        console.log("STRIP  padding=" + strip.padding + " left=" + strip.leftPadding + " top=" + strip.topPadding
                    + " radius=" + strip.radius + " titlePx=" + title.font.pixelSize + " titleWeight=" + title.font.weight)
        console.log("TILE   padding=" + tile.padding + " left=" + tile.leftPadding + " top=" + tile.topPadding
                    + " radius=" + tile.radius + " valuePx=" + tval.font.pixelSize + " valueWeight=" + tval.font.weight
                    + " labelPx=" + tlab.font.pixelSize)
        // title inset from the strip card's top-left border (real geometry)
        var tp = title.mapToItem(strip, 0, 0)
        var vp = tval.mapToItem(tile, 0, 0)
        var laneItem = findChild(view, "blendStrip")
        var lanePos = laneItem.mapToItem(strip, 0, 0)
        var gap = lanePos.y - (tp.y + title.height)
        console.log("STRIP  title inset x=" + tp.x.toFixed(1) + " y=" + tp.y.toFixed(1)
                    + " laneHeight=" + laneItem.height + " title->lane gap=" + gap.toFixed(1))
        console.log("TILE   value inset x=" + vp.x.toFixed(1) + " y=" + vp.y.toFixed(1))
        // Card container matches the dashboard tiles (padding 16, radius 8).
        compare(strip.padding, tile.padding, "card padding matches")
        compare(strip.radius, tile.radius, "card corner radius matches")
        compare(tp.x, 16, "title left inset = padding")
        compare(tp.y, 16, "title top inset = padding")
        // Strip is the dashboard STATUS card's counterpart: hero title 32, lane 30, gap 24
        // (content spacing 8 + lane topMargin 16). Reference values read from NodeDashboardView.
        compare(title.font.pixelSize, 32, "strip title = dashboard hero size (32)")
        compare(laneItem.height, 30, "lane height = dashboard Lifecycle lane (30)")
        compare(Math.round(gap), 24, "title->lane gap = dashboard Status card (24)")
    }
}
