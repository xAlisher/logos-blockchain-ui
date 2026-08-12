# Retro log — logos-blockchain-ui (community fork + official-app Blend)

## Week of 2026-08-10 — Blend status feature (fork 0.2.6 + official PR #57)

### Wins
- [project] **Rotation-proof Blend detection.** "Blend unknown" on a healthy Online edge node was a
  detection bug: the `blend::service` lifecycle line is written once at the Online transition and the node
  rotates its log hourly, so reading only the newest file lost it. Fixed by driving state off the live node
  mode (`/cryptarchia/info`) + `/blend/info` and scanning the newest ~6 log files. Extracted →
  `blend-status-detection` (basecamp-skills).
- [project] **`NodeError`, not `Error`.** repc flattens all `.rep` enum values into one scope; `BlendStatus::Error`
  collided with `BlockchainStatus::Error`. Naming it `NodeError` fixed the build. Same fix applied to both the
  fork (`logos_node_1click`) and the official (`blockchain_ui`) modules.
- [process] **Peer-swap resumes with no resync — proven, not assumed.** Swapping a node's `initial_peers` and
  restarting resumes from the saved chain height (khidr came back at 14759, not genesis), vs a DB wipe which
  forces a full resync. Verified empirically before recommending, which is why we could confidently tell the
  operator NOT to wipe.
- [process] **STUN probe isolated network-vs-peer.** A STUN request to a public server (udp/3478) that got a
  reply proved khidr's UDP egress worked — decisively ruling out "the wifi blocks UDP" that QUIC-timeout logs
  had suggested. A cheap decisive probe beats inference.
