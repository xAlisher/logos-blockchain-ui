"""Black-box recovery scenarios driving the REAL packaged backend, not a reducer.

Only API response files change. No lifecycle/recovery state is assigned by tests.
Each NativeProcess is a separate exec under the mandatory inherited seccomp filter.
"""
import copy
import json
import os
from pathlib import Path
import select
import subprocess
import time
import traceback

ID, PROVIDER, FUNDING, NOTE = 'b' * 64, 'a' * 64, '3' * 64, 'e' * 64
LOCATOR = '/ip4/192.0.2.1/udp/3400/quic-v1'
WITHDRAW, JOIN, BIND = '/sdp/withdrawal', '/blend/join', '/sdp/set-declaration-id'
WALLET = '/wallet/' + FUNDING + '/balance'


def check(condition, message):
    if not condition:
        raise AssertionError(message)


class NativeProcess:
    def __init__(self, harness, root, env, binary, generation):
        self.root = root
        self.stderr = (root / f'process-{generation}.stderr.log').open('w')
        self.stdout = (root / f'process-{generation}.stdout.log').open('w')
        self.proc = subprocess.Popen(['/usr/bin/python3', '-I', str(harness.HERE / 'run.py'),
                                      '--child', str(binary.resolve())],
                                     cwd=root, env=env, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=self.stderr, bufsize=0)
        self.buffer = b''
        try:
            ready = self.read()
            check(ready.get('ready') is True, f'Native startup did not acknowledge: {ready}')
            self.pid = ready['pid']
        except Exception:
            if self.proc.poll() is None:
                self.proc.kill()
                self.proc.wait(timeout=10)
            self.stderr.close()
            self.stdout.close()
            self.proc.stdin.close()
            self.proc.stdout.close()
            raise

    def read(self):
        deadline = time.monotonic() + 45
        while True:
            while b'\n' in self.buffer:
                line, self.buffer = self.buffer.split(b'\n', 1)
                self.stdout.write(line.decode(errors='replace') + '\n')
                self.stdout.flush()
                if line.startswith(b'BLEND_REPORT '):
                    return json.loads(line[len(b'BLEND_REPORT '):])
            remaining = deadline - time.monotonic()
            check(remaining > 0, 'Native command timeout; see process stderr')
            readable, _, _ = select.select([self.proc.stdout], [], [], remaining)
            check(readable, 'Native command timeout; see process stderr')
            chunk = os.read(self.proc.stdout.fileno(), 65536)
            check(chunk, f'Native process exited while awaiting report (exit={self.proc.poll()}); see {self.stderr.name}')
            self.buffer += chunk

    def command(self, op):
        self.proc.stdin.write((json.dumps({'op': op}) + '\n').encode())
        self.proc.stdin.flush()
        reply = self.read()
        check(reply.get('op') == op, f'Out of order native response: {reply}')
        return reply

    def close(self):
        try:
            if self.proc.poll() is None:
                self.proc.stdin.write(b'{"op":"exit"}\n')
                self.proc.stdin.flush()
                self.proc.wait(timeout=10)
            check(self.proc.returncode == 0, f'Native exit={self.proc.returncode}; see {self.stderr.name}')
        finally:
            if self.proc.poll() is None:
                self.proc.kill()
                self.proc.wait()
            self.stderr.close()
            self.stdout.close()
            self.proc.stdin.close()
            self.proc.stdout.close()


