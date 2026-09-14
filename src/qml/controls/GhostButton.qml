import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// Small, gray, low-emphasis secondary button (rounded corners, never a pill).
// For recessive actions like "Clear" that must sit quietly next to a primary CTA.
Rectangle {
    id: root

    property string text: ""
    property bool enabled: true
    signal clicked()

    implicitHeight: 28
    implicitWidth: lbl.implicitWidth + 2 * Theme.spacing.large
    radius: Theme.spacing.radiusLarge          // unified small-button rounding (not a pill)
    opacity: root.enabled ? 1 : 0.4
    color: ma.pressed
           ? Theme.palette.backgroundHover
           : (ma.containsMouse
              ? Qt.rgba(Theme.palette.text.r, Theme.palette.text.g, Theme.palette.text.b, 0.06)
              : "transparent")
    border.width: 1
    border.color: ma.containsMouse ? Theme.palette.text : Theme.palette.border

    LogosText {
        id: lbl
        anchors.centerIn: parent
        text: root.text
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
        font.weight: Theme.typography.weightMedium
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
