# Wallet rescan — rebuild node state from the chain

**When:** the Leader Rewards panel shows the red banner — two or more claims **verified absent
on chain**. That is the stale-wallet-state signature: the node's local wallet database has
drifted from chain truth (it may offer already-spent vouchers, or miss settlements), and only a
rebuild clears it. Proven on a live node 2026-08-24: balance reconstructed **to the exact digit**,
claims settle and register again immediately after ([full investigation][inv]).

**What is preserved:** your keys (`user_config.yaml`, `keystore.yaml`) and your entire balance —
both live on the chain and in your config, not in the database being rebuilt. **What is rebuilt:**
the node's local chain + wallet database (`db/`), by resyncing from the network (~30–60 min for
the current testnet).

## Procedure

1. **Quit Basecamp** normally (clean shutdown closes the database safely).
2. **Set the database aside** (keep it — don't delete; fish/bash alike):

   ```
   cd ~/.local/share/Logos/LogosBasecamp/module_data/blockchain_module/*/
   mv db db.stale-backup
   ```

3. **Relaunch Basecamp** and start the node. It re-syncs the chain from the network
   (Bootstrapping → Online → Following) and rebuilds wallet + voucher state from chain truth.
4. **Check:** balance matches what you had; the Rewards feed backfills — claims previously stuck
   "Confirming" flip to **Paid** if they landed. The banner clears once no verified-absent
   claims remain.

If anything looks wrong afterwards, restore by quitting Basecamp and moving `db.stale-backup`
back to `db`. Questions → the node-runners Discord thread.

[inv]: https://github.com/logos-blockchain/logos-blockchain/pull/3393#issuecomment-5409450704
