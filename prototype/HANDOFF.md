# Blockchain-node dashboard + Settings — design handoff

**For:** Khushboo (implementation) · **From:** Alisher (design)
**Nature:** design reference. The QML on the fork is a **throwaway draft** — re-implement from these
designs following the DS + the repo's QML guidelines. Don't integrate the draft branch.

---

## 1. Explore it (runnable spec)

The best spec here is the **runnable studio** — the interactions are dynamic (transitions, the aging
pulse, flash-on-update, copy feedback, modals) and don't read from static mocks.

```
git clone -b feat/dashboard-redesign https://github.com/xAlisher/logos-blockchain-ui
bash logos-blockchain-ui/prototype/run.sh      # needs nix + git; no node
```

Tabs: **Dashboard ⟷ Settings** live. Right panel: scenario presets + **▶ Play Start → Online**.
Full instructions: `prototype/README.md`.

Static frames: `screenshots/example-*.png` — starting, bootstrapping, online, funded-aging,
validating, merged-hero, full-dashboard, settings, stub-animation.gif.

---

## 1b. Onboarding flow

Launch from the right panel: **FLOWS → ▶ Start onboarding** (or `bash prototype/run.sh --onboarding`).

- **First screen is one click.** Two routes, no wizard chrome: **Quick start** (default testnet config,
  straight to the node) and **Advanced setup**. Options route on click (no radios).
- **Steps live only under Advanced:** Setup (generate, or point at an existing config + keystore) ·
  Network & peers · Back up keys · Fund. Steps are **user actions only** — start / sync / aging are
  node-driven and belong on the dashboard lifecycle lane, not clicked through in a wizard.
- **Key-backup is a banner, not a gate.** Quick start lands on the dashboard with a thin red
  "Back up your keys" banner → **Settings › Back up your keys › Download keystore.yaml**. It clears
  once keys are backed up, and never shows if they were backed up during Advanced setup.
- Source: `prototype/OnboardingProto.qml`. Upstream API mapping (what the module/CLI already supports
  vs what the UI must add — keystore backup and `participate` are UI-absent today):
  `prototype/onboarding-map.md`.

---

## 2. Dashboard layout

- **Node hero (full width):** status value as the headline (no "Status" label), uptime/countdown in
  the upper-right corner, and the **lifecycle lane** across the bottom of the same card.
- **Metric grid (responsive, min ~210px, wraps):** Stake · Earned · Blend · Epoch · Proposed in
  current epoch · Peers · Peer ID · Mining · CPU · RAM · Slot · Height · LiB · TiP.
- **Footer:** `core • UI • testnet` version (copyable) + a gray **Legal disclaimer** link (opens an
  inner-scroll modal).
- Flat surfaces (no state tint on the hero); the **colored value** carries state. Green is reserved
  for the **live** thing (see the lane), not decoration.

### Per-tile spec
The authoritative per-tile content (**what it is / how it's calculated / states / docs link**) is the
info-modal source: **`src/qml/views/infoContent.js`** (15 tiles, sourced from docs + cryptarchia code).
Every tile has an **(i)** that opens that content (white on hover).

See the gaps in §7 (detailed issue drafts are tracked internally, being filed as issues).

Wiring honesty (matches the current 0.3 API):
- **Real today:** Status, Peer ID, Slot, Height, LiB, TiP.
- **Shows `—` until wired:** Blend, Epoch, Stake, Earned, Proposed, Peers, Mining, CPU, RAM — see the
  backend gaps in **the summary below** (detailed drafts tracked internally).

---

## 3. Lifecycle lane (the chevron pipeline)

Stages: **Started · Online · Funded · Aged · Proposing · Earning**. One accent at a time.

- **Done** stage = gray chevron + a **green check**.
- **Live** stage (the one being worked) = the single **accented** chevron. Green when settled; **yellow
  + an animated fill pulse** while transitioning.
- **Future** = darkest chevrons.
- Chevrons interlock (tip ~2px from the next notch), rounded corners, inset from the card edges.

Monotonic: a confirmed later stage implies the earlier ones. Transition labels change on the live
stage: **Starting** (Started unchecked, live), **Bootstrapping** → Online reads **"Syncing…"**,
**Funded→Aged** → Aged reads **"Aging"**. Only Started/Online are detectable today; the rest light up
as their backend signals land ("aged" is the real Cryptarchia term — a note leads ~2 epochs after it
exists; queryable via `get_leader_aged_notes`, not wired yet).

---

## 4. Interactions

- **(i) modals** — per-tile; four sections + copyable docs link (click the link → copies, "Copied").
- **Copy** — Peer ID / LiB / TiP third line is a copy button that copies the **full** value (not the
  shortened display) and flashes green **"Copied"** to its right.
- **Flash-on-update** — live numeric values (Slot/Height/Proposed/CPU/RAM/…) flash green on change.
- **Transitions** — Start → Starting → bootstrapping countdown → Online; mining climbs to 100% then
  stops (wallet Funded); aging counts epochs down then flips to Proposing.
- **Mining ("Fund")** — top-level header button during testnet (only way to fund a testnet node);
  opens a target-balance modal. Per David: PoW is a **permissionless on-ramp to PoS**, bootstrapping
  only — long-term it moves into the Wallet tab with that disclaimer. Auto-claim lives in Settings.

---

## 5. Settings

Sections: **Node** (Node/Dev/Keys config → Change · Backup · Apply=restart; Backup writes
`<file>_backup_<date>.zip` beside the file) · **Bootstrap nodes** (multiline IP:port · Apply) ·
**Rewards** (auto-claim, on) · **Mining** (auto-claim, on) · **Hardware** (CPU/RAM/Disk caps, toggle
off; CPU/RAM cap hit → node stops, disk cap hit → prune logs) · **Destructive** (red buttons + warning
modals: Reset chain state, Regenerate keys).

Proposed tab grouping (David/Alisher): **Dashboard · Blocks · Rewards · Explorer · Wallet · Settings**
— Wallet groups Accounts · Transfer · Channel Deposit (pages TBD).

Suggested additions not yet drawn: confirmation on Apply(restart), Blend participation toggle, Mining
target field, Start-node-on-launch, Logs (view + level), Advanced (ports/external addr).

---

## 6. Design-system changes used

Forked DS branch: **`xAlisher/logos-design-system @ feat/dashboard-additions`** (feeds ecosystem #86):
- Primary orange brightened (default CTA now reads as a CTA); LogosButton **Danger** variant +
  **compact** size; LogosTabButton smaller default font.
Rationale + values: **`ds-additions.md`**. Component gaps still open: `missing-components.md`.

---

## 7. File map (fork `feat/dashboard-redesign`)

- `src/qml/views/NodeDashboardView.qml` — the dashboard (hero, lane, tiles, footer, Block/Info/CopyGlyph/Lifecycle).
- `src/qml/views/infoContent.js` — per-tile (i) content.
- `src/qml/views/InfoModal.qml` · `EmpoweringModal.qml` (Fund) · `LegalDisclaimerModal.qml`.
- `src/qml/views/SettingsView.qml` — Settings.
- `src/qml/BlockchainView.qml` — header (logo, title, Fund, Start/Stop) + tab bar + Settings section.
- `prototype/` — the runnable studio.
