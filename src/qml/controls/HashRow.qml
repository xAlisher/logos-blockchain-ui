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

    // All three centre on the same line. The label used to be Qt.AlignTop while
    // the value and button defaulted to centring in a row whose height comes from
    // the 22px copy button — so the label floated above its own value. The value
    // is single-line by construction (ElideMiddle, no wrapMode), so there is
    // nothing for AlignTop to serve. The label is also a different font family
    // from the monospace value, so centring is what keeps them visually level.
    LogosText {
        visible: root.label.length > 0
        text: root.label
        Layout.preferredWidth: root.labelWidth
        Layout.alignment: Qt.AlignVCenter
        color: Theme.palette.textSecondary
        font.pixelSize: Theme.typography.secondaryText
    }
    LogosText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        text: root.value && root.value.length > 0 ? root.value : "—"
        elide: Text.ElideMiddle
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Theme.typography.secondaryText
        font.family: "monospace"
    }
    BcCopyButton {
        Layout.alignment: Qt.AlignVCenter
        visible: root.copyable && root.value && root.value.length > 0
        onCopyText: root.copyRequested(root.value)
    }
}
