# Spec — Address check in the Enable Blend Core journey

_Status: DRAFT, in progress (requirements being dictated). Owner: Alisher. Surface: node dashboard
(logos-blockchain-ui fork, `feat/blend-core-lifecycle`), inside the Enable Blend Core flow, **before**
the declaration is submitted. Companion: [blend-core-progress-spec.md](blend-core-progress-spec.md);
operator guide [ecodev/nodes-workshop/connect-node-to-blend-core.md]._

## Why this exists
Submitting a Blend Core declaration is not free or reversible on a whim: it **locks a funded note as
stake** and **publishes your IP on-chain** (the locator). The #1 real-world failure is declaring with an
address that is not actually reachable or not stable, so the node earns nothing (nonce stays flat) while
the stake sits locked. Today the locator is guessed from an ipify HTTP lookup, which reports the IP your
*outbound HTTP* egresses from, not the address peers can actually reach you on. This step makes the
operator **see, understand, and confirm** the address before they commit.

---

## Requirement 1 — Show the IP (via libp2p) and have the user confirm it is stable + publicly reachable

### 1.1 Source of truth: libp2p, not ipify
Resolve the address from the node's own P2P layer, which knows what peers actually observe and can dial:
- **Identify** — peers report back the address they see you on (`observedAddr`).
- **AutoNAT** — peers actively **dial you back** on your Blend UDP port to confirm reachability, returning a Public / Private / Unknown verdict.

Show the operator the address AutoNAT has **confirmed reachable**, i.e. the exact locator that will be
published: `/ip4/<ip>/udp/<blend-port>/quic-v1`. If libp2p can't confirm, do **not** silently fall back
to ipify and present it as verified (see states).

### 1.2 The two properties the operator must learn + confirm
The UI must make the operator understand these are two *different* things, and confirm both:

1. **Publicly reachable** — peers on the internet can reach your Blend UDP port. AutoNAT dial-back
   succeeded. NOT a private / NAT-internal / Docker / CGNAT address.
2. **Stable** — the IP will not change for the life of the declaration. A dynamic residential IP (ISP
   DHCP lease) can rotate; when it does, the published locator becomes wrong and the node silently drops
   from Core mid-declaration while the stake stays locked.

### 1.3 The (i) explainer content (the "learn the difference" info)
An info popover on the field. Plain-language, two parts:

> **Reachable vs. not reachable.** Other Blend nodes must be able to reach your node from the internet to
> count your activity. A private address (starts with `192.168.`, `10.`, `172.16–31.`, `100.64.` for
> carrier-grade NAT, or a Docker-internal IP) is only visible inside your own network, so a declaration
> built on it earns nothing. We check reachability by having other nodes dial you back (AutoNAT).
>
> **Stable vs. dynamic.** Your declaration publishes this address on-chain and expects to be found there
> for as long as you run. Home internet connections often get a new IP every so often (dynamic / DHCP);
> if yours changes, your published address goes stale and you drop out of Core without an error. A static
> IP, a VPS, or a pinned address stays put. If you're on home internet, consider a static-IP add-on or
> pinning `external_address`.

### 1.4 States the check must handle
| State | Trigger | UI |
|---|---|---|
| **Checking…** | AutoNAT/Identify probing | spinner + "Asking other nodes if they can reach you…" |
| **Reachable (confirmed)** | AutoNAT = Public, dial-back OK | green; show `/ip4/<ip>/udp/<port>/quic-v1`; "Peers confirmed they can reach you." |
| **Not listening locally** | Blend Core isn't bound to the port (`ss`/RPC shows no listener; `core_info` null) | "Blend Core isn't running yet" — fix is start Core, **not** the router. Check this BEFORE blaming NAT (dial-back fails in both cases). |
| **Private / unreachable** | address is private, or dial-back failed *while bound locally* | red/warn; explain (NAT/port-forward the **blend** port); link the debug guide; **block or hard-warn** before declaring |
| **Reachable but likely dynamic** | reachable, but IP looks residential/dynamic (heuristic) | warn; "reachable now, but may change — see (i)"; allow with explicit acknowledgement |
| **Unknown / timeout** | AutoNAT inconclusive | can't confirm; offer manual pin (`external_address`) or proceed with an explicit "unverified" warning |

