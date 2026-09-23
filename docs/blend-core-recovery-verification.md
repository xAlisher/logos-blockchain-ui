# Controlled Blend recovery — verification

## Delivery status

**Implemented and packaged as `0.2.33-blend.3`; staged, not installed or activated on the live node.**

Artifact: `/extra/tmp/blend-recovery-delivery/logos_node_1click-0.2.33-blend.3-linux-amd64.lgx`

SHA256: `9f4a8d7b93da4d06a0c07586ac3d338641a2f5ccdb907be18e57b88c88dd77b1`

The currently installed UI backend stops the node in its destructor. Loading the new backend/QtRO replica/QML together therefore requires an operator-approved lifecycle change; no live hot swap or restart was attempted. The recovery itself additionally requires the card's explicit confirmation.

## Executed checks

| Layer | Actual result |
| --- | --- |
| Production backend unit/transport/snapshot executables | 8/8 passed |
| Independent production-controller policy executable | 1/1 passed |
| Real packaged native library, synthetic API responses | 33 scenarios passed |
| Extracted-package QML, matching Qt 6.9.2 | 94 passed |
| Extracted-package composed parent, inert backend | 6 passed |
| Extracted-package rendering from native scenario output | 16 passed; narrow/wide captures visually inspected |
| Fixture transport/network-denial tests | 8 passed |
| Portable LGX audit | All 42 QML/JS files byte-matched; native recovery exports and matching QtRO replica contract present |
| Worktree whitespace check | `git diff --check` passed |

The native harness links the packaged `.so`; it does not recompile a substitute backend. HOME/XDG/config/logs are synthetic and isolated under `/extra`; inherited seccomp denies IPv4/IPv6 sockets. The full progression verifies one withdrawal and one join with exact original ID/collateral/locator bodies. Unknown withdrawal/join replies survive actual fixture-process kills and restarts without replay. Getter-only paths emit no POSTs.

## Regressions exercised

- Missing/malformed registry telemetry cannot imply removal; time alone and acknowledgements cannot release a join.
- Observed withdrawal, canonical absence, and the irreversible-slot barrier precede re-declaration.
- Same-ID old incarnation cannot be bound as a fresh declaration.
- Pause and mutation ownership persist; Pause is usable despite a chain-read failure.
- Explicit Start works for the same `NotStarted`/`Stopped` node, but live restart and changed public identity remain blocked.
- Scope faults remain stopped after controller reload; private journal deletion/write failure cannot silently recreate authority.
- A known missed bootstrap renewal cannot later become “unobserved.”
- Elapsed epochs cannot mark runtime Core activation complete; nonce and repeated polling cannot count as renewals.
- Completion requires three observed consecutive accepted activity epochs, runtime Core, and current-run binding acknowledgement. A known binding is not set again every monitoring poll.

Focused failures were observed before the corresponding fixes; logs labelled `*-red.log` are deliberate historical regression evidence, not outstanding failures. Independent review's Pause and stopped-node findings were addressed and re-tested.

## Evidence and reproducibility

Evidence root: `/extra/tmp/blend-recovery-delivery/`

- `build-release.log`, `package-audit.log`, `build-source-sha256.json`
- `native-final.log`; full native wire/state evidence: `/extra/tmp/blend-native-zevd3pre/`
- `packaged-qml.log`, `packaged-parent.log`, `packaged-observed.log`
- `observed/*.png`: actual packaged component, synthetic native-backend scenario data, explicitly marked **NOT LIVE**
- `live-baseline.json`, `live-after.json`: allowlisted read-only runtime checks

Rebuild with `TMPDIR=/extra/tmp nix build path:/extra/tmp/blend-core-lifecycle#lgx-portable --cores 2 --max-jobs 1`. Audit using `python3 tests/verify_portable.py <archive.lgx> --extract <isolated-directory>`. Run the native package matrix with `bash tests/integration/run-native.sh <extracted-plugin.so> /extra/tmp/blend-recovery-native-harness`. See `tests/integration/README.md` for the isolation and individual scenarios.

The Nix Qt 6.9.2 QML tests require that build's `lib/qt-6/qml` as an explicit `-import`, plus the design-system and inert test enum imports. This is a test-runtime setup requirement, not a missing component in the portable package.

## Live state and remaining gates

Read-only check at **2026-09-22 04:47:42 UTC**: same engine PID as baseline (`1788303`), runtime Core in epoch 42, three healthy peers, installed UI still `0.2.33-blend.1`. No recovery journal appeared in the checked live module-data profile. No live withdrawal, re-declaration, key change, reset, installation or restart was performed.

These checks prove the packaged implementation against controlled fixtures, **not live multi-epoch recovery**. Actual transaction inclusion, collateral availability, fresh declaration, and accepted renewals remain live acceptance gates after operator authorization. QtRO metadata/replica compatibility is audited and native slots are exercised; a separate live remote-host/replica round trip is not claimed.

Pinned-engine limits remain: wallet note presence is not exact spendability/fee-sufficiency proof, and the LIB-slot wait is not an atomic historical registry query. Unknown potentially delivered paid outcomes stay pending rather than being retried. Successful recovery does not promise permanent Core membership or payouts.
