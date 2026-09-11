# Node Onboarding — upstream map (for the Khushboo prototype)

_Research pass 2026-09-11 against current `logos-blockchain/*` master. Shallow clones under `/extra/tmp/{ui,module,node,lez}-onboard/`. Every claim carries a `repo:path:line` pointer — verify before asserting downstream._

## Verdict

A node first-run flow **exists and is built** in the upstream node UI (`logos-blockchain-ui`), but it is a **2-page config-setup flow, not a wizard**: config generation → node start → funding-by-copying-a-key. The deeper "get productive" steps — **keystore/recovery-material management, staking, leader/SDP registration (`participate`)** — exist in the node **CLI and the module API but are NOT wired into the UI**. Testnet staking eligibility is currently **automatic (token aging ~3.5h)**, so there is no registration screen to build against yet.

That gap is the prototype opportunity: the screens worth designing are exactly the ones the API already supports but the UI never surfaces.

## The flow today (built)

- **Router:** `logos-blockchain-ui:src/qml/BlockchainView.qml:360-373` (`_d.currentPage` 0/1), StackLayout `:391-805`. First-run routing `:117-123` (`_applyInitialRoute`: saved config → skip chooser; cites upstream issue #36).
- **Page 0 — config chooser:** `ConfigChoiceView.qml`. Generate (`:56-62`) vs Set-path (`:64-70`).
  - Generate: `GenerateConfigView.qml` — output path, initial peers, net/blend ports, HTTP addr, external address, no-public-IP-check, deployment radio (Default/Custom), state path (`:62-202`).
  - Set-path: `SetConfigPathView.qml` — user-config + deployment-config pickers.
- **Page 1 — operations dashboard:** `BlockchainView.qml:471-804`; node start/stop in `NodeStatusCard` (`:565-602`); "Change config" → back to page 0 (`:601`).
- **State:** `BlockchainBackend.rep:7-16` (`status`, `blendRole`, `userConfig`, `generatedUserConfigPath`, `lastErrorMessage`, `nodeRecovering`). Persisted to **QSettings `("Logos","BlockchainUI")`** keys `userConfigPath`/`deploymentConfigPath` (`BlockchainBackend.cpp:268-320`); honors `LB_CONFIG_PATH`.
- **Doctest of the flow:** `logos-blockchain-ui:doctests/blockchain-ui-app.test.yaml` (~59-184).

## Node lifecycle — authoritative CLI

`logos-blockchain:nodes/node/binary/src/cli/mod.rs:93-114` — `InitConfig` (config + generated keys), `UpdateConfig`/`MigrateConfig`, `GenerateKey`/`AddKey`/`RemoveKey`, **`Participate`** ("generate stakeholder.yaml + provider.yaml"), `GetPeerId`.

- **Keystore** (8 keys, auto-created, invisible in UI): `cli/config/keystore.rs:22-38` — `BlendSigning`, `NetworkSwarm`, `BlendZk`, `LeaderFunding`, `SdpFunding`, `PoWClaim`, `VaucherMaster`, `Stake`. Wiring: `cli/config/init.rs:125-222`.
- **Bootstrap/IBD peers:** `initial_peers` → `cryptarchia_config.network.bootstrap.ibd.peers` (`init.rs:170-180`).
- **Network/genesis:** via **deployment config** (Default vs custom YAML) — `cli/mod.rs:443-451`, radio `GenerateConfigView.qml:157-187`. No named testnet/mainnet dropdown exists.
- **Staking/registration:** `Participate` → `participation_data.yaml` with stakeholder identities + blend provider (`participate.rs:37-110`). On testnet, eligibility is otherwise automatic via aging.

## API surface vs what the UI calls (the gap)

- **Module exposes** (`logos-blockchain-module:src/logos_blockchain_module.h`): `generate_user_config` (`:53`), `update/migrate_user_config` (`:54-66`), **`participate`** (`:67-72`), **`generate_key`/`add_key`/`remove_key`** (`:76-93`), `get_peer_id` (`:96`), `start`/`stop` (`:25-26`), **`does_state_exist`/`purge_state`** (`:36-42`), wallet ops incl. `wallet_fund_tx`, `channel_deposit`, `leader_claim` (`:99-146`).
- **UI backend calls** (`logos-blockchain-ui:src/BlockchainBackend.rep:17-34`): only `generateConfig` from that setup set — **NOT** `participate`, key mgmt, `migrate*`, `does_state_exist`, `purge_state`, `wallet_fund_tx`, `submit_signed_transaction`.

## Designer mapping table — step → screen → state → API → built?

| # | Step | Screen (today / proposed) | State | API / config / CLI | Built? |
|---|------|---------------------------|-------|---------------------|--------|
| 1 | Choose setup path | `ConfigChoiceView.qml` | `selectedOption` | UI routing | **Yes** |
| 2 | Network / deployment | `GenerateConfigView.qml:157-187` | `deploymentMode`, `deploymentConfigPath` | `DeploymentSettings` (`cli/mod.rs:443`) | **Yes** (Default vs YAML; no named-network picker) |
| 3 | Bootstrap / initial peers | `GenerateConfigView.qml:86-102` | `initialPeers[]` | `network.initial_peers` (`init.rs:170`) | **Yes** |
| 4 | Ports / addresses / NAT | `GenerateConfigView.qml:104-149` | ports, addrs, noPublicIpCheck, statePath | `EmbeddedInitArgs` (`cli/mod.rs:158-196`) | **Yes** |
| 5 | Generate config **+ keys** | Generate submit (`BlockchainView.qml:417-463`) | `generatedUserConfigPath` | `generate_user_config` → `InitConfig` | **Partial** (config yes; keys created but **invisible/unmanaged**) |
| 6 | Point at existing config | `SetConfigPathView.qml` | `userConfig` (QSettings) | QSettings `userConfigPath` | **Yes** |
| 7 | Start node & sync | `NodeStatusCard` (`:565-602`) | `status`, cryptarchia poll | `startBlockchain`→`start`→`getCryptarchiaInfo` | **Yes** |
| 8 | View address/peer to fund | `ChainStatsView` + `AccountsView` | `peerId`, accounts | `getPeerId`, `getBalance` | **Yes** |
| 9 | Get funded | *no screen* (external web faucet) | — | faucet; copy key | **No** (out-of-app; `wallet_fund_tx` exists) |
| 10 | Age → eligible | *no screen* (~3.5h wait) | — | automatic | **N/A** |
| 11 | Staking / genesis / SDP register | *no screen* | — | `participate` → `Participate` (`participate.rs:37`) | **No in UI** (module + CLI yes) |
| 12 | Keystore mgmt (add/remove/rotate, backup) | *no screen* | — | `generate_key`/`add_key`/`remove_key` (`.h:76-93`) | **No in UI** (module + CLI yes) |
| 13 | Claim rewards | `LeaderRewardsView` | `claimableVouchersJson` | `claimLeaderRewards`→`leader_claim` | **Yes** |
| 14 | Wipe / re-onboard | *no screen* | — | `does_state_exist`/`purge_state` (`.h:36-42`) | **No in UI** (module yes) |

## Pattern to borrow — LEZ wallet OnboardingView

`logos-execution-zone-wallet-ui:src/qml/views/OnboardingView.qml` — a clean **`StackView`** onboarding (vs the node UI's flat `StackLayout`):
- `initialItem: createWalletPage` (`:36-40`); screens as pushed `Component`s: create / open / recovery-phrase / busy (`:42-82`).
- Create → backend returns **mnemonic** → recovery page shown **once**, gated by `mnemonicAcknowledged()` before dashboard unlocks (`:24-27`).
- Busy = property-driven overlay (`onBusyChanged` push/pop, `busyMessage`).
- **Persistence + onboarded-vs-main decision live in the parent** (`ExecutionZoneWalletView.qml:102`, wiring `:223-277`; QSettings in `LEZWalletBackend.cpp:15,27`).
- Doctest: `logos-execution-zone-wallet-ui:doctests/wallet-ui-onboarding.test.yaml`.

**Takeaway:** the LEZ StackView pattern (one screen per step, reveal-secret-once + acknowledge, busy overlay, parent gates the transition) is the template to restructure the node's flat chooser into a real stepper — and it already models the "save your recovery material" interaction the node's invisible keystore step (#5/#12) needs.

## Prototype candidates (highest design value first)

1. **Recovery-material screen** (#5/#12) — biggest safety gap: `InitConfig` writes 8 keys silently; no "back up your keys" step exists. LEZ mnemonic-once is the pattern.
2. **Staking / participation screen** (#11) — `participate` is module-exposed, UI-absent; a real "register for consensus" screen can be prototyped against it.
3. **In-app funding** (#9) — bring "copy key → request funds" in-app instead of the README web-faucet detour; `wallet_fund_tx` exists.
4. **Fresh-vs-returning + reset** (#14) — `does_state_exist`/`purge_state` give a real first-run signal and a "reset node" action.

## Caveats

- Version skew: node UI `metadata.json` `0.2.1-rc.3`; module `0.0.999` (dev placeholder).
- Testnet **re-genesises every release** → funding/aging reset each release; reflect in any "get productive" progress UI.
- `src/qml/controls/StepperButton.qml` is a numeric spinner, **not** a wizard stepper — not onboarding scaffolding.
