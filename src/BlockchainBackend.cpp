#include "BlockchainBackend.h"
#include "logos_api.h"
#include "logos_api_client.h"

#include <QByteArray>
#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QSignalBlocker>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <algorithm>

const QString BlockchainBackend::BLOCKCHAIN_MODULE_NAME =
    QStringLiteral("blockchain_module");

void BlockchainBackend::setError(const QString& message)
{
    setLastErrorMessage(message);
    setStatus(Error);
}

static QString toLocalPath(const QString& pathInput)
{
    if (pathInput.trimmed().isEmpty())
        return pathInput;
    return QUrl::fromUserInput(pathInput).toLocalFile();
}

namespace result {

static LogosResult err(const QString& message)
{
    return LogosResult{false, QVariant(), message};
}

// Normalises a `QVariant` (e.g. from a `invokeRemoteMethod()`) call to a `LogosResult`.
//
// `invokeRemoteMethod()` might return an invalid `QVariant` when the call itself fails to get a reply (e.g.: timeout).
// This function normalises the reply for the `LogosResult` case.
static LogosResult toLogosResult(const QVariant& reply)
{
    if (!reply.isValid())
        return err(QStringLiteral("Call failed."));
    return reply.value<LogosResult>();
}

static QString toErrorMessage(const LogosResult& result)
{
    return QStringLiteral("Error: %1").arg(result.error.toString());
}

// Returns a stringified version of a `LogosResult`.
//
// Used in some places that consume the success and error properties in the same manner.
static QString toDisplayMessage(const LogosResult& result)
{
    return result.success ? result.value.toString() : toErrorMessage(result);
}

static QVariantMap toVariantMap(const LogosResult& result)
{
    return QVariantMap{
        {"success", result.success},
        {"value", result.value},
        {"error", result.error},
    };
}

} // namespace result

// Decode a base58 (Bitcoin alphabet) string to raw bytes. On an invalid
// character *ok is set to false and an empty array is returned.
static QByteArray decodeBase58(const QString& input, bool* ok)
{
    static const QByteArray kAlphabet =
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

    const QByteArray s = input.trimmed().toLatin1();
    QByteArray bytes; // little-endian while building, reversed at the end
    bytes.append('\0');

    for (const char c : s) {
        const int value = kAlphabet.indexOf(c);
        if (value < 0) {
            if (ok) *ok = false;
            return {};
        }
        int carry = value;
        for (int j = 0; j < bytes.size(); ++j) {
            carry += static_cast<unsigned char>(bytes[j]) * 58;
            bytes[j] = static_cast<char>(carry & 0xff);
            carry >>= 8;
        }
        while (carry > 0) {
            bytes.append(static_cast<char>(carry & 0xff));
            carry >>= 8;
        }
    }

    // Each leading '1' maps to a leading zero byte.
    for (int i = 0; i < s.size() && s[i] == '1'; ++i)
        bytes.append('\0');

    std::reverse(bytes.begin(), bytes.end());
    if (ok) *ok = true;
    return bytes;
}

