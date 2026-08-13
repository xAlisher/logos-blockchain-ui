import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

import "../controls"

// Live Cryptarchia consensus state, polled from get_cryptarchia_info.
// The result `value` is a JSON string; parsed defensively (nested under
// "cryptarchia_info" or flat, mode as string or numeric enum).
Rectangle {
    id: root

    property string infoJson: ""
    property string errorText: ""

    signal copyToClipboard(string text)

    readonly property var info: parse(infoJson)

    function parse(s) {
        try { return s && s.length > 0 ? JSON.parse(s) : null } catch (e) { return null }
    }

    function field(key) {
        if (!info) return undefined
        if (info.cryptarchia_info && info.cryptarchia_info[key] !== undefined)
            return info.cryptarchia_info[key]
        return info[key]
    }

    function num(key) {
        var v = field(key)
        return (v === undefined || v === null) ? qsTr("—") : String(v)
    }

    function hash(key) {
        var v = field(key)
        return (v === undefined || v === null) ? "" : String(v)
    }

    // Liveness field. 0.2.1 moved it to `cryptarchia_info.state` (string
    // "Online"/"Bootstrapping"); older 0.2.0 builds put a top-level `mode`
    // (string, or the c-binding numeric enum 0 Bootstrapping / 1 Online /
    // 2 NotStarted). Accept all: top-level `mode` first, then nested `state`.
    function modeText() {
        var m = info ? info.mode : undefined
        if (m === undefined || m === null) m = field("state")
        if (m === undefined || m === null) return qsTr("—")
        if (typeof m === "number") {
            switch (m) {
            case 0: return qsTr("Bootstrapping")
            case 1: return qsTr("Online")
            case 2: return qsTr("Not Started")
            default: return String(m)
            }
        }
        return String(m)
    }

    function modeColor() {
        var t = modeText()
        if (t === qsTr("Online")) return Theme.palette.success
        if (t === qsTr("Bootstrapping")) return Theme.palette.warning
        return Theme.palette.textSecondary
    }

    implicitHeight: contentCol.implicitHeight + 2 * Theme.spacing.large
    color: Theme.palette.backgroundTertiary
    radius: Theme.spacing.radiusLarge
    border.color: Theme.palette.border
    border.width: 1

    ColumnLayout {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.large
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                text: qsTr("Consensus")
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            LogosText {
                text: root.modeText()
                color: root.modeColor()
                font.pixelSize: Theme.typography.secondaryText
                font.bold: true
            }
        }

        LogosText {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            text: root.errorText
            color: Theme.palette.error
            font.pixelSize: Theme.typography.secondaryText
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.errorText.length === 0
            spacing: Theme.spacing.large
            LogosText {
                text: qsTr("Slot: %1").arg(root.num("slot"))
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            LogosText {
                text: qsTr("Height: %1").arg(root.num("height"))
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            LogosText {
                visible: root.field("lib_slot") !== undefined
                text: qsTr("LIB slot: %1").arg(root.num("lib_slot"))
                font.pixelSize: Theme.typography.secondaryText
                color: Theme.palette.textSecondary
            }
            Item { Layout.fillWidth: true }
        }

        HashRow {
            visible: root.errorText.length === 0
            label: qsTr("Tip")
            value: root.hash("tip")
            onCopyRequested: (t) => root.copyToClipboard(t)
        }
        HashRow {
            visible: root.errorText.length === 0
            label: qsTr("LIB")
            value: root.hash("lib")
            onCopyRequested: (t) => root.copyToClipboard(t)
        }
    }
}
