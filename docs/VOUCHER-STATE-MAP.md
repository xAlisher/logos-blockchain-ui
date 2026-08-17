# Voucher claim — user journey and honest states

Grounded in a real claim on this machine: **9 claims settled 2026-08-17 07:53:17**, block
`10706dc859be25003b2e0b2111392fba9add6253c52209e6979843d4604637c6` (slot 1025597), reward
**9,517** each, fee **4,173** each. Node source read at `logos-blockchain/logos-blockchain` @ main.

---

## 1. The word "pending" currently means the opposite of what it means

`LeaderRewardsView.qml:74`:

```qml
text: qsTr("%1 pending").arg(root.vouchers.length)
```

`root.vouchers` is parsed from `wallet_get_claimable_vouchers`, and that endpoint returns
**`available` only** — the node builds `ClaimableVouchers { available, pending }`
(`services/wallet/src/states.rs:326-347`) and the HTTP layer maps `.available`.

So the badge labels **available** vouchers as "pending". Meanwhile the node's real `pending`
— reserved, claim in flight — is **never sent to the UI at all**. One word, two opposite
states, and the state it actually names is the invisible one.

`InfoButton` repeats it: *"The list shows your pending claimable vouchers"*.

This is the single highest-value fix in the panel: it is a rename, and it stops the UI
asserting something false about every voucher on screen.

---

## 2. The real lifecycle of a voucher

`claimable_vouchers(tip)` sorts every voucher the wallet knows into three buckets — and the
third one has no name and no display:

```rust
for voucher in self.wallet.voucher_commitments_and_nullifiers() {
    if self.pending_claims.is_reserved(&voucher.nullifier) {
        pending.push(voucher);            // ← reserved, in flight. Never reaches the UI.
        continue;
    }
    if self.wallet.voucher_path_snapshot(tip, &voucher.commitment)?.is_some() {
        available.push(voucher);          // ← the only bucket the UI ever sees
    }
    // ← no path snapshot at tip: falls through into NEITHER list. Invisible.
}
```

| # | State | Node truth | Shown today |
|---|---|---|---|
| 1 | **Earned** | you led a block; `voucher_cm` in the header | — |
| 2 | **Not yet provable** | no `voucher_path_snapshot` at tip | **nothing — silently absent from both lists** |
| 3 | **Ready** | provable at tip, not reserved | shown, mislabelled "pending" |
| 4 | **Reserved** | `reserve_claim()` fires on button press | **vanishes from the list, unexplained** |
| 5 | **Submitted** | tx posted to mempool | nothing |
| 6 | **In a block** | included, not final | nothing |
| 7 | **Settled** | nullifier in an immutable block; reward spendable | nothing |
| 8 | **Reservation expired** | evicted after `security_param` immutable blocks | **reappears in the list, unexplained** |

States 2 and 8 are the ones that make the panel feel haunted: vouchers appear and disappear
with no user action behind them.

---

## 3. The journey as it happens today

**Before.** Card reads *"Claimable vouchers"*, badge *"13 pending"*, thirteen cards each showing
two 64-char hex strings (`cm`, `nf`) that mean nothing to a node operator. Button **Claim**,
always enabled — there is no `enabled:` binding at all (`LeaderRewardsView.qml:165-169`).

**The press.** Nothing happens visually. No spinner, no disable, no acknowledgement. The button
stays live and pressable.

> This is very likely why my own claim was **nine claims**. Nine separate transactions, nine
> distinct nullifiers, all landing in one block. A button that gives no feedback and stays
> enabled gets pressed again. Each press silently spent a different voucher and a fresh
> 4,173 fee — **37,557 in fees for what was probably meant to be one claim.**

**~1s later.** Two things change, neither of them labelled:

1. A 64-character hex hash appears in `leaderClaimResultText` — `textSecondary` grey,
   `ElideRight`, no caption, sitting inside a `LogosButton` that does nothing. It is your only
   receipt, styled as decoration.
2. `refreshClaimableVouchers()` runs. Badge goes 13 → 12; a card disappears.

**The disappearance is the problem.** It is the panel's loudest signal and it carries no
information: a voucher leaves the list the instant it is *reserved locally*, before the network
has seen anything. It looks identical whether the claim settles or is dropped.

