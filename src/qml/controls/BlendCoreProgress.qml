import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Presentation only: independent evidence per stage, never inferred from Core mode.
LogosFrame {
    id: root
    property var lifecycle: ({})
    property bool busy: false
    property bool backendReady: false
    property bool loading: false
    property bool recoveryBusy: false
    property bool recoveryNeedsRead: false
    property bool recoveryLocked: !!recovery.active
    property string recoveryResultText: ""
    property bool recoveryResultError: false
    readonly property var recovery: data.recovery || ({})
    readonly property bool canRecover: backendReady && !busy && !recoveryBusy && !recoveryNeedsRead && !recoveryLocked && recovery.canStart === true
    readonly property color recoveryAccent: recovery.tone === "error" ? Theme.palette.error
        : recovery.tone === "warning" ? Theme.palette.warning : Theme.palette.textSecondary
    signal recoverRequested()
    signal pauseRecoveryRequested()
    signal resumeRecoveryRequested()
    signal dismissRecoveryRequested()   // clear a terminally-stopped (attention) recovery
    property string resultText: ""
    property bool resultError: false
    // Auto-hide the refresh result (e.g. "Checked — no change.") a few seconds after it lands,
    // shown to the right of the action button instead of permanently on top.
    property bool _showResult: false
    onResultTextChanged: if (resultText.length > 0) { _showResult = true; resultHideTimer.restart() }
    Timer { id: resultHideTimer; interval: 4000; repeat: false; onTriggered: root._showResult = false }
    property bool expanded: false
    property bool userToggled: false
    onDataChanged: if (!userToggled) expanded = data.tone === "warning" || data.tone === "error" || root.resultError
    Component.onCompleted: if (!userToggled) expanded = data.tone === "warning" || data.tone === "error"
    // An error result keeps the panel open so it stays visible (it lives in the detail area).
    onResultErrorChanged: if (resultError && !userToggled) expanded = true
    signal manageRequested()
    signal repairRequested()
    signal refreshRequested()
    readonly property var data: lifecycle || ({})
    readonly property color accent: data.tone === "error" ? Theme.palette.error
        : data.tone === "warning" ? Theme.palette.warning
        : data.tone === "success" ? Theme.palette.success : Theme.palette.textSecondary
    backgroundColor: Theme.palette.surfaceRaised
    borderColor: "transparent"
    background: Rectangle { color: root.backgroundColor; radius: Theme.spacing.radiusLarge }
    padding: Theme.spacing.large
    implicitWidth: 920
    QQC.Dialog {
        id: recoveryConfirmation
        objectName: "blendRecoveryConfirmation"
        parent: QQC.Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(460, parent ? parent.width - 24 : 460)
        modal: true
        title: qsTr("Recover Core?")
        background: Rectangle { color: Theme.palette.surfaceRaised; radius: Theme.spacing.radiusLarge }
        header: LogosText { text: recoveryConfirmation.title; padding: 20; color: Theme.palette.text; font.pixelSize: 22 }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            LogosText {
                objectName: "blendRecoveryDisclosure"
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                text: qsTr("Recovery requests one withdrawal, waits for chain removal, then makes a fresh declaration and restores binding. Transaction fees apply. The node will temporarily operate as Edge; Core activation can take epochs. Your wallet keys and node identity are preserved.")
                color: Theme.palette.textSecondary
            }
            LogosText {
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                text: qsTr("The backend runs and saves this workflow. Pausing stops automation only — it cannot undo an on-chain withdrawal. Resume reconciles progress, not blindly retries paid transactions. Accepted renewals are monitored; lasting Core membership is not guaranteed.")
                color: Theme.palette.textSecondary
            }
            Flow {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosButton { text: qsTr("Cancel"); onClicked: recoveryConfirmation.close() }
                LogosButton {
                    objectName: "blendRecoveryConfirm"
                    text: qsTr("Recover Core")
                    enabled: root.canRecover
                    onClicked: {
                        if (!root.canRecover || !recoveryConfirmation.opened) return
                        recoveryConfirmation.close()
                        root.recoverRequested()
                    }
                }
            }
        }
    }
    contentItem: ColumnLayout {
        spacing: Theme.spacing.small
        // The big state title doubles as the expand/collapse control (tap to toggle);
        // no separate "Blend Core" label or chevron row — the card lives in the Blend tab.
        LogosText {
            objectName: "blendTitle"
            Layout.fillWidth: true
            text: root.data.title || qsTr("Status unavailable")
            color: root.accent; font.pixelSize: 24; font.weight: Theme.typography.weightBold
            wrapMode: Text.WordWrap; textFormat: Text.PlainText
            Accessible.name: (root.expanded ? qsTr("Collapse") : qsTr("Expand")) + " " + text
            TapHandler {
                objectName: "blendToggle"
                onTapped: { root.userToggled = true; root.expanded = !root.expanded }
            }
        }
        Item {
            id: lane
            objectName: "blendStrip"
            Layout.fillWidth: true
            Layout.bottomMargin: Theme.spacing.medium   // breathing room between the strip and the text below it
            implicitHeight: 30
            readonly property var steps: root.data.steps && root.data.steps.length ? root.data.steps
                : [qsTr("Online"), qsTr("Declared"), qsTr("Activated"), qsTr("Connected"), qsTr("Activity"), qsTr("Maintaining")].map(function(label) { return {label: label, state: "pending"} })
            readonly property real depth: 14
            readonly property real segmentWidth: (width + (steps.length - 1) * 12) / Math.max(1, steps.length)
            function segmentLeft(i) { return i * (segmentWidth - 12) }
            onStepsChanged: canvas.requestPaint()
            onWidthChanged: canvas.requestPaint()
            // Breathe the CURRENT chevron (like the dashboard's aged lane): ease up, ease down.
            readonly property bool hasCurrent: {
                var s = steps; for (var i = 0; i < s.length; ++i) if (s[i].state === "current") return true; return false
            }
            property real breathe: 0
            onBreatheChanged: canvas.requestPaint()
            SequentialAnimation on breathe {
                running: lane.hasCurrent; loops: Animation.Infinite
                NumberAnimation { from: 0; to: 1; duration: 1400; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1; to: 0; duration: 1400; easing.type: Easing.InOutSine }
            }
            Canvas {
                id: canvas
                anchors.fill: parent
                onAvailableChanged: if (available) requestPaint()
                onPaint: {
                    var ctx = getContext("2d"); ctx.reset()
                    for (var i = 0; i < lane.steps.length; ++i) {
                        var x0 = lane.segmentLeft(i), x1 = x0 + lane.segmentWidth
                        var state = lane.steps[i].state
                        var c = state === "error" ? Theme.palette.error : root.accent
                        ctx.fillStyle = state === "complete" ? Theme.palette.surface
                            : state === "pending" ? Theme.palette.surfaceRecessed
                            : Qt.rgba(c.r, c.g, c.b, 0.14 + 0.30 * lane.breathe)   // current → breathing
                        var pts = [[x0, 0]]
                        if (i === lane.steps.length - 1) pts.push([x1, 0], [x1, height])
                        else pts.push([x1 - 14, 0], [x1, height / 2], [x1 - 14, height])
                        pts.push([x0, height])
                        if (i > 0) pts.push([x0 + 14, height / 2])
                        var last = pts[pts.length - 1], first = pts[0]
                        ctx.beginPath(); ctx.moveTo((last[0] + first[0]) / 2, (last[1] + first[1]) / 2)
                        for (var k = 0; k < pts.length; ++k) {
                            var p = pts[k], next = pts[(k + 1) % pts.length]
                            ctx.arcTo(p[0], p[1], next[0], next[1], 3)
                        }
                        ctx.closePath(); ctx.fill()
                    }
                }
            }
            Repeater {
                model: lane.steps
                Item {
                    id: stepCell
                    required property int index
                    required property var modelData
                    objectName: "blendStep" + index
                    x: lane.segmentLeft(index) + (index > 0 ? 14 : 0)
                    width: lane.segmentWidth - (index > 0 ? 14 : 0) - (index < lane.steps.length - 1 ? 14 : 0)
                    height: lane.height
                    // Like the dashboard lifecycle lane: a GREEN check for completed stages, with the
                    // label itself in muted GRAY; the current stage takes the state accent (yellow
                    // while in-progress), pending is faint.
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        LogosText {
                            id: stepCheck
                            visible: stepCell.modelData.state === "complete"
                            text: "✓"; color: Theme.palette.success
                            font.pixelSize: 12; font.weight: Theme.typography.weightBold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        LogosText {
                            text: stepCell.modelData.label
                            font.pixelSize: 12; textFormat: Text.PlainText; elide: Text.ElideRight
                            width: Math.min(implicitWidth, stepCell.width - (stepCheck.visible ? stepCheck.implicitWidth + parent.spacing : 0))
                            color: stepCell.modelData.state === "error" ? Theme.palette.error
                                : stepCell.modelData.state === "current" ? root.accent
                                : stepCell.modelData.state === "complete" ? Theme.palette.textSecondary
                                : Theme.palette.textTertiary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    QQC.ToolTip.visible: stepHover.hovered
                    QQC.ToolTip.text: stepCell.modelData.label + " · " + stepCell.modelData.state
                    HoverHandler { id: stepHover }
                }
            }
        }
        ColumnLayout {
            objectName: "blendRecoveryProgress"
            Layout.fillWidth: true
            visible: root.recoveryLocked || root.recovery.canStart === true || root.recovery.canResume === true
                || root.recoveryResultText.length > 0 || (!!root.recovery.phase && root.recovery.phase !== "idle")
            spacing: Theme.spacing.small
            LogosText {
                objectName: "blendRecoveryTitle"
                Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                text: root.recovery.title || (root.recoveryLocked ? qsTr("Recovery status pending") : qsTr("Recover Core"))
                color: root.recoveryAccent; font.weight: Theme.typography.weightBold
            }
            LogosText {
                objectName: "blendRecoveryDetail"
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                text: root.recovery.detail || qsTr("Refresh for verified recovery progress. No recovery transaction is sent until you confirm.")
                color: Theme.palette.textSecondary
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width < 520 ? 2 : 3
                columnSpacing: Theme.spacing.small; rowSpacing: Theme.spacing.small
                Repeater {
                    model: root.recovery.steps || []
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        objectName: "blendRecoveryStep" + index
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        implicitHeight: Math.max(34, recoveryStepLabel.implicitHeight + 12)
                        radius: Theme.spacing.radiusSmall
                        color: modelData.state === "current" || modelData.state === "error" ? Theme.palette.surface : Theme.palette.surfaceRecessed
                        LogosText {
                            id: recoveryStepLabel
                            anchors.centerIn: parent; width: parent.width - 16
                            wrapMode: Text.Wrap; textFormat: Text.PlainText
                            text: (modelData.state === "complete" ? "✓ " : modelData.state === "current" ? "• " : "") + modelData.label
                            font.pixelSize: 12
                            color: modelData.state === "error" ? Theme.palette.error
                                : modelData.state === "current" ? root.recoveryAccent : Theme.palette.textSecondary
                        }
                    }
                }
            }
            LogosText {
                objectName: "blendRecoveryResult"
                Layout.fillWidth: true; visible: root.recoveryResultText.length > 0
                text: root.recoveryResultText; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                color: root.recoveryResultError ? Theme.palette.error : Theme.palette.textSecondary
            }
            LogosText {
                Layout.fillWidth: true; visible: root.recoveryLocked
                text: qsTr("Pause stops automation only, not an on-chain withdrawal. Refresh remains available.")
                wrapMode: Text.Wrap; color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText
            }
            Flow {
                Layout.fillWidth: true; spacing: Theme.spacing.small
                LogosButton {
                    objectName: "blendRecover"; text: qsTr("Recover Core")
                    visible: root.recovery.canStart === true && !root.recoveryLocked
                    enabled: root.canRecover
                    onClicked: if (root.canRecover) recoveryConfirmation.open()
                }
                LogosButton {
                    objectName: "blendRecoveryPause"; text: qsTr("Pause recovery")
                    visible: root.recovery.canPause === true
                    enabled: root.backendReady && !root.recoveryBusy
                    onClicked: if (enabled) root.pauseRecoveryRequested()
                }
                LogosButton {
                    objectName: "blendRecoveryResume"; text: qsTr("Resume recovery")
                    visible: root.recovery.canResume === true
                    enabled: root.backendReady && !root.recoveryBusy && !root.recoveryNeedsRead
                    onClicked: if (enabled) root.resumeRecoveryRequested()
                }
                LogosButton {
                    objectName: "blendRecoveryDismiss"; text: qsTr("Dismiss")
                    // Terminal (attention) only — clears the retained journal so it stops nagging.
                    visible: root.recovery.canDismiss === true
                    enabled: root.backendReady && !root.recoveryBusy
                    onClicked: if (enabled) root.dismissRecoveryRequested()
                }
                LogosButton {
                    objectName: "blendRecoveryRefresh"; text: qsTr("Refresh")
                    enabled: root.backendReady && !root.loading
                    onClicked: root.refreshRequested()
                }
            }
        }
        ColumnLayout {
            objectName: "blendExplanation"
            visible: root.expanded
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText {
                Layout.fillWidth: true; text: root.data.detail || qsTr("Refresh to check the node's current evidence.")
                wrapMode: Text.WordWrap; textFormat: Text.PlainText   // whole words, never mid-word breaks
                color: Theme.palette.text                 // white
            }
            LogosText {
                objectName: "blendEvidence"
                Layout.fillWidth: true; text: root.data.evidence || qsTr("Evidence unavailable.")
                wrapMode: Text.WordWrap; textFormat: Text.PlainText   // whole words, never mid-word breaks
                color: Theme.palette.textTertiary; font.pixelSize: Theme.typography.secondaryText
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.spacing.medium
                LogosButton {
                    objectName: "blendAction"
                    text: root.data.actionLabel || qsTr("Refresh")
                    visible: ["manage", "repair", "refresh"].indexOf(root.data.action) >= 0
                    enabled: !root.busy && (!root.recoveryLocked || root.data.action === "refresh")
                    onClicked: {
                        if (!enabled) return
                        if (root.data.action === "manage") root.manageRequested()
                        else if (root.data.action === "repair") root.repairRequested()
                        else if (root.data.action === "refresh") root.refreshRequested()
                    }
                }
                // Refresh result to the RIGHT of the button; auto-hides after a few seconds.
                LogosText {
                    objectName: "blendResult"
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
                    // Errors persist; non-error results (e.g. "Checked — no change.") auto-hide.
                    visible: root.resultText.length > 0 && (root.resultError || root._showResult)
                    text: root.resultText; textFormat: Text.PlainText; elide: Text.ElideRight
                    color: root.resultError ? Theme.palette.error : Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }
        }
    }
}
