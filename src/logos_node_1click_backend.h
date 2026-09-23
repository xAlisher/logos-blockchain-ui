#ifndef BLOCKCHAIN_UI_BACKEND_H
#define BLOCKCHAIN_UI_BACKEND_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include "rep_BlockchainBackend_source.h"
#include "logos_ui_plugin_context.h"

#include "AccountsModel.h"
#include "BlockModel.h"
#include "BlendRecovery.h"

class LogosAPI;
class LogosAPIClient;

// Source-side implementation of the BlockchainBackend .rep interface.
//
// Inheriting from BlockchainBackendSimpleSource gives us the generated PROPs,
// SLOTs and SIGNALs from BlockchainBackend.rep.
//
// AccountsModel* / BlockModel* are subclass-only Q_PROPERTYs — QAbstractItemModel*
// can't flow through a .rep, so ui-host auto-remotes each such property as
// "<module>/<propertyName>" (see logos-view-module-runtime/ui-host/main.cpp).
// QML acquires them via logos.model("logos_node_1click", "accounts"|"blocks").
class LogosNode1clickBackend : public BlockchainBackendSimpleSource, public LogosUiPluginContext
{
    Q_OBJECT
    Q_PROPERTY(AccountsModel* accounts READ accounts CONSTANT)
    // Same rows as `accounts` but SPENDABLE keys only (no signing/identity keys). The
    // Transfer / Channel-Deposit "from account" pickers bind to this so a signing key can
    // never be picked as a transfer source. The Accounts view uses the full `accounts`.
    Q_PROPERTY(AccountsModel* spendableAccounts READ spendableAccounts CONSTANT)
    Q_PROPERTY(BlockModel* blocks READ blocks CONSTANT)

public:
    explicit LogosNode1clickBackend(QObject* parent = nullptr);
    ~LogosNode1clickBackend() override;

