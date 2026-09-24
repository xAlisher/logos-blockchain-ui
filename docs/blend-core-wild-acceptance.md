# Blend Core progress — wild acceptance

Epic: https://github.com/xAlisher/logos-blockchain-ui/issues/108

## Scope

This is the `logos_node_1click` **UI plugin** preview, not a replacement blockchain engine. Keep wild's current core module, keys, config and database. Do not use module-manager Reinstall to fetch a different dependency or erase state. The automated tests use isolated synthetic fixtures; they do not repair wild or establish epoch-to-epoch operation.

## Before installation

1. Record the current UI version and preserve its installed plugin directory as a rollback copy.
2. Choose a deliberate restart window. Closing the Basecamp window alone can leave module/UI hosts alive; fully quit the target instance and verify its processes have stopped before replacing its plugin.
3. Install the verified preview UI artifact into the correct Basecamp instance, preserving the engine and its persistence. Do not touch any other instance or kill unrelated hosts.
4. Restart the same Basecamp instance. Verify the footer reports `0.2.33-blend.1` and both progress blocks render.

No installer is run as part of development. Installation procedure and final artifact/hash are recorded in the build acceptance report once available.

## On opening the node page

- The new Blend Core block is directly below node progress.
- It observes the existing declaration; it must not submit Join or Withdraw on load.
- Expand/collapse shows or hides explanation, evidence and next-action CTA under the strip.
- Blocked/degraded states initially expand. Unknown data is not presented as healthy/earning.
- Current Core mode, healthy connections and accepted activity remain distinct.

## Existing declaration with missing activity binding

- Confirm the displayed identity/declaration belongs to wild.
- If the service's current-run diagnostics establish missing binding, the block offers the narrow explicit repair.
- Click once. Controls disable while pending; errors remain visible. Acknowledgement says binding accepted, **not activity accepted**.
- Refresh/reopen: the report remains evidence-based and does not re-declare or withdraw.
- A missing binding observed in an old run must not masquerade as a current verified failure. If it cannot be established, show unknown and explain the evidence gap.
- With missing/stale Core activity and unknown binding, **Set activity binding** is an explicit idempotent setup option, not a missing-binding diagnosis. Current-run missing-binding evidence instead uses **Restore activity binding**. Both reuse the verified owned declaration and refuse a pending withdrawal.

## Prove ongoing operation (manual, crosses epochs)

1. Leave the node online through the next transition/overlap.
2. Confirm a fresh activity operation is included: `active` changes from its creation baseline; correlate epoch/transaction logs. A nonce increase caused by withdrawal is not activity.
3. Check actual runtime Core membership separately; a corrected live record cannot rewrite an already frozen membership snapshot.
4. If Core lapses, the UI explains the gap and offers management—not automatic withdrawal. Review remaining proof window and confirmed registration before choosing withdrawal/redeclare.
5. After a controlled restart, confirm the UI reconciles the existing declaration and a subsequent activity update actually lands.
6. Rewards are separately attributed wallet receipts; neither a Core badge nor binding acknowledgement proves payout.

## Explicit exit/rejoin path

- Withdraw requires an operator click and clear delayed-unlock explanation.
- Request → canonical scheduling → effective removal are separate states.
- Do not offer duplicate withdrawal or fresh Join while the previous declaration remains.
- After confirmed removal, review spendable stake and prerequisites before a fresh Join.

## Rollback

Fully quit the same instance, restore only the previous UI plugin atomically, and relaunch. Preserve all core-module data and identity files. A UI rollback does not undo any operator-authorized on-chain transaction or binding change.