BlockchainBackend::BlockchainBackend(LogosAPI* logosAPI, QObject* parent)
    : BlockchainBackendSimpleSource(parent)
    , m_logosAPI(logosAPI)
    , m_accountsModel(new AccountsModel(this))
    , m_blockModel(new BlockModel(this))
{
    setStatus(NotStarted);
    setUseGeneratedConfig(false);
    setGeneratedUserConfigPath(
        QDir::currentPath() + QStringLiteral("/user_config.yaml"));

    // Restore saved config paths
    QSettings s("Logos", "BlockchainUI");
    const QString envConfigPath =
        QString::fromUtf8(qgetenv("LB_CONFIG_PATH"));
    const QString savedUserConfig =
        s.value("userConfigPath").toString();
    const QString savedDeploymentConfig =
        s.value("deploymentConfigPath").toString();

    if (!envConfigPath.isEmpty())
        setUserConfig(toLocalPath(envConfigPath));
    else if (!savedUserConfig.isEmpty())
        setUserConfig(toLocalPath(savedUserConfig));

    if (!savedDeploymentConfig.isEmpty())
        setDeploymentConfig(toLocalPath(savedDeploymentConfig));

    // Re-apply pre-.rep behavior: normalize file URLs, then persist (as master did in setters).
    connect(this, &BlockchainBackendSimpleSource::userConfigChanged, this, [this]() {
        const QString p = userConfig();
        const QString n = toLocalPath(p);
        if (n != p) {
            QSignalBlocker b(this);
            setUserConfig(n);
        }
        QSettings("Logos", "BlockchainUI")
            .setValue("userConfigPath", userConfig());
    });
    connect(this, &BlockchainBackendSimpleSource::deploymentConfigChanged, this, [this]() {
        const QString p = deploymentConfig();
        const QString n = toLocalPath(p);
        if (n != p) {
            QSignalBlocker b(this);
            setDeploymentConfig(n);
        }
        QSettings("Logos", "BlockchainUI")
            .setValue("deploymentConfigPath", deploymentConfig());
    });

    if (!m_logosAPI) {
        qWarning() << "BlockchainBackend: constructed without LogosAPI";
        return;
    }

    m_blockchainClient = m_logosAPI->getClient(BLOCKCHAIN_MODULE_NAME);
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        qWarning() << "BlockchainBackend: failed to get blockchain module client";
        return;
    }

    LogosObject* replica =
        m_blockchainClient->requestObject(BLOCKCHAIN_MODULE_NAME);
    if (replica) {
        m_blockchainClient->onEvent(
            replica, "newBlock",
            [this](const QString&, const QVariantList& data) {
                const QString timestamp =
                    QDateTime::currentDateTime().toString("HH:mm:ss");
                const QString raw = data.isEmpty() ? QString() : data.first().toString();
                m_blockModel->appendRaw(timestamp, raw);
            });
    } else {
        setError(QStringLiteral("Failed to subscribe to events"));
    }

    qDebug() << "BlockchainBackend: initialized";
}

BlockchainBackend::~BlockchainBackend()
{
    if (status() == Running || status() == Starting)
        stopBlockchain();
}

QVariantMap BlockchainBackend::claimLeaderRewards()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "leader_claim")));
}

QVariantMap BlockchainBackend::getCryptarchiaInfo()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_cryptarchia_info"))));
}

QVariantMap BlockchainBackend::getBlock(QString headerIdHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_block"), headerIdHex.trimmed())));
}

QVariantMap BlockchainBackend::getTransaction(QString txHashHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_transaction"), txHashHex.trimmed())));
}

QVariantMap BlockchainBackend::findTransactionInBlocks(QString txHashHex)
{
    // Local, in-memory resolution against the blocks currently held by the
    // model. The node's get_transaction only serves mempool (pending / very
    // recently mined) transactions, so a tx copied from the blocks view — which
    // is already mined — is looked up here instead. Returns the same shape as
    // the remote calls: { success, value, ... } with block context on success.
    const QVariantMap hit = m_blockModel->findTransaction(txHashHex);
    QVariantMap out;
    out.insert("success", hit.value("found").toBool());
    out.insert("value", hit.value("value"));
    out.insert("blockId", hit.value("blockId"));
    out.insert("slot", hit.value("slot"));
    out.insert("timestamp", hit.value("timestamp"));
    if (!out.value("success").toBool())
        out.insert("error", QStringLiteral("Not in loaded blocks."));
    return out;
}

QVariantMap BlockchainBackend::getPeerId()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    // Derived from the node key in the user config; available without the node
    // running.
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_peer_id"), userConfig())));
}

QVariantMap BlockchainBackend::getClaimableVouchers()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("wallet_get_claimable_vouchers"))));
}

void BlockchainBackend::startBlockchain()
{
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        return;
    }

    setStatus(Starting);

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "start", userConfig(), deploymentConfig()));

    if (r.success) {
        setStatus(Running);
        QTimer::singleShot(500, this, [this]() { refreshAccounts(); });
    } else {
        setError(r.error.toString());
    }
}

void BlockchainBackend::stopBlockchain()
{
    if (status() != Running && status() != Starting)
        return;

    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        return;
    }

    setStatus(Stopping);

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "stop"));

    if (r.success) {
        setStatus(Stopped);
    } else {
        setError(r.error.toString());
    }
}

