# Leader rewards — experiment log

Every hypothesis tested while building and dogfooding the Leader Rewards dashboard
(2026-08-17 → 18), what was predicted, and what actually happened.

It is kept because **most of these predictions were wrong**, and the wrong ones were wrong in a
consistent way: a shape or a timing read from one source and assumed to hold for another. Anyone
extending this feature will save a day by reading the REFUTED rows first.

Verdicts: **CONFIRMED** (measured) · **REFUTED** (measured, prediction wrong) ·
**INCONCLUSIVE** (evidence too thin to decide) · **OPEN** (under test).

---

## A. What the UI was saying

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| A1 | The `%1 pending` badge renders the node's `available` bucket, i.e. labels READY vouchers with the word for RESERVED ones | **CONFIRMED** | `states.rs` builds `ClaimableVouchers{available,pending}`; the endpoint ships `.available`. Renamed to "ready to claim". |
| A2 | The nine claims of 2026-08-17 07:53 happened because the button gave no feedback and stayed enabled | **INCONCLUSIVE** | 9 txs, 9 nullifiers, one block, submitted seconds apart — consistent with repeat presses, but never proven. Stated as *likely* in the issue, not as fact. |
| A3 | A voucher disappearing from the list means the claim succeeded | **REFUTED** | It leaves `available` the instant it is *reserved locally*, before the network sees anything. Identical whether the claim settles or dies. |
| A4 | Blocks led == vouchers earned | **REFUTED** | 111 led, 12 claimable, 10 claimed. Sub-label removed; the gap is now stated, not papered over. |

## B. The chain-reconciliation build

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| B1 | Settlement can be recovered from the chain even with no local record | **CONFIRMED** | Backfilled 9 claims — hashes, slot, nullifiers and 9,517 reward all matching a by-hand analysis done independently. |
| B2 | The scan finds nothing because `get_blocks` returns empty (slot args fail to marshal) | **REFUTED** | `blocks=749` over an 8,000-slot range. |
| B3 | The scan finds nothing because we match the wrong public key | **REFUTED** | `claimOps=9, ourClaims=9` at the claim slot; an unrelated pass showed `claimOps=8, ourClaims=0`, so the filter discriminates correctly. |
| B4 | `get_block_events` fails because the block id we pass is malformed | **CONFIRMED** | `Header` has no `id` field — it is computed (`"BLOCK_ID_V1"` hash). HTTP adds one; IPC does not. `header.id` was `""`. Fixed by taking block *i*'s id from block *i+1*'s `parent_block`. |
| B5 | A failed read can safely advance the scan watermark | **REFUTED** | It marked 126,000 slots scanned that were never read, permanently. Watermark now advances only on success. |

## C. Units and identity

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| C1 | `baseUnitsPerLgo = 10000` (raw value is a sub-unit of LGO) | **REFUTED** | `gas.rs` cites the spec as `P_STR(0) = 1 LGO/gas` and writes `GasPrice::new(1)`. Official UI and hackyguru/persona both render raw with no division; the constant had zero hits across GitHub. Balances were **10,000x too small**. |
| C2 | The dashboard's Balance tile shows the wallet that earns and pays | **REFUTED** | It showed `primaryAddress` (first entry of `get_known_addresses`). Rewards land in `leader.wallet.funding_pk` — a different key: 2,000,000,000,000 vs 4,000,000,047,950. The claim gate had the same bug. |
| C3 | The leader reward is a constant | **REFUTED** | Four values observed on one chain: **9,517 → 9,535 → 9,676**. Pool value is now sourced from the last settled claim and labelled an estimate. |

## D. Claim mechanics

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| D1 | Rewards become visible only after finalization (~2 h) | **REFUTED** | All reward notes appeared in the wallet **within seconds**. The wallet applies blocks at *tip*; LIB governs reorg-safety, not spendability. |
| D2 | Only ~3 claims can be in flight (one per unreserved note), so a 4th fails | **REFUTED, then PARTIALLY CONFIRMED** | The 4th succeeded — change notes are immediately spendable. But claiming 43 in sequence, attempts 8 and 9 failed with `available=0`; a 5 s backoff cleared both. So: a transient, self-healing wall, not a hard limit. |
| D3 | `available=0` means the wallet is out of funds | **REFUTED** | It reported `available=0` while holding **3,000,000,258,641 LGO**. It counts *unreserved notes*. Reported upstream. |
| D4 | Restarting the node explains expired claims (in-memory mempool discarded) | **REFUTED** | A burst of 12 claims on 9 h 25 m of continuous uptime still gave 5 settled / 7 expired. Restarts are at most contributory. |
| D5 | A claim that has not landed yet may still land later | **REFUTED** | The 7 failures never appeared in **1,586 blocks over 6 hours**, while 40 unrelated leader-claims did. A claim is included within ~20 slots or never. |
| D6 | Pacing claims improves the landing rate | **SUPPORTED, not isolated** | 47/47 landed at 2 s intervals on one node; ~12 in 11 s kept 5 on another. Peers also differed (92 vs 64), so pacing is correlated, not proven causal. |
| D7 | An expired row means something is broken | **REFUTED** | The reservation ages out, the voucher returns to `available`, and no fee is charged — verified both halves. The row is honest and complete. |

