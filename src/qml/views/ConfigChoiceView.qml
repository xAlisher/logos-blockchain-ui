import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

ColumnLayout {
    id: root

    property string userConfigPath: ""
    property string deploymentConfigPath: ""
    property string generatedUserConfigPath: ""

    property bool generateResultSuccess: false
    property string generateResultMessage: ""

    signal generateRequested(string outputPath, var initialPeers, int netPort, int blendPort, string httpAddr, string externalAddress, bool noPublicIpCheck, int deploymentMode, string deploymentConfigPath, string statePath)
    signal setPathToConfigsRequested()
    signal userConfigPathSelected(string path)
    signal deploymentConfigPathSelected(string path)

    QtObject {
        id: d
        property int selectedOption: 0
    }

    // Switch to the "set path to config" sub-view. Used after a successful
    // generate to land on the resolved-config-path screen, from which the user
    // continues to start the node.
    function showSetConfigPath() { d.selectedOption = 2 }

    spacing: Theme.spacing.large

    LogosText {
        Layout.alignment: Qt.AlignLeft
        font.bold: true
        font.pixelSize: Theme.typography.primaryText
        text: qsTr("Choose how to set up your node config")
    }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        Layout.topMargin: -Theme.spacing.small
        text: qsTr("Generate a new config, or set paths to your existing config files.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.large

        LogosButton {
            text: qsTr("Generate config")
            Layout.preferredHeight: 50
            Layout.fillWidth: true
            onClicked: d.selectedOption = 1
        }

        LogosButton {
            text: qsTr("Set path to config")
            Layout.preferredHeight: 50
            Layout.fillWidth: true
            onClicked: d.selectedOption = 2
        }
    }

    Loader {
        id: contentLoader
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: d.selectedOption === 1 || d.selectedOption === 2
        active: d.selectedOption === 1 || d.selectedOption === 2
        sourceComponent: d.selectedOption === 1 ? generateConfigComponent : (d.selectedOption === 2 ? setConfigPathComponent : null)
    }

    Item {
        Layout.fillHeight: true
        visible: d.selectedOption !== 1 && d.selectedOption !== 2
    }

    Component {
        id: generateConfigComponent
        ColumnLayout {
            spacing: Theme.spacing.medium
            GenerateConfigView {
                generatedUserConfigPath: root.generatedUserConfigPath
                resultSuccess: root.generateResultSuccess
                resultMessage: root.generateResultMessage
                Layout.fillWidth: true
                onGenerateRequested: function(outputPath, initialPeers, netPort, blendPort,
                                              httpAddr, externalAddress, noPublicIpCheck,
                                              deploymentMode, deploymentConfigPath, statePath) {
                    root.generateRequested(outputPath, initialPeers, netPort, blendPort,
                                           httpAddr, externalAddress, noPublicIpCheck,
                                           deploymentMode, deploymentConfigPath, statePath)
                }
            }
        }
    }

    Component {
        id: setConfigPathComponent
        SetConfigPathView {
            userConfigPath: root.userConfigPath
            deploymentConfigPath: root.deploymentConfigPath
            onUserConfigPathSelected: function(path) { root.userConfigPathSelected(path) }
            onDeploymentConfigPathSelected: function(path) { root.deploymentConfigPathSelected(path) }
            onSetPathToConfigsRequested: root.setPathToConfigsRequested()
        }
    }
}
