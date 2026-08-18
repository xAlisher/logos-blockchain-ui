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
| E4 | The fee was lost because a block is scanned once and the ingredients discarded | **REFUTED** | Storing `feeInput`/`feeChange` and resolving lazily still produced **zero** entries after a full rescan — so `feeByTx` never populates at all. |
| E5 | The ledger op's `inputs`/`outputs` shape over IPC differs from the HTTP shape | **OPEN** | Diagnostic shipped (scanVersion 10) recording the tx's opcodes, `mantle_tx` keys and the ledger op's payload keys/sizes as seen over IPC. |

## F. Rewards and leadership

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| F1 | Vouchers accumulate safely and can be claimed whenever | **REFUTED (partly)** | 111 blocks led yielded 12 claimable. Vouchers not provable at the current tip fall into a bucket no API exposes. |
| F2 | A second node would show the same voucher gap | **INCONCLUSIVE** | Its logs rotate hourly and had already lost the history; inferring "no gap" from one retained proposal was not evidence. A persistent harvester is now running to settle it. |
| F3 | Claiming everything pauses block production until the next epoch | **OPEN** | Leadership filters notes to the *epoch snapshot* (`services/wallet/src/lib.rs:1099`); claiming replaces aged notes with fresh ones. After sweeping 47 claims: **0 blocks led, 0 new vouchers in 7+ h**, still epoch 30. Falsifiable prediction: it resumes when epoch 31 begins. |

---

## The pattern behind the REFUTED rows

Nearly every wrong prediction came from **reading a shape or a timing from the node's HTTP API and
assuming the module's IPC surface matched**. It does not, on nearly every call:

| Data | HTTP (`:8080`) | Module IPC |
|---|---|---|
| cryptarchia info | wrapped in `cryptarchia_info` | flat |
| wallet balance | JSON with a `notes` map | bare number string |
| wallet notes | `{id: value}` map | array, values stringified |
| block header | includes `id` | no `id` — computed |
| ledger op inputs/outputs | `[id]` / `[{value}]` | **under test (E5)** |

And the failures were silent every time: a bare `continue`, a watermark advanced outside its success
check, a zero read from a missing field. The rule that came out of it, and the reason this log
exists: **verify a field against the module's own source or a live diagnostic, never against a curl
response — and never let an error path produce no evidence.**
