# Native packaged-backend integration (Linux, headless)

These are **synthetic fixture tests**, not live-node observations. The harness compiles
against the production backend header and regenerated QtRO source, then links the
exact packaged native `.so`. It never compiles a replacement backend or policy reducer.

## Run after the parent finishes the package

Extract the LGX under `/extra` using the normal packaging tools. Pass the **actual native
plugin `.so`**, not the LGX archive or a QML-only directory:

```sh
cd /extra/tmp/blend-core-lifecycle
bash tests/integration/run-native.sh /absolute/path/to/extracted/logos_node_1click_plugin.so
```

The script configures/builds **only the harness**, using this repository's `nix develop`
(Qt 6.9.2, GCC 14), prints the supplied plugin hash, and runs the fixture matrix.
`LOGOS_QT_INCLUDE` can override the default available SDK header directory. Build output
defaults to `/extra/tmp/blend-native-harness`; an optional second argument changes it.
The source header/`.rep` must match the plugin build; do not use an older ABI's artifact.
If a bundled dependency cannot be resolved, retain the package directory layout and
inspect linker/runtime errors; never silently substitute a different plugin.

Results and every synthetic config, public identity file, curl transcript, stderr and
stdout are kept in a fresh `/extra/tmp/blend-native-*` directory. Nonzero exit means failure.

## Isolation and test seams

- Every case gets fresh HOME, XDG config/data/cache/runtime paths, TMPDIR, CWD and
  LB_CONFIG_PATH. Environment is rebuilt from an allowlist, not inherited.
- `keystore.yaml` contains **only** the synthetic `public_keys.BlendSigning` field.
  No real config, wallet, keystore, live logs or module API context is used.
- Neither `startBlockchain`, `onContextReady`, nor any join/withdraw slot is called.
- The backend constructor **does start a resource timer**. The harness immediately
  stops all its QTimers before any nested event loop.
- One test-only access-label seam seeds `m_nodePid` to the harness PID. This prevents
  production's `/proc` scanner from choosing an actual node and gives the real
  run-start parser a real process timestamp. No production implementation is replaced;
  all log evidence is generated under the case directory after process start.
- PATH contains only the fixture curl. It accepts an explicit route allowlist at
  `http://127.0.0.1:8080`, never executes real curl, logs every accepted request, rejects
  unexpected routes/arguments, and checks the stripped-loader-variable contract.
- Before exec, the runner installs and verifies an inherited seccomp rule rejecting
  IPv4 and IPv6 sockets. This is mandatory/fail-closed, even if PATH interception works.
  A shim miss cannot reach localhost or wild. Linux libseccomp and `/usr/bin/python3`
  are required; AF_UNIX remains available for Qt internals.

## Assertions

Fifteen cases cover offline/bootstrap, no declaration, activation, nonce-not-activity,
current-run missing binding + repair, accepted-activity health, risk/lapse, scheduled
and effective withdrawal, stored-ID/provider mismatch, ambiguous provider, pending
withdrawal cache retention/repair rejection, and repair HTTP failure. Native metaobject
methods must exist and return QVariantMap; lifecycle fields, string nonce and six stages
are checked. Successful repair must remain only binding confirmation, never activity
success. Only permitted mutation is an intercepted `/sdp/set-declaration-id` request
with a bare owned DeclarationId JSON string; guards must emit zero POSTs.

This exercises the real native slot/QtRO source contract, **not a remote host/replica
connection**. Real node execution, epoch advancement and live installation remain
manual acceptance. No fixture pass establishes live network health or earnings.

## Standalone prerequisite verification

```sh
nix develop --command cmake -S tests/integration -B /extra/tmp/blend-native-harness \
  -DLOGOS_QT_INCLUDE=/nix/store/kc44vpw5y7rxy91zdvch0ay54j1kfs6d-logos-qt-sdk-headers-0.1.0/include/cpp
nix develop --command cmake --build /extra/tmp/blend-native-harness --target harness_object -j2
/usr/bin/python3 -I tests/integration/run.py --self-test
```

These commands compile the native harness object and execute the real seccomp/curl-shim
self-test, but **do not constitute native integration execution without the plugin**.
At initial handoff, the upcoming `/extra/tmp/blend-core-lgx` plugin was unavailable;
`harness_object` compiled and the transport self-test passed. The full runner correctly
refused the absent native executable with exit 2. The parent must run the package command
above and report its actual result; no native pass is claimed here.
