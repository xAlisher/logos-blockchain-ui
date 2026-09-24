#!/usr/bin/python3
"""Linux-only fixture runner. No native backend substitute and no network fallback."""
import argparse
import ctypes
import errno
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ID, PROVIDER = 'b' * 64, 'a' * 64


def peer_id(provider):
    raw = bytes.fromhex('002408011220' + provider)
    number = int.from_bytes(raw, 'big')
    alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    result = ''
    while number:
        number, remainder = divmod(number, 58)
        result = alphabet[remainder] + result
    return '1' + result


def block_network():
    # Deny creation of IPv4/IPv6 sockets in this process AND every descendant.
    # Loading this filter is mandatory, including when the curl shim is working.
    lib = ctypes.CDLL('libseccomp.so.2')
    class Compare(ctypes.Structure):
        _fields_ = [('arg', ctypes.c_uint), ('op', ctypes.c_uint),
                    ('datum_a', ctypes.c_uint64), ('datum_b', ctypes.c_uint64)]
    lib.seccomp_init.argtypes = [ctypes.c_uint32]
    lib.seccomp_init.restype = ctypes.c_void_p
    lib.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    lib.seccomp_syscall_resolve_name.restype = ctypes.c_int
    lib.seccomp_rule_add_array.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int,
                                          ctypes.c_uint, ctypes.POINTER(Compare)]
    lib.seccomp_load.argtypes = [ctypes.c_void_p]
    lib.seccomp_release.argtypes = [ctypes.c_void_p]
    ctx = lib.seccomp_init(0x7fff0000)  # SCMP_ACT_ALLOW
    if not ctx:
        raise RuntimeError('seccomp_init failed')
    try:
        nr = lib.seccomp_syscall_resolve_name(b'socket')
        assert nr >= 0
        for family in (socket.AF_INET, socket.AF_INET6):
            comparison = Compare(0, 4, family, 0)  # SCMP_CMP_EQ
            assert lib.seccomp_rule_add_array(ctx, 0x50000 | errno.EPERM, nr, 1, ctypes.byref(comparison)) == 0
        assert lib.seccomp_load(ctx) == 0, 'Cannot install network sandbox'
    finally:
        lib.seccomp_release(ctx)
    for family in (socket.AF_INET, socket.AF_INET6):
        try:
            socket.socket(family, socket.SOCK_STREAM)
        except OSError as error:
            assert error.errno == errno.EPERM
        else:
            raise RuntimeError('Network sandbox verification failed')
    os.environ['BLEND_NETWORK_BLOCKED'] = 'seccomp'


def fixtures():
    # Explicitly synthetic public identities and protocol responses; no live observations.
    return [
        dict(name='offline', state='offline', running=False, repairOk=False),
        dict(name='bootstrap', state='bootstrap', mode='Bootstrapping', repairOk=False),
        dict(name='no-declaration', state='no-declaration', empty=True, repairOk=False),
        dict(name='activation', state='activation-pending', epoch=11),
        dict(name='not-core-after-delay', state='activation-pending', epoch=13, core=False),
        dict(name='collecting-nonce-not-activity', state='collecting', repairOk=True, posts=1),
        dict(name='missing-binding-repair', state='binding-missing', missingBinding=True, repairOk=True, posts=1),
        dict(name='healthy-accepted-activity', state='healthy', epoch=14, active=14),
        dict(name='at-risk', state='at-risk', epoch=14),
        dict(name='lapsed', state='lapsed', epoch=15),
        dict(name='withdrawal-scheduled', state='withdrawal-scheduled', withdraw_at=16, repairOk=False),
        dict(name='withdrawal-due-still-present', state='withdrawal-scheduled', withdraw_at=12, repairOk=False),
        dict(name='removed', state='removed', empty=True, removed=True, repairOk=False),
        dict(name='stored-id-foreign-provider', state='identity-error', foreign=True, missingBinding=True, repairOk=False),
        dict(name='wrong-api-instance', state='identity-error', wrong_api=True, missingBinding=True, repairOk=False),
        dict(name='ambiguous-provider', state='identity-error', ambiguous=True, missingBinding=True, repairOk=False),
        dict(name='withdrawal-pending', state='withdrawal-requested', pending=True, missingBinding=True, repairOk=False),
        dict(name='storage-failure-blocks-withdrawal', state='collecting', storageFailure=True),
        dict(name='repair-http-error', state='binding-missing', missingBinding=True, repairOk=False, posts=1, repair_code=500),
    ]


