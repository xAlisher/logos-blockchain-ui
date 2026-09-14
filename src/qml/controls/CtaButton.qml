import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// The orange primary CTA, matching the welcome screen's "Run the node" button:
// primary-orange fill that deepens on hover/press, white label, pill radius.
//
// NB: the dark theme has NO plain `orange` token — using Theme.palette.orange
// yields undefined and Qt renders the fill WHITE. Use the `primary` family.
// (That exact trap already cost a round on the claim status colours.)
//
// `compact: true` gives the smaller in-card size; the default matches the
// full-width welcome-screen CTA.
Rectangle {
    id: root

    property string text: ""
    property bool enabled: true
    // Compact matches the header's "Fund the node" GEOMETRY (28px pill, tight
    // padding, small label) while keeping the filled-orange treatment.
    property bool compact: false

    signal clicked()

    readonly property color ctaOrange: Theme.palette.primaryHover

    implicitWidth: label.implicitWidth + (root.compact ? 22 : 4 * Theme.spacing.large)
    implicitHeight: root.compact ? 28 : 48
    radius: root.compact ? 14 : Theme.spacing.radiusXlarge
    opacity: root.enabled ? 1 : 0.4
    color: !root.enabled
           ? root.ctaOrange
           : (mouse.pressed  ? Qt.darker(root.ctaOrange, 1.16)
           : (mouse.containsMouse ? Qt.darker(root.ctaOrange, 1.08)
                                  : root.ctaOrange))

    LogosText {
        id: label
        anchors.centerIn: parent
        text: root.text
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: root.compact ? Theme.typography.secondaryText
                                     : Theme.typography.primaryText
        font.weight: Theme.typography.weightMedium
        color: Theme.palette.text
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
