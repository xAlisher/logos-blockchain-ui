import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

// A labelled value row with an elided monospace value and a copy button.
// Used for hashes/keys and any short scalar field.
RowLayout {
    id: root

    property string label: ""
    property string value: ""
    property int labelWidth: 110
    property bool copyable: true

    signal copyRequested(string text)

    Layout.fillWidth: true
    spacing: Theme.spacing.small

    LogosText {
        visible: root.label.length > 0
        text: root.label
        Layout.preferredWidth: root.labelWidth
        Layout.alignment: Qt.AlignTop
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }
    LogosText {
        Layout.fillWidth: true
        text: root.value && root.value.length > 0 ? root.value : "—"
        elide: Text.ElideMiddle
        font.pixelSize: Theme.typography.secondaryText
        font.family: "monospace"
    }
    BcCopyButton {
        visible: root.copyable && root.value && root.value.length > 0
        onCopyText: root.copyRequested(root.value)
    }
}
