"""Audit the actual portable LGX, not just its build status; no installation."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

p = argparse.ArgumentParser()
p.add_argument('archive', type=Path)
p.add_argument('--extract', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
with tarfile.open(a.archive) as archive:
    members = archive.getmembers()
    for member in members:
        path = PurePosixPath(member.name)
        assert not path.is_absolute() and '..' not in path.parts, member.name
        assert member.isfile() or member.isdir(), f'Unexpected archive entry: {member.name}'
    manifest_file = archive.extractfile('manifest.json')
    assert manifest_file is not None
    manifest = json.load(manifest_file)
    metadata = json.loads((root / 'metadata.json').read_text())
    assert manifest['name'] == 'logos_node_1click'
    assert manifest['version'] == metadata['version']
    assert 'linux-amd64' in manifest['main']
    assert 'linux-amd64-dev' not in manifest['main']
    base = 'variants/linux-amd64/'
    assert manifest['view'] == 'qml/BlockchainView.qml'
    count = 0
    for source in (root / 'src/qml').rglob('*'):
        if source.is_file() and source.suffix in ('.qml', '.js'):
            name = base + 'qml/' + str(source.relative_to(root / 'src/qml'))
            packaged = archive.extractfile(name)
            assert packaged is not None, f'Missing packaged source: {name}'
            assert packaged.read() == source.read_bytes(), f'Packaged source mismatch: {name}'
            count += 1
    archive.extractall(a.extract, filter='data')
variant = a.extract / 'variants/linux-amd64'
plugin = variant / manifest['main']['linux-amd64']
syms = subprocess.check_output(['nm', '-D', '-C', str(plugin)], text=True)
for method in ('getBlendLifecycle()', 'repairBlendBinding()'):
    assert any(' T ' in line and 'LogosNode1clickBackend::' + method in line for line in syms.splitlines()), method
replica = variant / 'logos_node_1click_replica_factory.so'
assert replica.is_file()
replica_bytes = replica.read_bytes()
for name in (b'getBlendLifecycle', b'repairBlendBinding'):
    assert name in replica_bytes, f'Replica missing {name!r}'
print(json.dumps({'version': manifest['version'], 'variant': 'linux-amd64', 'qml_js_files_matched': count,
    'backend_methods': ['getBlendLifecycle', 'repairBlendBinding'], 'replica_contract': 'present',
    'archive_bytes': a.archive.stat().st_size, 'sha256': hashlib.sha256(a.archive.read_bytes()).hexdigest(),
    'extracted': str(variant)}, indent=2))
