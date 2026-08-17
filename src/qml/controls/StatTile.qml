import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A stat tile matching the Node dashboard's Slot/Height/Balance/Peers row:
// rounded, elevated, centred label over value. Shared so the two pages cannot
// drift apart — the private-duplicate habit is what left three different hash
// rows in this module.
//
// `info` puts a click-to-open (i) in the top-right, the same InfoButton the
// Claims header uses. Deliberately NOT a hover tooltip: long explanations
// popping up under the cursor were unreadable, and they fired while the pointer
// was merely on its way to the CTA.
//
// `interactive: true` makes the VALUE the affordance — it tints on hover and
// emits clicked(). The hit area is the number alone, never the whole tile, or it
// swallows anything else in the card.
//
// Default children sit on the value's line, immediately after it. The value stays
// centred on the tile axis and extras hang off its right edge, so the number
// still lines up under the label — centring the pair as a group is what made the
// number look off-axis.
Rectangle {
    id: root

    property string label: ""
    property string value: ""
    property string sub: ""
    // Long-form help behind the (i). Empty = no icon.
    property string info: ""
    property bool interactive: false
    // Flash the value green when it changes — for tiles that tick (Slot, Height).
    property bool flashOnChange: false
    // Keeps the Node dashboard's tile geometry; taller content grows past it.
    property int minHeight: 68
    // Pin content to the top instead of centring. Pinning keeps LABELS on one
    // line when sibling tiles carry a different number of rows.
    property bool topAligned: false

    signal clicked()

    default property alias extra: inlineSlot.data

    readonly property color _rest: (root.interactive && valueHover.hovered)
        ? Theme.palette.primary : Theme.palette.text

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(root.minHeight,
                                     col.implicitHeight
                                     + (root.topAligned ? 2 * Theme.spacing.large
                                                        : 2 * Theme.spacing.medium))
    radius: Theme.spacing.radiusLarge
    color: Theme.palette.backgroundTertiary
    border.width: 0

    InfoButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacing.tiny
        visible: root.info.length > 0
        text: root.info
    }

    ColumnLayout {
        id: col
        // Explicit anchors: centerIn and horizontalCenter together are a conflict
        // and Qt silently drops one of them.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: root.topAligned ? undefined : parent.verticalCenter
        anchors.top: root.topAligned ? parent.top : undefined
        anchors.topMargin: root.topAligned ? Theme.spacing.large : 0
        width: parent.width - 2 * Theme.spacing.medium
        spacing: root.topAligned ? Theme.spacing.small : 2

        LogosText {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            font.pixelSize: Theme.typography.secondaryText
            color: Theme.palette.textSecondary
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(valueText.implicitHeight, inlineSlot.implicitHeight)

            LogosText {
                id: valueText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                text: root.value
                font.pixelSize: Theme.typography.panelTitleText
                font.weight: Theme.typography.weightMedium
                color: root._rest
                Behavior on color {
                    enabled: !root.flashOnChange
                    ColorAnimation { duration: 120 }
                }
                onTextChanged: if (root.flashOnChange) flashAnim.restart()

                HoverHandler {
                    id: valueHover
                    enabled: root.interactive
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    enabled: root.interactive
                    onTapped: root.clicked()
                }
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

            RowLayout {
                id: inlineSlot
                anchors.left: valueText.right
                anchors.leftMargin: Theme.spacing.medium
                anchors.verticalCenter: valueText.verticalCenter
                spacing: Theme.spacing.tiny
            }
        }

        LogosText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            visible: root.sub.length > 0
            text: root.sub
            color: Theme.palette.textTertiary
            opacity: 0.65
            font.pixelSize: Theme.typography.secondaryText
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
