import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Rectangle {
    id: root

    // --- Public API ---
    required property string statusText
    required property color  statusColor
    required property string userConfig
    required property string deploymentConfig
    required property bool   useGeneratedConfig
    required property bool   canStart
    required property bool   isRunning

    signal startRequested()
    signal stopRequested()
    signal changeConfigRequested()
    signal resetChainStateRequested()

    implicitHeight: contentLayout.height + Theme.spacing.large
    color: Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.color: Theme.palette.border
    border.width: 1

    RowLayout {
        id: contentLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacing.large
        spacing: Theme.spacing.large

        // Status Card
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacing.medium

            ColumnLayout {
                LogosText {
                    font.bold: true
                    text: root.statusText
                    color: root.statusColor
                }
                LogosText {
                    text: qsTr("Mainnet - chain ID 1")
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }
            LogosButton {
                Layout.preferredHeight: 40
                Layout.preferredWidth: 100
                enabled: root.canStart
                text: root.isRunning ? qsTr("Stop Node") : qsTr("Start Node")
                onClicked: root.isRunning ? root.stopRequested() : root.startRequested()
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Theme.palette.borderSecondary
        }

        // Config Card
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacing.medium

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosText {
                        text: qsTr("User Config: ")
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: (root.userConfig || qsTr("No file selected")) +
                              (root.useGeneratedConfig ? " " + qsTr("(Generated)") : "")
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        // A long absolute config path has no spaces to wrap on and
                        // overflows the row — elide the middle so the leading dirs
                        // and the file name both stay visible.
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosText {
                        text: qsTr("Deployment Config: ")
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        Layout.fillWidth: true
                        text: (root.useGeneratedConfig && root.deploymentConfig ?
                                   root.deploymentConfig :
                                   root.useGeneratedConfig ?
                                       qsTr("Default") :
                                       (root.deploymentConfig || qsTr("No file selected")))
                        font.pixelSize: Theme.typography.secondaryText
                        color: Theme.palette.textSecondary
                        elide: Text.ElideMiddle
                    }
                }
            }

            LogosButton {
                // Config can't be changed while the node is running — hide the
                // button entirely (not just disable it) in that state.
                visible: !root.isRunning
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 100
                Layout.preferredHeight: 40
                text: qsTr("Change")
                onClicked: root.changeConfigRequested()
            }

            // Recovery for a node wedged after an unclean shutdown
            // (logos-blockchain#3171): wipe the chain DB + consensus state to
            // force a clean start. Keeps the wallet keystore + config, so no
            // keys are lost. Only offered while the node is stopped.
            LogosButton {
                visible: !root.isRunning
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 160
                Layout.preferredHeight: 40
                text: qsTr("Reset chain state")
                onClicked: root.resetChainStateRequested()
            }
        }
    }
}