**Then nothing, forever.** The balance tile is never refreshed — `onClaimLeaderRewardsRequested`
calls `refreshClaimableVouchers()` and nothing else. Roughly two hours later the claim finalizes
in silence. On this node the claim was invisible even in the logs: `wallet_get_balance` is
written every 5 seconds; `leader_claim` appears **zero times**.

---

## 4. The honest UI: a pool and a ledger, not one board

Design rule, and the one this panel breaks everywhere: **never let a value outlive the state it
described.** The disappearance survives the reservation; the word "pending" survives its own
meaning.

### Why not a kanban board

The obvious first shape is a board with a column per state. It is the wrong fit here:

- **Vouchers are fungible.** Every one is worth 9,517. Kanban exists to track distinct items with
  identity; giving identity to interchangeable units invites the reader to care which card sits
  where, when the honest answer is "it doesn't matter, there are thirteen".
- **You cannot move the cards.** The protocol moves everything on a timer. A board you can't drag
  is a table with extra whitespace.
- **The distribution is pathological** — 13 / 1 / 0 / 9 today. One column always overflowing, two
  usually empty.
- **No time axis.** The single most important fact in the flow is *"this takes about two hours"*.
  Columns cannot express duration. That is precisely the question today's UI fails, and a board
  would fail it identically.

Kanban would earn its place if vouchers had different values worth comparing, if the operator
chose which to claim, or if a voucher could take branching paths. None hold.

### The shape that does fit

**The state machine belongs to the claim, not the voucher.** Before the press, vouchers are a
*pool* — a quantity, fungible, no identity. After the press you care about a *claim*, which has
identity, a hash, a cost, a duration and an outcome. Two data shapes; one board would force one of
them into the wrong clothes.

```
┌─ Leader rewards ───────────────────────────────────────────┐
│  Ready to claim                                             │
│  13 vouchers · 123,721 total · fee 4,173 each               │
│                                        [ Claim one ▸ ]      │
│  ⓘ 2 more earned, not yet provable                          │
└─────────────────────────────────────────────────────────────┘

┌─ Claims ────────────────────────────────────────────────────┐
│ ◐ Claiming    3c63ee96…   ●━━━━━○─────○      ~2h remaining  │
│                           sent  block  settled              │
│ ✓ Settled 07:53  28db9420…   +9,517 − 4,173 = +5,344        │
│ ✓ Settled 07:53  0a0242be…   +9,517 − 4,173 = +5,344        │
│ ⟲ Expired 04:11  voucher returned to pool · no fee charged  │
└─────────────────────────────────────────────────────────────┘
```

Every state from §2 lands somewhere honest. State 2 becomes a footnote on the pool instead of
vanishing. State 4 becomes a live row instead of a disappearance. State 8 becomes a visible row
that says *no fee charged* — the thing an operator most wants to know. And it scales to the real
incident: nine concurrent claims are nine rows with nine timers, where a board would stack nine
identical cards in one column with no ordering.

An optional one-line summary strip can sit above the list — `Earned 2 ─▸ Ready 13 ─▸ Claiming 1
─▸ Settled 9` — but it is a summary, not a replacement, because it still carries no time.

### The pool card

- Rename the badge to **"%1 ready"**. Fix the `InfoButton` text with it.
- Show **"%1 in flight"** from the node's real `pending` (needs the upstream ask in §6).
- Lead with the aggregate — count, total value, fee per claim — not with `cm`/`nf` hex. Keep the
  per-voucher hex behind a disclosure.

### The button

- `enabled: vouchers.length > 0 && balance > 0`. Today there is no `enabled:` binding at all.
- **Disable while a claim is in flight.** This alone prevents the 9× fee.
- Say *why* when disabled: "No vouchers ready" vs "Not enough balance to pay the claim fee".

### Refresh the balance

`onClaimLeaderRewardsRequested` must refresh the balance too. Right now the one number that proves
the claim worked is the last one to move.

---

## 5. The claims ledger (permanent — claims are never dismissed)

### Precedent

`getProposals()` (`logos_node_1click_backend.cpp:881`) already does this: an accumulate-only JSON
array at `proposals-history.json`, beside `user_config.yaml` in the node's `module_data` dir,
unioned with a fresh scan on every read. Reuse the pattern and the location — storing beside the
node config means the ledger is scoped to that node identity, which is correct.

### The asymmetry that changes the design

