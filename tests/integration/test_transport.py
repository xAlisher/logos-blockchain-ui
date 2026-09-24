#!/usr/bin/python3
"""Transport boundary regressions only; never counts as native recovery coverage."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import run


class TransportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='blend-transport-', dir='/extra/tmp')
        self.root = Path(self.tmp.name) / 'fixture'
        self.env = run.prepare(self.root, dict(name='transport', state='collecting'))

    def tearDown(self):
        self.tmp.cleanup()

    def request(self, route, body, response):
        (self.root / 'responses.json').write_text(json.dumps({'POST ' + route: response}))
        return subprocess.run(['/usr/bin/python3', '-I', str(run.HERE / 'run.py'), '--child',
                               str(self.root / 'bin/curl'), '-X', 'POST', '-d', json.dumps(body),
                               '-w', '\n%{http_code}', 'http://127.0.0.1:8080' + route],
                              cwd=self.root, env=self.env, capture_output=True, text=True, timeout=15)

    def test_recovery_fixture_shapes_and_external_transition(self):
        import recovery_cases
        scenario = recovery_cases.Scenario(run, Path(self.tmp.name), Path('/not-an-executable'), 'wire-shapes')
        try:
            before = json.loads((scenario.root / 'responses.json').read_text())
            declaration = before['GET /mantle/sdp/declarations']['body'][run.ID]
            self.assertEqual(set(declaration), {'provider_id', 'service_type', 'created', 'active', 'nonce',
                                               'locked_note_id', 'zk_id', 'withdraw_at', 'locators'})
            self.assertEqual(set(before['GET ' + recovery_cases.WALLET]['body']),
                             {'address', 'tip', 'balance', 'notes'})
            scenario.snapshot(epoch=17, slot=1700, lib=1600, record=None)
            after = json.loads((scenario.root / 'responses.json').read_text())
            self.assertEqual(after['GET /mantle/sdp/declarations']['body'], {})
            self.assertEqual(after['GET /cryptarchia/info']['body']['cryptarchia_info']['lib_slot'], 1600)
            self.assertTrue((scenario.root / 'responses-001.json').exists())
            self.assertFalse((scenario.root / 'requests.jsonl').exists())
            self.assertFalse((scenario.root / 'blend-recovery.json').exists())
        finally:
            scenario.close()

    def test_descendant_inherits_ipv4_ipv6_denial(self):
        probe = ('import socket, errno\n'
                 'for family in (socket.AF_INET, socket.AF_INET6):\n'
                 ' try: socket.socket(family, socket.SOCK_STREAM)\n'
                 ' except OSError as error: assert error.errno == errno.EPERM\n'
                 ' else: raise AssertionError("seccomp was not inherited")\n'
                 'print("IPv4/IPv6 denied in exec descendant")\n')
        result = subprocess.run(['/usr/bin/python3', '-I', str(run.HERE / 'run.py'), '--child',
                                 '/usr/bin/python3', '-I', '-c', probe], cwd=self.root, env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('IPv4/IPv6 denied', result.stdout)

    def test_withdrawal_bare_owned_id(self):
        reply = self.request('/sdp/withdrawal', run.ID, {'body': None, 'expect_body': run.ID})
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertEqual(reply.stdout, 'null\n200')
        logged = json.loads((self.root / 'requests.jsonl').read_text())
        self.assertEqual(json.loads(logged['body']), run.ID)

    def test_join_exact_body(self):
        body = {'locator': '/ip4/192.0.2.1/udp/3400/quic-v1', 'locked_note_id': 'e' * 64}
        reply = self.request('/blend/join', body, {'body': run.ID, 'expect_body': body})
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertEqual(json.loads(reply.stdout.splitlines()[0]), run.ID)

    def test_reject_incorrect_body(self):
        reply = self.request('/sdp/withdrawal', {'id': run.ID}, {'body': None, 'expect_body': run.ID})
        self.assertEqual(reply.returncode, 99)

    def test_reject_unapproved_mutation(self):
        reply = self.request('/wallet/fund', {}, {'body': None, 'expect_body': {}})
        self.assertEqual(reply.returncode, 99)

    def test_timeout_is_recorded_without_reply(self):
        reply = self.request('/sdp/withdrawal', run.ID,
                             {'body': None, 'expect_body': run.ID, 'exit': 28})
        self.assertEqual(reply.returncode, 28, reply.stderr)
        self.assertEqual(reply.stdout, '')
        self.assertEqual(len((self.root / 'requests.jsonl').read_text().splitlines()), 1)

    def test_http_500_is_not_a_shim_failure(self):
        reply = self.request('/sdp/withdrawal', run.ID,
                             {'body': {'error': 'synthetic uncertainty'}, 'expect_body': run.ID, 'code': 500})
        self.assertEqual(reply.returncode, 0, reply.stderr)
        self.assertTrue(reply.stdout.endswith('\n500'))


if __name__ == '__main__':
    unittest.main()