class Scenario:
    def __init__(self, harness, output, binary, name):
        self.harness, self.binary = harness, binary
        self.root = output / name
        self.env = harness.prepare(self.root, dict(name=name, state='lapsed', epoch=15, recoverySession=True))
        # Synthetic PUBLIC fields only; pinned wallet balance endpoint returns notes.
        config = ('blend:\n  listening_address: /ip4/127.0.0.1/udp/3400/quic-v1\n'
                  '  external_address: /ip4/192.0.2.1/udp/3400/quic-v1\n'
                  f'sdp:\n  wallet:\n    funding_pk: {FUNDING}\n')
        for path in (self.root / 'user_config.yaml', self.root / 'data/Logos/LogosBasecamp/module_data/blockchain_module/synthetic/user_config.yaml'):
            path.write_text(config)
        self.responses = json.loads((self.root / 'responses.json').read_text())
        self.record = copy.deepcopy(self.responses['GET /mantle/sdp/declarations']['body'][ID])
        self.responses['POST ' + WITHDRAW] = dict(body=None, expect_body=ID)
        self.responses['POST ' + JOIN] = dict(body=ID, expect_body=dict(locator=LOCATOR, locked_note_id=NOTE))
        self.responses['POST ' + BIND] = dict(body=None, expect_body=ID)
        self.responses['GET ' + WALLET] = dict(body=dict(tip='1' * 64, balance=1000000000,
                                                        notes={'4' * 64: 1000000000}, address=FUNDING))
        self.responses['GET /mantle/gas-prices'] = dict(body=dict(tip='1' * 64,
            execution_base_gas_price=1, storage_gas_price=1))
        self.snapshot_serial = 0
        self.snapshot(epoch=15, slot=1500, lib=1400, core=True)
        self.generation = 0
        self.native = None
        self.trace = (self.root / 'scenario.jsonl').open('w')

    def write(self):
        self.snapshot_serial += 1
        payload = json.dumps(self.responses)
        (self.root / f'responses-{self.snapshot_serial:03d}.json').write_text(payload)
        temp = self.root / 'responses.next.json'
        temp.write_text(payload)
        temp.replace(self.root / 'responses.json')

    def snapshot(self, *, epoch=None, slot=None, lib=None, record='unchanged', core=None):
        if epoch is not None:
            self.responses['GET /time/info'] = dict(body=dict(slot_duration_ms=1000,
                genesis_time_unix_ms=0, current_slot=slot if slot is not None else epoch * 100,
                current_epoch=epoch))
        info = self.responses['GET /cryptarchia/info']['body']['cryptarchia_info']
        info.update(state='Online', tip='1' * 64, height=100)
        if slot is not None:
            info['slot'] = slot
        if lib is not None:
            info.update(lib_slot=lib, lib='2' * 64)
        if record != 'unchanged':
            self.responses['GET /mantle/sdp/declarations'] = dict(body={} if record is None else {ID: record})
        if core is not None:
            self.responses['GET /blend/info']['body']['core_info'] = (
                dict(current_epoch_peers=[[self.harness.peer_id('5' * 64), True]], old_epoch_peers=None)
                if core else None)
        self.write()

    def start_process(self):
        self.generation += 1
        self.native = NativeProcess(self.harness, self.root, self.env, self.binary, self.generation)

    def restart(self, abrupt=False):
        pid = self.native.pid
        if abrupt:
            # Kill only the exact Popen child owned by this fixture; never use a
            # process-name search. Journal recovery must survive absent destructors.
            self.native.proc.kill()
            self.native.proc.wait(timeout=10)
            self.native.stderr.close()
            self.native.stdout.close()
            self.native.proc.stdin.close()
            self.native.proc.stdout.close()
        else:
            self.native.close()
        self.start_process()
        check(self.native.pid != pid, 'Restart must be a real new process')

    def call(self, op):
        response = self.native.command(op)
        self.trace.write(json.dumps(response) + '\n')
        self.trace.flush()
        error = self.root / 'transport-errors.log'
        check(not error.exists(), error.read_text() if error.exists() else '')
        return response['result']

    def status(self):
        reply = self.native.command('getBlendLifecycle')
        self.trace.write(json.dumps(reply) + '\n')
        self.trace.flush()
        error = self.root / 'transport-errors.log'
        check(not error.exists(), error.read_text() if error.exists() else '')
        lifecycle = reply['result']
        recovery = lifecycle.get('recovery', {})
        required = {'active', 'phase', 'title', 'detail', 'tone', 'steps', 'canStart', 'canPause', 'canResume'}
        check(required <= recovery.keys(), f'Missing recovery contract fields: {required - recovery.keys()}')
        for key in ('active', 'canStart', 'canPause', 'canResume'):
            check(isinstance(recovery[key], bool), key + ' must be bool')
        check(reply['activeProperty'] == recovery['active'], 'QtRO property and status active disagree')
        check(isinstance(recovery['steps'], list) and recovery['steps'], 'Recovery steps missing')
        return recovery

    def posts(self):
        path = self.root / 'requests.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines() if json.loads(line)['method'] == 'POST'] if path.exists() else []

    def counts(self, withdraw=0, join=0, bind=None, min_bind=None):
        actual = self.posts()
        if bind is None:
            bind = 1 if withdraw else 0  # explicit recovery preflight binds the original ID
        if min_bind is not None:
            bind = sum(p['path'] == BIND for p in actual)
            check(bind >= min_bind, f'Expected >= {min_bind} binding POSTs, got {bind}')
        expected = {WITHDRAW: withdraw, JOIN: join, BIND: bind}
        check(len(actual) == sum(expected.values()), f'Unexpected POSTs: {actual}; expected {expected}')
        for route, count in expected.items():
            matching = [p for p in actual if p['path'] == route]
            check(len(matching) == count, f'{route}: expected {count}, got {len(matching)}; {actual}')
            body = dict(locator=LOCATOR, locked_note_id=NOTE) if route == JOIN else ID
            check(all(json.loads(p['body']) == body for p in matching), f'Wrong exact body on {route}')

    def ticks(self, count=3):
        for _ in range(count):
            self.call('tick')
        return self.status()

    def authorize(self):
        result = self.call('startBlendRecovery')
        check(result.get('ok') is True, f'Explicit start rejected: {result}')
        self.ticks()
        self.counts(withdraw=1)
        check(self.status()['active'], 'Authorized flow must retain mutation ownership')

    def schedule(self):
        record = dict(self.record, withdraw_at=16, nonce=10)
        self.snapshot(epoch=16, slot=1600, lib=1500, record=record)
        self.ticks()
        self.counts(withdraw=1)

    def absence(self):
        self.snapshot(epoch=17, slot=1700, lib=1600, record=None)
        wallet = self.responses['GET ' + WALLET]['body']
        wallet['notes'][NOTE] = 1000000000
        wallet['balance'] = 2000000000
        self.write()
        self.ticks()
        self.counts(withdraw=1)

    def finalize(self):
        self.snapshot(epoch=18, slot=1800, lib=1699, record=None)
        self.ticks()
        self.counts(withdraw=1)  # LIB immediately before first absence slot cannot join.
        self.snapshot(epoch=20, slot=2000, lib=1700, record=None)
        for _ in range(3):
            self.status()  # Even an authorized flow's getter must not perform the now-ready join.
        self.counts(withdraw=1)
        self.ticks(5)
        self.counts(withdraw=1, join=1)  # Inclusive pinned barrier at the observed slot.

    def to_join(self):
        self.authorize()
        self.schedule()
        self.absence()
        self.finalize()

    def close(self):
        try:
            if self.native:
                self.native.close()
        finally:
            self.trace.close()