## E. Fees

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| E1 | The fee can be derived from the chain alone | **REFUTED** | Inputs carry an id and no value; outputs a value and no id; block events record neither. It needs a locally-tracked note map. |
| E2 | `wallet_get_balance` supplies the note breakdown for that map | **REFUTED** | Over IPC it returns a **bare number string**, not JSON. The `notes` map exists only on the HTTP endpoint. Switched to `wallet_get_notes` — which returns an *array* with stringified values, a third shape again. |
| E3 | Fees stay unknown only for claims whose note was spent before harvesting began | **REFUTED** | A settled claim's input note **is** in the map with the right value (9,517), change 5,344, fee 4,173 — and the row still had no fee. |
| E4 | The fee was lost because a block is scanned once and the ingredients discarded | **REFUTED as the cause, kept as a fix** | Storing `feeInput`/`feeChange` and resolving lazily still produced zero entries — the map was never populated (see E5). The lazy resolution was kept anyway: it is correct, and it is what lets a fee appear whenever its note later shows up. |
| E5 | The ledger op's `inputs`/`outputs` shape over IPC differs from the HTTP shape | **REFUTED — the shape was right, the KEY was wrong** | Diagnostic returned `opcodes=48,0`, `ledgerShape=plKeys=inputs\|outputs in=1 out=1` — exactly as expected. But `txKeys=ops`: **`mantle_tx` over IPC has no `hash` field** (the HTTP DTO adds one), so the map collapsed to a single `""`-keyed entry and every lookup missed. Re-keyed by `voucher_nullifier`, which both the claim op and the event carry. |
| E6 | With the key fixed, fees resolve for claims whose input note was harvested | **CONFIRMED** | 6 of 16 resolved, every one **4,173**: `+9,535 − 4,173` and `+9,676 − 4,173` ×5. The other 10 spent their notes before harvesting began and correctly read "unknown". |
| E7 | Both the reward and the fee vary | **REFUTED, then NARROWED** | On wild the **fee was constant at 4,173** while the reward moved (9,517 / 9,535 / 9,676), so the "43–44 %" figure drifted solely because the numerator changed. **Corrected 2026-08-19 by E8:** the constant is per node/version, not global. |
| E8 | The 4,173 fee is a property of the protocol, so a third node will show it too | **REFUTED** | optiplex (`blockchain_module` **0.2.2**, vs 0.2.1 on wild/sneg) charged **4,602** on all four claims, with all four rewards identical at **9,664** — a 47.6 % cost, not 43–44 %. The fee *is* constant within a node, which is why it looked protocol-wide from a single machine. Stating it as a universal constant was over-reach from one node's data. |

## F. Rewards and leadership

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| F1 | Vouchers accumulate safely and can be claimed whenever | **REFUTED (partly)** | 111 blocks led yielded 12 claimable. Vouchers not provable at the current tip fall into a bucket no API exposes. |
| F2 | A second node would show the same voucher gap | **INCONCLUSIVE** | Its logs rotate hourly and had already lost the history; inferring "no gap" from one retained proposal was not evidence. A persistent harvester is now running to settle it. |
| F3 | Claiming everything pauses block production until the next epoch | **OPEN** | Leadership filters notes to the *epoch snapshot* (`services/wallet/src/lib.rs:1099`); claiming replaces aged notes with fresh ones. After sweeping 47 claims: **0 blocks led, 0 new vouchers in 7+ h**, still epoch 30. Falsifiable prediction: it resumes when epoch 31 begins. |

---

## G. Third node — optiplex, `blockchain_module` 0.2.2 (2026-08-19)

