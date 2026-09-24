# Native packaged-backend integration (Linux, headless)

These are **synthetic public-only fixture tests**, not live-node observations. The
harness links the **actual packaged native `.so`**, using matching backend headers
and independently regenerated QtRO declarations. It neither recompiles production
backend `.cpp` files nor substitutes a Python recovery policy.

## Run against the recovery package

```sh
cd /extra/tmp/blend-core-lifecycle
bash tests/integration/run-native.sh \
  /absolute/path/to/NEW/extracted/logos_node_1click_plugin.so \
  /extra/tmp/blend-recovery-native-harness
```

Do **not** use `blend-recovery-delivery/baseline-plugin.so`: it is intentionally the
pre-recovery artifact, not evidence for the new ABI. Preserve the packaged directory
layout/dependencies. The script builds only this harness with the repository Nix
shell (Qt 6.9.2/GCC 14), prints the supplied library SHA256, then runs both matrices.
`LOGOS_QT_INCLUDE` overrides the SDK header path when needed. It never installs a
package or launches a node. Missing binary/slot/tick support is a hard failure, not a
skip or a fallback to a mocked implementation.

For diagnosis after building:

```sh
python3 -I tests/integration/run.py --binary /extra/tmp/blend-recovery-native-harness/blend_native --suite lifecycle
python3 -I tests/integration/run.py --binary /extra/tmp/blend-recovery-native-harness/blend_native --suite recovery
python3 -I tests/integration/run.py --binary /extra/tmp/blend-recovery-native-harness/blend_native --suite recovery --case full-observed
```

Every run retains fresh evidence under `/extra/tmp/blend-native-*`: synthetic config
and public identity, initial case, every response snapshot, `requests.jsonl` with
**actual POST route/body**, native stdout/stderr per process generation, scenario
reports, production journals, and failures. A nonzero exit is a failed gate.

## Isolation is mandatory

- Fresh HOME, XDG config/data/cache/runtime/system-config paths, TMPDIR, CWD and
  LB_CONFIG_PATH. Environment is reconstructed from an allowlist.
- `keystore.yaml` contains only synthetic `public_keys.BlendSigning`. The funding
  configuration and all note IDs are public synthetic placeholders, not private
  keys, funds, real profiles, live logs, or a host module context.
- No `onContextReady`, real node restart, reset, key regeneration, process-name
  scanning, faucet or signing operation is invoked. One explicit Start-guard test
  calls `startBlockchain` with the module framework disconnected: the live-state
  guard must reject, same-identity stopped states must reach "Module not initialized",
  and changed identity must reject before that point. No engine can be launched.
- Constructor QTimers are stopped **before any event dispatch or process wait**.
  The test-only private-access seam seeds the cached PID with the harness's own PID
  (never discovers a running node). Dependency headers precede the access-label
  macro. All actual production methods remain unchanged.
- Recovery ticks are explicit calls to the real native backend tick. Timers are
  stopped again after every command. Python atomically replaces `responses.json`
  **between acknowledged commands**, never from inside a replacement native method.
- PATH contains only the fixture curl, which accepts explicit localhost routes,
  checks exact permitted POST bodies, records them and never delegates to real curl.
  Undocumented endpoints and external IP-discovery requests fail the test.
- Before exec, inherited seccomp **denies IPv4 and IPv6 socket creation**. This is
  fail-closed even if PATH interception fails. Self-tests also verify denial in a
  separately exec'd descendant. AF_UNIX is retained for Qt internals.
- Uncertain-outcome restart scenarios kill only the exact fixture-owned Popen child,
  then exec a genuinely new process with the same isolated persistence root. They
  do not rely on destructor flushing or modify the persisted recovery state.

## Pinned wire shapes (official engine 0.2.4)

The supplied `/extra/tmp/lb-node0.2.4` path was absent. The existing
`/extra/tmp/lb-node` checkout reports `git describe = 0.2.4`; its relevant API source
was inspected read-only. No new APIs were invented:

