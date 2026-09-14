import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Shared epoch sidebar for the Rewards / Blocks / Proposals pages. Lists
// "All epochs" then every epoch present in the page's own data (descending),
// with the chain's current epoch marked. Emits the selected epoch via `selected`
// (-1 = All). The page filters its list to `selected`, and when All is chosen it
// groups the list with per-epoch divider headers.
Item {
    id: root
    property var epochs: []            // unique epoch numbers present in the data, DESC
    property int currentEpoch: -1      // chain's current epoch (gets the "(current)" tag)
    property int selected: -1          // -1 = All epochs
    // Optional per-epoch counts, shown right-aligned in each row (e.g. blocks
    // proposed in that epoch). `counts` maps epoch -> number; `total` fills the
    // "All epochs" row. Leave `total` at -1 to hide counts entirely.
    property var counts: ({})
    property int total: -1
    property bool bootstrapping: false   // hold the per-epoch list during IBD (it would churn 1,2,3…)
    function _countFor(e) {
        if (root.total < 0 || !root.counts) return -1
        var v = root.counts[e]
        return (v === undefined || v === null) ? 0 : v
    }
    implicitWidth: 168

    component Row: Rectangle {
        id: rr
        property string label: ""
        property int value: -2
        property int count: -1        // >= 0 renders a right-aligned count
        property bool sel: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 34
        radius: Theme.spacing.radiusMedium
        color: sel ? Theme.palette.surfaceRaised
                   : (ma.containsMouse ? Qt.rgba(Theme.palette.text.r, Theme.palette.text.g, Theme.palette.text.b, 0.05) : "transparent")
        LogosText {
            id: rrLabel
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.leftMargin: Theme.spacing.medium
            anchors.right: rrCount.visible ? rrCount.left : parent.right
            anchors.rightMargin: Theme.spacing.small
            text: rr.label; elide: Text.ElideRight
            color: rr.sel ? Theme.palette.text : Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            font.weight: rr.sel ? Theme.typography.weightBold : Theme.typography.weightRegular
        }
        LogosText {
            id: rrCount
            visible: rr.count >= 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right; anchors.rightMargin: Theme.spacing.medium
            text: rr.count >= 0 ? String(rr.count) : ""
            color: rr.sel ? Theme.palette.text : Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
            font.weight: rr.sel ? Theme.typography.weightBold : Theme.typography.weightRegular
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rr.picked() }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 2

        Row { label: qsTr("All epochs"); value: -1; count: root.total; sel: root.selected === -1; onPicked: root.selected = -1 }
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 4; Layout.bottomMargin: 4; height: 1; color: Theme.palette.borderSecondary }

        QQC.ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth; clip: true
            ColumnLayout {
                width: parent.width; spacing: 2
                Repeater {
                    // While bootstrapping the model fills with IBD-replay blocks from
                    // genesis, so the per-epoch list would churn 1,2,3…; hold it back
                    // until the node is synced and the epochs are meaningful.
                    model: root.bootstrapping ? [] : root.epochs
                    delegate: Row {
                        required property int index
                        required property var modelData
                        label: modelData === root.currentEpoch ? qsTr("%1 (current)").arg(modelData) : String(modelData)
                        value: modelData
                        count: root._countFor(modelData)
                        sel: root.selected === modelData
                        onPicked: root.selected = modelData
                    }
                }
                LogosText {
                    visible: root.bootstrapping || root.epochs.length === 0
                    Layout.fillWidth: true; Layout.margins: Theme.spacing.small
                    text: root.bootstrapping ? qsTr("Syncing…") : qsTr("No epochs yet"); color: Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
