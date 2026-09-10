# Logos DS — additions / changes we need (node-dashboard redesign)

Running list of Design-System changes surfaced by the Blockchain-node dashboard work.
Feeds **ecosystem #86** (DS promotion list); component *gaps* live in
[missing-components.md](missing-components.md), this file tracks *changes to existing tokens/components*.
Values verified against DS master (`Logos/Theme`, `Logos/Controls`).

| # | Change | Current | Proposed | Why |
|---|--------|---------|----------|-----|
| 1 | **Smaller button variant** | `LogosButton` floors at `implicitHeight ≥ 44`, `implicitWidth ≥ 100`; padding `large` (16) L/R, `medium` (8) T/B; no size/compact prop (only the *icon* has `size`) | add a `compact` size (~32–36 h, ~8/6 padding, lower min-width) | dense toolbars/headers (our node header pair) need a smaller control than the 44px touch-target default |
| 2 | **Brighter primary orange** | `primary = orange300 #ED7B58` (muted terracotta), `primaryHover = orange500 #F55702`, `primaryPressed = orange800 #8F3C03` | `primary → orange500 #F55702` (the brighter one, i.e. today's hover), `primaryHover → orange700 #BF5104` (a bit darker), `pressed` stays `orange800` | the default CTA reads muted; promoting the vivid orange to default makes primary actions pop, with hover darkening instead of brightening |
| 3 | **Smaller tab font** | `LogosTabButton` uses `typography.primaryText = 14`, `weightMedium` | tab label → `secondaryText = 12` (or a dedicated `tabText` token) | tabs sit as chrome, not body; 14px reads heavy across a full tab bar |

## Notes
- #2 and #3 are **theme-token / component-default** changes (touch every module) — raise on #86 as a system decision, not a per-module override. Until then we can preview them by overriding locally in the fork's DS pin.
- #1 is a **new variant** (additive, non-breaking).
- Related open gaps (in missing-components.md): `LogosCopyButton`, `LogosStatCard`, `LogosKeyValue`, `mono` type token, info tooltip, status pill, toast/error banner.

_Last updated: 2026-09-10._