| Fixture | Pinned source |
| --- | --- |
| `POST /blend/join {locator,locked_note_id}` → optional declaration-ID JSON string | `nodes/api-common/src/paths.rs`, `bodies/blend.rs`; binary API handler `blend_join_network` |
| `POST /sdp/withdrawal`, `/sdp/set-declaration-id` with bare ID JSON string | `paths.rs`, SDP handlers |
| `GET /wallet/<public-key>/balance` → `{address,tip,balance,notes:{noteId:value}}` | `nodes/api-common/src/bodies/wallet.rs` |
| Registry rows `{service_type,provider_id,locked_note_id,locators,zk_id,created,active,withdraw_at,nonce}` | `core/src/sdp/mod.rs::Declaration` |
| `GET /time/info` fields `slot_duration_ms,genesis_time_unix_ms,current_slot,current_epoch` | `nodes/api-common/src/lib.rs::TimeInfo` |
| `cryptarchia_info.{lib,lib_slot,tip,slot,height,state}` | `services/chain/chain-service/src/lib.rs::CryptarchiaInfo` |
| `blend/info {node_id,core_info}` and peer tuples/old peers | `services/blend/src/message.rs` |

No wallet-notes HTTP endpoint or finalized-registry query exists in this pin. The
production contract uses repeated canonical absence after observed effective
withdrawal and `lib_slot >= first absence slot`. This conservative slot barrier is
**not an atomic historical registry proof**. Fixtures supply independent public
telemetry; this harness does not exercise engine cryptography, ledger consensus or
real epoch advancement. Engine-side implementation tests remain a separate gate.

## Regression matrix

The inherited lifecycle matrix covers offline/bootstrap, absent declaration,
activation, nonce-not-activity, missing binding/repair, accepted-activity health,
risk/lapse, scheduled/effective withdrawal, provider/API mismatch, ambiguous provider,
pending cache retention, cache disk failure and repair HTTP failure.

Recovery matrix additionally checks:

- Getter/card polling and inactive ticks emit zero POSTs.
- Explicit authorization sends one original binding and **exactly one withdrawal**;
  acknowledgement and epoch advancement alone cannot trigger a join.
- Malformed/null/array/incomplete/error registry responses never prove removal,
  including after the withdrawal schedule was observed.
- Actual absence and the LIB boundary (one slot before vs at the first absence slot)
  release **exactly one join** with the original collateral and locator.
- Reappearing old same-ID incarnation fails closed; a same-ID **newer-created**
  incarnation is bound. The engine's idempotent binding setter can repeat when
  current-run acknowledgement is unknown; every binding body is checked, while paid requests remain once-only.
- New-binding acknowledgement, nonce, Core alone and repeated polls of one accepted
  activity value do not complete recovery. Three sequential accepted renewals plus
  runtime Core and current-run binding acknowledgement do.
- Withdrawal and join timeouts (curl exit 28) and HTTP 503 outcomes remain pending,
  including abrupt whole-process restart, duplicate start and explicit resume.
- Ownership mismatch, absent fee funds, journal failure, pause/resume and exclusion
  of manual withdraw/join/repair while the recovery owns mutations.

Assertions inspect actual native QtRO slots/property types, getter fields, status
and wire transcripts. Status strings alone never establish paid-action safety.

## Prerequisite-only checks (not native execution)

```sh
python3 -B tests/integration/test_transport.py
python3 -I tests/integration/run.py --self-test
nix develop --offline --command cmake -S tests/integration \
  -B /extra/tmp/blend-recovery-harness-prereq \
  -DLOGOS_QT_INCLUDE=/nix/store/kc44vpw5y7rxy91zdvch0ay54j1kfs6d-logos-qt-sdk-headers-0.1.0/include/cpp
nix develop --offline --command cmake --build /extra/tmp/blend-recovery-harness-prereq \
  --target harness_object -j2
```

The transport tests were observed RED before extending the shim (withdraw/join,
HTTP 500 and timeout unsupported), then GREEN. Transport tests alone do not claim
a native recovery pass: run the packaged-library suite above. Executed package
results are recorded in `docs/blend-core-recovery-verification.md`.
QML interactions/rendering, portable package audit, QtRO remote host/replica E2E,
engine recovery tests and live multi-epoch acceptance remain separate gates.
