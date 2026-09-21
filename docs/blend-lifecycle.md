# Blend Core / SDP — states & lifecycle (source of truth for the UI)

Purpose: one honest, cited model of how a node becomes and stays a **Blend Core provider**, so the
dashboard's blend states map onto protocol reality instead of guesswork. Grounded in the node source
(`logos-blockchain` **v0.2.4**, read at `/extra/tmp/lb-node`), the SDP ledger rules, and upstream
issues. Every claim cites code `file:line` or an issue number. Inference is marked **(inf)**.

## Correction / current implementation specification

The September 20 source cross-check found errors in the original investigation below.
For the new operator UI, use [blend-core-progress-spec.md](blend-core-progress-spec.md)
and [epic #108](https://github.com/xAlisher/logos-blockchain-ui/issues/108).

- Core, accepted activity and rewards are separate states. `nonce=0` proves no accepted
  nonce-advancing operation, not zero tokens or zero attempted submissions.
- Activity is automatic, but depends on a qualifying proof and successful submission/inclusion.
  Do not periodically withdraw/redeclare a working provider.
- SDP has a persisted declaration binding; UI JSON and nullable config are not its runtime state.
  A missing binding is a distinct recoverable failure, not proof that the declaration must be replaced.
- The full ledger path verifies Blend proofs in `ledger/src/mantle/sdp/rewards/blend`.
  The TODO in the generic Active validator does not mean arbitrary heartbeats are accepted.
- First exclusion under inactivity=2 is `active+3`, using the applicable frozen snapshot.
  Lapse alone neither removes the declaration nor unlocks the stake.
- Withdrawal submission is not exit: inclusion in W schedules removal/unlock at W+2.
- Core checkpoints are epoch-sensitive (`services/blend/src/core/mod.rs:642-705`).
  Existing persistence is not an end-to-end restart guarantee.
- The current investigation observed `No declaration_id set. Cannot post activity without declaration.`
  at wild's 37→38 and 38→39 boundaries. This identifies a concrete submission blocker;
  duplicate locator remains a separate reachability problem, not a proven zero-token cause.

The original incident account below is retained for provenance, with corrected operative claims.

## TL;DR — the one thing to internalise

Core membership is **not** "declare once and stay". It is a **per-epoch, work-gated, probabilistic**
state. You keep it only if, each epoch, the node (a) is in the frozen Core set, (b) actually mixes and
collects a qualifying blend token, and (c) that token's activity proof lands on-chain to refresh the
declaration's `active` epoch. Miss `inactivity_period` (= **2** on testnet) consecutive refreshes and
the declaration **ages out** of the Core set. A still-valid prior-epoch proof can sometimes refresh a
lapsed live record, but cannot retroactively alter frozen membership. Once excluded from the required
proof epoch, withdrawal followed by redeclaration is the general recovery path. Diagnose missing
local binding and failed submission before suggesting this stake-changing action.

## Constants (fact)

| Constant | Value | Source |
|---|---|---|
| `SNAPSHOT_FINALIZATION_DELAY` | 2 epochs | `core/src/sdp/mod.rs:382` |
| `inactivity_period` (testnet) | 2 epochs | `nodes/node/binary/src/config/deployment/settings.yaml:33` (invariant `>= SNAPSHOT_FINALIZATION_DELAY`: `core/src/sdp/mod.rs:64-70`) |
| Only declared service type | `BlendNetwork` ("BN") | `core/src/sdp/mod.rs:244-256` |

Governing definitions:
- **`active`** = "latest epoch an activity message was sent"; used **only** to decide inactivity, **not**
  to decide becoming active (that's the snapshot) — `core/src/sdp/mod.rs:361-370`.
- **`is_active(decl, epoch)`** = `decl.active + inactivity_period >= epoch` **AND** (`withdraw_at` None
  or `> epoch`) — `ledger/src/mantle/sdp/mod.rs:271-279`.
- **Frozen Core set** for an epoch = all `is_active` declarations, snapshotted into `EpochState`;
  the mixing network consumes the snapshot from `SNAPSHOT_FINALIZATION_DELAY` epochs ago —
  `ledger/src/mantle/sdp/mod.rs:570-592`, `core/src/mantle/ops/sdp/withdraw.rs:107-112`.

## State machine (state → trigger → next → timing)

Declared at accepted-block epoch **C**:

1. **Edge / not-declared** → `SDPDeclareOp` accepted → **Declared (pending)**. Sets `created = C`,
   `active = C + 2` — `core/src/sdp/mod.rs:384-398`. Declaring **locks** a stake note ≥ min-stake
   (`core/src/sdp/locked_notes.rs:59-89`).
2. **Declared (pending)** → snapshot evaluates `is_active` (passes, `active = C+2`) → **Active / in
   Core set** from ~epoch C onward; consumed by the mixing network ~2 epochs later (inf on the exact
   mixing-epoch offset) — `ledger/src/mantle/sdp/mod.rs:824-859`.
3. **Active** → node mixes an epoch, collects tokens, and at the **epoch-transition expiry** submits an
   activity proof (`SDPActiveOp`) for the **just-ended** epoch → **Active, refreshed** (`active = current
   epoch`) — `core/src/mantle/ops/sdp/active.rs:79`; emitter `services/blend/src/core/mod.rs:1236-1243,
   2100-2119`. **This is the only keep-alive.** It is emitted **at the boundary, for the prior epoch** —
   NOT an in-epoch timer.
4. **Active** → `inactivity_period` epochs with no accepted refresh (`active + inactivity < epoch`) →
   **Inactive / aged out** — dropped from the snapshot; the row **persists** in the ledger (still
   queryable) — `ledger/src/mantle/sdp/mod.rs:760-818`.
5. **Inactive → Active** — possible at the ledger level, but **blocked in practice**: re-entry needs an
   activity proof only Core mixing produces, and you can't mix if you're not in the set. Upstream
   **#425 (OPEN)**: *"once a declaration drops out of the snapshot it can never get back in; the only
   transition out of 'lapsed' is Withdraw (2 epochs) then a fresh Declare (2 more)"* → **re-declare**.
6. **Active / Inactive** → `SDPWithdrawOp` at epoch W → **Withdrawing**. Sets `withdraw_at = W + 2`;
   still counts as active until then — `core/src/mantle/ops/sdp/withdraw.rs:113`,
   `ledger/src/mantle/sdp/mod.rs:276-278`. Can't withdraw twice (`withdraw.rs:46-51`).
7. **Withdrawing** → ledger reaches `withdraw_at` → **Withdrawn**: note unlocks (`SdpNoteUnlocked`),
   declaration **removed**, `provider_id` reusable — `ledger/src/mantle/sdp/mod.rs:218-257`.

## Why the heartbeat is fragile (the honest part)

The refresh **exists and is wired** (submission path merged, upstream **#1930 CLOSED**; core+SDP
services always spawned, `nodes/node/binary/src/lib.rs:119,127`). It is not a missing feature. But:

- **Work-gated, not a timer.** `compute_activity_proof()` returns `None` unless a collected blend token
  beats the Hamming `activity_threshold` that epoch — `blend/message/src/reward/mod.rs:82,150`. No token
  → silent no-op (`core/mod.rs:1244-1246`). Sparse traffic / small deployments legitimately miss it.
- **Mode coupling → cascade.** The Core service (the only thing that submits) runs only when active
  membership `>= minimum_network_size` **and** the local node is in it; else the node silently drops to
  Broadcast/Edge and submits nothing — `services/blend/src/instance.rs:300-311`. As members age out,
  survivors fall below the minimum and stop refreshing too.
- **Proof verification is required.** Generic `SDPActiveOp::validate` checks declaration, withdrawal,
  nonce and signature. The full ledger execution additionally verifies proof epoch, provider, PoQ,
  PoSel, threshold and uniqueness (`ledger/src/mantle/sdp/mod.rs:483-507`; rewards/blend).
  This is not the same as independently proving useful external forwarding volume.
- **Submission boundaries.** Proof generation, SDP binding, wallet funding, mempool submission and
  canonical inclusion can each fail. SDP and Core have recovery code, with epoch-sensitive Core
  restore; successful whole-process recovery must be tested, not inferred from the existence of storage.

## What our node showed — RE-CHECKED against live artifacts at epoch 39 (2026-09-20)

Our declaration `cdd5bdd7…` (provider `601dcb79…`, note `1836184b…`): `created=35`, `active=37`,
`withdraw_at=None`, **`nonce=0`**. Re-examined once epoch 39 was ~14 slots in (i.e. just after the
38→39 boundary). The artifacts **confirm the age-out outcome but overturn the earlier "timing-lag /
may self-heal" framing** — this was never a near-miss race:

- **`active=37` is `created+2`, i.e. the automatic snapshot baseline — NOT a refresh.** It has not moved
  since declaring, across **two** refresh boundaries (37→38, 38→39).
- **`nonce=0`** — the SDPActive op carries a strictly-increasing nonce; zero means the declaration has
  **no accepted nonce-advancing operation.** Contrast the 6 healthy core providers, all refreshed at the same
  38→39 boundary to `active=39` with `nonce` 11–39 (`sdp_activity_committed … previous_active_epoch=38
  new_active_epoch=39 active_until_epoch=41`). A genuine timing-lag node would show nonce climbing one
  epoch behind; ours never climbed.
- **Epoch-40 frozen snapshot already excludes us.** The node's own log has exactly one line naming our
  provider: `event="blend_snapshot_provider_decision" target_epoch=40 … frozen_included=false` (no
  `snapshot_active_epoch` printed — we fail `is_active` for 40, since `37+2=39 < 40`). The refreshers
  show `snapshot_active_epoch=38 snapshot_active_until_epoch=40 frozen_included=true`.
- **Why "still Core" right now is correct but terminal:** at epoch 39, `is_active(37, 39) = 37+2=39 ≥ 39`
  → true, so `core_info` is populated for this **one last** epoch. At epoch 40 it drops to Edge.

**Cause (as far as INFO logs allow):** the node reached the snapshot (nominal Core) but is **not landing
activity proofs at all** — one of the fragile-heartbeat modes above (work-gated no qualifying token /
mode-coupling below minimum / submission-or-mempool drop). Which one is not decidable from these logs:
`blend_activity_token_evaluation` is `tracing::debug!` and this node runs at **INFO** (180 INFO lines, 0
DEBUG), so its absence is log-level filtering, not evidence. The unambiguous facts are on-chain: `nonce=0`
vs peers' `nonce 11–39`, and `frozen_included=false` for epoch 40. `diagnostic="blend_tsi_outage"` on
these lines is a **shared grep-label** stamped on all blend/SDP tracing (it rides healthy
`sdp_activity_committed` events too), **not** an outage signal.

**Verdict vs the hypothesis:** the *outcome* (age-out to Edge at epoch 40) is **confirmed**; the earlier
*framing* ("racing its own age-out by design, may refresh at the boundary") is **wrong** — the node isn't
one epoch behind, it is a nominal member that has never refreshed once. Recovery is still withdraw(+2) +
re-declare(+2) (#425), and re-declaring alone won't help unless the node actually mixes and lands proofs.

## UI mapping (how the dashboard should read each state) — honest

| Protocol state | Card value | Sub | Notes |
|---|---|---|---|
| not declared, online | **Edge** | Mixed by the core network | baseline |
| declared, live, not yet in mixing set | **Edge** + gold underline on strip | "Declared — activating at epoch N" | maturing window |
| in Core set, mixing (`core_info` present) | **Core** (gold) | "Node mixing proposals" | healthy |
| Core but `active` behind (within 1 of age-out) | **Core** ⚠ | **"Ageing — refreshes if it mixes this epoch; if it lapses, re-declare"** | **may self-heal at the next boundary** — do NOT prompt an immediate withdraw |
| aged out (dropped from set) → Edge | **Edge** | "Declaration lapsed — re-declare to rejoin Core" | no self-recovery; withdraw+re-declare |
| withdraw-pending | (gates) | "withdrawing → clears epoch N" | stake locked until withdraw_at |

**Correction to ship (not yet installed):** the current "Core at risk — withdraw & re-declare to renew"
copy is **premature** for the ageing-but-not-lapsed state — the node may still refresh at the next epoch
boundary, and prompting a withdraw there needlessly triggers the ~4-epoch (#425) penalty. Split it: while
still `is_active`, advise *wait/keep mixing + funded*; only advise *withdraw + re-declare* once it has
actually lapsed to Edge.

## Recommendations

- **#107 alert** — correct to keep, with the split copy above.
- **#105 automatic redeclaration is not adopted by #108.** Prefer explicit narrow repair, preserve
  the stake, and require an operator decision for withdrawal after diagnosing genuine lapse.
- Do **not** implement an unconditional timer heartbeat: the complete ledger path requires a valid
  Blend proof. Changes to that mechanism belong upstream.
- Historical issue references in this account are context, not independently reverified current status.

## Sources
Code: `core/src/sdp/mod.rs`, `ledger/src/mantle/sdp/mod.rs`,
`core/src/mantle/ops/sdp/{declare,active,withdraw}.rs`, `core/src/sdp/locked_notes.rs`,
`services/blend/src/{core/mod.rs,instance.rs}`, `services/sdp/src/lib.rs`,
`blend/message/src/reward/` — all under logos-blockchain v0.2.4.
Issues: logos-blockchain#1930 (merged submit path); agent-message-board #421/#334 (not-work-verified),
#425 (no lapse recovery), #88/#172/#333/#367/#368 (client-side drops); logos-blockchain-module#64
(`core_info` source). Internal: referral proposal "T4" assumption (contradicted).
