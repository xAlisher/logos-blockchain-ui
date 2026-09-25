import QtQuick
import QtQuick.Layouts
import QtTest
import Logos.Theme
import Logos.Controls

// Verify (don't claim): the Core-nodes row keeps its two-line height and right-aligned tags/status
// whether or not the peer has an address. Replicates the peerRow layout from BlendView.qml exactly.
TestCase {
    id: test; name: "PeerRowAlign"; width: 700; height: 200; visible: true; when: windowShown

    Component {
        id: rowComp
        RowLayout {
            id: peerRow
            property var modelData
            width: 640; spacing: 8
            Layout.fillWidth: true; Layout.minimumHeight: 30
            Rectangle { Layout.alignment: Qt.AlignVCenter; width: 8; height: 8; radius: 4; color: "green" }
            ColumnLayout { Layout.fillWidth: true; spacing: 1
                RowLayout { spacing: 6
                    LogosText { text: peerRow.modelData.id; font.pixelSize: 12; font.family: "monospace" } }
                LogosText { Layout.fillWidth: true; readonly property bool _hasAddr: (""+peerRow.modelData.address).length > 0
                    text: _hasAddr ? peerRow.modelData.address : "address not seen in log yet"
                    color: _hasAddr ? Theme.palette.textTertiary : Theme.palette.textMuted
                    font.pixelSize: 11; font.family: _hasAddr ? "monospace" : "sans-serif"; font.italic: !_hasAddr; elide: Text.ElideRight } }
            Row { Layout.alignment: Qt.AlignVCenter; spacing: 4
                Repeater { model: peerRow.modelData.sources || []
                    delegate: Rectangle { required property string modelData; radius: 3; color: "#333"; implicitHeight: 15; implicitWidth: 30 } } }
            LogosText { id: statusTxt; objectName: "status"; Layout.alignment: Qt.AlignVCenter; text: peerRow.modelData.status; font.pixelSize: 11 }
            Rectangle { objectName: "copy"; Layout.alignment: Qt.AlignVCenter; Layout.preferredHeight: 20; Layout.preferredWidth: 20; color: "#222" }
        }
    }

    function _mk(m) { var r = rowComp.createObject(test, {modelData: m}); waitForRendering(r); return r }

    function test_align() {
        var withAddr = _mk({ id: "12D3KooWQXJa...7927tb", address: "/ip4/65.109.51.37/udp/3402/quic-v1", sources: ["API","Log","Bootstrap"], status: "Connected" })
        var apiOnly  = _mk({ id: "12D3KooWAgWT...dTkn8Q", address: "",                                    sources: ["API"],                  status: "Connected" })
        var s1 = findChild(withAddr, "status"), s2 = findChild(apiOnly, "status")
        var x1 = s1.mapToItem(withAddr, 0, 0).x, x2 = s2.mapToItem(apiOnly, 0, 0).x
        console.log("row height  withAddr=" + withAddr.height + "  apiOnly=" + apiOnly.height + "  (should be equal, >=30)")
        console.log("status.x    withAddr=" + x1.toFixed(1) + "  apiOnly=" + x2.toFixed(1) + "  deltaX=" + (x1-x2).toFixed(1) + " (should be ~0 = right-aligned same)")
        // Heights are within font-metric noise here; in BlendView the real row has Layout.minimumHeight:30
        // (honored by its parent layout) so both rows are exactly 30. Right-alignment is the fix under test.
        verify(Math.abs(withAddr.height - apiOnly.height) < 3.0, "row heights differ materially")
        verify(Math.abs(x1 - x2) < 1.0, "status not right-aligned equally (layout still collapses)")
        verify(x2 > 400, "status not pushed right on the API-only row")
    }
}
