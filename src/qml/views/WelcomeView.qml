import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// First-run welcome splash. A full-bleed basecamp photo behind a centred title,
// an honest "experimental fork" line, and the two entry points (Quick start /
// Advanced). Version and a copy-on-click GitHub link are pinned to the bottom.
// Shown only before a node config exists.
Item {
    id: root

    signal quickStartRequested()     // generate a default config + start → dashboard
    signal advancedRequested()       // open the advanced setup stepper
    signal copyToClipboard(string text)

    property string versionText: qsTr("UI 0.2.20, core 0.2.4")
    property string repoUrl: "https://github.com/xAlisher/logos-blockchain-ui"

    readonly property color ctaOrange: Theme.colors.orange400

    // ── Full-bleed background photo (fit to fill), darkened for legible text ──
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../icons/node_welcome_BG.png")
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        clip: true
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.30) }
            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.20) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.60) }
        }
    }

    // ── Centred hero + entry buttons ──
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 360)
        spacing: Theme.spacing.medium

        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Blockchain Node")
            font.pixelSize: Theme.typography.pageTitleText
            font.weight: Theme.typography.weightBold
            color: Theme.palette.text
        }
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("Experimental fork, community preview,\nnot an official Logos app.")
            font.pixelSize: Theme.typography.subtitleText
            color: Theme.palette.textSecondary
        }

        // Quick start — orange primary CTA.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.medium
            Layout.preferredHeight: 48
            radius: Theme.spacing.radiusXlarge
            color: quickMouse.pressed
                   ? Qt.darker(root.ctaOrange, 1.16)
                   : (quickMouse.containsMouse ? Qt.darker(root.ctaOrange, 1.08) : root.ctaOrange)
            LogosText {
                anchors.centerIn: parent
                text: qsTr("Quick start")
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
                color: Theme.palette.text
            }
            MouseArea {
                id: quickMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.quickStartRequested()
            }
        }

        // Advanced — secondary (dark) button.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            radius: Theme.spacing.radiusXlarge
            color: advMouse.pressed ? Theme.palette.backgroundHover
                   : (advMouse.containsMouse ? Qt.rgba(Theme.palette.text.r, Theme.palette.text.g, Theme.palette.text.b, 0.10)
                                             : Qt.rgba(Theme.palette.text.r, Theme.palette.text.g, Theme.palette.text.b, 0.06))
            border.width: 1
            border.color: advMouse.containsMouse ? Theme.palette.text : Theme.palette.border
            LogosText {
                anchors.centerIn: parent
                text: qsTr("Advanced")
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
                color: Theme.palette.text
            }
            MouseArea {
                id: advMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.advancedRequested()
            }
        }
    }

    // ── Pinned footer: version + copy-on-click GitHub link ──
    ColumnLayout {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.spacing.large
        spacing: 2

        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: root.versionText
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        // "Github" link: click copies the URL and flashes "Copied" (docs-link pattern).
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: ghCopied.running ? qsTr("Copied ✓") : qsTr("Github")
            font.pixelSize: Theme.typography.secondaryText
            font.underline: ghMouse.containsMouse && !ghCopied.running
            color: ghCopied.running ? Theme.palette.success : root.ctaOrange
            Timer { id: ghCopied; interval: 1500 }
            MouseArea {
                id: ghMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.copyToClipboard(root.repoUrl); ghCopied.restart() }
            }
        }
    }
}