`getProposals()` is only a *cache*: the node logs every block it proposes, so the file can always
be rebuilt from logs. **Claims have no such source** — `leader_claim` appears zero times in the
Basecamp log while `wallet_get_balance` is written every five seconds.

So the local write is **write-ahead, not cache**. If we do not record the press, no evidence that
it happened exists anywhere on the machine.

| | Source of truth | Recoverable? |
|---|---|---|
| **Submission** — tx hash, press time | local write-ahead | **no** — lost if not written |
| **Settlement** — slot, block, reward, voucher | the chain (opcode `0x30` + our pk) | yes, always |

### Reconciliation

1. **Write-ahead** on press: append `{tx, submitted_at, status: submitted}` as the call returns.
2. **Reconcile** forward from a stored `last_scanned_slot` watermark; match chain claims to rows
   by tx hash; fill in slot, block, reward, voucher nullifier.
3. **Backfill**: any on-chain claim bearing our pk with no local row is inserted as settled. This
   is what makes it a ledger rather than a session log — a fresh install, a wiped `module_data`,
   or claims made from another machine all come back. Only in-flight and expired rows are lost,
   and those are transient by nature.

Steady state is a few blocks per poll. Only the first backfill is expensive — pulling ~3 hours of
blocks was ~1 MB / 271 blocks — so it should run in the background.

### Reorg safety falls out of the state model

Mark **Settled** only from blocks below LIB. An above-LIB sighting is **In a block** — already a
state in §2. A reorg then moves a row honestly backwards to Claiming, instead of un-settling
something the UI already called final.

### Row schema

```json
{ "tx": "3c63ee96…", "submitted_at": "2026-08-17T07:52:44",
  "status": "settled",              // submitted | in_block | settled | expired
  "slot": 1025597, "block": "10706dc8…", "settled_at": "2026-08-17T07:53:17",
  "voucher_nf": "fd81857a…", "reward": 9517, "fee": 4173 }
```

### The block-events endpoint gives us almost everything

`GET /cryptarchia/blocks/:id/events` returns a `LeaderRewardClaimed` event per claim, keyed by
`tx_hash`, carrying **both** the voucher nullifier and the minted note's value:

```json
{"Tx":{"tx_hash":"3c63ee96…","payload":{"LeaderRewardClaimed":{
  "voucher_nullifier":"fd81857a…",
  "utxo":{"output_index":0,"note":{"value":9517,"pk":"5da62d70…"}}}}}}
```

Verified against the real block: 9 events for our pk, **9,517 each, 85,653 total** — read from the
chain, not inferred from wallet notes. So reward and voucher are both exact at settlement, matched
to a local row by `tx_hash`. The scan is cheap: fetch events only for blocks already found to
contain an opcode-`0x30` op.

### Two remaining gaps

1. **The voucher is unknown at press time.** `leader_claim` returns only a tx hash; the node picks
   the voucher internally via `available.next()`. `voucher_nf` shows `—` until settlement, then
   fills in from the event. Not worth an upstream ask.
2. **Fee still needs a note-value memory.** The reward comes from the event, but the fee is
   `input_note_value − change_output` and the block carries only the input's *id*. Since balance is
   polled every 5s anyway, a rolling `{note_id: value}` map makes it exact and cheap.
3. **Expiry has no chain event.** A claim that never lands produces nothing to observe. It must be
   *inferred* — not seen on chain after `security_param` finalized blocks — and the UI should label
   it as an inference rather than assert it.

### The lifetime summary is therefore computable

Total claimed = sum of `LeaderRewardClaimed` values for our pk across all scanned blocks. Total
fees = sum of per-claim fees (gap 2). Net = the difference. The pool's *potential* value must be
labelled as an estimate — it is `ready_count × last_observed_reward`, since the reward is read from
ledger state at execution and can change.

---

## 5b. Why claims expire: restarting the node discards them

State 8 ("reservation expired") is not a rare edge case during development — it is the **normal
outcome of claiming and then restarting**. Observed 2026-08-17: of six claims submitted from this
machine, **three expired**, and the cause was mundane.

**The mempool is in memory.** Every Basecamp restart discards every pending transaction. A claim
that has not yet been included in a block simply ceases to exist. On this machine that day:

| | |
|---|---|
| Basecamp restarts | **22** |
| mempool before / after | 4,817 → **2** |
| block production | 1 per **67** slots (down from ~1 per 39) |
| claims submitted 15:25–15:31 | none on chain, none in mempool |