def readonly(s):
    s.start_process()
    for _ in range(3):
        s.status()
        s.call('getBlendDeclarations')
    s.ticks()
    s.counts()


def progression(s):
    s.start_process()
    s.authorize()
    s.ticks(5)  # HTTP acknowledgement is not inclusion.
    s.counts(withdraw=1)
    s.snapshot(epoch=16, slot=1600, lib=1500)
    s.ticks()
    s.counts(withdraw=1)  # Time alone cannot prove removal.
    original = copy.deepcopy(s.responses['GET /mantle/sdp/declarations'])
    for malformed in (dict(raw='{broken'), dict(body=[]), dict(body=None), dict(body={'not-an-id': {}}), dict(body={}, code=503)):
        s.responses['GET /mantle/sdp/declarations'] = malformed
        s.write()
        s.ticks()
        s.counts(withdraw=1)
    s.responses['GET /mantle/sdp/declarations'] = original
    s.snapshot(record=None)
    s.ticks()
    s.counts(withdraw=1)  # Absence without previously observed schedule is not removal.
    s.schedule()
    s.absence()
    s.finalize()
    s.ticks()
    s.counts(withdraw=1, join=1)  # Join acknowledgement is not canonical acceptance.
    fresh = dict(s.record, created=21, active=23, nonce=0)
    s.snapshot(epoch=23, slot=2300, lib=2200, record=fresh, core=False)
    s.ticks(5)
    s.counts(withdraw=1, join=1, min_bind=2)
    check(s.status()['active'], 'Binding/activation grace must not complete recovery')
    fresh['nonce'] = 100
    s.snapshot(record=fresh, core=True)
    s.ticks()
    check(s.status()['active'], 'Nonce/Core alone cannot prove accepted activity')
    # Three sequential accepted activity increments, not three polls of one value.
    s.snapshot(epoch=24, slot=2400, lib=2300, record=dict(fresh, active=24), core=False)
    s.ticks(5)
    check(s.status()['active'], 'Repeated polls must count only one accepted renewal')
    s.snapshot(epoch=25, slot=2500, lib=2400, record=dict(fresh, active=25))
    s.ticks()
    check(s.status()['active'], 'Two accepted renewals must not complete recovery')
    s.snapshot(epoch=26, slot=2600, lib=2500, record=dict(fresh, active=26))
    s.ticks()
    check(s.status()['active'], 'Three renewals without runtime Core must still wait')
    s.snapshot(core=True)
    result = s.ticks()
    check(not result['active'], f'Three renewals + runtime Core must complete: {result}')
    check(result['tone'] == 'success', f'Completion needs success evidence: {result}')
    s.counts(withdraw=1, join=1, min_bind=2)


