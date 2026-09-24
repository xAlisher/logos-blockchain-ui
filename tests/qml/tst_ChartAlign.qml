import QtQuick
import QtQuick.Layouts
import QtTest

import "../../src/qml/controls"

// Verify (don't claim): render EpochBarChart and BlendEpochStrip side-by-side at the SAME
// fillHeight, and print the actual scene-Y of each title and the bottom (baseline) of each
// chart body, so the "Blend title sits lower / bars baseline misaligned" report is measured.
TestCase {
    id: test
    name: "ChartAlign"
    width: 900; height: 320; visible: true
    when: windowShown
    property var row

    Component {
        id: comp
        RowLayout {
            width: 900; height: 260; spacing: 16
            EpochBarChart {
                objectName: "bar"
                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.alignment: Qt.AlignTop
                title: "Vouchers claimed by epoch"; unit: "vouchers"; decimals: 0
                info: ({ title: "x", body: "y" })
                series: [{epoch:40,value:1},{epoch:41,value:3},{epoch:42,value:2},{epoch:43,value:5},{epoch:44,value:2}]
            }
            BlendEpochStrip {
                objectName: "strip"
                Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.fillHeight: true; Layout.alignment: Qt.AlignTop
                info: ({ title: "x", body: "y" })
                series: [{epoch:40,mode:"edge"},{epoch:41,mode:"core"},{epoch:42,mode:"edge"},{epoch:43,mode:"core"},{epoch:44,mode:"core"}]
            }
        }
    }

    function init() {
        row = comp.createObject(test)
        verify(row !== null); waitForRendering(row); wait(60)
    }
    function cleanup() { if (row) { row.destroy(); row = null } }

    function _titleOf(frame) {
        // first LogosText child = the title
        function find(it) {
            for (var i=0;i<it.children.length;i++){
                var c=it.children[i]
                if (c && c.hasOwnProperty("text") && c.hasOwnProperty("font") && String(c.text).length>3 && String(c.text).indexOf("Epoch")<0) return c
                var r=find(c); if(r) return r
            }
            return null
        }
        return find(frame)
    }

    function test_measure() {
        var bar = findChild(row, "bar")
        var strip = findChild(row, "strip")
        var bt = _titleOf(bar), st = _titleOf(strip)
        var btp = bt.mapToItem(row, 0, 0)
        var stp = st.mapToItem(row, 0, 0)
        // frame bottoms (card bottom border) in scene coords
        var barBot = bar.mapToItem(row, 0, bar.height).y
        var stripBot = strip.mapToItem(row, 0, strip.height).y
        console.log("=== TITLE Y (scene) ===")
        console.log("bar.title   text='" + bt.text + "' y=" + btp.y.toFixed(1) + " px=" + bt.font.pixelSize)
        console.log("strip.title text='" + st.text + "' y=" + stp.y.toFixed(1) + " px=" + st.font.pixelSize)
        console.log("titleDeltaY=" + (stp.y - btp.y).toFixed(1) + "  (positive = strip lower)")
        console.log("=== CARD HEIGHT ===")
        console.log("bar.height=" + bar.height + " strip.height=" + strip.height + "  bottomDelta=" + (stripBot-barBot).toFixed(1))
        console.log("bar.padding=" + bar.padding + " strip.padding=" + strip.padding)
    }
}
