# Dashboard prototype studio — design reference

A runnable, clickable **design spec** for the redesigned Blockchain-node dashboard + Settings.
It drives this fork's **real QML views** (`../src/qml/views`) with **mock state** and a **mock
backend**, so every state and interaction can be explored **without a running node**.

> These are **throwaway design drafts**. The final implementation is written from the designs
> (following the DS + the repo's own QML guidelines), not by integrating this branch.

## Run

```
bash prototype/run.sh
```

Needs **nix** (for the Qt QML runtime) and **git** — no node, no Basecamp. First run clones the
forked Logos DS (`xAlisher/logos-design-system @ feat/dashboard-additions`) into `.ds-cache/`.

## What to click

- **Tabs** (top): Dashboard ⟷ Settings are live; the rest are placeholders.
- **Scenarios** (right panel): jump to a coherent node state —
  *Fresh · Starting · Bootstrapping · Online · Funded–aging · Validating · Error*.
- **▶ Play Start → Online**: the real timed transition (Starting → bootstrapping countdown →
  Online), with the chevron lane, flash-on-update, and the aging pulse.
- **(i) on any tile**: the info modal (what it is / how it's calculated / states / copyable docs link).
- **Copy** icons (Peer ID / LiB / TiP): copy the full value, "Copied" flashes green.
- **Settings**: Node config (Change/Backup/Apply=restart), Bootstrap nodes, Rewards/Mining
  auto-claim, Hardware caps, and the red **Destructive** actions (open warning modals).

## What's real vs mock

- **Real**: all the QML views, layout, components, the info-modal copy (`../src/qml/views/infoContent.js`),
  the chevron lifecycle lane, the Settings structure.
- **Mock**: the node data (driven by the control panel), the backend (an enum stub in `mock/`), and
  every tile the 0.3 node API doesn't expose yet — those honestly show `—`.

## Design decisions + backend deps (read alongside)
- Full design spec: `../../ecodev design/node-dashboard/HANDOFF.md` (screenshots + per-tile spec).
- Backend/UI gaps the "—" tiles need: `backend-issue-drafts.md` (in ecodev design/node-dashboard).
- DS changes used: forked DS branch above (brighter primary, compact + danger buttons, smaller tabs)
  — feeds ecosystem #86.

## Files
- `proto-studio.qml` — the studio (mock state + control panel; imports the real views).
- `mock/Logos/BlockchainBackend/` — enum stand-in for the C++ backend (status enum only).
- `run.sh` — nix launcher (fetches the forked DS, sets the QML import path).
