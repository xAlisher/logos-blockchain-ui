.pragma library
// Info (i) tooltip content for the dashboard tiles. Sourced from docs.logos.co +
// the cryptarchia consensus code + the app's own derivation logic. Honest about
// which values are wired in the 0.3 API vs still showing "—".

var data = {
    status: {
        title: "Status",
        what: "The node's current lifecycle state — off, starting, catching up, or fully online and validating. The dashboard's headline.",
        calc: "From the backend status enum (NotStarted / Starting / Running / Stopping / Stopped / Error). 'Online' vs 'Bootstrapping' is decided client-side: the node is synced when it reports mode Online and its tip is within ~3 slots of the network head. The bootstrapping countdown is a client-side ~60:00 timer, not a backend progress field.",
        states: [
            { label: "Not started", meaning: "Node is off / idle." },
            { label: "Starting", meaning: "Launching and checking configuration." },
            { label: "Bootstrapping", meaning: "Running but the chain is behind the head; shows a rough countdown." },
            { label: "Online", meaning: "Running and synced — validating." },
            { label: "Error", meaning: "The node reported an error (message shown)." }
        ],
        docs: "https://docs.logos.co/blockchain/get-started/run-a-logos-blockchain-node-from-basecamp"
    },
    blend: {
        title: "Blend",
        what: "Whether this node uses the Blend Network — the mixnet that hides which node proposed a block, strengthening proposer privacy for the whole network.",
        calc: "A node opts in as a Blend core node via the Service Declaration Protocol (proving ownership of a min-stake note); the declaration activates two epochs later. Not exposed by the 0.3 node API yet — the tile shows 'Not active' until a Blend health signal is wired.",
        states: [
            { label: "Not active", meaning: "Proposals not mixed — node is not on Blend." },
            { label: "Edge", meaning: "Proposals mixed — node relays its own proposals through Blend." },
            { label: "Core", meaning: "Proposals mixed — a declared Blend node that mixes traffic for others and earns rewards." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-the-blend-network"
    },
    epoch: {
        title: "Epoch",
        what: "The current epoch number. An epoch spans many slots; each new epoch refreshes the randomness and the eligible-stake set used to elect block leaders.",
        calc: "epoch = floor(current_slot / epoch_length). epoch_length (in slots) = (stake-distribution stabilization + nonce buffer + nonce stabilization) × base_period_length, where base_period_length = floor(security_param / slot_coefficient). The node reports current_epoch; the app doesn't read epoch_length yet, so the number and the 'Nh of Mh' progress are placeholders for now.",
        states: [
            { label: "Number", meaning: "The current epoch, e.g. 174." },
            { label: "Progress", meaning: "Elapsed of total, e.g. '6h of 10h' (testnet epoch ≈ 2h; reference network ≈ 7.5 days)." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#time-units"
    },
    stake: {
        title: "Stake",
        what: "The value of notes this node controls that back its leadership election — its weight in the lottery. Cryptarchia has no minimum stake; any note can participate.",
        calc: "Leadership odds scale with a note's stake relative to the total participating stake. The eligible set is snapshotted at the first slot of the previous epoch. Not exposed by the 0.3 API yet — shows —.",
        states: [
            { label: "Amount", meaning: "Token value, with the founding address beneath." },
            { label: "—", meaning: "Not reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#leadership-election"
    },
    earned: {
        title: "Earned",
        what: "Leader rewards this node has earned for proposing blocks, claimable to the wallet.",
        calc: "The node can claim rewards and list claimable vouchers, but a running total isn't surfaced to this tile yet — shows —. A non-zero value marks the lifecycle stage 'Earning'.",
        states: [
            { label: "Amount", meaning: "Earned LGO, with 'Fees this epoch: N%' beneath." },
            { label: "—", meaning: "Not reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    proposed: {
        title: "Proposed in current epoch",
        what: "How many blocks this node has proposed (won the leader lottery for) this epoch, and whether it's currently eligible to propose at all.",
        calc: "A note can only lead once it has 'aged' — it must have existed since the start of the previous epoch to enter the eligible set — so newly funded stake waits ~2 epochs before it can propose. The proposed count and validation state aren't exposed by the 0.3 API yet — shows —.",
        states: [
            { label: "N · Validation active", meaning: "Eligible and proposing." },
            { label: "Activates in N epochs", meaning: "Funded but still aging." },
            { label: "Validation inactive", meaning: "Not eligible to propose." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#leadership-election"
    },
    peers: {
        title: "Peers",
        what: "How many other nodes this node is connected to on the peer-to-peer network. Peers are how the node gossips blocks in and out.",
        calc: "Reading the live connection count needs a bridge to the node's HTTP API; not wired in the 0.3 module yet — shows —. The sub line breaks out total connections (a peer can hold more than one).",
        states: [
            { label: "Count", meaning: "Connected peers, with total connections beneath." },
            { label: "—", meaning: "Not reported yet." }
        ],
        docs: ""
    },
    peerId: {
        title: "Peer ID",
        what: "This node's unique libp2p network identity — the address other peers use to find and connect to it. Stable for a given node key.",
        calc: "From getPeerId, derived from the node key in the config, so it's available even before the node is running. Shown shortened (first 6 … last 4); the full ID is copyable. Wired / real.",
        states: [
            { label: "12D3…EwLz", meaning: "Shortened peer ID (copyable to the full value)." },
            { label: "—", meaning: "Config / key not available." }
        ],
        docs: "https://docs.logos.co/get-started/glossary"
    },
    mining: {
        title: "Mining",
        what: "The node's funding helper — acquiring the stake (notes) it needs before it can lead, i.e. getting to 'Funded'. Shown as progress toward a target, not a token total. It's a permissionless on-ramp to staking, not consensus proof-of-work — Cryptarchia is proof-of-stake.",
        calc: "Percentage = min(100, round(mined / target × 100)), with 'mined / target LGO' beneath. No backend feeds this yet — shows —. Reaching the target marks the lifecycle stage 'Funded'.",
        states: [
            { label: "N%", meaning: "Progress toward the target while mining is running." },
            { label: "—", meaning: "Not started." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#leadership-election"
    },
    cpu: {
        title: "CPU",
        what: "How much processor the node process is using on this machine.",
        calc: "Community preview: the app finds the blockchain_module process and samples /proc (utime+stime) every 2s. Real, until the node reports it directly.",
        states: [
            { label: "NN%", meaning: "Current usage. A cap can be set in Settings → Hardware." },
            { label: "—", meaning: "Node not running — nothing to sample." }
        ],
        docs: ""
    },
    ram: {
        title: "RAM",
        what: "How much memory the node process is using on this machine.",
        calc: "Community preview: sampled from the node process's /proc VmRSS every 2s. Real, until the node reports it directly.",
        states: [
            { label: "N.N GB", meaning: "Current resident memory." },
            { label: "—", meaning: "Node not running — nothing to sample." }
        ],
        docs: ""
    },
    disk: {
        title: "Disk",
        what: "How much disk the node's data directory (chain db, state, logs, config) occupies.",
        calc: "Community preview: the app sums the node data-dir size every ~20s. Real, until the node reports it directly.",
        states: [
            { label: "N.N GB", meaning: "Current on-disk footprint. A cap can be set in Settings → Hardware." },
            { label: "—", meaning: "Node not running / config not located." }
        ],
        docs: ""
    },
    slot: {
        title: "Slot",
        what: "The current time slot. Cryptarchia divides time into fixed slots (~1s on the reference network); each slot is one chance for a block to be added.",
        calc: "slot = floor((now − genesis_time) / slot_duration). The app prefers the wall-clock head slot (current_slot) and falls back to the tip's slot; the gap between the two is what drives the 'Bootstrapping' sync check. Wired / real.",
        states: [
            { label: "Integer", meaning: "Increases every slot, e.g. 184 502." },
            { label: "—", meaning: "No time info reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#time-units"
    },
    height: {
        title: "Height",
        what: "The number of blocks in this node's canonical chain, from genesis to its tip. It ticks up as blocks are applied, so it doubles as the real sync-progress indicator.",
        calc: "Read directly from the node's cryptarchia_info.height. Wired / real.",
        states: [
            { label: "Integer", meaning: "Block count, e.g. 92 118." },
            { label: "—", meaning: "Node hasn't reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia"
    },
    lib: {
        title: "LiB — Last Immutable Block",
        what: "The most recent block considered final — deep enough in the chain that a fork can no longer revert it. Everything at or below LiB is settled.",
        calc: "A block becomes immutable once it is k blocks deep, where k is the fork-choice security parameter. Read from cryptarchia_info.lib (a block header ID), shown shortened. Wired / real.",
        states: [
            { label: "0x1a2b…9f0c", meaning: "Shortened block header ID." },
            { label: "—", meaning: "Node hasn't reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#fork-choice-rule"
    },
    tip: {
        title: "TiP — Tip",
        what: "The head of this node's preferred chain — the newest block it has accepted. Blocks between LiB and the tip are confirmed but not yet immutable (could still reorg).",
        calc: "The head branch selected by the fork-choice rule (the densest valid chain). Read from cryptarchia_info.tip (a block header ID), shown shortened. Wired / real.",
        states: [
            { label: "0x7d3e…b118", meaning: "Shortened block header ID." },
            { label: "—", meaning: "Node hasn't reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#fork-choice-rule"
    }
}
