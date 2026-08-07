#include "logos_node_1click_backend.h"
#include "logos_sdk.h"
#include "logos_api.h"
#include "logos_api_client.h"

#include <QByteArray>
#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSettings>
#include <QSignalBlocker>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <algorithm>

const QString LogosNode1clickBackend::BLOCKCHAIN_MODULE_NAME =
    QStringLiteral("blockchain_module");

// Explain a failed call from the node's own log, so the user sees the real
// cause instead of a generic "Call failed". Reads the tail of the newest log
// file under the config's per-instance logs/ dir and maps known signatures to
// an honest, actionable message. Returns empty if nothing recognisable.
QString LogosNode1clickBackend::lastNodeError() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return {};
    const QDir logsDir(QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("logs")));
    if (!logsDir.exists())
        return {};
    const QFileInfoList files = logsDir.entryInfoList(QDir::Files, QDir::Time);
    if (files.isEmpty())
        return {};
    QFile f(files.first().absoluteFilePath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    const qint64 tail = qMin<qint64>(f.size(), 128 * 1024);
    f.seek(f.size() - tail);
    const QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    f.close();
    for (int i = lines.size() - 1; i >= 0; --i) {
        const QString& ln = lines.at(i);
        // ── Honest-error table: node-log signature → plain-language cause. ──
        // Recovery FIRST (it's not an error): the node replaying stored blocks.
        if (ln.contains(QStringLiteral("blocks to replay")) || ln.contains(QStringLiteral("Chain recovery"))
            || ln.contains(QStringLiteral("recovering chain state")))
            return QStringLiteral("The node is replaying stored blocks to catch up — this can take a few minutes.");
        // Process died.
        if (ln.contains(QStringLiteral("crashed (signal")) || ln.contains(QStringLiteral("panicked"))
            || ln.contains(QStringLiteral("SIGABRT")) || ln.contains(QStringLiteral("SIGSEGV")))
            return QStringLiteral("The node process crashed. Wipe the database and start over to recover.");
        // Chain storage inconsistent.
        if (ln.contains(QStringLiteral("Storage backend error")) || ln.contains(QStringLiteral("from storage"))
            || ln.contains(QStringLiteral("Storage request failed")))
            return QStringLiteral("The chain database is in a bad state. Wipe the database and start over.");
        // Database locked / disk I/O.
        if (ln.contains(QStringLiteral("LOCK")) || ln.contains(QStringLiteral("No locks available"))
            || ln.contains(QStringLiteral("IO error")) || ln.contains(QStringLiteral("Resource temporarily unavailable")))
            return QStringLiteral("The database is locked (another node may be running) or the disk had an I/O error. "
                                  "Make sure only one node runs, then wipe and start over.");
        // Disk full.
        if (ln.contains(QStringLiteral("No space left")) || ln.contains(QStringLiteral("ENOSPC")))
            return QStringLiteral("The disk is full — free up space, then wipe and start over.");
        // Network port already in use.
        if (ln.contains(QStringLiteral("AddrInUse")) || ln.contains(QStringLiteral("address already in use"))
            || ln.contains(QStringLiteral("EADDRINUSE")) || ln.contains(QStringLiteral("failed to bind")))
            return QStringLiteral("A required network port is already in use — another node may still be running. "
                                  "Stop it and try again.");
        // Genesis / network mismatch.
        if (ln.contains(QStringLiteral("genesis")) &&
            (ln.contains(QStringLiteral("mismatch")) || ln.contains(QStringLiteral("does not match"))))
            return QStringLiteral("This database is from a different network (genesis mismatch). "
                                  "Wipe the database and start over.");
        // Peer / protocol-version mismatch.
        if (ln.contains(QStringLiteral("AllPeersFailed")) || ln.contains(QStringLiteral("does not support"))
            || (ln.contains(QStringLiteral("protocol")) && ln.contains(QStringLiteral("mismatch"))))
            return QStringLiteral("Couldn't sync from the configured peers (unreachable, or a different "
                                  "network/version). Check the peers and network.");
        // Config parse.
        if (ln.contains(QStringLiteral("missing field")) || ln.contains(QStringLiteral("invalid type"))
            || ln.contains(QStringLiteral("failed to parse")) || ln.contains(QStringLiteral("deserialize")))
            return QStringLiteral("The node config couldn't be parsed. Open Settings and regenerate the config.");
        // Wallet / keystore.
        if (ln.contains(QStringLiteral("keystore")) || ln.contains(QStringLiteral("key not found"))
            || (ln.contains(QStringLiteral("wallet")) && ln.contains(QStringLiteral("error"))))
            return QStringLiteral("The node couldn't load its wallet keys. Check the key paths in the config.");
    }
    return {};
}

