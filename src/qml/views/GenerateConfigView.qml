import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

import Logos.Theme
import Logos.Controls

import "../controls"

ColumnLayout {
    id: root

    property string generatedUserConfigPath: ""
    property bool resultSuccess: false
    property string resultMessage: ""

    // Pre-fill the "Initial peers" box so it is never empty (see logos-blockchain#3153): an empty peers
    // box produces a config that never syncs, and nothing tells the operator. Shown in the field so it is
    // visible + editable — a user can keep, change, or clear them.
    // NOTE for maintainers: these are the testnet peers verified to reach chain tip (workshop, on
    // Linux/WSL/macOS). The module's config/node_config.yaml currently lists a *different* set — please
    // confirm the canonical bootstrap peers, ideally sourcing this default from the module config rather
    // than hardcoding it here.
    readonly property var defaultInitialPeers: [
        "/ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWFrouXfmrR4nsLMtE7wu15DoMJ6VtoUtHinREZCvbWHar",
        "/ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWJRGau8M1rjT7R5e4YYsgdFhsMX35nRDtMwCDjxQkXAHz",
        "/ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWQXJavMDTRscjauFSgVAB1VLB6Rzpy2uY5SU9Tk7927tb",
        "/ip4/65.109.51.37/udp/50001/quic-v1/p2p/12D3KooWSQc7CcGtvWDPF1yCbBthFnQjprfCVHmfmNDUrSmqQsU1"
    ]

    signal generateRequested(string outputPath, var initialPeers, int netPort, int blendPort, string httpAddr, string externalAddress, bool noPublicIpCheck, int deploymentMode, string deploymentConfigPath, string statePath)


    // Leave the output field empty by default: the module writes the config to
    // its own host-provisioned writable location and returns that path. A user
    // can still type/browse an explicit path to override.

    QtObject {
        id: d
        function doGenerate() {
            var peers = initialPeersArea.text.split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
            root.generateRequested(
                outputField.text.trim(),
                peers,
                netPortSpin.value,
                blendPortSpin.value,
                httpAddrField.text.trim(),
                externalAddrField.text.trim(),
                noPublicIpCheckBox.checked,
                defaultNetworkRadioButton.checked ? 0 : 1,
                customDeploymentField.text.trim(),
                statePathField.text.trim())
        }
    }

    spacing: Theme.spacing.medium

    LogosText {
        Layout.alignment: Qt.AlignLeft
        font.bold: true
        text: qsTr("Generate user config")
    }

    LogosText {
        Layout.alignment: Qt.AlignLeft
        Layout.topMargin: -Theme.spacing.small
        text: qsTr("All fields are optional. Values are passed as args to generate config.")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textSecondary
        wrapMode: Text.WordWrap
    }

    // Output path (defaults to generated path; user can change via text or folder browse)
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.small
        LogosTextField {
            id: outputField
            Layout.fillWidth: true
            placeholderText: qsTr("Output config path (optional — defaults to module data dir)")
        }
        LogosButton {
            text: qsTr("Browse…")
            onClicked: outputFolderDialog.open()
        }
        InfoButton {
            text: qsTr("Leave empty (or use a relative path) to let the module store the "
                       + "config and node state in its own per-instance data directory — "
                       + "the safe default.\n\n"
                       + "Enter a full absolute path only to write the config there yourself. "
                       + "Note: depending on where the app runs (e.g. embedded in Basecamp, "
                       + "sandboxed, or read-only locations) an arbitrary absolute path may not "
                       + "be writable and starting the node can fail.")
        }
    }

    // Initial peers (multi-line)
    LogosText {
        Layout.alignment: Qt.AlignLeft
        text: qsTr("Initial peers (one per line)")
        font.pixelSize: Theme.typography.secondaryText
    }

    ScrollView {
        Layout.fillWidth: true
        Layout.preferredHeight: 60
        clip: true
        TextArea {
            id: initialPeersArea
            text: root.defaultInitialPeers.join("\n")
            background: Rectangle {
                radius: Theme.spacing.radiusSmall
                color: Theme.palette.backgroundSecondary
                border.width: 1
                border.color: d.inputActiveFocus ? Theme.palette.overlayOrange : Theme.palette.backgroundElevated
            }
            placeholderText: qsTr("Peer addresses, one per line")
            placeholderTextColor: Theme.palette.textTertiary
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.text
        }
    }

    // Net port / Blend port
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.large
        LogosText {
            text: qsTr("Net port")
            font.pixelSize: Theme.typography.secondaryText
        }
        SpinBox {
            id: netPortSpin
            from: 0
            to: 65535
            value: 0
            Layout.preferredWidth: 100
            editable: true
        }
        Item { Layout.fillWidth: true }
        LogosText {
            text: qsTr("Blend port")
            font.pixelSize: Theme.typography.secondaryText
        }
        SpinBox {
            id: blendPortSpin
            from: 0
            to: 65535
            value: 0
            Layout.preferredWidth: 100
            editable: true
        }
    }

    LogosTextField {
        id: httpAddrField
        Layout.fillWidth: true
        placeholderText: qsTr("HTTP address (e.g. 0.0.0.0:8080)")
    }

    LogosTextField {
        id: externalAddrField
        Layout.fillWidth: true
        placeholderText: qsTr("External address (e.g. /ip4/1.2.3.4/udp/3000/quic-v1)")
    }

    CheckBox {
        id: noPublicIpCheckBox
        text: qsTr("No public IP check")
        font.pixelSize: Theme.typography.secondaryText
        palette.windowText: Theme.palette.text
    }

    // Deployment
    LogosText {
        Layout.alignment: Qt.AlignLeft
        text: qsTr("Deployment")
        font.pixelSize: Theme.typography.secondaryText
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(defaultNetworkRadioButton.implicitHeight,
                                          customNetworkRadioButton.implicitHeight,
                                          customDeploymentField.implicitHeight,
                                          browseDeploymentButton.implicitHeight)
        spacing: Theme.spacing.medium
        RadioButton {
            id: defaultNetworkRadioButton
            font.pixelSize: Theme.typography.secondaryText
            palette.windowText: Theme.palette.text
            checked: true
            text: qsTr("Default")
        }
        RadioButton {
            id: customNetworkRadioButton
            font.pixelSize: Theme.typography.secondaryText
            palette.windowText: Theme.palette.text
            text: qsTr("Custom config")
        }
        LogosTextField {
            id: customDeploymentField
            visible: customNetworkRadioButton.checked
            Layout.fillWidth: true
            placeholderText: qsTr("Path to deployment config")
        }
        LogosButton {
            id: browseDeploymentButton
            visible: customNetworkRadioButton.checked
            text: qsTr("Browse")
            onClicked: deploymentConfigFileDialog.open()
        }
    }

    LogosTextField {
        id: statePathField
        Layout.fillWidth: true
        placeholderText: qsTr("State path")
    }

    LogosButton {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 50
        text: qsTr("Generate config")
        onClicked: d.doGenerate()
    }

    LogosText {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: true
        text: root.resultMessage
        color: root.resultSuccess ? Theme.palette.success : Theme.palette.error
        font.pixelSize: Theme.typography.secondaryText
        wrapMode: Text.WordWrap
        visible: root.resultMessage !== ""
    }

    FileDialog {
        id: deploymentConfigFileDialog
        modality: Qt.NonModal
        nameFilters: ["YAML files (*.yaml *.yml)", "All files (*)"]
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: customDeploymentField.text = selectedFile
    }

    FolderDialog {
        id: outputFolderDialog
        modality: Qt.NonModal
        title: qsTr("Choose folder for config file")
        onAccepted: {
            var urlStr = selectedFolder.toString()
            if (urlStr.indexOf("file://") === 0)
                urlStr = urlStr.substring(7)
            if (urlStr.length > 0)
                outputField.text = urlStr + "/user_config.yaml"
        }
    }     
}
