# Controlled Blend recovery — implementation and acceptance contract

User request: automate controlled withdrawal and fresh declaration, with progress on the existing Blend Core card. This is a UI/backend feature, not a consensus-rule change or permission to execute test transactions on the live node.

## Authorization and ownership

- Recovery starts only after an explicit operator confirmation covering one withdrawal and one fresh declaration, normal network fees, and a temporary activity/membership gap.
- Page load, Refresh, status polling, an at-risk warning, or loss of binding must never implicitly authorize paid actions.
- Resolve the configured public provider and verify it against the running API identity and the owned canonical declaration. Reuse the existing collateral note, locator and identity; do not generate keys or select a stranger's declaration by shared IP.
- Persist versioned, scoped intent and write-ahead mutation status atomically. No secrets or proof/token contents belong in the journal or QML.

## Progress milestones

1. Preflight: node Online, owned stale declaration, usable funding configuration, no conflicting operation, writable journal.
2. Withdrawal: persist the attempted operation before POST; acknowledgement is not inclusion.
3. Removal: observe the on-chain withdrawal schedule and later actual registry absence at/after its effective epoch. Neither time alone nor an API failure proves removal. Use a finality barrier before re-declaring.
4. Fresh declaration: submit once with the same collateral/locator, then wait for on-chain acceptance. The declaration ID may repeat; require a newer creation epoch to distinguish re-entry from the old record.
5. Binding: explicitly set the accepted owned declaration in SDP; acknowledgement is not accepted activity.
6. Activation and renewals: wait for actual runtime Core and successive accepted activity epochs beyond initial `created+2` grace. Show observed renewal progress; do not describe nonce increments or Core alone as completion, and never promise permanent membership or rewards.

### Important engine behavior

`services/sdp/src/lib.rs:637–642` in the pinned official0.2.4 source clears `declaration_id` after withdrawal submission. Therefore do **not** require another old-declaration activity proof while waiting for removal, and do not silently repair the old binding during that wait. Resumed activity is checked after the fresh declaration has been accepted and bound.

## Failure behavior

- Ambiguous timeout/5xx/crash-after-dispatch: retain pending state and reconcile; never automatically replay a potentially delivered paid mutation.
- Definitive preflight failures: show the specific blocker. Read-only polling may continue. Explicit resume must revalidate prerequisites.
- Ownership change, corrupt journal, persistence failure and invalid/malformed telemetry fail closed.
- Pause stops future automation, not an on-chain withdrawal already submitted. It remains available when chain telemetry fails but the backend is reachable.
- A confirmed durable Pause enables Stop. Native Stop and its force-stop fallback require paused recovery and no in-flight recovery/read/mutation. Starting the same node again preserves Pause; only explicit Resume re-arms recovery. Reset, key/config changes and manual Blend actions remain locked while paused.
- Progress remains visible across card navigation and disconnection; a transport failure cannot silently release mutation locks.
- Block conflicting manual Blend actions and live-node restart/reset/key regeneration while recovery remains active. An operator can explicitly start the same stopped node without changing its configuration or public identity. Closing the application interrupts execution; persisted intent resumes only when the same configured node is available again.

## Verification and delivery gates

- Deterministic production state-machine tests, including the intended red case before implementation.
- Real packaged native backend with synthetic responses, isolated HOME/XDG and mandatory inherited network denial. Test exact POST counts and bodies; getter-only paths must send no paid request.
- QML interactions and narrow/wide rendering against real components, explicit confirmation, pause/resume, stale callbacks and active-flow guards.
- Portable LGX audit for all QML bytes, backend exports and matching QtRO replica methods/properties.
- No live withdrawal, redeclaration, reset, restart or key changes during tests. Live multi-epoch acceptance remains a separate gate; synthetic fixture success is not that evidence.

Build version: `0.2.33-blend.4` (Pause enables Stop correction). The prior `.3` verification is recorded in [verification report](blend-core-recovery-verification.md); it is not proof of this revision. Loading a new native backend requires a controlled application reload. Do not interrupt a running recovery to apply the update without operator approval.
