# Design-system gaps the node dashboard needs

> **Correction (2026-09-10, verified against DS master `4632460`):** two items below are **already in
> the current DS**, they were just missing from the older/pinned DS I first checked: **`LogosCopyButton`
> exists**, and **`LogosButton` ships a `Variant.Primary` accent** (orange `Theme.palette.primary`) — so
> the "CTA button" gap (#2) is resolved on master. The real gap is that the 0.3 UI **pins a stale DS**
> (`73e482b`) that lacks these — bumping the DS pin is the fix. `LogosDotMatrix` also landed on master.


_Found by building the dashboard (`NodeDashboardPage.qml`) **entirely from the DS** and logging every
point where the DS had no component and I had to hand-roll one. Feeds **#86** (build core DS components
in QML). "Have" = confirmed in `logos-design-system/src/qml/Logos/Controls`; "Missing" = I had to inline
a stand-in (tagged `// MISSING-DS` in the page)._

## Missing components (in priority order for the dashboard)

1. **LogosCopyButton** — copy-to-clipboard affordance for a value. Every hash / Peer ID / address /
   amount row needs it; `blockchain-ui`'s `HashRow` already depends on a fork-local one. **Not in DS.**
2. **CTA / primary accent button** — the DS *has* the color (`Theme.palette.accentOrange`,
   `accentBurntOrange`) but `LogosButton` exposes **no accent/primary variant**, so every button renders
   gray — the "no visible call-to-action" gap flagged on the 09-08 call. Need `LogosButton { variant:
   "primary" }` (or a `LogosCtaButton`). Used here for **Claim now** / **Start node**.
3. **LogosStatCard** — a labelled big-value metric tile (Khushboo's `StatTile`: value → divider →
   label → optional info). Currently composed ad-hoc from `LogosFrame`; should be one DS component so
   Peers / Connections / Blend and every other module's stats render identically.
4. **LogosKeyValue** — a labelled field row: label + elided-middle value + copy (Khushboo's `HashRow`).
   Recurring across Peer ID, Tip/LIB, addresses. Belongs in the DS, not per-module.
5. **`mono` typography token** — `Theme.typography` has **no monospace family**. Hashes, Peer IDs,
   addresses and aligned amounts need one (`Theme.typography.mono`). I fell back to a literal
   `"monospace"` family — should be a token.
6. **InfoButton / info tooltip** — a small "i" that reveals an explanation (used by `StatTile`; needed
   for "what is a voucher", "why ~3h to validate", fee breakdown). **Not in DS.**
7. **Status pill (semantic state)** — `LogosBadge` exists, but a state-colored status pill with a dot
   (green online / orange bootstrapping / red error / yellow starting) would standardize node + health
   status across modules. Could be a `LogosBadge { state: … }` variant.
8. **Toast + error-state banner** — the 09-08 "error / toast states" gap. Needed for the crash →
   **Reset chain state** recovery surface (module `purge_state`, PR#74 → ui#63). **Not designed in DS.**

## Tooling finding (worth an upstream note)
- **`LogosFrame` does not composite under the offscreen software renderer** — it blanks the whole
  scene under `QT_QPA_PLATFORM=offscreen` on all backends (software / vulkan / opengl). `LogosTabBar`,
  `LogosText`, `LogosButton`, `LogosBadge` render fine. This blocks **headless screenshot / visual-
  regression testing** of any DS surface built on `LogosFrame` (likely a shadow/`layer`/effect). The
  storybook draft therefore uses a plain `Rectangle` stand-in (`// Card`) for `LogosFrame`; the real
  integration keeps `LogosFrame`/`StatTile`.

## Already in the DS (used directly, no gap)
`LogosTabBar` / `LogosTabButton` (tabs), `LogosText`, `LogosButton`, `LogosBadge`, `LogosFrame`
(surface), `LogosIcon` / `LogosIconButton`, `LogosProgressBar`, `LogosScrollView`, `LogosTable`,
`LogosToolTip`, `LogosSpinner` — plus the full token set (`Theme.palette.*`, `Theme.spacing.*`,
`Theme.typography.*`), which is rich and sufficient for color/spacing/type.