A third machine, and the first on **0.2.2** rather than 0.2.1. It had been running 5½ days,
had earned vouchers, and had **never claimed** — which made it a clean read on numbers that
had only ever been measured on 0.2.1.

**Setup before touching anything:** tip advancing ~1 slot/s, 64 peers, `Online`/`Following`,
`leader.wallet.funding_pk` correctly set (the `logos-blockchain-ui#35` trap is absent here —
note the file also carries an unrelated `sdp.wallet.funding_pk`, and funding *that* is the bug).
Wallet held exactly one note of 1,000,000,000,000 — the untouched faucet note, no rewards.

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| G1 | Zero proposals in the retained logs means the node stopped leading | **REFUTED — and it nearly fooled me** | The hourly files retain ~10 hours. At 8 proposals per 5½ days, the *expected* count in a 10-hour window is ~0.3, so zero is the normal reading, not a fault. The real history lives in `logoscore.out`, which never rotates. |
| G2 | The rotating hourly logs are the only proposal source, so history before them is lost | **REFUTED** | `logoscore.out` (~400 MB, logoscore's own stdout) holds the whole run. Harvesting it recovered all 8 proposals back to 2026-08-14, four days beyond the hourly window. |
| G3 | The fee is 4,173 on any node (see E7) | **REFUTED** | 4,602 on every one of the four claims. See E8. |
| G4 | Rewards vary between claims | **REFUTED here** | All four rewards were identical at 9,664. On wild they varied — the difference is that these four were claimed within 35 seconds of each other, so they share their epoch conditions. Variation across time, not across claims. |
| G5 | The transient `available=0` failure is specific to 0.2.1 | **REFUTED** | Attempt 2 of 4 failed with `Wallet API error: Wallet does not have enough funds, available=0` while the wallet held 1,000,000,000,000. Reproduces unchanged on 0.2.2. A plain retry succeeded. Evidence for `logos-blockchain-node#3336`. |
| G6 | Every led block yields a claimable voucher | **REFUTED — second-node confirmation of module#67** | **8 proposals, 4 vouchers.** Exactly half, and no API accounts for the other four. This is the independent evidence the upstream issue was missing: wild's 113→12 gap could have been machine-specific; two machines on different module versions cannot both be a local accident. |

**The claim run** — four vouchers, one at a time, 6s apart:

```
06:01:57  200  b9b36ad5…
06:02:03  500  available=0          ← transient; wallet held 1e12
06:02:09  200  2453a8ad…
06:02:15  200  29fdb108…
06:02:31  200  e04ab569…            ← retry of the failed one
```

All four settled **within ~35 seconds** of the last submission, consistent with the
"lands within ~20 slots or never" finding from wild.

**Reconciliation** — the arithmetic closes exactly, which is what makes the fee trustworthy:

```
4 rewards × 9,664          =  38,656
faucet note 1,000,000,000,000 → 999,999,981,592
fees                       =  18,408  → 4,602 each
net                        =  20,248  = 4 × (9,664 − 4,602)
balance 1,000,000,000,000  → 1,000,000,020,248 ✓
```

A **proposal harvester** now runs here every 15 minutes
(`/home/dar/logos-harvest/harvest_proposals.py`, cron `*/15`). It reads `logoscore.out`
incrementally by byte offset — a full pass costs 22.9s, an incremental one 0.30s — and
snapshots vouchers, balance and reward notes alongside the proposal count, so the
proposals-vs-vouchers gap accumulates as a time series instead of being re-derived from a log
that has already been pruned.

## The pattern behind the REFUTED rows

Nearly every wrong prediction came from **reading a shape or a timing from the node's HTTP API and
assuming the module's IPC surface matched**. It does not, on nearly every call:

| Data | HTTP (`:8080`) | Module IPC |
|---|---|---|
| cryptarchia info | wrapped in `cryptarchia_info` | flat |
| wallet balance | JSON with a `notes` map | bare number string |
| wallet notes | `{id: value}` map | array, values stringified |
| block header | includes `id` | no `id` — computed |
| ledger op inputs/outputs | `[id]` / `[{value}]` | same |
| `mantle_tx.hash` | present | **absent — only `ops`** |

And the failures were silent every time: a bare `continue`, a watermark advanced outside its success
check, a zero read from a missing field. The rule that came out of it, and the reason this log
exists: **verify a field against the module's own source or a live diagnostic, never against a curl
response — and never let an error path produce no evidence.**
