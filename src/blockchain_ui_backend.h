#ifndef BLOCKCHAIN_UI_BACKEND_H
#define BLOCKCHAIN_UI_BACKEND_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include "rep_BlockchainBackend_source.h"
#include "logos_ui_plugin_context.h"

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
class BlockchainUiBackend : public BlockchainBackendSimpleSource, public LogosUiPluginContext
{
    Q_OBJECT
    Q_PROPERTY(AccountsModel* accounts READ accounts CONSTANT)
    Q_PROPERTY(BlockModel* blocks READ blocks CONSTANT)

public:
    explicit BlockchainUiBackend(QObject* parent = nullptr);
    ~BlockchainUiBackend() override;

    AccountsModel* accounts() const { return m_accountsModel; }
    BlockModel* blocks() const { return m_blockModel; }

public slots:
    // Overrides of the pure-virtual slots generated from the .rep.
    void startBlockchain() override;
    void stopBlockchain() override;
    void refreshAccounts() override;
    QVariantMap getBalance(QString addressHex) override;
    QVariantMap transferFunds(QString fromKeyHex, QString toKeyHex, QString amountStr) override;
    QVariantMap claimLeaderRewards() override;
    QVariantMap getCryptarchiaInfo() override;
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

protected:
    void onContextReady() override;

private:
    void fetchBalancesForAccounts(const QStringList& list);
    void setError(const QString& message);

    LogosAPIClient* m_blockchainClient = nullptr;
    AccountsModel* m_accountsModel = nullptr;
    BlockModel* m_blockModel = nullptr;

    static const QString BLOCKCHAIN_MODULE_NAME;
};

#endif // BLOCKCHAIN_UI_BACKEND_H