With blocks that sparse, a claim must survive a long time to be picked up. Across 59 blocks in slots
1052000–1056000 there were **zero** leader-claim ops from anyone — so those three were not
out-competed, they were simply gone.

### Nothing is lost, and the UI already says so correctly

The cycle closes as designed: submitted → transaction dropped → the node's reservation ages out
after `security_param` immutable blocks → **the voucher returns to `available`**, and **no fee is
charged** because the transaction never executed. Verified: the voucher count went back up and the
balance was unchanged.

So an "Expired · voucher returned to pool · no fee charged" row is **honest and complete**. It is
not a bug, and it should not be "fixed" by hiding it.

### The practical rule

**Do not claim immediately before restarting the node**, and while iterating on the module expect
claims to need re-submitting. Contrast: a long-running node (sneg, up 2 d 5 h, mempool 625) had
**four of four** claims land within seconds.

This is an operational failure mode, not an API gap — worth stating because the next person to see
an Expired row will reasonably assume something is broken.

---

## 6. Is the missing history a privacy measure? No.

Worth settling explicitly, because the answer changes what the UI is allowed to imply.

### What *is* private by design

The claim carries a Groth16 proof whose public inputs are only three values
(`core/src/proofs/leader_claim_proof.rs:104-111`):

```rust
pub struct LeaderClaimPublic {
    pub voucher_nullifier: Fr,
    pub voucher_root: Fr,
    pub mantle_tx_hash: Fr,
}
```

The voucher **commitment is absent** — it is the private witness. So an observer cannot link a
claim back to the block that earned it. Our own code documents the matching half in
`getProposals()` (`logos_node_1click_backend.cpp:876`): Cryptarchia leadership is private, each
block's `leader_key` is per-note-derived rather than a stable identity, so an on-chain
`leader_key` match cannot identify our blocks. That is exactly why proposals have to be scraped
from our own logs.

**The protected property is: your block-proposal identity is unlinkable from your reward claims.**

### What is *not* private

`LeaderClaimOp` carries `pk` in cleartext on chain:

```json
{"opcode": 48, "payload": {"rewards_root": "37f67cc7…", "voucher_nullifier": "fd81857a…",
  "pk": "5da62d70bdc0230b8a552d3f4e730658b2aef07c694eaed859f4e24aa4ccca0e"}}
```

All nine claims cited at the top of this document were identified as ours by a **string match on
public block data** — no
keys, no node access. Anyone can count a pk's claims and total its rewards.

### Therefore the ledger crosses no boundary

The data is already public *and* already bound to the pk. Recording it locally leaks nothing that
is not on chain under that name. The privacy boundary sits between *proposing* and *claiming*, and
a claims ledger does not touch it.

The one theory that would have justified the silence — log hygiene, since operators paste logs
into bug reports — does not survive the code. `logos_blockchain_module.cpp:611` does:

```cpp
fprintf(stderr, "wallet_get_balance: address_hex=%s\n", address_hex.c_str());
```

a raw `fprintf` rather than the tracing framework used everywhere else, stamping the pk into the
log every five seconds regardless. That reads as leftover debug output, not policy. If
claim-silence were deliberate hygiene, this line would be the first thing removed.

**Read: claims are unlogged because nobody built it, not because someone decided against it.**

### The UI consequence

Two different guarantees sit side by side in the same panel, and the difference must be stated
rather than left to inference:

- **Proposals** — genuinely private; this is *why* they come from local logs, not the chain.
- **Claims** — fully public under your pk; anyone can total them.

An operator who assumes the claim inherits the proposal's privacy would be wrong, and that is a
costlier misunderstanding than any of the state bugs above. One line of copy in the claims card.

---

## 7. Implementation trap: the module's IPC shapes are NOT the node's HTTP shapes

Every bug in the first working build of the ledger had one cause: the code was written
against the node's HTTP API — which is what you get when you explore with `curl` on
`127.0.0.1:8080` — while the module exposes a **different serialization of the same data** over
IPC. They diverge on nearly every call:

| Data | Node HTTP (`:8080`) | Module IPC (`invokeRemoteMethod`) |
|---|---|---|
| cryptarchia info | wrapped: `{"cryptarchia_info":{…},"phase":…}` | **flat**: `{lib_slot, slot, height, mode}` |
| wallet balance | JSON incl. a `notes` map | **a bare number string** — not JSON at all |
| wallet notes | `{noteId: value}` map | `{"notes":[{"id":…,"value":"<string>"}]}` — array, value stringified |
| block header | includes `id` (and calls it `block_root`) | **no `id`** — five fields, `id` is computed |

The block-header one is the nastiest. `core/src/header/mod.rs` defines
`Header { version, parent_block, slot, body_root, proof_of_leadership }` — the ID is *derived*
(a hash over `"BLOCK_ID_V1"`), so serde never emits it. Only the HTTP DTO adds one. Reading
`header.id` therefore yields `""`, and every `get_block_events` call is rejected with
*"Header ID must be 64 hex characters"*.

**Workaround, and it is the supported one:** for finalised blocks in slot order, block *i*'s id
is block *i+1*'s `parent_block`. Sort each chunk by slot, fetch a small lookahead past the chunk
end so the last in-range block has a successor, and process only blocks that have one.

**The rule: verify every field against the module's own source, not against a curl response.**
A shape that "obviously" matches has been wrong four times out of four here.

### The compounding failure: silent error paths

None of the above was visible, because each was reached through a path that produced no
evidence — a bare `continue`, or a watermark advanced outside its success check. The scan
cheerfully reported `blocks=228, ourClaims=9` while writing zero rows.

Two habits fixed it, and both are worth keeping:

1. **Never advance state on a failed read.** The watermark now moves only inside
   `if (blocks.success)`; a failure holds position and retries.
2. **Record scan health where it can actually be seen.** This plugin runs under `ui-host`,
   whose stderr Basecamp does **not** persist — so `qWarning`/`qInfo` from a `ui_qml` plugin is
   discarded outright. Diagnostics therefore go into `claims-history.json` as a `lastScan`
   object (`from`, `to`, `ok`, `blocks`, `claimOps`, `ourClaims`, `events`, `eventsFailed`,
   `eventsError`). That is what turned "it finds nothing" into a named cause in one pass.

`scanVersion` in the store forces a rescan when the scan logic changes, so ranges burned by an
earlier bug are re-examined instead of being trusted forever.

---

## 8. What needs upstream, and what does not

**Fixable here, today:** the "pending" rename, the `enabled` gate, in-flight disable, the pool +
claims-list layout, the persistent ledger with chain backfill, the balance refresh.

**Needs the node:**
- `wallet_get_claimable_vouchers` should return `pending` alongside `available` (it already
  computes both and throws one away).
- **Bucket 2 — vouchers provable at no tip — should be reported rather than dropped
  silently. This is now MEASURED, not inferred, and it is the strongest of these asks.**
  On this node, 2026-08-17:

  | | |
  |---|---|
  | blocks led (node's own log, from 2026-08-06) | **110** |
  | claims settled | 10 |
  | vouchers reported claimable | 12 |
  | **unaccounted** | **~88** |

  The easy explanations were ruled out rather than assumed:
  - **not a chain re-genesis** — genesis is ~2026-08-05 (slot ≈1,065,700 at 1 s/slot) and
    the proposal log starts 08-06, so every entry is on the current chain;
  - **not orphaned blocks** — 8 logged proposals sampled against
    `/cryptarchia/blocks/<id>/events`: **7 are in the chain**, 1 returned 404;
  - **not pruning** — `wallet/src/lib.rs:848` `prune_vouchers` removes only vouchers whose
    nullifier already appeared on chain, i.e. the 10 claimed ones.

  What remains is the silent third bucket in `claimable_vouchers`: a voucher the wallet
  cannot prove at the current tip is pushed into neither `available` nor `pending`, and no
  endpoint lists it. So an operator cannot tell whether ~88 vouchers exist and are
  temporarily unprovable, or never materialised. At the observed reward that is on the
  order of 800k LGO of ambiguity.

  **Ask:** either include that bucket in `wallet_get_claimable_vouchers` with a reason, or
  expose a count. Silence here is indistinguishable from loss.
- `leader_claim` should return the voucher nullifier it consumed, and ideally the fee.
- A claim should be logged. Today it leaves no trace on the operator's own machine.
- (Tracked separately: `InsufficientFunds` reports `available` without `required`. Confirmed
  concretely here — the wallet held **3,862**, the fee was **4,173**; the withheld number was a
  shortfall of **311**.)