void BlockchainBackend::refreshAccounts()
{
    if (!m_blockchainClient) return;

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_known_addresses"));

    if (!r.success) {
        qWarning() << "refreshAccounts: failed:" << r.error.toString();
        return;
    }

    // The SDK marshals the JSON array into a QVariantList; rely on toList()
    // rather than canConvert<QStringList>() (which is unreliable for a
    // QVariantList under Qt6), and fall back to toStringList() for the rare
    // case where the value already arrives as a QStringList.
    QStringList list;
    const QVariantList items = r.value.toList();
    if (!items.isEmpty()) {
        for (const QVariant& item : items) {
            const QString addr = item.toString();
            if (!addr.isEmpty())
                list << addr;
        }
    } else {
        list = r.value.toStringList();
    }

    qDebug() << "refreshAccounts: loaded" << list.size() << "addresses";

    m_accountsModel->setAddresses(list);

    QTimer::singleShot(0, this,
                       [this, list]() { fetchBalancesForAccounts(list); });
}

void BlockchainBackend::fetchBalancesForAccounts(const QStringList& list)
{
    if (!m_blockchainClient) return;
    for (const QString& address : list) {
        if (address.isEmpty()) continue;
        getBalance(address);
    }
}

QVariantMap BlockchainBackend::getBalance(QString addressHex)
{
    const LogosResult lr = m_blockchainClient
        ? result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
              BLOCKCHAIN_MODULE_NAME, "wallet_get_balance", addressHex))
        : result::err(QStringLiteral("Module not initialized."));

    m_accountsModel->setBalanceForAddress(addressHex, result::toDisplayMessage(lr));
    return result::toVariantMap(lr);
}

QVariantMap BlockchainBackend::transferFunds(
    QString fromKeyHex, QString toKeyHex, QString amountStr)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    QStringList senders{fromKeyHex};
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_transfer_funds",
        fromKeyHex, senders, toKeyHex, amountStr, QString())));
}

QVariantMap BlockchainBackend::generateConfig(
    QString outputPath, QStringList initialPeers, int netPort, int blendPort,
    QString httpAddr, QString externalAddress, bool noPublicIpCheck,
    int deploymentMode, QString deploymentConfigPath, QString statePath)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    QVariantMap normalized;

    // The output path drives persistence routing through the module's single
    // switch (use_persistence_paths), which routes output + state + storage +
    // logs under the host-provisioned per-instance dir:
    //   - empty    → omit "output"; module writes "<persistence>/user_config.yaml".
    //   - relative → pass it through; module resolves it under <persistence>.
    //   - absolute → write exactly there; no persistence routing.
    const QString rawOut = outputPath.trimmed();
    const QString localOut = rawOut.isEmpty() ? QString() : toLocalPath(rawOut);
    const QString chosenOut = !localOut.isEmpty() ? localOut : rawOut;
    const bool absoluteOut = !chosenOut.isEmpty() && QDir::isAbsolutePath(chosenOut);
    if (!rawOut.isEmpty())
        normalized.insert("output", absoluteOut ? chosenOut : rawOut);
    if (!absoluteOut)
        normalized.insert("use_persistence_paths", true);

    if (!initialPeers.isEmpty()) {
        QVariantList peersList;
        for (const QString& p : initialPeers) {
            if (!p.trimmed().isEmpty())
                peersList.append(p.trimmed());
        }
        if (!peersList.isEmpty())
            normalized.insert("initial_peers", peersList);
    }
    if (netPort > 0)
        normalized.insert("net_port", netPort);
    if (blendPort > 0)
        normalized.insert("blend_port", blendPort);
    if (!httpAddr.trimmed().isEmpty())
        normalized.insert("http_addr", httpAddr.trimmed());
    if (!externalAddress.trimmed().isEmpty())
        normalized.insert("external_address", externalAddress.trimmed());
    if (noPublicIpCheck)
        normalized.insert("no_public_ip_check", true);
    // An explicit node state dir still wins: the module leaves a pinned path
    // untouched even when use_persistence_paths routing is on.
    if (!statePath.trimmed().isEmpty())
        normalized.insert("state_path", toLocalPath(statePath.trimmed()));

    const QJsonDocument doc = QJsonDocument::fromVariant(normalized);
    const QString jsonToSend =
        QString::fromUtf8(doc.toJson(QJsonDocument::Compact));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "generate_user_config", jsonToSend)));
}