def uncertain(s, route, failure):
    s.responses['POST ' + route].update(failure)
    s.write()
    s.start_process()
    if route == WITHDRAW:
        s.authorize()
        expected = dict(withdraw=1)
    else:
        s.to_join()
        expected = dict(withdraw=1, join=1)
    s.ticks(5)
    s.counts(**expected)
    before = s.status()
    check(before['active'], 'Ambiguous outcome must keep durable intent active')
    s.restart(abrupt=True)  # Same root; no Python-assigned journal/state or destructor flush.
    check(s.status()['active'], 'Pending ownership lost at process restart')
    s.ticks(6)
    s.call('startBlendRecovery')
    s.call('resumeBlendRecovery')
    s.ticks()
    s.counts(**expected)
    check(s.status()['active'], 'Restart/resume must preserve ambiguous pending outcome')


def old_incarnation(s):
    s.start_process()
    s.to_join()
    s.snapshot(record=s.record)
    state = s.ticks(5)
    s.counts(withdraw=1, join=1)
    check(state['active'] and state['phase'] == 'attention',
          f'Same ID with old created must fail closed, never bind: {state}')


def malformed_removal(s):
    s.start_process()
    s.authorize()
    s.schedule()
    s.snapshot(epoch=17, slot=1700, lib=1600)
    for malformed in (dict(raw='{broken'), dict(body=[]), dict(body=None),
                      dict(body={'not-an-id': {}}), dict(body={ID: dict(s.record, active=None)}),
                      dict(body={}, code=503)):
        s.responses['GET /mantle/sdp/declarations'] = malformed
        s.write()
        s.ticks()
        s.counts(withdraw=1)
    # API recovery must still require real absence + advancing LIB, not the earlier errors.
    s.absence()
    s.finalize()


def ownership(s):
    s.snapshot(record=dict(s.record, provider_id='c' * 64))
    s.start_process()
    result = s.call('startBlendRecovery')
    check(not result.get('ok'), f'Foreign declaration authorized: {result}')
    s.ticks()
    s.counts()


def missing_funds(s):
    s.responses['GET ' + WALLET]['body'].update(balance=0, notes={})
    s.write()
    s.start_process()
    result = s.call('startBlendRecovery')
    s.ticks()
    s.counts()
    status = s.status()
    check(not result.get('ok') or status['canResume'], f'Missing funds must reject or pause before any POST: {result}; {status}')


def disk_failure(s):
    s.start_process()
    result = s.call('startBlendRecovery')
    check(result.get('ok'), f'Authorization failed before injecting disk failure: {result}')
    # Obstruct an already-open controller's next real QSaveFile write, not merely
    # journal parsing. Directory obstruction works even under root. Own fixture only.
    journal = s.root / 'blend-recovery.json'
    check(journal.is_file(), 'Explicit authorization did not persist intent')
    journal.unlink()
    journal.mkdir()
    state = s.ticks()
    s.counts()
    check(state['active'] and state['phase'] == 'attention', f'Persistence failure must retain exclusion: {state}')