void LogosNode1clickBackend::confirmRunning()
{
    // The node's HTTP API answered — it really is up, whatever the start RPC said.
    if (status() != Running) {
        setStatus(Running);
        QTimer::singleShot(500, this, [this]() { refreshAccounts(); });
    }
}

void LogosNode1clickBackend::confirmStartFailed()
{
    // The node's API never came up after a start — surface the honest reason
    // (setError swaps the opaque "Call failed." for the node's real log signature).
    if (status() == Running)
        return;
    setError(QStringLiteral("Call failed."));
}

void LogosNode1clickBackend::requestFaucetFunds(QString publicKeyHex)
{
    const QString pk = publicKeyHex.trimmed();
    if (pk.isEmpty()) {
        emit faucetResult(false, QStringLiteral("No node key available yet — wait until the node is online."));
        return;
    }
    // Fund the wallet key the operator sees on the dashboard (user-facing result).
    postFaucet(pk, /*userFacing=*/true);
    // ALSO fund the leader funding_pk. Block proposal draws from it, and the module
    // assigns it a DIFFERENT key than the wallet key (logos-blockchain#3271 / ui#35):
    // funding only the wallet key leaves the leader wallet empty → "no claimable
    // voucher" → the node never proposes despite a funded balance shown here.
    const QString leader = leaderFundingKey();
    if (!leader.isEmpty() && leader.compare(pk, Qt::CaseInsensitive) != 0) {
        qInfo() << "requestFaucetFunds: also funding leader funding_pk (proposal key)" << leader;
        postFaucet(leader, /*userFacing=*/false);
    } else if (leader.isEmpty()) {
        qWarning() << "requestFaucetFunds: leader funding_pk not found in config — only the "
                      "wallet key was funded; the node may not propose (ui#35).";
    }
}

// POST a public key to the cryptarchia faucet via system curl (the AppImage's
// Qt/QML HTTPS fails with status 0; system curl uses working OpenSSL). The faucet
// credits testnet funds; funds auto-stake. userFacing=true emits faucetResult (the
// wallet request the operator initiated); false = the silent leader-key top-up.
void LogosNode1clickBackend::postFaucet(const QString& pk, bool userFacing)
{
    const QString url =
        QStringLiteral("https://testnet.blockchain.logos.co/web/faucet-backend/%1").arg(pk);
    QProcess* proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
            [this, proc, userFacing, pk](int, QProcess::ExitStatus) {
                const QString out = QString::fromUtf8(proc->readAllStandardOutput());
                const QString errOut = QString::fromUtf8(proc->readAllStandardError()).trimmed();
                // curl -w "\n%{http_code}" appends the status after the body.
                const int nl = out.lastIndexOf(QLatin1Char('\n'));
                const QString body = (nl >= 0 ? out.left(nl) : out).trimmed();
                const QString code = (nl >= 0 ? out.mid(nl + 1) : QString()).trimmed();
                const bool okReq = !code.isEmpty() && code.startsWith(QLatin1Char('2'));
                if (userFacing) {
                    if (code.isEmpty())
                        emit faucetResult(false, errOut.isEmpty()
                            ? QStringLiteral("Couldn't reach the faucet. Check your connection and try again.")
                            : errOut);
                    else if (okReq)
                        emit faucetResult(true, body);
                    else
                        emit faucetResult(false, body.isEmpty()
                            ? QStringLiteral("The faucet returned an error (HTTP %1).").arg(code)
                            : body);
                } else {
                    qInfo() << "postFaucet(leader" << pk << "): http" << code
                            << (okReq ? QStringLiteral("ok") : body);
                }
                proc->deleteLater();
            });
    connect(proc, &QProcess::errorOccurred, this, [this, proc, userFacing](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;   // `finished` handles the rest
        if (userFacing)
            emit faucetResult(false, QStringLiteral("Couldn't run the faucet request (curl unavailable)."));
        proc->deleteLater();
    });
    proc->start(QStringLiteral("curl"),
                {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("30"),
                 QStringLiteral("-X"), QStringLiteral("POST"),
                 QStringLiteral("-w"), QStringLiteral("\n%{http_code}"), url});
}

