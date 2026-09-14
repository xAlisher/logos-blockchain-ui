import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// First-run screen (one-click UX #10). Shown only when no node config exists
// yet (#15): one orange button gets a newcomer to a syncing node; two links
// cover the expert paths; a pinned footer marks the fork.
Item {
    id: root

    signal runNodeRequested()
    signal haveConfigRequested()
    signal generateCustomRequested()

    // The design-system `primary` orange (#ED7B58) is too pale for a CTA. Use the
    // brighter tone (primaryHover, #F55702) as the base and darken it slightly on
    // hover/press.
    readonly property color ctaOrange: Theme.palette.primaryHover

    // Centered, contained hero — never let it sprawl across the whole canvas.
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(root.width - 80, 360)
        spacing: Theme.spacing.large

        // ── Logos logo on top, "Blockchain" below ──
        Image {
            Layout.alignment: Qt.AlignHCenter
            source: Qt.resolvedUrl("../icons/logos.svg")
            sourceSize.height: 72
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Blockchain")
            font.pixelSize: Theme.typography.pageTitleText
            font.weight: Theme.typography.weightMedium
            color: Theme.palette.text
        }

        // ── Subtitle ──
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -Theme.spacing.small
            text: qsTr("Testnet v0.2.1")
            font.pixelSize: Theme.typography.subtitleText
            color: Theme.palette.textSecondary
        }

        // ── Orange primary CTA: Run the node ──
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.small
            Layout.preferredHeight: 48
            radius: Theme.spacing.radiusXlarge
            // Primary-orange fill (deepens on hover/press); white text.
            // NB: the dark theme has NO plain `orange` token — using it yields
            // undefined → Qt renders the Rectangle white. Use the `primary` family.
            color: runMouse.pressed
                   ? Qt.darker(root.ctaOrange, 1.16)
                   : (runMouse.containsMouse ? Qt.darker(root.ctaOrange, 1.08) : root.ctaOrange)

            LogosText {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Run the node")
                font.pixelSize: Theme.typography.primaryText
                font.weight: Theme.typography.weightMedium
                color: Theme.palette.text
            }
            MouseArea {
                id: runMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runNodeRequested()
            }
        }

        // ── Expert paths as links (not buttons) ──
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.spacing.medium

            LogosText {
                text: qsTr("I already have config")
                font.pixelSize: Theme.typography.secondaryText
                color: haveCfgMouse.containsMouse ? root.ctaOrange : Theme.palette.textSecondary
                font.underline: haveCfgMouse.containsMouse
                MouseArea {
                    id: haveCfgMouse
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.haveConfigRequested()
                }
            }
            LogosText {
                text: "·"
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textTertiary
            }
            LogosText {
                text: qsTr("Generate custom config")
                font.pixelSize: Theme.typography.secondaryText
                color: genMouse.containsMouse ? root.ctaOrange : Theme.palette.textSecondary
                font.underline: genMouse.containsMouse
                MouseArea {
                    id: genMouse
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.generateCustomRequested()
                }
            }
        }
    }

    // ── Pinned footer: fork attribution ──
    LogosText {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.spacing.large
        text: qsTr("One-Click — a fork of the official Logos blockchain module")
        font.pixelSize: Theme.typography.secondaryText
        color: Theme.palette.textTertiary
    }
}
