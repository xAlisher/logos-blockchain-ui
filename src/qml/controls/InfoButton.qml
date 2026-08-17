import QtQuick
import QtQuick.Controls

import Logos.Theme
import Logos.Controls

// Small circled-"i" help button. Click to toggle a popup with `text`, a short
// description of the operation. Styled to match the other SVG icon buttons.
Item {
    id: root

    property string text: ""

    implicitWidth: 28
    implicitHeight: 28

    Button {
        id: btn
        anchors.fill: parent
        display: AbstractButton.IconOnly
        flat: true
        padding: 4
        // `flat` does NOT guarantee a transparent background across Qt Quick
        // Controls styles — the default one painted a light square behind the
        // icon while the popup was open. Make it explicit.
        background: Rectangle { color: "transparent" }
        icon.source: Qt.resolvedUrl("../icons/info.svg")
        icon.width: 18
        icon.height: 18
        // textMuted (#5C5C5C) rather than textTertiary (#969696): at rest the
        // icon should recede, and it still lights up primary-orange on hover so
        // it stays discoverable.
        icon.color: (btn.hovered || popup.visible)
            ? Theme.palette.primary
            : Theme.palette.textMuted
        onClicked: popup.visible ? popup.close() : popup.open()
        // No hover tooltip. The icon already reads as help, and a "What is this?"
        // tip firing on the way past added noise without adding information —
        // the popup this opens IS the answer.
    }

    Popup {
        id: popup
        // Parented to the window overlay: LeaderRewardsView (and others) sit in a
        // ScrollView with clip:true, which would otherwise slice the popup off.
        parent: Overlay.overlay

        // Position is COMPUTED ON OPEN, not bound. mapToItem() is a function call,
        // not a reactive dependency — as a binding it evaluated once (before layout
        // had settled) and never tracked scrolling, which put the popup nowhere
        // near its button.
        onAboutToShow: {
            const o = root.mapToItem(Overlay.overlay, 0, 0)
            const pad = Theme.spacing.small
            // Right-align to the button, clamped inside the window.
            x = Math.max(pad, Math.min(o.x + root.width - width,
                                       Overlay.overlay.width - width - pad))
            // Below the button, or above it when there is no room underneath.
            const below = o.y + root.height + Theme.spacing.tiny
            y = (below + implicitHeight > Overlay.overlay.height - pad)
                ? Math.max(pad, o.y - implicitHeight - Theme.spacing.tiny)
                : below
        }
        width: 300
        padding: Theme.spacing.medium
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.palette.backgroundSecondary
            border.color: Theme.palette.border
            border.width: 1
            radius: Theme.spacing.radiusLarge
        }
        contentItem: LogosText {
            text: root.text
            wrapMode: Text.WordWrap
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.text
        }
    }
}
