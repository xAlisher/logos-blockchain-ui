# Blend Core progress — preview handoff

**Ready for controlled manual testing on wild, not certified live epoch maintenance.**

- UI plugin: `logos_node_1click` **0.2.33-blend.1**, portable `linux-amd64`.
- Epic: https://github.com/xAlisher/logos-blockchain-ui/issues/108
- Implementation/acceptance: #109, #110, #111 in the same repository.
- Local branch: `feat/blend-core-lifecycle`.
- Worktree: `/extra/tmp/blend-core-lifecycle`; changes are uncommitted/unpushed.
- Artifact SHA-256: `70ce38541e8b97b2b6cd2d94c1c4a2e15fd7734d614cc97b0b0e7d6a36ae1749`.
- Artifact bytes: `5954793`.
- Packaged native plugin SHA-256: `a9722a32b2f32e963447e8ce1af6345b4b35c978b2cb7651ea376baf86834a1d`.

## Delivered behavior

An expandable Blend Core block immediately below the node progress block. Its strip stays visible; explanation, observed evidence and a state-specific CTA appear beneath it. Blocked/degraded states initially expand. Safe states distinguish offline/bootstrap, registration/submission, pending activation, observed Core membership, peer health, accepted activity, risk/lapse, local binding and withdrawal.

Binding actions reuse an owned declaration. `Restore activity binding` is supported by a current-run diagnostic; `Set activity binding` is an explicit idempotent setup action when the engine cannot report the binding and activity is missing/stale. Unknown is never described as missing. API public PeerId must match the configured public provider identity; foreign/ambiguous records fail closed. Repair acknowledgement is not activity inclusion, restored membership or rewards.

Join/withdraw controls have busy, timeout, disconnect and late-callback guards. Paid mutations require durable pending-state storage before any POST. Definitive HTTP rejection restores the pre-attempt state; ambiguous delivery remains pending to prevent duplicate paid requests. Withdrawal removal requires observed schedule and successful registry absence, not merely reaching an epoch number. Routine withdraw/redeclare is not maintenance.

## Executed verification

| Check | Real result |
|---|---|
| Nix portable LGX build | Passed |
| CTest backend policy/transport/review/identity/mutation/timing suites | 6/6 passed |
| Native integration against the **packaged** `.so`, Qt 6.9.2 | 19/19 passed |
| QML interaction suite against **extracted packaged QML**, Qt 6.9.3 | 60 passed, 0 failed |
| Packaged full-dashboard layout/expansion/screenshot | 3 passed, 0 failed |
| Dashboard wiring regression tests | 3 passed |
| Package content audit | 42 QML/JS files match source byte-for-byte; both native methods exported; replica contract present |
| Whitespace/diff check | Passed |

The native harness uses synthetic public-only fixtures and an inherited seccomp network block; no test POST can reach wild. It covers missing and unknown binding, safe repair, errors, identity mismatch including the wrong API instance, unhealthy peer flags, activation delay, nonce-not-activity, risk/lapse, withdrawal scheduling/removal/pending guards, and persistence failure. A storage-failure regression was observed failing against the previous packaged binary and passing after the fix.

The native suite uses the real plugin and Qt metaobject methods, not a replacement implementation. It does **not** establish a full remote-host/replica roundtrip. QML tests use fixture backend bridges; screenshots are explicitly synthetic, not live wild evidence.

Existing standalone-QML warnings remain: the design-system Settings singleton lacks application identifiers in qmltestrunner; the older management modal has an anchored click shield under a layout and a repeated QString argument. No tests failed because of these warnings. They are not hidden as a warning-free run.

## Evidence paths

- Native fixture reports/transcripts: `/extra/tmp/blend-native-pst1z1nd/`
- Packaged QML: `/extra/tmp/blend-packaged-qml-tests.txt`
- Packaged dashboard preview: `/extra/tmp/blend-packaged-preview-tests.txt`
- Dashboard screenshot: `/extra/tmp/blend-core-dashboard-preview.png`
- Build log: `/extra/tmp/blend-core-release-build.log`
- Backend CTest: `/extra/tmp/blend-backend-tests/cmake/Testing/Temporary/LastTest.log`
- Reproduction harnesses: `tests/backend/`, `tests/integration/`, `tests/qml/`, `tests/preview/`, `tests/verify_portable.py`.

## Manual gate and limits

Use `blend-core-wild-acceptance.md`. Install **only this UI plugin**, retain the existing 0.2.4 blockchain runtime, and preserve module data/keys/state. This work did not install/restart the live node, modify its configuration, or submit an on-chain operation.

Live installation, real binding repair, accepted activity over an epoch boundary, persistence across a real node restart and wallet release remain unverified. A successful UI repair cannot manufacture a missed proof or alter frozen membership. Runtime binding is not directly queryable; timestamped diagnostics and an acknowledgement are bounded evidence, not an enduring health assertion. If an asynchronously accepted join/withdraw never reaches the chain, the pending guard requires operator reconciliation rather than an unsafe automatic retry. Rewards are never inferred from these states.
