# Blend Core / SDP — states & lifecycle (source of truth for the UI)

Purpose: one honest, cited model of how a node becomes and stays a **Blend Core provider**, so the
dashboard's blend states map onto protocol reality instead of guesswork. Grounded in the node source
(`logos-blockchain` **v0.2.4**, read at `/extra/tmp/lb-node`), the SDP ledger rules, and upstream
issues. Every claim cites code `file:line` or an issue number. Inference is marked **(inf)**.

## TL;DR — the one thing to internalise

Core membership is **not** "declare once and stay". It is a **per-epoch, work-gated, probabilistic**
state. You keep it only if, each epoch, the node (a) is in the frozen Core set, (b) actually mixes and
collects a qualifying blend token, and (c) that token's activity proof lands on-chain to refresh the
declaration's `active` epoch. Miss `inactivity_period` (= **2** on testnet) consecutive refreshes and
the declaration **ages out** of the Core set — and there is **no heartbeat-your-way-back**: recovery is
withdraw (2 epochs) + re-declare (2 epochs). Aging out is a **legitimate lifecycle transition, not a
bug** — the "Core at risk" warning is honest.

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
- **NOT work-verified.** The ledger's `SDPActiveOp::validate` checks only declaration-exists, not-
  withdrawn, strictly-increasing nonce, zk-sig — with a literal `// TODO: check service specific logic`
  (`core/src/mantle/ops/sdp/active.rs:34-69`). Upstream **#421 (closed, superseded) / #334 (OPEN)**: the
  proof is a re-provable quota+selection+lottery ticket, **not evidence of relaying**. So *"actively
  mixing" is neither necessary nor sufficient for the refresh to land.* (This directly contradicts the
  internal referral-proposal assumption "T4 · the SDP active heartbeat carries a ZK proof of real Blend
  activity" — it does not, in 0.2.x.)
- **Client-side drops.** A submitted refresh can be evicted from the SDP mempool (#333/#330), lost on
  restart (Edge/Core state is in-memory, #172), or dropped by a premature tracker/declaration reset
  (#88/#367/#368) — any of which silently stops refresh.

## What our node showed (epoch 38, `active=37`) — the timing-lag case

Declared ~epoch 37 → `active=37`. It only becomes a snapshot member ~epoch 38, so its **first** possible
refresh (for epoch 38) can't be emitted until the **38→39 boundary** (into epoch 39). At epoch 38, zero
`SDPActive` submissions is **exactly what the code produces** — confirmed: the live log has no
`blend_activity_token_evaluation` / `sdp_activity_proof_submitted` / mode-transition events yet. So at
epoch 38 it's genuinely at-risk-but-undecided: it **may** refresh at the 38→39 boundary (if it collects
a token and stays core) and clear, or lapse and drop to Edge at epoch 40. It is **racing its own age-out
by design**, because the first refresh opportunity lands ~2 epochs behind declare.

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
- **#105 auto-re-declare watchdog** — the right operator-side mitigation, given no self-recovery. It must
  act only after a genuine **lapse** (Edge with a stale/aged declaration), not while still `is_active`.
- Do **not** implement an unconditional timer heartbeat in our UI/module — the ledger would accept it
  (`active.rs:34`), but it deliberately ties refresh to real mixing; a blind timer re-creates exactly the
  #334 "premium capture by re-proving" abuse. Any keep-alive change is an **upstream design decision**.
- Track upstream **#334** (work-binding) and **#425** (lapse re-entry) — both OPEN, no merged fix.

## Sources
Code: `core/src/sdp/mod.rs`, `ledger/src/mantle/sdp/mod.rs`,
`core/src/mantle/ops/sdp/{declare,active,withdraw}.rs`, `core/src/sdp/locked_notes.rs`,
`services/blend/src/{core/mod.rs,instance.rs}`, `services/sdp/src/lib.rs`,
`blend/message/src/reward/` — all under logos-blockchain v0.2.4.
Issues: logos-blockchain#1930 (merged submit path); agent-message-board #421/#334 (not-work-verified),
#425 (no lapse recovery), #88/#172/#333/#367/#368 (client-side drops); logos-blockchain-module#64
(`core_info` source). Internal: referral proposal "T4" assumption (contradicted).