def prepare(root, case):
    root.mkdir()
    (root / 'SYNTHETIC_FIXTURE').write_text('PUBLIC-ONLY SYNTHETIC TEST DATA; NOT A NODE PROFILE\n')
    for directory in ('home', 'config', 'data', 'cache', 'runtime', 'tmp', 'bin', 'config-system'):
        (root / directory).mkdir(mode=0o700)
    shutil.copyfile(HERE / 'curl_fixture.py', root / 'bin/curl')
    (root / 'bin/curl').chmod(0o700)
    (root / 'user_config.yaml').write_text('blend:\n  listening_address: /ip4/127.0.0.1/udp/3400/quic-v1\n')
    public_identity = 'public_keys:\n  BlendSigning: ' + PROVIDER + '\n'
    (root / 'keystore.yaml').write_text(public_identity)
    instance = root / 'data/Logos/LogosBasecamp/module_data/blockchain_module/synthetic'
    instance.mkdir(parents=True)
    (instance / 'keystore.yaml').write_text(public_identity)
    shutil.copyfile(root / 'user_config.yaml', instance / 'user_config.yaml')
    record = dict(provider_id='c' * 64 if case.get('foreign') else PROVIDER,
                  service_type='BN', created=10, active=case.get('active', 12), nonce=9,
                  locked_note_id='e' * 64, zk_id='3' * 64,
                  withdraw_at=case.get('withdraw_at'), locators=['/ip4/192.0.2.1/udp/3400/quic-v1'])
    declarations = {} if case.get('empty') else {ID: record}
    if case.get('ambiguous'):
        declarations['d' * 64] = record.copy()
    store = dict(declaration_id=ID, locked_note_id='e' * 64, locator=record['locators'][0])
    if case.get('pending'):
        store['withdraw_pending'] = True
    if case.get('removed'):
        store.update(observed_on_chain=True, scheduled_withdraw_at=12, withdraw_pending=True)
    if not case.get('empty') or case.get('removed'):
        (root / 'blend-declaration.json').write_text(json.dumps(store))
    responses = {
        'GET /cryptarchia/info': {'body': {'cryptarchia_info': {
            'state': case.get('mode', 'Online'), 'tip': '1' * 64,
            'slot': case.get('epoch', 12) * 100, 'lib_slot': case.get('epoch', 12) * 100 - 100}}},
        'GET /time/info': {'body': {'current_epoch': case.get('epoch', 12)}},
        'GET /blend/info': {'body': {'node_id': peer_id('c' * 64 if case.get('wrong_api') else PROVIDER),
            'core_info': {'current_epoch_peers': [['synthetic-peer', True], ['unhealthy-peer', False]]} if case.get('core', True) else None}},
        'GET /mantle/sdp/declarations': {'body': declarations},
    }
    if case.get('posts'):
        responses['POST /sdp/set-declaration-id'] = {'body': None, 'code': case.get('repair_code', 200)}
    (root / 'responses.json').write_text(json.dumps(responses))
    (root / 'case.json').write_text(json.dumps(case))
    env = {'HOME': str(root / 'home'), 'PATH': str(root / 'bin'),
           'BLEND_FIXTURE_ROOT': str(root), 'LB_CONFIG_PATH': str(root / 'user_config.yaml'),
           'XDG_CONFIG_HOME': str(root / 'config'), 'XDG_DATA_HOME': str(root / 'data'),
           'XDG_CACHE_HOME': str(root / 'cache'), 'XDG_RUNTIME_DIR': str(root / 'runtime'),
           'XDG_CONFIG_DIRS': str(root / 'config-system'), 'XDG_DATA_DIRS': str(root / 'data'),
           'TMPDIR': str(root / 'tmp'), 'QT_QPA_PLATFORM': 'offscreen', 'LANG': 'C.UTF-8'}
    return env


