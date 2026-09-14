import QtQuick
import QtQuick.Controls

import Logos.Theme

Button {
    id: root

    signal copyText()

    // Sized to match the Node tab's copy control (NodeDashboardView's CopyBtn:
    // 22px button, padding 2, 14px icon). This previously declared a 24px icon
    // inside a 24px button with NO padding override — the style's default Button
    // padding then squeezed the icon into the leftover ~12px, so it rendered
    // smaller and fainter than the Node tab's. Keep padding explicit so the
    // result does not depend on which Qt Quick Controls style is active.
    padding: 2
    implicitWidth: 22
    implicitHeight: 22
    display: AbstractButton.IconOnly
    flat: true

    property string iconSource: Qt.resolvedUrl("../icons/copy.svg")

    icon.source: root.iconSource
    icon.width: 14
    icon.height: 14
    // Matches the (i): recedes at rest, lifts on hover.
    icon.color: hovered ? Theme.palette.text : Theme.palette.textMuted

    function reset() {
        iconSource = Qt.resolvedUrl("../icons/copy.svg")
    }

    Timer {
        id: resetTimer
        interval: 1500
        repeat: false
        onTriggered: root.reset()
    }

    onClicked: {
        root.copyText()
        root.iconSource = Qt.resolvedUrl("../icons/checkmark.svg")
        resetTimer.restart()
    }
}