### 1.5 Manual override (advanced)
Let the operator **pin the address** (`external_address`) — for relays / reverse-proxies / when they know
better than AutoNAT. A pinned value skips the lookup and is shown as "pinned by you (not auto-verified)."

### 1.5b Blend port — always shown, editable only as a restart-gated advanced action
The locator's port is the **Blend Core listening port** (`blend.core.backend.listening_address`, default
**3400**), which is a *different* service from the **3000** blockchain/consensus port. Operators reliably
confuse the two (the guide leads with 3000; the blend port is a generated default they never saw), so:

**Default — show it, read-only.**
- Display the blend port prominently as part of the locator, labelled e.g. "Blend Core port (forward
  this — not your 3000 blockchain port)". Read from config; no typing needed for the common case.
- The port-forward guidance names **this** port, so the operator forwards the right one.

**Advanced — "Change port" (behind an explicit affordance).** Changing the port is **not a live edit** —
the port binds at node startup, so it requires a node restart. Therefore the change flow must:
- **Warn plainly:** "Changing the Blend port restarts your node." No silent restart.
- **Be pre-declaration only.** Before joining: change → restart → re-verify reachability → then declare.
  If a declaration already exists, editing the port is really **withdraw → change → restart → re-declare**
  (the on-chain locator carries the old port, and the stake note re-locks) — offer that as the path, not
  a bare edit.
- **Respect node state:** disabled while the node is mid-Blend-recovery or otherwise blocks config/identity
  changes ("only the same stopped node may be started").
- **Own the sequence:** the module drives stop → rewrite `listening_address` (via `generateConfig` / edit)
  → start. The operator never hand-edits the yaml.
- **Re-check after restart:** once the node is back up on the new port, re-run the AutoNAT reachability
  check (§1.1/§1.4) against the new port before the declaration is submittable again.

**Why default-read-only:** every port change is a node restart (bounce + resync churn), so the field must
not read like a casual text input. Most operators should only ever *forward* the shown port, never change it.

### 1.6 The confirm gate
The declaration button stays disabled until the operator ticks a confirm:
> ☐ I understand this address will be published on-chain, and my node must stay reachable at it to earn.
Ties the confirmation to the real stakes (locked note + on-chain publication).

### 1.7 Acceptance criteria
- Before the declaration is submittable, the operator has seen the exact locator to be published and its
  reachability verdict, sourced from libp2p (AutoNAT/Identify), not ipify.
- A private/unreachable address cannot be submitted without an explicit override.
- The (i) explains reachable-vs-not and stable-vs-dynamic in plain language.
- ipify is never presented as a *verified* address; at most it's a last-resort "unverified" fallback.
- The **blend port is surfaced explicitly** (from config), labelled distinct from the 3000 blockchain
  port, so the operator forwards the right one. Editing it is a deliberate, restart-gated, pre-declaration
  action (§1.5b) — never a plain text field.
- The check distinguishes **"not listening" (start Core)** from **"not forwarded/private" (fix NAT)** —
  it must not tell an operator to fix their router when the real issue is Core isn't running.

### 1.8 Open questions
- Does the node expose AutoNAT's verdict + `observedAddr` over the RPC today, or is that new backend
  work? (David is sending the Identify/AutoNAT reference — confirm the API surface.)
- "Likely dynamic" is a heuristic — what signal do we have (reverse-DNS / ASN / none)? May be
  best-effort or dropped for v1.

---

## Requirement 2 — Show and confirm the stake note (`locked_note_id`) before declaring

The second and final input to `/blend/join`. It bonds a funded note as the provider stake. The operator
must understand their money is being **locked, not spent**, see how much, and not be able to declare with
an unfunded key.

### 2.1 What it is — and TWO keys must be funded
The operator guide is explicit: **fund both the `BlendZk` key and the `SdpFunding` key** before joining.
They pay for different things:
- **`BlendZk` key** — the declaration **locks one of its notes as the provider stake** (`locked_note_id`).
  Sybil resistance: you bond value to declare. The note stays locked for the life of the declaration and
  **unlocks only on withdrawal**. (This corrects an earlier draft that said the stake note came from the
  SDP funding key — it comes from the BlendZk key.)
