import QtQuick
import QtQuick.Layouts
import Logos.Theme
import Logos.Controls

// ── EXPERIMENT: drag-to-reorder metric tiles ───────────────────────────────
// Only the lower metric cards reorder (the Status hero is fixed). Interaction:
//   • hover a card → a grip appears in its lower-right
//   • press the grip and drag → a lifted, highlighted proxy follows the cursor,
//     the source card stays as a faint ghost
//   • while dragging → the nearest gap between cards shows a vertical indicator
//     (gray, darker than the background)
//   • release → the card drops into that gap; the rest rearrange (animated)
// Self-contained, sample values — a feel test before porting into the real grid.
Item {
    id: root

    readonly property int minCard: 210
    readonly property int gap: Theme.spacing.large
    readonly property int cols: Math.max(1, Math.floor((width + gap) / (minCard + gap)))
    readonly property real cardW: cols > 0 ? (width - (cols - 1) * gap) / cols : width
    readonly property int cardH: 108

    // drag state
    property int dragIndex: -1                 // model row being dragged (-1 = none)
    property int targetIndex: -1               // insertion slot the indicator marks
    property real proxyX: 0
    property real proxyY: 0
    property string proxyLabel: ""
    property string proxyValue: ""

    ListModel {
        id: tiles
        ListElement { label: "Stake";    value: "5T LGO" }
        ListElement { label: "Earned";   value: "—" }
        ListElement { label: "Blend";    value: "Not active" }
        ListElement { label: "Epoch";    value: "173" }
        ListElement { label: "Proposed"; value: "0 Blocks" }
        ListElement { label: "Peers";    value: "39" }
        ListElement { label: "Peer ID";  value: "12D3Ko…EwLz" }
        ListElement { label: "Mining";   value: "—" }
        ListElement { label: "CPU";      value: "15%" }
        ListElement { label: "RAM";      value: "1.2GB" }
        ListElement { label: "Slot";     value: "150001" }
        ListElement { label: "Height";   value: "150001" }
    }

    // insertion slot nearest the cursor, in reading order (row-major).
    // counts cards whose center precedes the cursor; the dragged card is skipped.
    function computeTarget(px, py) {
        var idx = 0
        for (var i = 0; i < rep.count; i++) {
            if (i === root.dragIndex) continue
            var it = rep.itemAt(i)
            if (!it) continue
            var cx = it.x + it.width / 2, cy = it.y + it.height / 2
            var earlierRow = py > cy + it.height / 2                 // cursor is below this card's row
            var sameRow = Math.abs(py - cy) <= it.height / 2 + root.gap / 2
            if (earlierRow || (sameRow && px > cx)) idx++
        }
        return idx
    }

    function endDrag(commit) {
        if (commit && root.dragIndex >= 0 && root.targetIndex >= 0) {
            var from = root.dragIndex
            var to = root.targetIndex
            if (to > from) to -= 1          // removing the source shifts later slots left
            if (to !== from && to >= 0 && to < tiles.count) tiles.move(from, to, 1)
        }
        root.dragIndex = -1; root.targetIndex = -1
    }

    // ── the grid ──
    Flow {
        id: flow
        anchors.fill: parent
        spacing: root.gap
        move: Transition { NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic } }

        Repeater {
            id: rep
            model: tiles

            delegate: LogosFrame {
                id: card
                required property int index
                required property string label
                required property string value
                width: root.cardW; height: root.cardH
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: hoverArea.containsMouse && root.dragIndex < 0 ? Theme.palette.border : "transparent"
                radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
                opacity: root.dragIndex === index ? 0.35 : 1.0      // source ghost while its proxy is dragged
                Behavior on opacity { NumberAnimation { duration: 120 } }

                contentItem: ColumnLayout {
                    spacing: Theme.spacing.small
                    LogosText { text: card.label; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                    LogosText { text: card.value; color: Theme.palette.text; font.pixelSize: 24; font.weight: Theme.typography.weightBold }
                }

                // hover tracking (whole card) — reveals the grip
                MouseArea {
                    id: hoverArea; anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.NoButton                     // hover only; the grip handles the drag
                }

                // grip handle (lower-right) — appears on hover, is the drag affordance
                Item {
                    id: grip
                    width: 22; height: 22
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.rightMargin: Theme.spacing.small; anchors.bottomMargin: Theme.spacing.small
                    opacity: (hoverArea.containsMouse || dragArea.pressed) && root.dragIndex !== card.index ? 1 : (root.dragIndex === card.index ? 0 : 0)
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    // six-dot drag glyph
                    Grid {
                        anchors.centerIn: parent; columns: 2; rowSpacing: 3; columnSpacing: 3
                        Repeater { model: 6; Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.palette.textTertiary } }
                    }
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent; cursorShape: Qt.OpenHandCursor
                        onPressed: (m) => {
                            root.dragIndex = card.index
                            root.proxyLabel = card.label; root.proxyValue = card.value
                            var p = mapToItem(root, m.x, m.y)
                            root.proxyX = p.x - root.cardW + 30; root.proxyY = p.y - root.cardH + 30
                            root.targetIndex = card.index
                        }
                        onPositionChanged: (m) => {
                            if (root.dragIndex < 0) return
                            var p = mapToItem(root, m.x, m.y)
                            root.proxyX = p.x - root.cardW + 30; root.proxyY = p.y - root.cardH + 30
                            root.targetIndex = root.computeTarget(p.x, p.y)
                        }
                        onReleased: root.endDrag(true)
                        onCanceled: root.endDrag(false)
                    }
                }
            }
        }
    }

    // ── insertion indicator: a vertical bar in the target gap (gray, darker than bg) ──
    Rectangle {
        id: indicator
        visible: root.dragIndex >= 0 && root.targetIndex >= 0
        width: 4; radius: 2
        color: Qt.darker(Theme.palette.background, 2.2)
        z: 5
        // sit just left of the card currently at the target slot; if the target is the
        // end of a row / list, sit just right of the last card before it.
        Binding on x {
            when: indicator.visible
            value: {
                var t = root.targetIndex
                var ref = (t < rep.count) ? rep.itemAt(t) : null
                if (ref && !(t === root.dragIndex)) return ref.x - root.gap / 2 - width / 2
                var prev = rep.itemAt(Math.max(0, t - 1))
                return prev ? prev.x + prev.width + root.gap / 2 - width / 2 : 0
            }
        }
        Binding on y {
            when: indicator.visible
            value: {
                var t = root.targetIndex
                var ref = (t < rep.count) ? rep.itemAt(t) : rep.itemAt(Math.max(0, t - 1))
                return ref ? ref.y : 0
            }
        }
        height: root.cardH
    }

    // ── the lifted proxy that follows the cursor (highlighted) ──
    LogosFrame {
        id: proxy
        visible: root.dragIndex >= 0
        x: root.proxyX; y: root.proxyY; z: 10
        width: root.cardW; height: root.cardH
        backgroundColor: Theme.palette.surfaceRaised
        borderColor: Theme.palette.primary; radius: Theme.spacing.radiusLarge; padding: Theme.spacing.large
        scale: root.dragIndex >= 0 ? 1.03 : 1.0
        Behavior on scale { NumberAnimation { duration: 120 } }
        // soft lift shadow
        Rectangle {
            anchors.fill: parent; anchors.margins: -1; z: -1
            radius: parent.radius; color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.35); border.width: 6
            opacity: 0.4
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { text: root.proxyLabel; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            LogosText { text: root.proxyValue; color: Theme.palette.text; font.pixelSize: 24; font.weight: Theme.typography.weightBold }
        }
    }
}
