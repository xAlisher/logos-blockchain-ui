import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A stat tile matching the Node dashboard's Slot/Height/Balance/Peers row:
// rounded, elevated, centred label over value. Extracted as a shared control so
// the two pages cannot drift apart — the private-duplicate habit is exactly what
// left three different hash rows in this module.
//
// `interactive: true` makes the value the affordance: it tints on hover and
// emits clicked(), for tiles that open a detail view.
// Extra children (a small CTA, say) stack under the value.
Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string sub: ""
    property string tip: ""
    property bool interactive: false
    // Flash the value green when it changes — for tiles that tick (Slot, Height).
    // Folded in from NodeDashboardView's private FlashValue so the node page can
    // adopt this tile without losing the animation.
    property bool flashOnChange: false
    // Keeps the Node dashboard's existing tile geometry; content taller than this
    // (a tile with a CTA) grows past it.
    property int minHeight: 68

    signal clicked()

    default property alias extra: extraSlot.data

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(root.minHeight,
                                     col.implicitHeight + 2 * Theme.spacing.medium)
    radius: Theme.spacing.radiusLarge
    color: Theme.palette.backgroundTertiary
    border.width: 0

    readonly property color _rest: (root.interactive && hh.hovered)
        ? Theme.palette.primary : Theme.palette.text

    HoverHandler { id: hh; cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor }
    ToolTip.visible: hh.hovered && root.tip.length > 0
    ToolTip.text: root.tip

    TapHandler {
        enabled: root.interactive
        onTapped: root.clicked()
    }

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.spacing.medium
        spacing: 2

        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }
        LogosText {
            id: valueText
            Layout.alignment: Qt.AlignHCenter
            text: root.value
            font.pixelSize: Theme.typography.panelTitleText
            font.weight: Theme.typography.weightMedium
            // The value carries the hover state, so it is obvious what is clickable.
            color: root._rest
            // Behavior and the flash animation both drive `color`; only one of
            // them is ever active on a given tile.
            Behavior on color {
                enabled: !root.flashOnChange
                ColorAnimation { duration: 120 }
            }
            onTextChanged: if (root.flashOnChange) flashAnim.restart()
            SequentialAnimation {
                id: flashAnim
                ColorAnimation {
                    target: valueText; property: "color"
                    to: Theme.palette.success; duration: 160; easing.type: Easing.OutQuad
                }
                ColorAnimation {
                    target: valueText; property: "color"
                    to: root._rest; duration: 1100; easing.type: Easing.InOutQuad
                }
            }
        }
        LogosText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.sub.length > 0
            text: root.sub
            color: Theme.palette.textTertiary
            opacity: 0.65
            font.pixelSize: Theme.typography.secondaryText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        ColumnLayout {
            id: extraSlot
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: children.length > 0 ? Theme.spacing.small : 0
            spacing: Theme.spacing.tiny
        }
    }
}
