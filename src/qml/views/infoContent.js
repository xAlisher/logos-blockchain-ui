.pragma library
// Info (i) tooltip content for the dashboard tiles. Sourced from docs.logos.co +
// the cryptarchia consensus code + the app's own derivation logic. Honest about
// which values are wired in the 0.3 API vs still showing "—".

var data = {
    status: {
        title: "Status",
        what: "The node's current lifecycle state — off, starting, catching up, or fully online and following the chain. The dashboard's headline.",
        calc: "From the backend status enum (NotStarted / Starting / Running / Stopping / Stopped / Error). 'Online' vs 'Bootstrapping' is decided client-side: the node is synced when it reports mode Online and its tip is within ~3 slots of the network head. The bootstrapping countdown is a client-side ~60:00 timer, not a backend progress field.",
        states: [
            { label: "Not started", meaning: "Node is off / idle." },
            { label: "Starting", meaning: "Launching and checking configuration." },
            { label: "Bootstrapping", meaning: "Running but the chain is behind the head; shows a rough countdown." },
            { label: "Bootstrap stuck", meaning: "Bootstrapping but block height has stopped advancing for 10+ min — the node isn't following the chain (crashed sync or lost peers). Restart, or reset chain state. Note: LIB staying at 0 during bootstrap is normal (it finalizes once Online), not stuck." },
            { label: "Online", meaning: "Running and synced, following the chain." },
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
        what: "Net leader rewards (reward minus claim fee) from the claims this app has collected — the rewards for blocks your node proposed and claimed.",
        calc: "Summed from this app's claims ledger: each settled / in-a-block claim's reward minus its fee. It counts the claims the app has SEEN, reconciled from a recent window of the chain — NOT from genesis — so it is not a lifetime total. Rewards claimed before that window are already in your wallet (they show in the Stake balance) but are not summed here, so Earned can read lower than the balance actually grew. The Stake balance is the authoritative figure; this is the app's per-claim accounting of recent rewards.",
        states: [
            { label: "Amount", meaning: "Earned LGO, with 'Fees this epoch: N%' beneath." },
            { label: "—", meaning: "Not reported yet." }
        ],
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    earnedByEpoch: {
        title: "Earned by epoch",
        what: "The same net rewards as the Earned tile, broken out per epoch — one bar per epoch, its height the net LGO (reward minus fee) from the claims this app collected in that epoch.",
        calc: "Built from this app's claims ledger, the same source as the Earned tile: each claim's net reward (reward minus fee) is grouped into its epoch (epoch = floor(slot / 36000)), and the bars sum those groups. So it is the app's per-claim accounting over a recent window of the chain — NOT from genesis — and epochs whose rewards were claimed before that window won't appear. Bars pack from the left and stay a fixed width; once history outgrows the width, the chart shows a rolling window of the most recent epochs. Epoch numbers are hidden to keep the bars readable — hover a bar to see 'Epoch N: X LGO'.",
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    proposedByEpoch: {
        title: "Blocks proposed by epoch",
        what: "How many blocks this node proposed in each epoch — one bar per epoch, its height the count.",
        calc: "Built from this node's own proposal log (the same source as the Proposals tab): each proposal is grouped into its epoch (from the proposal's timestamp vs. genesis + epoch length), and the bar is the count. The series is filled continuously to the current epoch, so an epoch with zero proposals shows as an empty slot rather than being skipped. Bars pack from the left at a fixed width; hover to see 'Epoch N: X blocks'. Log retention bounds how far back it reaches — older epochs roll off."
    },
    vouchersByEpoch: {
        title: "Vouchers claimed by epoch",
        what: "How many leader vouchers this app claimed (settled or in-block) in each epoch — one bar per epoch, its height the count.",
        calc: "Built from this app's claims ledger, the same source as the Earned chart, but counting claims rather than summing their LGO. Each settled/in-block claim is grouped into its epoch (epoch = floor(slot / 36000)); the series is filled continuously to the current epoch so a no-claim epoch shows as an empty slot. Hover to see 'Epoch N: X vouchers'."
    },
    chainPosition: {
        title: "Chain position",
        what: "Slot and Height in one picture: a slot axis with three markers — lib (finalized), tip (your latest block), and now (the clock / current_slot) — plus the block count.",
        calc: "Slot is the clock (it ticks every slot whether or not a block is produced); Height is the chain (it only climbs when a block lands). The solid segment lib→tip is built-but-not-yet-finalized; the faint segment tip→now is the gap you're catching up to the clock. When synced, tip≈now and the faint part disappears. During a prolonged bootstrap the finalized edge (lib) freezes far behind — visible here as a large 'slots to finality'. Point-in-time (current values), not a history."
    },
    blocksByEpoch: {
        title: "Blocks per epoch",
        what: "How many blocks the NETWORK added each epoch (the rise in chain Height), one bar per epoch.",
        calc: "The app records the max block Height it saw in each epoch into a small store (epoch-height.json); blocks-per-epoch is the difference between consecutive epochs' heights. This is total network block production (not just yours), so it reads the chain's liveness — steady bars = healthy, falling = trouble; your bootstrap epochs show as tall catch-up bars. History starts the first time you run this build; the current epoch's bar is partial until it ends."
    },
    syncGap: {
        title: "Sync gap",
        what: "How many slots your node's tip is behind the clock (current_slot − tip), over the last ~10 minutes.",
        calc: "Sampled every ~4 seconds into a rolling in-session buffer. A large, falling line means you're bootstrapping and catching up; near-zero and flat means you're synced and following the tip. Recent view only — it resets when the node stops."
    },
    blendModeByEpoch: {
        title: "Blend type by epoch",
        what: "The Blend mode this node was in each epoch — Core (mixing), Declared (edge) (an on-chain Core declaration but running edge), Edge, Activating, or Off — one coloured cell per epoch.",
        calc: "Recorded by the app into a small write-ahead store (blend-mode-history.json) each time it refreshes the Blend status: the current epoch's cell is set to the resolved mode (last-seen wins within an epoch). This is why it survives even though the node's own log — the only other source — rotates after ~10h. A blank/faint cell means the node was down or the mode was unknown that epoch. History begins the first time you run this app version; older epochs it never observed won't appear."
    },
    peersSeries: {
        title: "Peers",
        what: "Connected-peer count over the last ~10 minutes — a live trend line, not per-epoch.",
        calc: "Sampled every ~4 seconds while the node runs (the same poll that refreshes the peer/connection tiles) into a rolling in-session buffer of the most recent ~150 samples (~10 minutes). This is a RECENT view, not persisted history: it starts empty and resets whenever the node is stopped. The legend shows the latest value; the line is scaled to its own recent max."
    },
    hwSeries: {
        title: "Hardware",
        what: "CPU, RAM and Disk usage of the node process over the last ~10 minutes, on one chart.",
        calc: "The three metrics come from sampling the blockchain_module process (CPU %, RAM in GB, node data-dir size in GB), captured every ~4 seconds into a rolling in-session buffer (~150 samples ≈ 10 minutes). Because the units differ, EACH line is scaled to its own recent max so the three trends are comparable on one axis — the legend shows each metric's actual latest value (e.g. CPU 13%, RAM 1.5 GB, Disk 42 GB). Recent view only: it resets when the node stops. These come from /proc while the node exposes no resource API (PREVIEW)."
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
        what: "Available in 0.3.0."
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

// Rewards-tab (i) content — same shape as `data` above so the Rewards tab opens
// the SAME structured InfoModal (what / calc / states / docs) as the dashboard.
var rewards = {
    readyToClaim: {
        title: "Ready to claim",
        what: "Leadership vouchers the wallet can prove and claim right now. Each block your node leads mints a voucher; claiming turns it into spendable balance (auto-claim does this at each epoch start).",
        calc: "Counted from wallet_get_claimable_vouchers, which returns only the READY (available) set. The node's own reserved / in-flight vouchers are never sent to the UI, and a voucher the wallet cannot prove at the current tip is hidden until it can — so this can be lower than the number of blocks led.",
        states: [
            { label: "Number", meaning: "Vouchers claimable now — click the tile to inspect each one." },
            { label: "0", meaning: "Nothing ready this moment (or all already claimed)." }
        ],
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    submitted: {
        title: "Submitted",
        what: "Claims you have submitted that have not yet finalized on chain.",
        calc: "Counted from this ledger (claims in flight). The node never sends the UI its own reserved-voucher list, so this is derived from what the app has submitted, not from node state.",
        states: [
            { label: "In a block", meaning: "Included at the tip, finalizing behind the last-immutable block." },
            { label: "0", meaning: "Nothing in flight." }
        ],
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    claimed: {
        title: "Claimed",
        what: "Total leader rewards you have claimed and that have settled to the wallet.",
        calc: "Summed from the settled rows of the claims ledger below (net of the claim fee). Only blocks at or below the last-immutable block count as settled.",
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    unclaimed: {
        title: "Unclaimed (estimate)",
        what: "Value still on the table — vouchers ready to claim, valued at the most recent settled reward.",
        calc: "vouchers ready × last settled reward. An ESTIMATE: the reward is read from ledger state when a claim executes and does move between claims (9,517 then 9,535 observed on this chain).",
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    costToClaim: {
        title: "Cost to claim",
        what: "What a single claim costs. A claim is itself a transaction, so it pays a fee — which is why an empty wallet cannot claim.",
        calc: "The fee is the spent note minus its change. The block records only the note's id, so a claim whose note was spent before this ledger existed cannot be priced (shows 'not known yet').",
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    blocksLed: {
        title: "Blocks led",
        what: "Blocks this node proposed. Leadership is private on chain, so this is read from the node's own log.",
        calc: "This is NOT the number of claimable vouchers: the wallet hides any voucher it cannot prove at the current tip, and the node exposes no way to list those — so blocks-led can exceed claimed + claimable and the difference cannot be explained from here.",
        docs: "https://docs.logos.co/blockchain/concepts/about-cryptarchia#leadership-election"
    },
    lastClaim: {
        title: "Last claim",
        what: "When your most recent claim landed, and the reward it carried.",
        calc: "Stamped by the chain scan on settle; an explorer-verdicted settle has no timestamp, so it falls back to the submission time.",
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    },
    claims: {
        title: "Claims",
        what: "Every claim you have made, kept permanently. The rows say what happened; the summary above says how it is going.",
        calc: "A claim is recorded the moment it is submitted, then reconciled against the chain: Submitted → In a block → Settled. Only blocks below the last-immutable block count as settled, so a chain reorg moves a claim back rather than un-settling it. A claim that is never included shows as Not included — nothing is consumed, the node releases its reservation and the voucher becomes claimable again.",
        states: [
            { label: "Submitted", meaning: "Sent, waiting to be included in a block." },
            { label: "In a block", meaning: "Included at the tip, finalizing." },
            { label: "Paid", meaning: "Settled below the last-immutable block." },
            { label: "Not included", meaning: "Never landed — nothing consumed, voucher released." }
        ],
        docs: "https://docs.logos.co/blockchain/node-app/claim-leader-rewards-in-logos-blockchain-ui-app"
    }
}
