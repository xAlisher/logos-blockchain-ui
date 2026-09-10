import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Logos.Theme
import Logos.Controls

// Legal disclaimer — long text in an inner-scrolling dialog.
LogosDialog {
    id: root
    title: qsTr("Legal disclaimer")
    modal: true
    anchors.centerIn: parent
    width: 560
    height: 460

    property string body: qsTr(
        "This software runs an experimental Logos blockchain node on a test network.\n\n" +
        "No warranty. The software is provided “as is”, without warranty of any kind, express or implied, " +
        "including but not limited to the warranties of merchantability, fitness for a particular purpose and " +
        "non-infringement. You run the node at your own risk.\n\n" +
        "Test network only. Tokens, rewards, balances and any other value shown by this application are part of a " +
        "test network. They have no monetary value, are not securities, and may be reset, revoked or lost at any " +
        "time without notice. Nothing here constitutes financial, investment, tax or legal advice.\n\n" +
        "Mining / funding. “Fund”, “Mining” and related actions generate and claim test tickets. Fees are paid " +
        "from claimed tickets. Unclaimed tickets may expire. Progress, thresholds and estimates are indicative and " +
        "may change as the protocol evolves.\n\n" +
        "Validation. A node becomes eligible to lead only after its notes have aged (approximately two epochs). " +
        "Eligibility, proposing and rewards depend on network conditions outside the operator’s control.\n\n" +
        "Resource use. Running a node consumes CPU, memory, disk and bandwidth. You are responsible for your own " +
        "hardware, connectivity and any costs incurred.\n\n" +
        "Data. Configuration and keys are stored locally on your machine. Protect your keys; loss of keys may mean " +
        "loss of access to any associated test balances.\n\n" +
        "By continuing to use this application you acknowledge that you have read and understood this disclaimer.")

    contentItem: QQC.ScrollView {
        id: sv
        clip: true
        QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded
        LogosText {
            width: sv.availableWidth
            text: root.body
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            wrapMode: Text.WordWrap
            lineHeight: 1.35
        }
    }

    rightActions: [
        LogosButton { text: qsTr("Close"); onClicked: root.close() }
    ]
}
