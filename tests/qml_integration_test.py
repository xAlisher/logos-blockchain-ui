"""Static integration guards supplement real Qt component tests; no live backend.

Updated for the Blend TAB (BlendView) that replaced the modal (#112/#119): the
evidence strip + enable/manage flow live under a dedicated tab, the Node page no
longer carries the strip (#118), the header Enable-Blend button is gone (#120),
and every spendable wallet key has a real Fund action (#117).
"""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / 'src/qml'


class Integration(unittest.TestCase):
    def test_blend_tab_hosts_strip(self):
        # The evidence strip now lives in the Blend tab, not the Node page (#118).
        blend = (ROOT / 'views/BlendView.qml').read_text()
        self.assertIn('BlendCoreProgress {', blend)
        self.assertIn('lifecycle: root.controller', blend)
        node = (ROOT / 'views/NodeDashboardView.qml').read_text()
        self.assertNotIn('BlendCoreProgress {', node)
        # BlendView is registered in the views module so `BlendView {}` resolves.
        qmldir = (ROOT / 'views/qmldir').read_text()
        self.assertIn('BlendView 1.0 BlendView.qml', qmldir)

    def test_controller_wired_to_tab(self):
        text = (ROOT / 'BlockchainView.qml').read_text()
        self.assertIn('BlendLifecycleController {', text)
        self.assertIn('bridge: logos', text)
        self.assertIn('BlendView {', text)
        self.assertIn('controller: blendLifecycleController', text)

    def test_modal_removed(self):
        # The modal file is gone and nothing references it any more (#119).
        self.assertFalse((ROOT / 'views/EnableBlendCoreModal.qml').exists())
        text = (ROOT / 'BlockchainView.qml').read_text()
        self.assertNotIn('enableBlendModal', text)
        self.assertNotIn('EnableBlendCoreModal 1.0', (ROOT / 'views/qmldir').read_text())

    def test_header_button_removed(self):
        # No header "Enable Blend Core" GhostButton; the Blend tab button is the entry (#120).
        text = (ROOT / 'BlockchainView.qml').read_text()
        self.assertNotIn('id: blendBtn', text)
        # The dead enableBlendRequested signal + handler are gone (no tile CTA).
        self.assertNotIn('enableBlendRequested', text)
        self.assertIn('text: qsTr("Blend")', text)   # Blend tab button is the entry point

    def test_wallet_fund_wired(self):
        # A real Fund action on every spendable key → faucet (#117).
        delegate = (ROOT / 'controls/AccountDelegate.qml').read_text()
        self.assertIn('signal fundRequested(string addressHex)', delegate)
        self.assertIn('text: qsTr("Fund")', delegate)
        view = (ROOT / 'views/AccountsView.qml').read_text()
        self.assertIn('signal fundRequested(string addressHex)', view)
        blockchain = (ROOT / 'BlockchainView.qml').read_text()
        self.assertIn('onFundRequested:', blockchain)

    def test_honest_copy(self):
        blend = (ROOT / 'views/BlendView.qml').read_text()
        helptext = (ROOT / 'views/infoContent.js').read_text()
        for claim in ['Included in a block', 'Your staked note is unlocked.', 'emitting the active heartbeat']:
            self.assertNotIn(claim, blend)
        self.assertNotIn('does NOT emit', helptext)
        self.assertNotIn('and earning rewards.', helptext)

    def test_no_hardcoded_liveness(self):
        # Liveness must derive from real signals, not hardcoded values. (Values are rendered
        # neutral/white now, so this guards the derivation, not the colour.)
        blend = (ROOT / 'views/BlendView.qml').read_text()
        # heartbeat must never be an unconditional green "Sending" — it needs a negative branch
        self.assertNotIn('v: qsTr("Sending"); valColor: Theme.palette.success', blend)
        self.assertIn('Not sending', blend)                 # heartbeat has a real negative state
        self.assertIn('_hb ? qsTr("Sending")', blend)       # ...derived from blendStatus, not hardcoded
        # reachability honours a real unreachable verdict, and can show it
        self.assertIn('reachVerdict === "unreachable"', blend)
        self.assertIn('Not reachable', blend)

    def test_core_nodes_table_and_message_cards(self):
        # The Blend tab (not the dashboard) hosts the Core-nodes table + message cards,
        # fed from the merged API+log telemetry the backend attaches to the lifecycle payload.
        blend = (ROOT / 'views/BlendView.qml').read_text()
        self.assertIn('property var corePeers', blend)
        self.assertIn('property var blendMsgs', blend)
        self.assertIn('Core nodes', blend)
        self.assertIn('component Tile', blend)
        # source tags per node come from the backend, not hardcoded
        self.assertIn('peerRow.modelData.sources', blend)

    def test_lifecycle_stages_modal(self):
        # The lifecycle strip's (i) opens a stages modal; the six stages match the reducer labels.
        blend = (ROOT / 'views/BlendView.qml').read_text()
        strip = (ROOT / 'controls/BlendCoreProgress.qml').read_text()
        self.assertIn('signal explainRequested', strip)
        self.assertIn('onExplainRequested: root._openInfo(root._lifecycleInfo)', blend)
        for stage in ['Online', 'Declared', 'Activated', 'Connected', 'Activity', 'Maintaining']:
            self.assertIn('qsTr("%s")' % stage, blend)


if __name__ == '__main__':
    unittest.main()