def pause_resume(s):
    s.start_process()
    s.authorize()
    check(s.call('pauseBlendRecovery').get('ok'), 'Pause failed')
    paused = s.status()
    check(paused['active'] and paused['canResume'], f'Paused flow lost ownership/resume: {paused}')
    s.schedule()
    s.absence()
    s.snapshot(epoch=20, slot=2000, lib=1800, record=None)
    s.ticks(6)
    s.counts(withdraw=1)
    for action in ('withdrawBlendCore', 'declareBlendCore', 'repairBlendBinding'):
        check(not s.call(action).get('ok'), f'Manual action escaped recovery lock: {action}')
    s.counts(withdraw=1)
    check(s.call('resumeBlendRecovery').get('ok'), 'Explicit resume failed')
    s.ticks()
    s.snapshot(epoch=22, slot=2200, lib=2100, record=None)
    s.ticks(6)
    s.counts(withdraw=1, join=1)


def manual_exclusion(s):
    s.start_process()
    s.authorize()
    for action in ('withdrawBlendCore', 'declareBlendCore', 'repairBlendBinding', 'startBlendRecovery'):
        check(not s.call(action).get('ok'), f'Manual/duplicate action escaped recovery lock: {action}')
    s.ticks()
    s.counts(withdraw=1)


def stopped_node_restart(s):
    s.start_process()
    s.authorize()
    live = s.call('startBlockchain')
    check('recovery' in live.get('error', '').lower(), f'Live restart was not blocked: {live}')
    for stopped_state in ('setNotStarted', 'setStopped'):
        s.call(stopped_state)
        stopped = s.call('startBlockchain')
        # Framework is deliberately disconnected: reaching this check proves the
        # real recovery guard allows explicit Start without launching any engine.
        check(stopped.get('error') == 'Module not initialized', f'{stopped_state}: cannot start: {stopped}')
    s.counts(withdraw=1)
    # The stopped-node exception must not permit a different public identity.
    s.call('setStopped')
    for path in (s.root / 'keystore.yaml', s.root / 'data/Logos/LogosBasecamp/module_data/blockchain_module/synthetic/keystore.yaml'):
        path.write_text('public_keys:\n  BlendSigning: ' + 'c' * 64 + '\n')
    changed = s.call('startBlockchain')
    check('identity' in changed.get('error', '').lower(), f'Changed identity escaped restart guard: {changed}')
    s.counts(withdraw=1)


def run_suite(harness, output, binary, selected=None):
    scenarios = [('recovery-getters-never-post', readonly), ('recovery-full-observed-progression', progression),
                 ('recovery-ownership-mismatch', ownership), ('recovery-missing-funds', missing_funds),
                 ('recovery-journal-disk-failure', disk_failure), ('recovery-pause-resume', pause_resume),
                 ('recovery-manual-exclusion', manual_exclusion),
                 ('recovery-stopped-node-explicit-start', stopped_node_restart),
                 ('recovery-old-incarnation-never-rebinds', old_incarnation),
                 ('recovery-malformed-registry-not-removal', malformed_removal)]
    for route, label in ((WITHDRAW, 'withdraw'), (JOIN, 'join')):
        for failure, kind in (({'exit': 28}, 'timeout'), ({'code': 503, 'body': {'error': 'synthetic uncertain outcome'}}, '5xx')):
            scenarios.append((f'recovery-{label}-{kind}-restart-no-replay',
                              lambda s, r=route, f=failure: uncertain(s, r, f)))
    check(not selected or any(selected in name for name, _ in scenarios), f'No recovery test matched {selected!r}')
    failures = []
    for name, test in scenarios:
        if selected and selected not in name:
            continue
        scenario = None
        error = ''
        try:
            scenario = Scenario(harness, output, binary, name)
            test(scenario)
        except Exception:
            error = traceback.format_exc()
        finally:
            if scenario:
                try:
                    scenario.close()
                except Exception:
                    error += traceback.format_exc()
        if error:
            failures.append(name)
            (output / name / 'failure.log').write_text(error)
        print(('FAIL ' if error else 'PASS ') + name + (': ' + error.strip().splitlines()[-1] if error else ''), flush=True)
    return failures