- **`SdpFunding` key** (`sdp.wallet.funding_pk`) — pays the **declaration fee** to submit on-chain.

So the UI needs **two funded-key checks**, not one.

### 2.2 Fund-first: both keys must be funded
Declaration is impossible unless the BlendZk key has a lockable note AND the SDP funding key can pay the
fee. Before the stake step, the UI must:
- Read the **BlendZk key's** spendable notes (for the note to lock) and the **SDP funding key's** balance
  (for the fee) — e.g. `/wallet/<blendzk_key>/balance` and `/wallet/<sdp_funding_key>/balance` → `notes`.
- If either is short, show a **Fund first** state per key ("Fund your BlendZk key" / "Fund your SDP
  funding key"), with the faucet action and the key/address to fund. Block the declaration until both are
  satisfied.

### 2.3 How much — the minimum stake
- Surface the **minimum stake** requirement, if any, and the note value that will be locked.
- Known today (0.2.x): SDP `MinStake.threshold = 1` lepta (`ledger/src/config.rs`; `declare.rs`), i.e.
  effectively **any non-zero note qualifies**. **Confirm for 0.3** before asserting a floor in the UI —
  if there is still no meaningful minimum, say so plainly rather than inventing a number.

### 2.4 Note selection — auto vs. pick
- **Default: auto-select** a suitable spendable note (smallest note that meets the minimum, to avoid
  over-locking), and show the operator exactly which note + its value will be locked.
- **Advanced: let the operator pick** a specific note (some may want to lock a particular denomination).
- Never lock the note that is already bonded by an existing declaration; never silently lock the largest
  note by default.

### 2.5 "Locked, not spent" — the core comprehension point
The operator must leave this step understanding: **this value is bonded, not paid.** It is not a fee and
not gone — it is returned when they withdraw. State the amount, that it's locked for the life of the
declaration, and how to get it back (Withdraw → clears after ~2 epochs → note spendable again).

### 2.6 The (i) explainer content
> **A stake, not a fee.** To declare as a Blend provider you lock one of your funded notes as a stake.
> This is not spent — it is bonded on-chain to prove you have skin in the game (it stops one machine from
> declaring endlessly for free). You get it back when you stop being a provider: withdraw the declaration
> and the note becomes spendable again after a couple of epochs. The funds come from your node's Blend
> funding key, which you top up from the faucet.

### 2.7 States the check must handle
| State | Trigger | UI |
|---|---|---|
| **Unfunded** | SDP key has no spendable note ≥ min | block; "Fund your Blend key first" + faucet/fund action + the address |
| **Ready** | ≥1 spendable note ≥ min | show the note (id elided + value) that will be locked; "This stays locked until you withdraw" |
| **Choosing** (advanced) | operator opens note picker | list spendable notes with values; exclude already-locked |
| **Locking…** | after submit | "Bonding your stake…" (part of the declaration submission) |
| **Locked** | declaration active | show the bonded note + value on the Core status, with a Withdraw path that returns it |

### 2.8 The confirm gate (extends Req 1.6)
Fold the stake into the same pre-submit confirm, so the operator acknowledges both the public address and
the locked funds in one place:
> ☐ I understand this address is published on-chain and my node must stay reachable, **and that <amount>
> will be locked as my stake until I withdraw.**

### 2.9 Acceptance criteria
- Declaration is not submittable unless **both** keys are funded: the BlendZk key has a lockable note ≥ the minimum, and the SDP funding key can pay the fee.
- The operator sees the exact note + value that will be locked before submitting.
- Copy makes "locked, not spent" unambiguous, and the withdrawal path (how to get it back) is visible.
- No minimum is invented: the UI states the real threshold (confirmed for 0.3) or that there is none.

### 2.10 Open questions
- 0.3 minimum stake — still `1` lepta / any non-zero, or a real floor now? (confirm in source before UI.)
- Does the module auto-select the note today, or must the UI pass `locked_note_id` explicitly (raw RPC
  requires it)? Define who owns note-selection: backend helper vs. UI.
- Is there a wait between funding the SDP key and the note being spendable/lockable (a note-maturity or
  block-inclusion delay) that the "Fund first" state must account for?

---

## Requirement 3 — Show the node identity being declared (`provider_id` + `zk_id`) before submit

The operator doesn't type these, but they must **see and recognise which node/identity they are
declaring** before they lock a stake and publish on-chain — especially because `provider_id` is also
their **referral identity**. Declaring the wrong node (multi-node hosts, a restored keystore, a fresh key)
is a silent, expensive mistake.

### 3.1 What these are
Both are derived from the node's keystore and bundled into the declaration:
- **`provider_id`** — the node's **Blend signing key**. This is the `NodeId`, and in the referral program
  it **is the referral identity** that accrues points. Declaring Blend Core establishes the very identity
  the referral rewards attach to.
- **`zk_id`** — the node's **BlendZk key**, used for the actual Blend mixing / ZK proofs. Distinct from
  `provider_id`; different key, different job.

### 3.2 Why show them pre-submit
- **Right-node confirmation.** On a host that has run more than one node, or after a keystore restore, it
  is easy to declare with the wrong identity. Showing `provider_id` lets the operator confirm "yes, this
  is the node I mean."
- **The referral tie-in.** Because `provider_id` = the referral identity, this is the moment to connect
  the two journeys: the identity you declare here is the one that earns referral points. If the operator
  has (or will) enrol in the referral program, they should see it's the same key.
- **Backup stakes.** These keys live in the node keystore. Lose them and you lose the identity **and**
  access to the locked stake. Reinforce key backup here (or link to it).

### 3.3 What the UI shows
- **`provider_id`** — labelled "Your node identity" (and, when referral is in scope, "= your referral
  identity"): middle-elided with a copy button + full value on demand (the shared HashRow pattern).
- **`zk_id`** — labelled "Blend key": elided + copy, secondary emphasis.
- A one-line plain statement: "You are declaring node `12D3…abcd`." so the identity is unmissable.

### 3.4 The (i) explainer content
> **Two keys, one node.** Your node identity (`provider_id`) is how the network — and the referral
> program — knows *you*; it's the key that earns. Your Blend key (`zk_id`) does the actual private mixing
> work. Both come from your node's keystore and are published in the declaration. If you run more than one
> node, make sure this is the one you mean. Back up your keystore: lose these keys and you lose this
> identity and the stake locked under it.

### 3.5 States
| State | Trigger | UI |
|---|---|---|
| **Identity ready** | keystore present, keys resolvable | show `provider_id` + `zk_id`; "Declaring node 12D3…" |
| **No identity** | node not initialised / no keystore | block; "This node has no identity yet — finish node setup first." |
| **Referral-linked** (if applicable) | referral enrolment uses this `provider_id` | badge: "This is also your referral identity." |

### 3.6 Confirm gate (extends Req 1.6 / 2.8)
The single pre-submit confirm now covers address + stake + **identity**:
> ☐ I'm declaring node `12D3…abcd`, I understand its address is published on-chain and must stay
> reachable, and that `<amount>` will be locked as its stake until I withdraw.

### 3.7 Acceptance criteria
- Before submit, the operator sees the exact `provider_id` (labelled as their node/referral identity) and
  `zk_id` that the declaration will carry.
- On a host with no node identity, declaration is blocked with a clear next step.
- The referral tie-in is made explicit when the referral program is in scope (same key, one identity).
- Key-backup is surfaced or linked at this step.

### 3.8 Open questions
- Does the RPC expose `provider_id` + `zk_id` **before** a declaration exists (config/keystore-derived)?
  The backend has a config-derived path (`{ok, key, blendPort, publicIp, locator}`) — confirm `key` =
  `provider_id` and whether `zk_id` is exposed the same way, or is only visible once declared.
- How tightly do we couple the referral tie-in here vs. keeping Blend Core and referral as separate
  journeys? (Show the badge only when the operator is/along the referral flow, to avoid confusing pure
  node operators who don't care about referrals.)

---

## Requirement 4 — _(to add)_