// The key block proposal draws from is leader.wallet.funding_pk, which the module
// assigns separately from the wallet key (logos-blockchain#3271). Read it from the
// generated node config so the faucet can fund it. Empty if no config is found yet.
QString LogosNode1clickBackend::leaderFundingKey() const
{
    // Candidate configs, most-specific first: the path we generated, an explicitly
    // set userConfig, then the module's per-instance persistence dirs (generate_user_config
    // with use_persistence_paths writes user_config.yaml there).
    QStringList candidates;
    if (!generatedUserConfigPath().isEmpty()) candidates << generatedUserConfigPath();
    if (!userConfig().isEmpty())              candidates << userConfig();
    const QString dataHome = QString::fromUtf8(qgetenv("XDG_DATA_HOME"));
    const QString base = dataHome.isEmpty()
        ? QDir::homePath() + QStringLiteral("/.local/share") : dataHome;
    const QDir md(base + QStringLiteral("/Logos/LogosBasecamp/module_data/blockchain_module"));
    const QFileInfoList insts =
        md.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time);
    for (const QFileInfo& inst : insts)
        candidates << inst.absoluteFilePath() + QStringLiteral("/user_config.yaml");

    static const QRegularExpression hexRe(QStringLiteral("[0-9a-fA-F]{64}"));
    for (const QString& path : candidates) {
        QFile f(path);
        if (!f.exists() || !f.open(QIODevice::ReadOnly)) continue;
        const QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
        f.close();
        // Mirror the proven approach: enter the `leader:` block, take the first
        // `funding_pk:` after it — that is the key proposal draws from.
        bool inLeader = false;
        for (const QString& line : lines) {
            const QString t = line.trimmed();
            if (t.startsWith(QStringLiteral("leader:"))) { inLeader = true; continue; }
            if (inLeader && t.startsWith(QStringLiteral("funding_pk:"))) {
                const auto m = hexRe.match(t);
                if (m.hasMatch()) return m.captured(0);
            }
        }
    }
    return QString();
}

void LogosNode1clickBackend::setError(const QString& message)
{
    // If the SDK handed us the opaque no-reply string, ask the node's log why.
    QString honest = message;
    if (message.contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
        const QString real = lastNodeError();
        if (!real.isEmpty())
            honest = real;
    }
    setLastErrorMessage(honest);
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

LogosNode1clickBackend::LogosNode1clickBackend(QObject* parent)
    : BlockchainBackendSimpleSource(parent)
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

}

// Universal ui_qml lifecycle hook (interface: universal). modules() is live here;
// modules().api is the raw LogosAPI the codegen glue built from the host.
void LogosNode1clickBackend::onContextReady()
{
    m_blockchainClient = modules().api->getClient(BLOCKCHAIN_MODULE_NAME);
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        qWarning() << "LogosNode1clickBackend: failed to get blockchain module client";
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

    qDebug() << "LogosNode1clickBackend: initialized";
}

LogosNode1clickBackend::~LogosNode1clickBackend()
{
    if (status() == Running || status() == Starting)
        stopBlockchain();
}

QVariantMap LogosNode1clickBackend::claimLeaderRewards()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "leader_claim")));
}

QVariantMap LogosNode1clickBackend::getCryptarchiaInfo()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_cryptarchia_info")));
    // The Consensus view polls this; swap the opaque no-reply string for the
    // node's real reason (crash / recovering / storage / peers) from its log.
    if (!r.success
        && r.error.toString().contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
        const QString real = lastNodeError();
        if (!real.isEmpty())
            r.error = real;
    }
    return result::toVariantMap(r);
}

QVariantMap LogosNode1clickBackend::getNetworkInfo()
{
    QVariantMap out;
    out.insert(QStringLiteral("peers"), -1);
    out.insert(QStringLiteral("connections"), -1);
    QProcess p;
    p.start(QStringLiteral("curl"),
            {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("3"),
             QStringLiteral("http://127.0.0.1:8080/network/info")});
    if (!p.waitForFinished(4000)) { p.kill(); return out; }
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput());
    if (!doc.isObject())
        return out;
    const QJsonObject o = doc.object();
    int peers = -1;
    if (o.contains(QStringLiteral("n_peers")))
        peers = o.value(QStringLiteral("n_peers")).toInt();
    else if (o.contains(QStringLiteral("connected_peers")))
        peers = o.value(QStringLiteral("connected_peers")).toArray().size();
    out.insert(QStringLiteral("peers"), peers);
    out.insert(QStringLiteral("connections"),
               o.contains(QStringLiteral("n_connections"))
                   ? o.value(QStringLiteral("n_connections")).toInt()
                   : peers);
    return out;
}

