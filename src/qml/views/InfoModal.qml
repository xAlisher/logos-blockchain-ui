import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Info (i) modal — explains a dashboard tile: what it is, how it's calculated,
// its states, and a copyable docs link. Content is passed in via `info`:
//   { title, what, calc, states: [{label, meaning}], docs }
LogosDialog {
    id: root
    modal: true
    anchors.centerIn: parent
    width: 560
    height: Math.min(520, parent ? parent.height - 80 : 520)

    property var info: null
    title: info && info.title ? info.title : qsTr("Info")
    signal copyText(string t)

    component Section: ColumnLayout {
        property string heading: ""
        property string body: ""
        Layout.fillWidth: true; spacing: 4
        visible: body.length > 0
        LogosText { text: heading; color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightBold }
        LogosText { Layout.fillWidth: true; text: body; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; wrapMode: Text.WordWrap; lineHeight: 1.3 }
    }

    contentItem: QQC.ScrollView {
        id: sv
        clip: true
        QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded
        ColumnLayout {
            width: sv.availableWidth
            spacing: Theme.spacing.medium

            Section { heading: qsTr("WHAT IS IT"); body: root.info && root.info.what ? root.info.what : "" }
            Section { heading: qsTr("HOW IT'S CALCULATED"); body: root.info && root.info.calc ? root.info.calc : "" }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 6
                visible: root.info && root.info.states && root.info.states.length > 0
                LogosText { text: qsTr("STATES"); color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightBold }
                Repeater {
                    model: root.info && root.info.states ? root.info.states : []
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: Theme.spacing.small
                        LogosText { text: modelData.label; color: Theme.palette.text; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightMedium
                                    Layout.preferredWidth: 120; Layout.alignment: Qt.AlignTop; wrapMode: Text.WordWrap }
                        LogosText { text: modelData.meaning; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                visible: root.info && root.info.docs && root.info.docs.length > 0
                LogosText { text: qsTr("DOCS"); color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText; font.weight: Theme.typography.weightBold }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.small
                    LogosLink {
                        Layout.fillWidth: true
                        text: root.info && root.info.docs ? root.info.docs : ""
                        href: root.info && root.info.docs ? root.info.docs : ""
                        font.pixelSize: Theme.typography.secondaryText
                        elide: Text.ElideRight
                        onActivated: (url) => Qt.openUrlExternally(url)
                    }
                    LogosCopyButton { value: root.info && root.info.docs ? root.info.docs : ""; Layout.alignment: Qt.AlignVCenter }
                }
            }
        }
    }

    rightActions: [ LogosButton { text: qsTr("Close"); onClicked: root.close() } ]
}
