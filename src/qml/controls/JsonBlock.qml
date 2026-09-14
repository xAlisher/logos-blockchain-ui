import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A boxed, monospace, wrapping JSON/text block. Used for prettified payloads
// and raw fallbacks. Rendered with a read-only TextEdit so the content can be
// selected with the mouse and copied (Cmd/Ctrl+C), in addition to the dedicated
// copy buttons elsewhere.
Rectangle {
    id: root

    property string json: ""

    Layout.fillWidth: true
    implicitHeight: jsonText.implicitHeight + 2 * Theme.spacing.small
    color: Theme.palette.backgroundSecondary
    radius: Theme.spacing.radiusSmall
    border.color: Theme.palette.border
    border.width: 1

    TextEdit {
        id: jsonText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.small
        text: root.json
        readOnly: true
        selectByMouse: true
        persistentSelection: true
        // Treat the payload as literal text; never interpret it as rich text.
        textFormat: TextEdit.PlainText
        color: Theme.palette.text
        selectionColor: Theme.palette.overlayOrange
        selectedTextColor: Theme.palette.text
        font.pixelSize: Theme.typography.secondaryText
        font.family: "monospace"
        wrapMode: TextEdit.WrapAnywhere
    }
}