QVariantMap LogosNode1clickBackend::getBlock(QString headerIdHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_block"), headerIdHex.trimmed())));
}

QVariantMap LogosNode1clickBackend::getTransaction(QString txHashHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_transaction"), txHashHex.trimmed())));
}

QVariantMap LogosNode1clickBackend::findTransactionInBlocks(QString txHashHex)
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

QVariantMap LogosNode1clickBackend::getPeerId()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    // Derived from the node key in the user config; available without the node
    // running.
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_peer_id"), userConfig())));
}

QVariantMap LogosNode1clickBackend::getClaimableVouchers()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("wallet_get_claimable_vouchers"))));
}

// Blocks THIS node proposed, parsed from the node's own log. Cryptarchia leadership
// is private (each block's leader_key is per-note-derived, not a stable identity), so
// an on-chain leader_key match can't identify our blocks — but the node LOGS every block
// it produces ("proposed block HeaderId(<id>) with <n> transactions (<m> removed)"), which
// is authoritative. Same source the logos-node-dashboard uses. Returns {success, value:[…]}.
QVariantMap LogosNode1clickBackend::getProposals()
{
    QVariantList out;
    QStringList seenIds;
    const QString cfg = userConfig();
    if (!cfg.isEmpty()) {
        const QDir logsDir(QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("logs")));
        if (logsDir.exists()) {
            const QFileInfoList files = logsDir.entryInfoList(QDir::Files, QDir::Time);   // newest first
            static const QRegularExpression tsRe(
                QStringLiteral("(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})"));
            static const QRegularExpression propRe(QStringLiteral(
                "proposed block HeaderId\\(([0-9a-f]+)\\) with (\\d+) transactions \\((\\d+) removed\\)"));
            int scannedFiles = 0;
            for (const QFileInfo& fi : files) {
                if (scannedFiles++ >= 4) break;                 // newest few files
                QFile f(fi.absoluteFilePath());
                if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
                const qint64 tail = qMin<qint64>(f.size(), 1024 * 1024);
                f.seek(f.size() - tail);
                const QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
                f.close();
                for (const QString& ln : lines) {
                    const auto m = propRe.match(ln);
                    if (!m.hasMatch()) continue;
                    const QString id = m.captured(1);
                    if (seenIds.contains(id)) continue;
                    seenIds << id;
                    QVariantMap p;
                    p.insert(QStringLiteral("id"), id);
                    p.insert(QStringLiteral("txs"), m.captured(2).toInt());
                    p.insert(QStringLiteral("removed"), m.captured(3).toInt());
                    const auto tm = tsRe.match(ln);
                    p.insert(QStringLiteral("time"),
                             tm.hasMatch() ? QString(tm.captured(1)).replace(QLatin1Char('T'), QLatin1Char(' '))
                                           : QString());
                    out.append(p);
                }
            }
        }
    }
    // newest first (ISO timestamps sort lexically); cap the list
    std::sort(out.begin(), out.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("time")).toString()
             > b.toMap().value(QStringLiteral("time")).toString();
    });
    while (out.size() > 100) out.removeLast();
    // value is a JSON string (same convention as getCryptarchiaInfo / getClaimableVouchers).
    const QString json = QString::fromUtf8(
        QJsonDocument(QJsonArray::fromVariantList(out)).toJson(QJsonDocument::Compact));
    QVariantMap res;
    res.insert(QStringLiteral("success"), true);
    res.insert(QStringLiteral("value"), json);
    return res;
}

