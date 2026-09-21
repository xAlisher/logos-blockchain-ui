"""Static integration guards supplement real Qt component tests; no live backend."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1] / 'src/qml'

class Integration(unittest.TestCase):
    def test_panel_below_node(self):
        text = (ROOT / 'views/NodeDashboardView.qml').read_text()
        self.assertLess(text.index('showLane: true; laneSteps:'), text.index('BlendCoreProgress {'))
        self.assertIn('onRepairRequested: root.repairBlendRequested()', text)
    def test_controller_wired(self):
        text = (ROOT / 'BlockchainView.qml').read_text()
        self.assertIn('BlendLifecycleController {', text)
        self.assertIn('bridge: logos', text)
        self.assertIn('onRepairBlendRequested: blendLifecycleController.repair()', text)
    def test_honest_copy(self):
        modal = (ROOT / 'views/EnableBlendCoreModal.qml').read_text()
        helptext = (ROOT / 'views/infoContent.js').read_text()
        for claim in ['Included in a block', 'Your staked note is unlocked.', 'emitting the active heartbeat']:
            self.assertNotIn(claim, modal)
        self.assertNotIn('does NOT emit', helptext)
        self.assertNotIn('and earning rewards.', helptext)

if __name__ == '__main__': unittest.main()