QVariantMap BlockchainBackend::getNotes(QString walletAddressHex, QString optionalTipHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_notes",
        walletAddressHex, optionalTipHex)));
}

QVariantMap BlockchainBackend::channelDepositWithNotes(
    QString channelIdHex, QStringList inputNoteIdHexes, QString metadataBase58,
    QString changePublicKeyHex, QStringList fundingPublicKeyHexes,
    QString maxTxFee, QString optionalTipHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    // The metadata arrives base58-encoded; the module expects metadata_hex, so
    // decode to bytes and hex-encode. Empty stays empty (metadata is optional).
    QString metadataHex;
    if (!metadataBase58.trimmed().isEmpty()) {
        bool ok = false;
        const QByteArray bytes = decodeBase58(metadataBase58, &ok);
        if (!ok)
            return result::toVariantMap(result::err(QStringLiteral("Invalid base58 metadata.")));
        metadataHex = QString::fromLatin1(bytes.toHex());
    }

    // 7 positional args exceed the variadic invokeRemoteMethod overloads
    // (max 5), so pass them through the QVariantList form.
    QVariantList args;
    args << channelIdHex << inputNoteIdHexes << metadataHex << changePublicKeyHex
         << fundingPublicKeyHexes << maxTxFee << optionalTipHex;

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("channel_deposit_with_notes"),
        args)));
}

void BlockchainBackend::clearBlocks()
{
    m_blockModel->clear();
}

QVariantMap BlockchainBackend::resetChainState()
{
    // Recover a node wedged after an unclean shutdown (logos-blockchain#3171:
    // the chain service spams "channel closed" and the API never becomes
    // serviceable). Wiping the chain database + consensus state forces a clean
    // start. Unlike deleting the whole module_data dir — which the docs
    // currently tell operators to do — this KEEPS the wallet keystore and the
    // user config, so neither keys nor settings are lost; the node re-runs IBD
    // from genesis on the next Start.
    if (status() == Running || status() == Starting || status() == Stopping)
        return result::toVariantMap(result::err(
            QStringLiteral("Stop the node before resetting chain state.")));

    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return result::toVariantMap(result::err(
            QStringLiteral("No config loaded — nothing to reset.")));

    // db / state / logs are provisioned alongside the config under the module's
    // per-instance persistence dir (use_persistence_paths). Remove those and
    // leave keystore.yaml + user_config.yaml untouched.
    const QDir dir = QFileInfo(cfg).absoluteDir();
    QStringList removed;
    QStringList failed;
    const QStringList targets{QStringLiteral("db"),
                              QStringLiteral("state"),
                              QStringLiteral("logs")};
    for (const QString& sub : targets) {
        QDir target(dir.filePath(sub));
        if (!target.exists())
            continue;
        if (target.removeRecursively())
            removed.append(sub);
        else
            failed.append(sub);
    }

    if (!failed.isEmpty())
        return result::toVariantMap(result::err(
            QStringLiteral("Could not remove: %1").arg(failed.join(", "))));

    setStatus(NotStarted);
    return result::toVariantMap(
        LogosResult{true, QVariant(removed.join(", ")), QVariant()});
}

void BlockchainBackend::copyToClipboard(QString text)
{
    // The backend runs in a non-GUI ViewModuleHost subprocess, where there is
    // no QGuiApplication and accessing the clipboard segfaults. Clipboard is
    // handled QML-side (see BlockchainView.copyText); guard here so any stray
    // call is a no-op rather than a crash.
    if (!qobject_cast<QGuiApplication*>(QCoreApplication::instance())) {
        qWarning() << "copyToClipboard: no GUI application; ignoring";
        return;
    }
    if (QClipboard* clipboard = QGuiApplication::clipboard())
        clipboard->setText(text);
}
