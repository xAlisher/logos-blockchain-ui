# logos-blockchain-ui

> **⚠️ Fork of the official module.** This is a fork of
> [`logos-blockchain/logos-blockchain-ui`](https://github.com/logos-blockchain/logos-blockchain-ui)
> (`combined-all-prs` base) for the testnet 0.2.0 demo: adds `bootstrap.ibd.peers` autofill (so the
> prefilled peers actually drive IBD) and **honest node errors** (the real cause instead of "Call
> failed"), on top of the reset button + peer prefill + resume-on-config. Pairs with the patched node module.


A QML + C++ backend UI module for the [Logos](https://logos.co) platform that provides a graphical interface to control and monitor the Logos blockchain node.

Built with [`logos-module-builder`](https://github.com/logos-co/logos-module-builder) using the `mkLogosQmlModule` pattern (QML frontend + C++ backend with Qt Remote Objects).

## Features

- Start/Stop blockchain node
- Configure node parameters (config path, deployment)
- Check wallet balances
- Monitor node status and information
- Account management

## Standalone App Quickstart

1. Build and run the app:

```bash
nix run
```

2. Generate a new config using initial peers from the live testnet. See the [⚙️ Initialize Your Node](https://github.com/logos-blockchain/logos-blockchain/releases/latest#-initialize-your-node) section of the latest release notes
> Note that what's shown in the release document is a CLI command.
> For the UI's "Initial peers" field, strip everything but the peer addresses themselves (no quotes, brackets, or commas) and paste one per line.
> 
> Like so:
> ```text
> /ip4/203.0.113.10/udp/3000/quic-v1/p2p/12D3KooWh82pJGF9p7kpzb6eU326EFZf2cDnimbTFVeJtx1qtBmU
> /ip4/203.0.113.10/udp/3001/quic-v1/p2p/12D3KooWNJAEqN76R7PwPfHt3oWb8R6cKvhgyxQdDn53jFrK6wFx
> /ip4/203.0.113.10/udp/3002/quic-v1/p2p/12D3KooW7RJWhvQBQPEjJmki5fhBboGBWRJhmcFkMvrr4Fu3tMSJ
> /ip4/203.0.113.10/udp/3003/quic-v1/p2p/12D3KooW5EdynMEiYSyiWAH9GpcbHpeUzeSQF9ZY6q4x8AhBskUf
> ```

3. Start the node and let it sync. Track progress:

```bash
watch -n1 'curl -s localhost:8080/cryptarchia/info'
```

Compare the `height` with the [block explorer](https://testnet.blockchain.logos.co/web/explorer/).

4. Request funds from the [faucet](https://testnet.blockchain.logos.co/web/faucet/) — copy one of the keys from the UI and paste it there.

5. Once synced, refresh your balance to see your funds.

Leaving the node running for ~3.5 hours allows your tokens to age and become eligible for consensus participation (automatic).

For a video walkthrough, see this [recording](https://drive.google.com/file/d/1hw6rQZnuka3Y_JBpUz0WyLXglTSPiZEc/view?usp=drive_link).

## How to Run

### Standalone (recommended for development)

```bash
# Run directly
nix run

# With local workspace overrides
nix run --override-input liblogos_blockchain_module path:../logos-blockchain-module \
        --override-input liblogos_blockchain_module/logos-module-builder path:../logos-module-builder
```

### In Basecamp

```bash
# Build LGX
nix build .#lgx

# Install into Basecamp's plugin directory
lgpm --ui-plugins-dir ~/Library/Application\ Support/Logos/LogosBasecampDev/plugins \
     install --file result/*.lgx
```

Or from the workspace:

```bash
ws bundle logos-blockchain-ui --auto-local
```

### Build Targets

```bash
nix build            # default — combined plugin + QML output
nix build .#lgx      # .lgx package for distribution
nix build .#install  # lgpm-installed output (modules/ + plugins/)
nix run              # standalone app with blockchain module
nix develop          # enter development shell
```

## Module Structure

```
logos-blockchain-ui/
├── flake.nix                       # mkLogosQmlModule
├── metadata.json                   # Module config (ui_qml type)
├── CMakeLists.txt                  # logos_module() macro
└── src/
    ├── BlockchainBackend.rep       # RemoteObject interface
    ├── BlockchainBackend.h/cpp     # Business logic (extends BlockchainBackendSimpleSource)
    ├── BlockchainPlugin.h/cpp      # Thin plugin entry point
    ├── BlockchainPluginInterface.h # Plugin interface marker
    ├── AccountsModel.h/cpp         # QAbstractListModel for accounts
    ├── LogModel.h/cpp              # QAbstractListModel for logs
    └── qml/
        └── BlockchainView.qml     # QML frontend (+ sub-views)
```

## Configuration

### Blockchain Node Configuration

- **Via UI**: Enter the config path in the "Config Path" field
- **Via Environment Variable**: Set `LB_CONFIG_PATH` to your configuration file path

### QML Hot Reload

During development, set the environment variable to load QML from disk:

```bash
export BLOCKCHAIN_UI_QML_PATH=/path/to/logos-blockchain-ui/src/qml
```

## Dependencies

| Dependency | Purpose |
|---|---|
| Qt6 Core, Gui, RemoteObjects, Declarative | UI framework + IPC |
| [`logos-module-builder`](https://github.com/logos-co/logos-module-builder) | Build system (mkLogosQmlModule) |
| [`logos-blockchain-module`](https://github.com/logos-blockchain/logos-blockchain-module) | Blockchain backend module |

## Related Repositories

| Repository | Role |
|---|---|
| [`logos-blockchain-module`](https://github.com/logos-blockchain/logos-blockchain-module) | Blockchain backend — this UI's required dependency |
| [`logos-module-builder`](https://github.com/logos-co/logos-module-builder) | Module build system |
| [`logos-liblogos`](https://github.com/logos-co/logos-liblogos) | Logos Core platform |