    AccountsModel* accounts() const { return m_accountsModel; }
    AccountsModel* spendableAccounts() const { return m_spendableModel; }
    BlockModel* blocks() const { return m_blockModel; }

public slots:
    // Overrides of the pure-virtual slots generated from the .rep.
    void startBlockchain() override;
    void stopBlockchain() override;
    // Start liveness-confirm (see startBlockchain): the `start` RPC can return
    // before the node's API is up on a slow recovery, so a no-reply keeps status
    // Starting. The UI polls :8080 and calls confirmRunning() once it answers, or
    // confirmStartFailed() if it never does (~60s).
    void confirmRunning() override;
    void confirmStartFailed() override;
    // Faucet POST via curl (the app's Qt/QML HTTPS stack fails with status 0 on
    // this AppImage; system curl uses working system OpenSSL). Async → faucetResult.
    void requestFaucetFunds(QString publicKeyHex) override;
    void refreshAccounts() override;
    QVariantMap getBalance(QString addressHex) override;
    QVariantMap transferFunds(QString fromKeyHex, QString toKeyHex, QString amountStr) override;
    QVariantMap claimLeaderRewards() override;
    QVariantMap getCryptarchiaInfo() override;
    // Peer/connection counts from the node's local HTTP API via curl (the app's
    // Qt/QML network stack is unreliable here — see requestFaucetFunds).
    QVariantMap getNetworkInfo() override;
    QVariantMap getRecoveryStatus() override;
    QVariantMap getBlock(QString headerIdHex) override;
    QVariantMap getTransaction(QString txHashHex) override;
    QVariantMap findTransactionInBlocks(QString txHashHex) override;
    QVariantMap getPeerId() override;
    QVariantMap getClaimableVouchers() override;
    // Persistent leader-claim ledger: local write-ahead rows reconciled against the
    // chain. Returns { claims: [...], summary: {...} } as a JSON string in `value`.
    QVariantMap getLeaderClaims() override;
    QVariantMap clearLeaderClaims() override;
    QVariantMap clearProposals() override;
    // Blocks THIS node proposed, parsed from the node's own log (the authoritative
    // "my proposals" — leadership is private on-chain so a leader_key match can't work).
    QVariantMap getProposals() override;
    QVariantMap getProposalsFull() override;
    QVariantMap generateConfig(QString outputPath, QStringList initialPeers, int netPort,
                       int blendPort, QString httpAddr, QString externalAddress,
                       bool noPublicIpCheck, int deploymentMode,
                       QString deploymentConfigPath, QString statePath) override;
    QVariantMap getNotes(QString walletAddressHex, QString optionalTipHex) override;
    QVariantMap channelDepositWithNotes(QString channelIdHex,
                                    QStringList inputNoteIdHexes,
                                    QString metadataBase58,
                                    QString changePublicKeyHex,
                                    QStringList fundingPublicKeyHexes,
                                    QString maxTxFee,
                                    QString optionalTipHex) override;
    void clearBlocks() override;
    QVariantMap resetChainState() override;
    // Last-resort stop for a WEDGED node whose graceful "stop" never lands: SIGKILL the
    // module host bound to the node's port, then mark the node Stopped. Called by the UI's
    // stop-confirm probe after its deadline. Runs in the UI-host (no dependency on the
    // wedged module answering). NOTE: after this the module host is dead and only reopening
    // Basecamp respawns it, so a subsequent in-app Start will fail until then.
    void forceStopNow() override;
    // The UI's stop-confirm probe saw the node's API go down → mark it Stopped (idempotent).
    void confirmStopped() override;
    // PREVIEW (#81) config/key management workarounds (app-side file ops).
    QVariantMap backupUserConfig() override;
    QVariantMap regenerateNodeKeys() override;
    QVariantMap pruneLogs(QString capGb) override;
    QVariantMap saveKeystore(QString destPath) override;
    void copyToClipboard(QString text) override;
    // Recompute the Blend status (blendStatus + lastBlendEvent) from the node
    // state, the blend::service log, and the live /blend/info. Driven by the
    // dashboard refresh timer while the node is Running.
    void refreshBlendStatus() override;
    // Blend Core provider lifecycle (epic #89). See the .rep for the API contract.
    QVariantMap declareBlendCore(QString locator, QString lockedNoteId) override;
    QVariantMap getBlendDeclarations() override;
    QVariantMap getBlendLifecycle() override;
    QVariantMap repairBlendBinding() override;
    QVariantMap startBlendRecovery() override;
    QVariantMap pauseBlendRecovery() override;
    QVariantMap resumeBlendRecovery() override;
    QVariantMap dismissBlendRecovery() override;
    QVariantMap checkBlendReachable(QString nonceHex) override;
    // Per-epoch blend-mode history (write-ahead store) for the dashboard "Blend type" strip.
    QVariantMap getBlendModeHistory() override;
    // Per-epoch max block height (write-ahead) → blocks-per-epoch (Δheight) chart.
    void        recordEpochHeight(int epoch, int height) override;
    QVariantMap getEpochHeights() override;
    // Transactions per recent block (from m_blockModel) → the TX-on-blocks heatmap.
    QVariantMap getBlockTx() override;
    QVariantMap withdrawBlendCore() override;
    QVariantMap getSdpFundingKey() override;
    QVariantMap checkBlendPortReachable() override;

protected:
    void onContextReady() override;

private:
    std::unique_ptr<BlendRecovery::Controller> m_blendRecovery;
    BlendRecovery::Snapshot m_recoverySnapshot;
    QString m_recoveryScope;
    QTimer* m_blendRecoveryTimer = nullptr;
    bool m_recoveryTick = false;
    void ensureBlendRecovery();
    bool blendRecoveryBlocks();
    QVariantMap withBlendRecovery(QVariantMap lifecycle);
    void advanceBlendRecovery();
    void readBlendRecoveryFunding(BlendRecovery::Snapshot& snapshot);
    bool m_blendMutation = false;
    bool m_blendReading = false;
    bool m_blendSubmissionPending = false;
    bool m_blendWithdrawalPending = false;
    qint64 m_blendRunFloor = 0;
    qint64 m_blendRepairedAt = 0;
    QString m_blendRepairedId;
    qint64 blendRunStartedAt() const;
    qint64 blendMissingBindingAt(qint64 runStart) const;
    qint64 blendBindingLoadedAt(qint64 runStart, const QString& declId) const;
    // Core-peer roster + message telemetry, merged from the live /blend/info API and the node log.
    // Non-const: the membership roster (logged only ~once per epoch) is cached so the table stays
    // stable across polls where the roster line has scrolled out of the scanned log tail.
    QVariantMap blendCoreTelemetry(const QJsonValue& core, const QString& ourId, int currentEpoch, qint64 epochStartMs);
    QMap<QString, QString> m_coreRoster;   // peerId -> address, last seen in the node log
    // Per-epoch accumulators for proposals blended vs broadcast-direct. Reset when the epoch
    // changes; counted incrementally from new log lines so a 10h epoch needs no full re-scan.
    int m_epochProposals = 0;
    int m_epochDirect = 0;
    int m_countEpoch = -1;
    qint64 m_lastCountedTs = 0;
    // Last-resort force stop: SIGKILL the module host on the node's HTTP port.
    bool forceStopNode();
    // Shared proposal scan; tailBytes bounds per-file read (0 = whole file).
    QVariantMap scanProposals(qint64 tailBytes);
    // Bounded retries for refreshAccounts(): the wallet can lag the API after a start.
    int m_accountRetries = 0;
    void fetchBalancesForAccounts(const QStringList& list);
    void setError(const QString& message);
    // Reads the node's own log to explain a failed/no-reply call honestly
    // (crash / recovering / storage / peers) instead of a generic "Call failed".
    QString lastNodeError() const;
    // Blend status sources (both shell out to curl / read the log — see the .cpp).
    // getBlendInfo(): live /blend/info → { ok, coreInfoPresent, mixPeers }.
    // blendStateFromLog(): map the blend::service log tail → BlendStatus + *outEvent.
    QVariantMap getBlendInfo() const;
    BlendStatus blendStateFromLog(QString* outEvent) const;
    // Latest `membership_count=N` from the blend service log = the epoch's Blend CORE set size
    // (the "N core nodes" shown on the dashboard). -1 if not found (log rotated / not written).
    int blendMembershipCount() const;
    // On-chain state of OUR SDP declaration (matched by verified provider identity): { found, active, withdrawAt }.
    QVariantMap onchainBlendDecl() const;
    // Current epoch from the node's /time/info (-1 if unavailable). Distinguishes a genuinely
    // pending declaration (epoch < active) from an active-but-not-mixing one (epoch >= active).
    int currentEpochOnchain() const;
    // ---- Blend Core provider lifecycle helpers (epic #89) ----
    // sdp.wallet.funding_pk from the node config — the key the declaration fee is
    // paid from (mirrors leaderFundingKey()'s config walk, different sub-block).
    QString sdpFundingKey() const;
    // public_keys.BlendSigning from the node keystore — the node's Blend public key (64 hex),
    // identical to the on-chain SDP declaration provider_id. This is the value an operator pastes
    // into the Referral app to link the node. Read from keystore.yaml, not user_config.yaml.
    QString blendSigningKey() const;
    // Build the enriched accounts list (address+label+hint+group+fundable) for the wallet view:
    // classify each known wallet key by its config role, then append the identity keys
    // (Blend public key from the keystore, and the network peer id passed in).
    QVariantList buildAccounts(const QStringList& knownAddresses, const QString& peerId) const;
    // blend listening port from the config (blend_port / a udp/<port> in the blend
    // listening_address). Falls back to 3400 (the testnet default) if not found.
    int blendPortFromConfig() const;
    // Public IP for the declaration locator: prefer an external_address in the config,
    // else resolve via a public IP-echo over curl. Empty if it can't be determined.
    QString resolvePublicIp() const;
    // Build the declaration locator /ip4/<publicIp>/udp/<blendPort>/quic-v1. Empty if
    // the public IP can't be resolved.
    QString buildBlendLocator() const;
    // Write-ahead store for THIS node's Blend declaration ({declaration_id, locked_note_id,
    // locator, created_at}). declareBlendCore writes it so withdrawBlendCore can find the
    // declaration id and refreshBlendStatus can report Activating; withdraw retains it until confirmed removal.
    QString blendDeclStorePath() const;
    // Per-epoch blend-mode history store (blend-mode-history.json beside the node config):
    // recordBlendMode upserts {epoch: mode} (last-seen wins) from refreshBlendStatus.
    QString blendModeStorePath() const;
    void    recordBlendMode(int epoch, const QString& mode) const;
    // Per-epoch max-height store (epoch-height.json) backing the blocks-per-epoch chart.
    QString epochHeightStorePath() const;
    QJsonObject loadBlendDecl() const;
    void        saveBlendDecl(const QJsonObject& obj) const;
    void        clearBlendDecl() const;
    // Resolving the public IP hits the network (curl), so cache it for the session
    // rather than re-resolving on every gate poll.
    mutable QString m_publicIp;
    // Node consensus mode ("Online"/"Bootstrapping"/"") from the live API — the
    // authoritative gate for Blend (edge is automatic once Online).
    QString nodeMode() const;
    // Block proposal draws from leader.wallet.funding_pk, which the module assigns
    // to a DIFFERENT key than the wallet key (logos-blockchain#3271 / ui#35). Read it
    // from the generated node config so "Fund the node" can fund the RIGHT key —
    // funding only the wallet key leaves the leader wallet empty → never proposes.
    QString leaderFundingKey() const;
    // POST a public key to the faucet via curl. userFacing=true emits faucetResult
    // (the wallet-balance request the operator sees); false = the silent leader-key top-up.
    void postFaucet(const QString& pk, bool userFacing);

