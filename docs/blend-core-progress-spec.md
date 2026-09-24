# Blend Core progress block

Audience/owner: Alisher. Deliverable: a portable UI module for manual testing on wild; no automatic live installation, restart or on-chain mutation during development.

## UI contract

Add an expandable block immediately below the node status/progress block, matching its dark panel, typography, chevron strip and spacing. Collapsed: current status + progress strip. Expanded: concise explanation, evidence/unknowns, one primary next-action CTA and a result/error area. Blocked/degraded states expand initially; user may collapse. Controls are disabled during any pending mutation. Never hide an error in a success state.

Progress stages: Online → Declared → Activated → Connected → Activity → Maintaining. Each stage has independent evidence; Core/connectivity must not imply accepted activity or earnings. Maintaining means recent accepted activity plus current Core connectivity, not a guarantee of future eligibility. Explain snapshot delay and next epoch where known. No reward milestone without actual attributed receipts.

Backend API addition via .rep: getBlendLifecycle() returns QVariantMap with ok, state, title, detail, tone (neutral/success/warning/error), epoch, declarationId, created, active, nonce (string), withdrawAt (-1 if absent), mode, healthyPeers, bindingStatus (missing/confirmed/unknown), action (manage/repair/refresh/none), actionLabel, steps [{label,state: complete/current/pending/error}], evidence (string). repairBlendBinding() returns {ok,error,message}; acknowledgement is not activity success.

Reuse EnableBlendCoreModal for prerequisite funding/stake/address guidance and explicit join/withdraw. New block emits manageRequested(), repairRequested(), refreshRequested(); parent orchestrates asynchronous QtRO calls with logos.watch. Poll with overlap guards and bounded latency. No direct mutation on load.

## State requirements

Unavailable/offline/bootstrap; no declaration; submission pending; activation pending; Core collecting (no accepted activity); missing local SDP binding; confirmed binding awaiting next activity; Core healthy with accepted recent activity; at risk; lapsed; withdrawal requested; withdrawal scheduled; removed; ambiguous identity/API error. Unknown telemetry stays unknown. Log evidence must be current-run bounded; old failures cannot override newer verified repair indefinitely or survive restart as confirmed state.

## Safety and protocol

Match declaration by verified public provider identity, not locator. Exact stored ID must also match provider identity before any mutation; reject mismatch/ambiguity. Duplicate locators are a warning, not ownership or conclusive activity diagnosis. Nonce includes withdrawals; accepted activity requires active > created+2, with no payout claim. First excluded epoch under I=2 is active+3, subject to frozen snapshot lag. Preserve declaration cache through pending withdrawal. HTTP 2xx is not inclusion/unlock; null join ID is not success. Explicit repair binds an existing owned declaration using /sdp/set-declaration-id, never withdraws/redeclares. Reject repair during pending withdrawal or unverifiable ownership. Never expose private key material.

## Verification

### Operator binding setup when telemetry is unknown

The engine exposes a setter but no runtime binding GET. For a verified existing Core declaration with missing/stale activity and unknown binding, offer **Set activity binding** as an explicit idempotent setup action. Do not call the unknown state "missing", do not run it automatically, and keep the same ownership, current-run, pending-withdrawal and busy guards as repair. If a current-run missing-binding diagnostic exists, label the action **Restore activity binding**. Neither acknowledgement replays proofs nor alters frozen membership.

Removal requires successful registry absence after an observed scheduled withdrawal, not epoch arithmetic alone. The Activated stage requires observed Core membership. Peer health counts only the true health flags in the engine's `[node_id, healthy]` tuples.

TDD for state reducer, identity matching, pending withdrawal, null response, stale logs and repair guards. Headless QML: real production component, state matrix, narrow/wide widths, expansion, CTA dispatch, busy controls and screenshot. Build portable LGX; inspect packaged QML/backend and test packaged component. Read-only live observation allowed; no POST to wild in tests. Record honest coverage limits: end-to-end epoch refresh and real installation remain manual acceptance.

## Prior art

Build on fork issues #89–96 (join flow), #82 (node lifecycle strip), #107 (risk visibility). Related #105's auto-redeclare proposal is not adopted: prefer narrow explicit binding repair; no automatic stake-changing watchdog. Source baseline: 8b781c9; node protocol adc72a456 (0.2.4). Investigation: /home/alisher/ecodev/research/2026-09-20-blend-core-lifecycle.md.