- [process] **Accurate upstream reports.** The seed-outage issue (#3293) was confirmed by the team within the
  hour ("failed deployment to the bootstrap nodes"); the no-self-recover bug (#3294) and the fork's
  stuck-bootstrap UX (#36) were filed with evidence + repro. Docs PR #438 extended with the participation-check.

### Fails
- [process] **Asserted "0.2.2 core is ahead of the testnet" before checking the diff.** When khidr couldn't
  sync on 0.2.2, I concluded the testnet was still 0.2.1 and 0.2.2 was incompatible. Wrong action: stated it as
  the diagnosis and recommended a downgrade. Root cause: reasoned from "wild(0.2.1) works, khidr(0.2.2) doesn't"
  without running `gh api …/compare/0.2.1...0.2.2` — which showed 0.2.2 was a 3-commit wallet-only patch, wire-
  identical. Version was never it.
- [process] **Then blamed khidr's travel network.** After the version theory fell, I leaned on "khidr's wifi
  blocks peer UDP." Wrong action: nearly closed the investigation there. Root cause: inferred a UDP block from
  QUIC handshake timeouts without a real egress probe — the STUN test (later) showed UDP egress was fine. The
  actual cause was a shared bootstrap-seed outage (a healthy node was failing the *same* seeds). Lesson →
  `logos-node-zero-peers-seed-outage`: when N independent machines fail identically, suspect the shared
  dependency, not each environment.
- [project] **Swapped in ad-hoc "live peers" that were stale.** As a workaround I pointed khidr at peers wild
  happened to be connected to; they timed out for khidr and sent me chasing a phantom local-network issue.
  Root cause: assumed "peers a healthy node holds" = "reachable bootstrap peers for a fresh node" — they can be
  at-capacity/rotating. Reverting to the canonical documented seeds (once the outage cleared) connected khidr
  instantly (0 → 43 peers). Use the documented seeds for bootstrap, not discovered peers.

- [process] **Defaulted to a UI-side HTTP call for data the core module owns — twice.** For the official-app
  Blend port I had the UI backend `curl http://127.0.0.1:8080/blend/info` + `/cryptarchia/info`, even though the
  app's own `getCryptarchiaInfo()` already goes through the module client (`invokeRemoteMethod`). Maintainer
  (Khushboo) reviewed PR#57: *"the way to obtain the blend info shouldn't be via http local calls and should come
  from the module"* → opened blockchain-module#64 (v0.3). So #57 won't merge as-is. Root cause: reached for the
  quick local-HTTP path that ships fine on our fork, without asking "does this data belong in the core module?" —
  which upstream always answers yes. Same wall as the earlier `getClient("delivery_module")` episode. Lesson →
  `core-owned-data-from-module-not-ui-http` + a trigger, so next time we decide "core first?" before building/PRing.

### Skills extracted
- `blend-status-detection` (basecamp-skills, integration/pattern)
- `logos-node-zero-peers-seed-outage` (basecamp-skills, ops/heuristic)
- `core-owned-data-from-module-not-ui-http` (basecamp-skills, integration/heuristic) — wired into `_triggers.md`

### Shipped
- Fork `logos_node_1click` **v0.2.6** — released (linux+darwin signed, catalog + modules.alisher.xyz card).
- Official `blockchain_ui` — Blend-under-Consensus, **upstream PR #57**, render-verified on a live node.

## Week of 2026-08-12 — dashboard UX pass (v0.2.7 → v0.2.10)

### Wins
- [project] **LogosDialog actions belong in `rightActions`, not inline in contentItem.** The node-settings
  modal's Reset/Regenerate buttons were placed inside `contentItem` and the dialog set
  `closePolicy: … | Popup.CloseOnPressOutside`. Result: a press on a content button registered as "outside"
  and dismissed the modal instead of clicking — while the **Close** button worked *because* it was already in
  `rightActions` (the footer action bar the error-recovery modal uses). Moving the actions to `rightActions` +
  dropping `CloseOnPressOutside` + deferring the chained-modal open with `Qt.callLater` fixed it. Extracted →
  `logos-dialog-content-via-contentitem` (added the actions section).
- [project] **Chain-recovery replay window is invisible to the chain API — surface it from the node log.**
  After an unclean restart the node replays every stored block from LIB (genesis during ProlongedBootstrap)
  to the tip — ~18k blocks / ~2 min on khidr — during which `/cryptarchia/info` is down but `/network/info`
  is up, so the dashboard showed "peer id and nothing after." Fixed with `getRecoveryStatus()` scanning the
  node log (`chain::service: found N stored blocks to replay` → `… Chain recovery finished`) + a probe timer
  that runs while status is **Starting** (the replay finishes before the confirm-probe flips it to Running).
  Same log-tail technique as `blend-status-detection`. Extracted → `logos-node-chain-recovery-status`.
- [project] **Immutable identity fields should be sticky.** The peer id was blanked to "" on any failed
  `getPeerId()` and only fetched once (on config-change). Made it sticky (keep last on failure) + poll-until-
  obtained. Peer id is deterministic per config → never clear it on a transient API miss.
- [project] **Reserve fixed width for an animated ellipsis.** A centered title ("Starting…", "Recovering
  chain…", "Bootstrapping…") jitters left-right when the dot count animates. Fix: render the base label +
  a fixed-width dots block (all three dots always occupy width; only opacity animates in sequence).
- [process] **GUI-only fixes gated on a khidr install + human verify before release.** Settings buttons,
  recovery status, and the UI polish can't be verified headlessly (Qt render/click). Each went: build → sign →
  `lgpm` install to khidr → operator confirms in the GUI → *then* release. Held every release behind that gate;
  it caught nothing broken but kept an unverified UI change out of the public catalog.

### Fails
- [process] **Background catalog-sign poll gave up before the CI published (0.2.8).** The "wait for CI → sign
  the catalog .lgx → rebuild index" automation used a fixed ~7.5-min poll window; the Release CI took longer,
  so the poll returned "release not found", the download was empty, `sign` failed, and it uploaded/rebuilt on
  nothing → the catalog carried an **unsigned** 0.2.8 (which Basecamp rejects). Root cause: fixed short window
  for a variable-duration CI, with no "did the artifact actually publish?" guard before acting. Fix: generous
  poll window (~18 min) + verify the release exists before download/sign + verify `index.json` carries the
  `signature` at the end. Applied for 0.2.10.
- [process] **`lgpm` needs BOTH `--modules-dir` AND `--ui-plugins-dir` for a ui_qml plugin.** First install
  attempt on khidr failed "User UI plugins directory is not set"; a ui_qml plugin installs into `plugins/`,
  separate from core `modules/`. Also: reinstalling the *same* version can be refused → bump the version for
  each khidr test build (0.2.9 test → 0.2.10 release).

### Skills extracted
- `logos-dialog-content-via-contentitem` (basecamp-skills) — added the "actions go in rightActions" section.
- `logos-node-chain-recovery-status` (basecamp-skills, integration) — surface the replay window from the log.

### Shipped
- `logos_node_1click` **v0.2.7** (settings-modal buttons), **v0.2.8** (chain-recovery status + always-visible
  peer id), **v0.2.10** (title-ellipsis reserved space + Blend-dot alignment) — each linux+darwin signed,
  GitHub release + README + catalog + apps.alisher.xyz card. (Domain moved to apps.alisher.xyz this window.)