    // ---- Leader-claim ledger (docs/VOUCHER-STATE-MAP.md) ----
    // Claims are NOT logged by the node — unlike proposals, which getProposals()
    // can always rebuild from the log. So the row written at press time is
    // write-ahead, not a cache: miss it and no record the press happened exists.
    // Settlement, by contrast, is always recoverable from the chain, so any
    // on-chain claim without a local row is backfilled.
    QString claimsStorePath() const;
    QJsonObject loadClaimStore() const;
    /// Claims submitted from a paired phone, written by node_remote. READ ONLY — one
    /// writer per file is what lets the two modules share this directory without a lock.
    /// Absent (no node_remote installed) is normal and reads as empty.
    QString     pendingClaimsPath() const;
    QJsonArray  loadPendingClaims() const;
    void saveClaimStore(const QJsonObject& store) const;
    // Claimable-voucher count from the node, or -1 if unknown. See the .cpp:
    // a rise in this while claims are outstanding is direct evidence they died.
    int claimableVoucherCount();
    // Proposals in the durable store — a CEILING on vouchers newly earned
    // while a claim was in flight, so leadership is never read as a release.
    int proposalCount() const;
    void recordClaimSubmission(const QString& txHash);
    // Public keys a claim of ours can be credited to (leader funding key first,
    // then the wallet key — the module assigns them separately, see ui#35).
    QStringList ourClaimKeys() const;
    // Remember {noteId: value} from a balance payload so a settled claim's fee
    // (input note − change output) can be resolved exactly. The block carries
    // only the input's id, never its value.
    void rememberNoteValues(const QString& notesJson);

    // PREVIEW resource sampling (#65/#66): find the blockchain_module process and
    // sample /proc for CPU%/RSS while the node runs. Self-liquidates when the node
    // exposes resource stats over the API.
    QTimer* m_resourceTimer = nullptr;
    qint64 m_nodePid = -1;
    unsigned long long m_prevCpuTicks = 0;
    qint64 m_prevSampleMs = 0;
    int m_diskSampleTick = 0;                 // throttle dir-size scans (every Nth CPU tick)
    qint64 findBlockchainModulePid() const;
    void sampleNodeResources();
    qint64 dirSizeBytes(const QString& path) const;   // recursive node-data-dir size

    LogosAPIClient* m_blockchainClient = nullptr;
    AccountsModel* m_accountsModel = nullptr;
    AccountsModel* m_spendableModel = nullptr;   // spendable-only view for the transfer pickers
    BlockModel* m_blockModel = nullptr;

    static const QString BLOCKCHAIN_MODULE_NAME;
};

#endif // BLOCKCHAIN_UI_BACKEND_H
