import QtQuick
import QtQuick.Layouts
import Logos.Theme
import Logos.Controls

// "Start Empowering" modal — set the target balance to mine toward, then Start.
// Auto-claim lives in Settings (on by default); with it on, the node mines and
// claims in the background until the balance reaches this target, pausing there
// and resuming if it drops below. Naming (Empowering / Mine tokens) is TBD.
LogosDialog {
    id: root
    title: qsTr("Fund")
    modal: true
    anchors.centerIn: parent
    width: 420

    property alias target: field.text
    signal startRequested(real target)

    function _num() { return parseFloat((field.text || "").replace(/[^0-9.]/g, "")) || 0 }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium
        LogosText {
            Layout.fillWidth: true
            text: qsTr("Mine tokens in the background to keep your balance topped up. The node claims automatically until the target below is reached, then pauses.")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            wrapMode: Text.WordWrap
        }
        LogosText {
            text: qsTr("Target balance")
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Theme.spacing.small
            LogosTextField {
                id: field
                Layout.fillWidth: true
                placeholderText: "5000"
                validator: IntValidator { bottom: 0 }
            }
            LogosText { text: "LGO"; color: Theme.palette.textSecondary; Layout.alignment: Qt.AlignVCenter }
        }
    }

    rightActions: [
        LogosButton {
            text: qsTr("Cancel")
            onClicked: root.close()
        },
        LogosButton {
            text: qsTr("Start")
            variant: LogosButton.Variant.Primary
            enabled: root._num() > 0
            onClicked: { root.startRequested(root._num()); root.close() }
        }
    ]
}
