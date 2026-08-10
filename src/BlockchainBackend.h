#ifndef BLOCKCHAIN_BACKEND_H
#define BLOCKCHAIN_BACKEND_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "rep_BlockchainBackend_source.h"

#include "AccountsModel.h"
#include "BlockModel.h"

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
// QML acquires them via logos.model("blockchain_ui", "accounts"|"blocks").
class BlockchainBackend : public BlockchainBackendSimpleSource
{
    Q_OBJECT
    Q_PROPERTY(AccountsModel* accounts READ accounts CONSTANT)
    Q_PROPERTY(BlockModel* blocks READ blocks CONSTANT)

public:
    explicit BlockchainBackend(LogosAPI* logosAPI, QObject* parent = nullptr);
    ~BlockchainBackend() override;

    AccountsModel* accounts() const { return m_accountsModel; }
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
    QVariantMap getBlock(QString headerIdHex) override;
    QVariantMap getTransaction(QString txHashHex) override;
    QVariantMap findTransactionInBlocks(QString txHashHex) override;
    QVariantMap getPeerId() override;
    QVariantMap getClaimableVouchers() override;
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
    void copyToClipboard(QString text) override;
    // Recompute blendStatus + lastBlendEvent from node status + /blend/info + the blend::service log.
    void refreshBlendStatus() override;

private:
    void fetchBalancesForAccounts(const QStringList& list);
    void setError(const QString& message);
    // Reads the node's own log to explain a failed/no-reply call honestly
    // (crash / recovering / storage / peers) instead of a generic "Call failed".
    QString lastNodeError() const;
    // curl :8080/blend/info (Online-only; it hangs while bootstrapping). Returns { ok, coreInfoPresent, mixPeers }.
    QVariantMap getBlendInfo() const;
    // Scan the node log tail for the most-recent blend::service transition. Sets *outEvent to the
    // human message; returns the derived BlendStatus for an Online node (Edge/Core/Broadcast/BlendError/Unknown).
    BlendStatus blendStateFromLog(QString* outEvent) const;

    LogosAPI* m_logosAPI = nullptr;
    LogosAPIClient* m_blockchainClient = nullptr;
    AccountsModel* m_accountsModel = nullptr;
    BlockModel* m_blockModel = nullptr;

    static const QString BLOCKCHAIN_MODULE_NAME;
};

#endif // BLOCKCHAIN_BACKEND_H