// The node picks IBD download sources from bootstrap.ibd.peers — a list of bare
// peer-IDs, SEPARATE from initial_peers (multiaddrs). The module's
// generate_user_config only fills initial_peers, so ibd.peers stays empty and
// the node logs "Skipping IBD as no peers configured" and never syncs. Derive
// the peer-IDs from the config's own initial_peers and fill an empty ibd.peers
// in place, right before start (covers both generate and set-path flows).
static void injectIbdPeersFromInitialPeers(const QString& configPath)
{
    if (configPath.isEmpty())
        return;
    QFile f(configPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    QString cfg = QString::fromUtf8(f.readAll());
    f.close();

    // Only fill an empty ibd.peers list; leave a user-populated one untouched.
    static const QRegularExpression emptyIbd(
        QStringLiteral("(\\n[ \\t]*ibd:\\n([ \\t]*)peers:)[ \\t]*\\[\\]"));
    const QRegularExpressionMatch m = emptyIbd.match(cfg);
    if (!m.hasMatch())
        return;

    // Peer-IDs = substring after the last "/p2p/" in each initial_peers entry.
    static const QRegularExpression p2p(QStringLiteral("/p2p/([A-Za-z0-9]+)"));
    QStringList ids;
    QRegularExpressionMatchIterator it = p2p.globalMatch(cfg);
    while (it.hasNext()) {
        const QString id = it.next().captured(1);
        if (!ids.contains(id))
            ids.append(id);
    }
    if (ids.isEmpty())
        return;

    const QString indent = m.captured(2);  // indentation of the "peers:" line
    QString repl = m.captured(1) + QLatin1Char('\n');
    for (const QString& id : ids)
        repl += indent + QStringLiteral("- ") + id + QLatin1Char('\n');
    repl.chop(1);  // trim trailing newline so the next key stays put

    cfg.replace(m.capturedStart(), m.capturedLength(), repl);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        f.write(cfg.toUtf8());
        f.close();
    }
}

void LogosNode1clickBackend::startBlockchain()
{
    if (!m_blockchainClient) {
        setError(QStringLiteral("Module not initialized"));
        return;
    }

    setStatus(Starting);

    // Fill bootstrap.ibd.peers from initial_peers so IBD actually runs.
    injectIbdPeersFromInitialPeers(userConfig());

    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "start", userConfig(), deploymentConfig()));

    if (r.success) {
        setStatus(Running);
        QTimer::singleShot(500, this, [this]() { refreshAccounts(); });
    } else {
        // A no-reply / "Call failed" here usually means the node is still coming up
        // (a slow chain recovery outlives the RPC deadline), NOT a real failure.
        // Stay in Starting; the UI's liveness-confirm calls confirmRunning() once
        // the node's API answers, or confirmStartFailed() if it never does.
        qWarning() << "startBlockchain: start RPC returned no success ("
                   << r.error.toString() << ") — awaiting liveness confirm";
    }
}

void LogosNode1clickBackend::stopBlockchain()
{
    // Attempt the stop from any live-ish state (including Error) so an
    // errored-but-still-running node actually gets stopped and releases its DB —
    // the error-recovery wipe relies on this. Only skip when already fully down.
    if (status() == Stopped || status() == NotStarted)
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

void LogosNode1clickBackend::refreshAccounts()
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

    // Expose the node's primary public key (hex) for the faucet + the dashboard
    // balance tile (issue #22). First known address = the node's account key.
    setPrimaryAddress(list.isEmpty() ? QString() : list.first());

    QTimer::singleShot(0, this,
                       [this, list]() { fetchBalancesForAccounts(list); });
}

void LogosNode1clickBackend::fetchBalancesForAccounts(const QStringList& list)
{
    if (!m_blockchainClient) return;
    for (const QString& address : list) {
        if (address.isEmpty()) continue;
        getBalance(address);
    }
}

QVariantMap LogosNode1clickBackend::getBalance(QString addressHex)
{
    const LogosResult lr = m_blockchainClient
        ? result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
              BLOCKCHAIN_MODULE_NAME, "wallet_get_balance", addressHex))
        : result::err(QStringLiteral("Module not initialized."));

    m_accountsModel->setBalanceForAddress(addressHex, result::toDisplayMessage(lr));
    return result::toVariantMap(lr);
}

QVariantMap LogosNode1clickBackend::transferFunds(
    QString fromKeyHex, QString toKeyHex, QString amountStr)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    QStringList senders{fromKeyHex};
    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_transfer_funds",
        fromKeyHex, senders, toKeyHex, amountStr, QString())));
}

QVariantMap LogosNode1clickBackend::generateConfig(
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

QVariantMap LogosNode1clickBackend::getNotes(QString walletAddressHex, QString optionalTipHex)
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    return result::toVariantMap(result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, "wallet_get_notes",
        walletAddressHex, optionalTipHex)));
}

QVariantMap LogosNode1clickBackend::channelDepositWithNotes(
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

void LogosNode1clickBackend::clearBlocks()
{
    m_blockModel->clear();
}

QVariantMap LogosNode1clickBackend::resetChainState()
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

void LogosNode1clickBackend::copyToClipboard(QString text)
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