def child():
    block_network()
    os.execv(sys.argv[2], sys.argv[2:])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path)
    parser.add_argument('--output', type=Path, default=Path('/extra/tmp'))
    parser.add_argument('--self-test', action='store_true', help='Test isolation/shim only, not native implementation')
    parser.add_argument('--suite', choices=('all', 'lifecycle', 'recovery'), default='all')
    parser.add_argument('--case', help='Run matching recovery case names only (for diagnosis)')
    args = parser.parse_args()
    if not args.self_test and (not args.binary or not args.binary.is_file()):
        parser.error('Native executable missing: build against the packaged .so first (no mock fallback)')
    assert str(args.output.resolve()).startswith('/extra/'), 'Outputs must be under /extra'
    args.output.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='blend-native-', dir=args.output))
    cases = fixtures() if not args.self_test else [dict(name='transport-self-test', state='collecting', posts=1)]
    if not args.self_test and (args.suite == 'recovery' or args.case):
        cases = []
    failures = []
    for case in cases:
        root = output / case['name']
        env = prepare(root, case)
        executable = str(args.binary.resolve()) if args.binary else str(root / 'bin/curl')
        command = ['/usr/bin/python3', '-I', str(HERE / 'run.py'), '--child', executable]
        if args.self_test:
            command += ['-X', 'POST', '-d', json.dumps(ID), '-w', '\n%{http_code}', 'http://127.0.0.1:8080/sdp/set-declaration-id']
        result = subprocess.run(command, cwd=root, env=env, capture_output=True, text=True, timeout=120)
        (root / 'stdout.log').write_text(result.stdout)
        (root / 'stderr.log').write_text(result.stderr)
        errors = []
        if result.returncode:
            errors.append(f'exit={result.returncode}: {result.stderr.strip()}')
        if (root / 'transport-errors.log').exists():
            errors.append((root / 'transport-errors.log').read_text())
        requests = [json.loads(line) for line in (root / 'requests.jsonl').read_text().splitlines()] if (root / 'requests.jsonl').exists() else []
        posts = [r for r in requests if r['method'] == 'POST']
        if len(posts) != case.get('posts', 0):
            errors.append(f'Expected {case.get("posts", 0)} intercepted POSTs, got {len(posts)}')
        if case.get('pending'):
            retained = json.loads((root / 'blend-declaration.json').read_text()) if (root / 'blend-declaration.json').exists() else {}
            if retained.get('declaration_id') != ID or retained.get('withdraw_pending') is not True:
                errors.append('Pending withdrawal identity/state cache not retained')
        print(('FAIL ' if errors else 'PASS ') + case['name'] + (': ' + '; '.join(errors) if errors else ''))
        if errors:
            failures.append(case['name'])
    if not args.self_test and args.suite != 'lifecycle':
        # -I removes the script directory from sys.path; load exactly the sibling
        # fixture module, never an ambient module or user site package.
        import importlib.util
        spec = importlib.util.spec_from_file_location('blend_recovery_cases', HERE / 'recovery_cases.py')
        recovery = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(recovery)
        failures.extend(recovery.run_suite(sys.modules[__name__], output, args.binary, args.case))
    print(f'Evidence: {output}')
    if args.self_test:
        print('Isolation/shim self-test only; NOT native integration coverage.')
    return bool(failures)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--child':
        child()
    else:
        sys.exit(main())
