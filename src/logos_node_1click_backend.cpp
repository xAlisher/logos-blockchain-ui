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
#include <QJsonValue>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QProcessEnvironment>
#include <QSettings>
#include <QSignalBlocker>
#include <QTimer>
#include <QUrl>
#include <QVariant>

#include <algorithm>

const QString LogosNode1clickBackend::BLOCKCHAIN_MODULE_NAME =
    QStringLiteral("blockchain_module");

// Shared, persisted binary intent — the SAME QSettings key node-remote uses, so a
// Start/Stop from the phone (node-remote) and from this desktop UI are visible to each
// other. See node-remote node_probe.cpp readIntent()/writeIntent() and issue #40. Only
// Start/Stop is a user command; every richer state is node-driven and observed.
// Defined here (above getCryptarchiaInfo, which reads it) so it is in scope file-wide.
static void writeNodeIntent(const QString& v)
{
    QSettings s(QStringLiteral("Logos"), QStringLiteral("BlockchainUI"));
    if (s.value(QStringLiteral("nodeIntent")).toString() == v) return;   // no write churn
    s.setValue(QStringLiteral("nodeIntent"), v);
}

static QString readNodeIntent()
{
    return QSettings(QStringLiteral("Logos"), QStringLiteral("BlockchainUI"))
        .value(QStringLiteral("nodeIntent")).toString();
}

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


// ── Spawning system curl safely ───────────────────────────────────────────────────
//
// Two separate failure modes produced the same misleading "curl unavailable":
//
// 1. PATH. QProcess::start("curl") resolves through PATH, and a GUI-launched app does not
//    inherit a login shell's PATH. curl ships with macOS (/usr/bin/curl) and with every
//    mainstream desktop Linux, so "not found" here almost always means "not on OUR path",
//    not "not installed".
//
// 2. THE APPIMAGE LOADER VARS — the documented trap (basecamp-skills:
//    appimage-child-ld-library-path). The AppImage exports LD_LIBRARY_PATH pointing at its
//    bundled libs; a spawned SYSTEM binary resolves its libraries against the bundle and
//    dies at startup on a version mismatch. The skill notes this is "easy to mislabel"
//    because the only signal is an immediate exit — which is exactly what happened: the
//    user saw "curl unavailable" for a curl that was installed and working.
//
// So: resolve an ABSOLUTE path, and hand the child a sanitized environment.
static QString resolveCurl()
{
    // PATH first — respects a deliberately installed newer curl.
    const QString onPath = QStandardPaths::findExecutable(QStringLiteral("curl"));
    if (!onPath.isEmpty()) return onPath;

    // Then the standard locations, so a stripped PATH is not mistaken for a missing curl.
    for (const QString& c : {QStringLiteral("/usr/bin/curl"),      // macOS + most Linux
                             QStringLiteral("/bin/curl"),
                             QStringLiteral("/opt/homebrew/bin/curl"),  // macOS arm64 brew
                             QStringLiteral("/usr/local/bin/curl")}) {  // macOS intel brew
        if (QFileInfo::exists(c)) return c;
    }
    return QString();
}

// Strip the loader variables so a system binary links against the SYSTEM libraries.
static QProcessEnvironment curlEnv()
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    for (const char* v : {"LD_LIBRARY_PATH", "LD_PRELOAD",
                          "DYLD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES",
                          "QT_PLUGIN_PATH", "QML2_IMPORT_PATH"})
        env.remove(QString::fromLatin1(v));
    return env;
}

// Shown only when curl is genuinely absent — which on macOS means someone removed a system
// binary, and on Linux means a minimal install.
static QString curlMissingMessage()
{
#if defined(Q_OS_MACOS)
    return QStringLiteral("curl was not found. macOS ships it at /usr/bin/curl — if it is "
                          "missing, install it with:  brew install curl");
#else
    return QStringLiteral("curl was not found. Install it with:  sudo apt install curl  "
                          "(Debian/Ubuntu),  sudo dnf install curl  (Fedora),  or  "
                          "sudo pacman -S curl  (Arch).");
#endif
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
            emit faucetResult(false, QStringLiteral("Couldn't run the faucet request — curl failed to start."));
        proc->deleteLater();
    });
    const QString curlBin = resolveCurl();
    if (curlBin.isEmpty()) {
        if (userFacing)
            emit faucetResult(false, curlMissingMessage());
        proc->deleteLater();
        return;
    }
    proc->setProcessEnvironment(curlEnv());
    proc->start(curlBin,
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
    // A node the user asked to stop CANNOT be in error. Guarding here rather than at each
    // call site because every path funnels through setError(), and fixing them one at a
    // time is what let this survive two rounds: getCryptarchiaInfo was demoted to Stopped,
    // then confirmStartFailed() — the start-liveness poll, which keeps running after a
    // stop — called setError() and put it straight back to Error. The result was a red
    // panel reading "Error:" with no message at all, because the text had been cleared but
    // the STATE had not.
    //
    // Stopped is an existing, correct state in this UI. Use it.
    if (readNodeIntent() == QLatin1String("stopped")) {
        setLastErrorMessage(QString());
        setStatus(Stopped);
        return;
    }

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

    const LogosResult lr = result::toLogosResult(
        m_blockchainClient->invokeRemoteMethod(BLOCKCHAIN_MODULE_NAME, "leader_claim"));

    // Write-ahead. The node logs nothing for a claim, so if we do not record the
    // tx hash here, no evidence this press happened exists anywhere on the machine.
    if (lr.success)
        recordClaimSubmission(lr.value.toString().trimmed());

    return result::toVariantMap(lr);
}

QVariantMap LogosNode1clickBackend::getCryptarchiaInfo()
{
    if (!m_blockchainClient)
        return result::toVariantMap(result::err(QStringLiteral("Module not initialized.")));

    LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_cryptarchia_info")));
    // Two different jobs on a failed call, and the intent one must NOT be nested inside
    // the "Call failed" test — that was the bug. blockchain_module answers a stopped node
    // with "The node is not running.", which does not contain "Call failed", so the whole
    // block was skipped and the dashboard kept a red error for a deliberate stop.
    if (!r.success) {
        if (readNodeIntent() == QLatin1String("stopped")) {
            // Coherent propagation (#40): the API is down and the SHARED intent says the
            // user stopped it — e.g. from the phone. Whatever words the failure used, this
            // is a stop, not a fault.
            //
            // Error is in the demote list DELIBERATELY: by the time a phone-initiated stop
            // lands, this UI has usually already set Error from the failing poll, and
            // without Error the demote never fires — the control stays on "Stop node
            // before closing Basecamp" for a node that is not running.
            if (status() == Running || status() == Starting
                || status() == Stopping || status() == Error)
                setStatus(Stopped);

            // Clearing the status is not enough on its own: NodeDashboardView's
            // _statusDisplay() renders errorText AHEAD of the status, so a stale error line
            // survives the demote and keeps describing the stop as a failure.
            r.error = QString();
        } else if (r.error.toString().contains(QStringLiteral("Call failed"), Qt::CaseInsensitive)) {
            // Expected up. Swap the opaque no-reply string for the node's real reason
            // (crash / recovering / storage / peers) from its own log.
            const QString real = lastNodeError();
            if (!real.isEmpty())
                r.error = real;
        }
    }
    return result::toVariantMap(r);
}

// After an unclean restart the node replays every stored block from LIB (genesis
// during ProlongedBootstrap) to the tip — "chain recovery" — which can take a couple
// of minutes and during which the chain API isn't serving state yet. We surface it so
// the dashboard shows "Recovering chain — replaying N blocks…" instead of a bare peer
// id. Log signatures (chain::service, verbatim):
//   "found <N> stored blocks to replay during chain recovery"   → replaying (active)
//   "<N> blocks replayed. Chain recovery finished"              → done (not active)
// Walk the newest log tail newest→oldest: the first marker we hit decides current state.
QVariantMap LogosNode1clickBackend::getRecoveryStatus()
{
    QVariantMap out;
    out.insert(QStringLiteral("active"), false);
    out.insert(QStringLiteral("blocks"), 0);
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return out;
    const QDir logsDir(QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("logs")));
    if (!logsDir.exists())
        return out;
    const QFileInfoList files = logsDir.entryInfoList(QDir::Files, QDir::Time);   // newest first
    if (files.isEmpty())
        return out;
    QFile f(files.first().absoluteFilePath());
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return out;
    const qint64 tail = qMin<qint64>(f.size(), 256 * 1024);
    f.seek(f.size() - tail);
    const QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
    f.close();
    static const QRegularExpression reFound(
        QStringLiteral("found (\\d+) stored blocks to replay"));
    for (int i = lines.size() - 1; i >= 0; --i) {
        const QString& ln = lines.at(i);
        // A completion is the most recent marker → recovery is done.
        if (ln.contains(QStringLiteral("Chain recovery finished"))
            || ln.contains(QStringLiteral("blocks replayed")))
            return out;
        // A start with no later completion → replaying right now.
        const QRegularExpressionMatch m = reFound.match(ln);
        if (m.hasMatch()) {
            out.insert(QStringLiteral("active"), true);
            out.insert(QStringLiteral("blocks"), m.captured(1).toInt());
            return out;
        }
    }
    return out;
}

QVariantMap LogosNode1clickBackend::getNetworkInfo()
{
    QVariantMap out;
    out.insert(QStringLiteral("peers"), -1);
    out.insert(QStringLiteral("connections"), -1);
    QProcess p;
    p.setProcessEnvironment(curlEnv());
    p.start(resolveCurl(),
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

// Blend network status, split across two honest sources (the app's Qt/QML HTTPS
// stack is unreliable on this AppImage, so we shell out to curl — see getNetworkInfo).
//   getBlendInfo()      — the live /blend/info API (only answers once Online; core_info
//                          is present ONLY when this node is a Core/full Blend node).
//   blendStateFromLog() — the blend::service log lifecycle, the authoritative signal
//                          during sync (the API hangs while Bootstrapping).
// Every string below is verbatim from the node's own output — no invented codes.
QVariantMap LogosNode1clickBackend::getBlendInfo() const
{
    QVariantMap out;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("coreInfoPresent"), false);
    out.insert(QStringLiteral("mixPeers"), -1);
    QProcess p;
    p.setProcessEnvironment(curlEnv());
    p.start(resolveCurl(),
            {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("3"),
             QStringLiteral("http://127.0.0.1:8080/blend/info")});
    if (!p.waitForFinished(4000)) { p.kill(); return out; }
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput());
    if (!doc.isObject())
        return out;
    const QJsonObject o = doc.object();
    out.insert(QStringLiteral("ok"), true);
    const QJsonValue ci = o.value(QStringLiteral("core_info"));
    if (ci.isObject()) {
        out.insert(QStringLiteral("coreInfoPresent"), true);
        out.insert(QStringLiteral("mixPeers"),
                   ci.toObject().value(QStringLiteral("current_epoch_peers")).toArray().size());
    }
    return out;
}

// Scan the tail of the newest node log for the blend::service lifecycle and map
// it to a BlendStatus, setting *outEvent to a plain-language line about the
// current epoch. Newest-first, first match wins — order: error, broadcast
// fallback, edge-joined, waiting-for-online. Returns Unknown if nothing matches.
LogosNode1clickBackend::BlendStatus
LogosNode1clickBackend::blendStateFromLog(QString* outEvent) const
{
    if (outEvent)
        outEvent->clear();
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return Unknown;
    const QDir logsDir(QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("logs")));
    if (!logsDir.exists())
        return Unknown;
    const QFileInfoList files = logsDir.entryInfoList(QDir::Files, QDir::Time);  // newest first
    if (files.isEmpty())
        return Unknown;
    // Blend lifecycle lines are written ONCE (at the Online transition / an epoch
    // boundary), and the node rotates its log hourly — so the current file often
    // has no blend line at all. Scan the newest few files, newest-first, and
    // return the most recent signature found.
    const int maxFiles = qMin(6, static_cast<int>(files.size()));
    for (int fi = 0; fi < maxFiles; ++fi) {
        QFile f(files.at(fi).absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        const qint64 tail = qMin<qint64>(f.size(), 512 * 1024);
        f.seek(f.size() - tail);
        const QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
        f.close();
        for (int i = lines.size() - 1; i >= 0; --i) {
            const QString& ln = lines.at(i);
            // Blend/SDP failure — surface the node's own message verbatim (no stable code exists).
            if (ln.contains(QStringLiteral("Failed to join blend network"))
                || (ln.contains(QStringLiteral("SDP service")) && ln.contains(QStringLiteral("channel closed")))) {
                if (outEvent)
                    *outEvent = ln.section(QStringLiteral("] "), -1).trimmed();
                return BlendError;
            }
            // Too few core nodes this epoch → the edge service shuts down and the node
            // broadcasts directly. Graceful fallback, not a failure.
            if (ln.contains(QStringLiteral("does not satisfy edge node condition"))) {
                if (outEvent)
                    *outEvent = QStringLiteral("too few Blend nodes this epoch, no privacy");
                return Broadcast;
            }
            // Participating as an edge node — proposals are mixed through the core nodes.
            if (ln.contains(QStringLiteral("Blend edge swarm started"))
                || ln.contains(QStringLiteral("Service 'BlendEdge' is ready"))
                || ln.contains(QStringLiteral("Service 'Blend' is ready"))) {
                if (outEvent)
                    *outEvent = QStringLiteral("your proposals are being mixed");
                return Edge;
            }
            // Still bootstrapping — Blend can't start until the chain is Online.
            if (ln.contains(QStringLiteral("Waiting for chain to become Online"))) {
                if (outEvent)
                    *outEvent = QStringLiteral("waiting for the node to reach Online");
                return WaitingForOnline;
            }
        }
    }
    return Unknown;
}

// Node consensus mode from the live API ("Online" / "Bootstrapping" / "" if the
// API doesn't answer). The authoritative "is Blend even possible yet" signal —
// Blend can't run until the chain is Online, and the log alone can't be trusted
// (the lifecycle line rotates out). Same curl path as getBlendInfo (the app's
// Qt/QML HTTPS stack is unreliable on this AppImage).
QString LogosNode1clickBackend::nodeMode() const
{
    QProcess p;
    p.setProcessEnvironment(curlEnv());
    p.start(resolveCurl(),
            {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("3"),
             QStringLiteral("http://127.0.0.1:8080/cryptarchia/info")});
    if (!p.waitForFinished(4000)) { p.kill(); return {}; }
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput());
    if (!doc.isObject())
        return {};
    const QJsonObject o = doc.object();
    const QJsonObject ci = o.value(QStringLiteral("cryptarchia_info")).toObject();
    if (ci.contains(QStringLiteral("state")))
        return ci.value(QStringLiteral("state")).toString();
    return o.value(QStringLiteral("state")).toString();
}

// Recompute blendStatus + lastBlendEvent from the node state, the blend log, and
// (once past bootstrap) the live /blend/info. Called on the dashboard's refresh
// timer while the node is Running. Cheap: one log-tail read + at most one curl.
void LogosNode1clickBackend::refreshBlendStatus()
{
    BlendStatus st = Unknown;
    QString evt;
    const BlockchainStatus ns = status();
    if (ns == Error) {
        st = NodeError;
        evt = lastNodeError();
    } else if (ns != Running) {
        st = Off;
    } else {
        // Drive off the live node mode, not the log alone: Blend can't run until
        // the chain is Online, and once Online a normal node is an EDGE node
        // automatically (edge/broadcast leave no line in the current log after
        // rotation). The log is used only to override with Core/Broadcast/Error.
        const QString mode = nodeMode();
        if (mode != QLatin1String("Online")) {
            // Bootstrapping, or the API isn't answering yet → not blending.
            st = WaitingForOnline;
            evt = QStringLiteral("waiting for the node to reach Online");
        } else {
            const QVariantMap bi = getBlendInfo();
            if (bi.value(QStringLiteral("ok")).toBool()
                && bi.value(QStringLiteral("coreInfoPresent")).toBool()) {
                // Positive proof of a Core (full) Blend node.
                st = Core;
                const int mp = bi.value(QStringLiteral("mixPeers")).toInt();
                evt = mp >= 0
                          ? QStringLiteral("%1 mix peers this epoch").arg(mp)
                          : QStringLiteral("mixing for the network");
            } else {
                // Online and not core → edge by default, unless this epoch fell back
                // to broadcast or blend errored (both leave a log line we can find).
                const BlendStatus fromLog = blendStateFromLog(&evt);
                if (fromLog == Broadcast || fromLog == BlendError) {
                    st = fromLog;   // evt already set from the log
                } else {
                    st = Edge;
                    evt = QStringLiteral("your proposals are being mixed");
                }
            }
        }
    }
    setBlendStatus(st);
    setLastBlendEvent(evt);
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

// ---------------------------------------------------------------------------
// Leader-claim ledger  (design: docs/VOUCHER-STATE-MAP.md)
//
// Unlike proposals — which the node logs, so getProposals() can always rebuild
// from the log — a claim leaves NO trace on this machine: `leader_claim` appears
// zero times in the Basecamp log while wallet_get_balance is written every 5s.
// So the row we write on press is write-ahead; miss it and there is no record
// the press ever happened. Settlement is the opposite: always recoverable from
// the chain, so an on-chain claim with no local row is backfilled as settled.
// ---------------------------------------------------------------------------

// Scan budget. get_blocks over IPC returns full block JSON (~1 MB per 10k slots
// on this chain), so each pass is bounded and the watermark advances until it
// catches up with LIB.
static constexpr int kScanChunkSlots = 8000;
// How far back the FIRST ever scan reaches. Not genesis: that is ~1M slots and
// tens of MB. The summary is labelled with historyFromSlot so a partial scan is
// never presented as a lifetime total.
static constexpr int kInitialLookbackSlots = 120000;
// A submitted claim not seen on chain this many finalized slots later is
// inferred expired (the node's reservation is evicted after security_param
// immutable blocks). Inference, not observation — the UI must say so.
static constexpr int kExpiryLookaheadSlots = 20000;
// Extra slots fetched past the chunk end purely to resolve the last in-range
// block's id from its successor's parent_block. Blocks are ~10-40 slots apart
// here, so this comfortably contains at least one successor.
static constexpr int kIdLookaheadSlots = 600;
static constexpr int kMaxClaimRows = 2000;
static constexpr int kMaxNoteValues = 4000;

// Read a slot field from a get_cryptarchia_info payload, tolerating BOTH shapes.
// The MODULE returns it flat ({lib_slot, slot, height, mode}); the node's own HTTP
// endpoint wraps it ({"cryptarchia_info":{…},"phase":…}). Reading only the wrapped
// form silently yields 0, which would disable the whole chain scan without any
// error — the same failure class this ledger exists to eliminate. CryptarchiaInfoView.qml
// already handles both; match it.
static int slotField(const QString& infoJson, const char* key)
{
    const QJsonObject o = QJsonDocument::fromJson(infoJson.toUtf8()).object();
    const QJsonObject inner = o.value(QStringLiteral("cryptarchia_info")).toObject();
    if (inner.contains(QLatin1String(key)))
        return inner.value(QLatin1String(key)).toInt();
    return o.value(QLatin1String(key)).toInt();
}

QString LogosNode1clickBackend::claimsStorePath() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return {};
    return QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("claims-history.json"));
}

QJsonObject LogosNode1clickBackend::loadClaimStore() const
{
    const QString p = claimsStorePath();
    if (p.isEmpty())
        return {};
    QFile f(p);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    return doc.isObject() ? doc.object() : QJsonObject{};
}

void LogosNode1clickBackend::saveClaimStore(const QJsonObject& store) const
{
    const QString p = claimsStorePath();
    if (p.isEmpty())
        return;
    // QSaveFile, NOT QFile+Truncate. Truncate empties the file on open(), so any reader
    // landing inside the write window sees zero bytes or a partial document — a real
    // window even with a single writer, because this runs on a 20s timer while other
    // processes (node_remote's /v1/rewards, a person with `cat`) read the same path.
    // QSaveFile writes a temporary beside the target and renames over it on commit, and
    // POSIX rename is atomic: a reader gets either the whole old file or the whole new
    // one. On failure it discards the temporary, so a full disk can no longer destroy the
    // ledger by truncating it and then failing to write.
    QSaveFile f(p);
    if (!f.open(QIODevice::WriteOnly))
        return;
    if (f.write(QJsonDocument(store).toJson(QJsonDocument::Compact)) < 0) {
        f.cancelWriting();
        return;
    }
    f.commit();
}

QString LogosNode1clickBackend::pendingClaimsPath() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return {};
    return QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("pending-claims.json"));
}

QJsonArray LogosNode1clickBackend::loadPendingClaims() const
{
    // Claims submitted from a paired phone, written by node_remote. We READ this file and
    // never write it: one writer per file is what makes the two modules safe to run
    // together without a lock. See node-remote/node_remote/src/pending_claims.h.
    //
    // ABSENT IS NORMAL AND MEANS NOTHING IS WRONG. Nobody is required to install
    // node_remote, and without it this returns empty and every path below behaves exactly
    // as it did before this existed.
    const QString p = pendingClaimsPath();
    if (p.isEmpty())
        return {};
    QFile f(p);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    if (!doc.isObject())
        return {};
    return doc.object().value(QStringLiteral("pending")).toArray();
}

QStringList LogosNode1clickBackend::ourClaimKeys() const
{
    QStringList keys;
    // The claim credits leader.wallet.funding_pk, which the module assigns to a
    // DIFFERENT key than the wallet key (ui#35) — so check that one first.
    const QString leader = leaderFundingKey();
    if (!leader.isEmpty())
        keys << leader.toLower();
    const QString primary = primaryAddress();
    if (!primary.isEmpty() && !keys.contains(primary.toLower()))
        keys << primary.toLower();
    return keys;
}

// Harvest {noteId: value} from a wallet_get_notes payload.
//
// The MODULE returns { "tip": "<hex>", "notes": [ {"id": "<hex>", "value": "<u64
// as string>"} ] } — an ARRAY, with the value stringified to avoid JSON number
// precision loss. The node's HTTP /wallet/<pk>/balance returns a {id: value} MAP
// instead; reading that shape here silently harvested nothing. (wallet_get_balance
// over IPC is a bare number string, not JSON at all — it is not a notes source.)
void LogosNode1clickBackend::rememberNoteValues(const QString& notesJson)
{
    const QJsonDocument doc = QJsonDocument::fromJson(notesJson.toUtf8());
    if (!doc.isObject())
        return;
    const QJsonArray notes = doc.object().value(QStringLiteral("notes")).toArray();
    if (notes.isEmpty())
        return;

    QJsonObject store = loadClaimStore();
    QJsonObject known = store.value(QStringLiteral("noteValues")).toObject();
    bool changed = false;
    for (const QJsonValue& nv : notes) {
        const QJsonObject n = nv.toObject();
        const QString id = n.value(QStringLiteral("id")).toString();
        if (id.isEmpty() || known.contains(id))
            continue;
        // Stored as a string upstream; keep it as a number for the fee arithmetic.
        known.insert(id, static_cast<double>(
                             n.value(QStringLiteral("value")).toString().toLongLong()));
        changed = true;
    }
    if (!changed)
        return;

    // Bounded: drop arbitrary entries once oversized rather than grow forever.
    // Losing an old note only costs us a "—" in a fee column.
    while (known.size() > kMaxNoteValues)
        known.erase(known.begin());

    store.insert(QStringLiteral("noteValues"), known);
    saveClaimStore(store);
}

void LogosNode1clickBackend::recordClaimSubmission(const QString& txHash)
{
    if (txHash.isEmpty())
        return;

    QJsonObject store = loadClaimStore();
    QJsonArray claims = store.value(QStringLiteral("claims")).toArray();

    // Idempotent: never double-record the same submission.
    for (const QJsonValue& v : claims)
        if (v.toObject().value(QStringLiteral("tx")).toString() == txHash)
            return;

    // Stamp the tip slot so an unlanded claim can later be aged out.
    int tipSlot = 0;
    if (m_blockchainClient) {
        const LogosResult info = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
            BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_cryptarchia_info")));
        if (info.success)
            tipSlot = slotField(info.value.toString(), "slot");
    }

    QJsonObject row;
    row.insert(QStringLiteral("tx"), txHash);
    row.insert(QStringLiteral("status"), QStringLiteral("submitted"));
    row.insert(QStringLiteral("submittedAt"),
               QDateTime::currentDateTime().toString(Qt::ISODate));
    row.insert(QStringLiteral("submittedAtSlot"), tipSlot);
    claims.prepend(row);

    store.insert(QStringLiteral("claims"), claims);
    saveClaimStore(store);
}

QVariantMap LogosNode1clickBackend::getLeaderClaims()
{
    // Harvest note values BEFORE reading the store, so the fee map is as fresh as
    // possible: a claim spends a note, and once spent it disappears from
    // wallet_get_notes forever. Whatever we have not seen by then is unpriceable.
    if (m_blockchainClient && status() == BlockchainStatus::Running) {
        for (const QString& key : ourClaimKeys()) {
            const LogosResult n = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
                BLOCKCHAIN_MODULE_NAME, QStringLiteral("wallet_get_notes"), key, QString()));
            if (n.success)
                rememberNoteValues(n.value.toString());
        }
    }

    QJsonObject store = loadClaimStore();
    QJsonArray claims = store.value(QStringLiteral("claims")).toArray();
    const QJsonObject noteValues = store.value(QStringLiteral("noteValues")).toObject();
    const QStringList ours = ourClaimKeys();

    // --- adopt claims submitted from a paired phone -----------------------
    // node_remote records a write-ahead row when someone claims from the phone, because
    // `leader_claim` leaves no other trace on this machine. Merging here — before
    // reconciliation, the fee backfill and the expiry aging — means such a row travels
    // every path below exactly as one this module wrote itself, so both surfaces show the
    // same claim in the same state within one poll.
    //
    // Empty when node_remote is not installed, which is the ordinary case and changes
    // nothing.
    QSet<QString> adoptedTxs;
    for (const QJsonValue& v : loadPendingClaims()) {
        const QJsonObject row = v.toObject();
        const QString tx = row.value(QStringLiteral("tx")).toString();
        if (tx.isEmpty())
            continue;
        bool known = false;
        for (const QJsonValue& c : claims)
            if (c.toObject().value(QStringLiteral("tx")).toString() == tx) { known = true; break; }
        if (known)
            continue;               // ours already; the ledger row is the better one
        adoptedTxs.insert(tx);
        claims.append(row);
    }

    // Index existing rows by tx so reconciliation and backfill share one path.
    QHash<QString, int> rowByTx;
    for (int i = 0; i < claims.size(); ++i)
        rowByTx.insert(claims.at(i).toObject().value(QStringLiteral("tx")).toString(), i);

    bool changed = false;
    int libSlot = 0;

    // Slot -> wall clock, so a backfilled row can be dated. A claim recovered from
    // the chain has no local record of when it was submitted; its block's slot is
    // the only timestamp that exists. get_time_info is flat here (verified against
    // the module source, not the HTTP endpoint — see docs/VOUCHER-STATE-MAP.md §7).
    qint64 genesisMs = 0;
    int slotMs = 0;
    if (m_blockchainClient && status() == BlockchainStatus::Running) {
        const LogosResult ti = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
            BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_time_info")));
        if (ti.success) {
            const QJsonObject o =
                QJsonDocument::fromJson(ti.value.toString().toUtf8()).object();
            genesisMs = static_cast<qint64>(
                o.value(QStringLiteral("genesis_time_unix_ms")).toDouble());
            slotMs = o.value(QStringLiteral("slot_duration_ms")).toInt();
        }
    }

    // --- reconcile forward from the watermark -----------------------------
    if (m_blockchainClient && status() == BlockchainStatus::Running && !ours.isEmpty()) {
        const LogosResult info = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
            BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_cryptarchia_info")));
        if (info.success)
            libSlot = slotField(info.value.toString(), "lib_slot");

        // One-time rescan when the scan logic changes. The first release advanced
        // the watermark even when get_blocks failed, so an existing store can
        // claim to have scanned a range it never actually read. Bump this
        // constant whenever a fix means past ranges must be re-examined; settled
        // rows are keyed by tx hash, so a rescan re-confirms rather than
        // duplicating them.
        constexpr int kScanVersion = 11;
        if (store.value(QStringLiteral("scanVersion")).toInt() < kScanVersion) {
            qInfo() << "getLeaderClaims: scan logic changed, rescanning from"
                    << store.value(QStringLiteral("historyFromSlot")).toInt();
            store.insert(QStringLiteral("lastScannedSlot"),
                         store.value(QStringLiteral("historyFromSlot")).toInt());
            store.insert(QStringLiteral("scanVersion"), kScanVersion);
            changed = true;
        }

        int from = store.value(QStringLiteral("lastScannedSlot")).toInt();
        if (from <= 0 && libSlot > 0) {
            from = qMax(0, libSlot - kInitialLookbackSlots);
            store.insert(QStringLiteral("historyFromSlot"), from);
            changed = true;
        }

        // Only ever settle from BELOW LIB. An above-LIB sighting is "in a block",
        // not final — so a reorg moves a row honestly backwards instead of
        // un-settling something we already called settled.
        const int to = qMin(libSlot, from + kScanChunkSlots);
        if (libSlot > 0 && to > from) {
            // Fetch a little past `to` so the last in-range block has a successor
            // whose parent_block gives us its id (see the chaining note below).
            // Blocks beyond `to` are used for that and nothing else.
            const int fetchTo = qMin(libSlot, to + kIdLookaheadSlots);
            const LogosResult blocks =
                result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
                    BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_blocks"),
                    QVariant(from + 1), QVariant(fetchTo)));

            int dbgBlocks = 0, dbgClaimOps = 0, dbgOurClaims = 0;
            int dbgEvents = 0, dbgEvFail = 0, dbgMatched = 0;
            QString dbgEvErr, dbgBadId, dbgHdrKeys;
            int dbgFeeMap = 0;
            QString dbgOpcodes, dbgTxKeys, dbgLedgerShape;
            if (blocks.success) {
                const QJsonArray rawArr =
                    QJsonDocument::fromJson(blocks.value.toString().toUtf8()).array();
                dbgBlocks = rawArr.size();

                // A block's ID is NOT a field: core/src/header/mod.rs `Header` holds
                // {version, parent_block, slot, body_root, proof_of_leadership} and
                // the ID is COMPUTED (hash over "BLOCK_ID_V1"). The node's HTTP DTO
                // adds an `id`, but get_blocks over IPC serialises the raw Block, so
                // there is none — reading header.id yielded "" and every
                // get_block_events call was rejected as "must be 64 hex characters".
                //
                // Recover it from the chain instead: for finalised blocks in slot
                // order, block[i]'s id is block[i+1]'s `parent_block`. We therefore
                // fetch a small lookahead past `to` purely to resolve the last
                // block's id, and only process blocks that have a successor.
                QList<QJsonObject> arr;
                arr.reserve(rawArr.size());
                for (const QJsonValue& v : rawArr)
                    arr.append(v.toObject());
                std::sort(arr.begin(), arr.end(),
                          [](const QJsonObject& a, const QJsonObject& b) {
                              return a.value(QStringLiteral("header")).toObject()
                                         .value(QStringLiteral("slot")).toInt()
                                   < b.value(QStringLiteral("header")).toObject()
                                         .value(QStringLiteral("slot")).toInt();
                          });

                for (int bi = 0; bi + 1 < arr.size(); ++bi) {
                    const QJsonObject b = arr.at(bi);
                    const QJsonObject hdr = b.value(QStringLiteral("header")).toObject();
                    // Blocks past `to` were fetched only to resolve ids; the
                    // watermark does not cover them yet.
                    if (hdr.value(QStringLiteral("slot")).toInt() > to)
                        continue;
                    const QString blockId = arr.at(bi + 1)
                                                .value(QStringLiteral("header")).toObject()
                                                .value(QStringLiteral("parent_block")).toString();
                    const QJsonArray txs = b.value(QStringLiteral("transactions")).toArray();

                    // Cheap pre-filter: does this block contain a LeaderClaim (0x30 = 48)
                    // credited to one of our keys? Only then pay for get_block_events.
                    // Keyed by VOUCHER NULLIFIER, not tx hash: `mantle_tx` over IPC
                    // carries only `ops` — there is NO `hash` field (the node's HTTP
                    // block DTO adds one). Keying by hash silently produced a map
                    // with a single ""-keyed entry, so every fee lookup missed and
                    // 16 settled claims showed "fee unknown". The nullifier appears
                    // in both the claim op and the LeaderRewardClaimed event.
                    QHash<QString, QPair<QString, qint64>> feeByNf;  // nf -> (inputNoteId, change)
                    bool anyOurs = false;
                    for (const QJsonValue& tv : txs) {
                        const QJsonObject mt =
                            tv.toObject().value(QStringLiteral("mantle_tx")).toObject();
                        const QJsonArray ops = mt.value(QStringLiteral("ops")).toArray();
                        bool isOurClaim = false;
                        QString claimNf;
                        QString inputNote;
                        qint64 change = -1;
                        for (const QJsonValue& ov : ops) {
                            const QJsonObject op = ov.toObject();
                            const QJsonObject pl = op.value(QStringLiteral("payload")).toObject();
                            const int code = op.value(QStringLiteral("opcode")).toInt(-1);
                            if (code == 48) {
                                ++dbgClaimOps;
                                claimNf = pl.value(QStringLiteral("voucher_nullifier")).toString();
                                if (ours.contains(pl.value(QStringLiteral("pk")).toString().toLower()))
                                    isOurClaim = true;
                            } else if (code == 0) {
                                const QJsonArray in = pl.value(QStringLiteral("inputs")).toArray();
                                const QJsonArray outs = pl.value(QStringLiteral("outputs")).toArray();
                                if (in.size() == 1)
                                    inputNote = in.at(0).toString();
                                if (outs.size() == 1)
                                    change = static_cast<qint64>(
                                        outs.at(0).toObject().value(QStringLiteral("value")).toDouble());
                            }
                        }
                        if (isOurClaim) {
                            anyOurs = true;
                            ++dbgOurClaims;
                            if (dbgOpcodes.isEmpty()) {
                                QStringList codes;
                                for (const QJsonValue& ov : ops)
                                    codes << QString::number(
                                        ov.toObject().value(QStringLiteral("opcode")).toInt(-1));
                                dbgOpcodes = codes.join(QLatin1Char(','));
                                dbgTxKeys = QStringList(mt.keys()).join(QLatin1Char(','));
                                for (const QJsonValue& ov : ops) {
                                    const QJsonObject op = ov.toObject();
                                    if (op.value(QStringLiteral("opcode")).toInt(-1) != 0) continue;
                                    const QJsonObject pl =
                                        op.value(QStringLiteral("payload")).toObject();
                                    dbgLedgerShape = QStringLiteral("plKeys=%1 in=%2 out=%3")
                                        .arg(QStringList(pl.keys()).join(QLatin1Char('|')))
                                        .arg(pl.value(QStringLiteral("inputs")).toArray().size())
                                        .arg(pl.value(QStringLiteral("outputs")).toArray().size());
                                }
                            }
                            if (!claimNf.isEmpty())
                                feeByNf.insert(claimNf, qMakePair(inputNote, change));
                        }
                    }
                    dbgFeeMap += feeByNf.size();
                    if (!anyOurs)
                        continue;

                    // The reward amount lives ONLY in the block's events — the claim
                    // op carries the nullifier but never the amount. blockId came
                    // from the successor's parent_block above.
                    const LogosResult ev =
                        result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
                            BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_block_events"), blockId));
                    if (!ev.success) {
                        // Do NOT skip silently — this is the step that was losing
                        // every settlement while the scan reported success.
                        if (dbgEvErr.isEmpty()) {
                            dbgEvErr = ev.error.toString();
                            // Capture the value we actually sent and the header's
                            // key set — guessing the shape has been wrong 4x today.
                            dbgBadId = blockId;
                            dbgHdrKeys = QStringList(hdr.keys()).join(QLatin1Char(','));
                        }
                        ++dbgEvFail;
                        continue;
                    }

                    const QJsonArray events =
                        QJsonDocument::fromJson(ev.value.toString().toUtf8()).array();
                    dbgEvents += events.size();
                    for (const QJsonValue& evv : events) {
                        const QJsonObject tx = evv.toObject().value(QStringLiteral("Tx")).toObject();
                        const QJsonObject claimed = tx.value(QStringLiteral("payload"))
                                                        .toObject()
                                                        .value(QStringLiteral("LeaderRewardClaimed"))
                                                        .toObject();
                        if (claimed.isEmpty())
                            continue;
                        const QJsonObject note =
                            claimed.value(QStringLiteral("utxo")).toObject()
                                   .value(QStringLiteral("note")).toObject();
                        if (!ours.contains(note.value(QStringLiteral("pk")).toString().toLower()))
                            continue;

                        ++dbgMatched;
                        const QString txHash = tx.value(QStringLiteral("tx_hash")).toString();
                        const qint64 reward =
                            static_cast<qint64>(note.value(QStringLiteral("value")).toDouble());

                        QJsonObject row = rowByTx.contains(txHash)
                            ? claims.at(rowByTx.value(txHash)).toObject()
                            : QJsonObject{{QStringLiteral("tx"), txHash},
                                          // no local row: this claim predates the ledger
                                          // (or came from another machine). Say so.
                                          {QStringLiteral("backfilled"), true}};

                        row.insert(QStringLiteral("status"), QStringLiteral("settled"));
                        const int settledSlot = hdr.value(QStringLiteral("slot")).toInt();
                        row.insert(QStringLiteral("slot"), settledSlot);
                        row.insert(QStringLiteral("block"), blockId);
                        // Date it from the block's slot. Without this a backfilled
                        // row renders with an empty timestamp, which is why the
                        // ledger looked unsorted.
                        if (genesisMs > 0 && slotMs > 0) {
                            row.insert(QStringLiteral("settledAt"),
                                       QDateTime::fromMSecsSinceEpoch(
                                           genesisMs + static_cast<qint64>(settledSlot) * slotMs)
                                           .toString(Qt::ISODate));
                        }
                        row.insert(QStringLiteral("voucherNf"),
                                   claimed.value(QStringLiteral("voucher_nullifier")).toString());
                        row.insert(QStringLiteral("reward"), reward);

                        // Fee = input note value − change output. The block gives only
                        // the input's ID, never its value, so pricing needs the harvested
                        // note map.
                        //
                        // RECORD THE INGREDIENTS, do not just compute. A block is scanned
                        // exactly once — the watermark then moves past it forever — so
                        // computing the fee here and discarding the inputs meant that if
                        // the note happened not to be in the map at that instant, the fee
                        // was unrecoverable even though the data arrived moments later.
                        // That is what left 15 settled claims with no fee while their
                        // input notes sat in the map. Storing the pair lets a later pass
                        // resolve it (see the back-fill below).
                        const auto fp = feeByNf.value(
                            claimed.value(QStringLiteral("voucher_nullifier")).toString());
                        if (!fp.first.isEmpty() && fp.second >= 0) {
                            row.insert(QStringLiteral("feeInput"), fp.first);
                            row.insert(QStringLiteral("feeChange"), fp.second);
                        }

                        if (rowByTx.contains(txHash)) {
                            claims.replace(rowByTx.value(txHash), row);
                        } else {
                            claims.prepend(row);
                            rowByTx.clear();
                            for (int i = 0; i < claims.size(); ++i)
                                rowByTx.insert(
                                    claims.at(i).toObject().value(QStringLiteral("tx")).toString(), i);
                        }
                        changed = true;
                    }
                }
            }

            // ONLY advance the watermark when the range was actually read. This
            // used to sit outside the success check, so a failing get_blocks
            // silently marked the range scanned and the watermark raced past real
            // claims that were never looked at — a silent skip path, and exactly
            // the class of bug this ledger exists to remove. Fail loudly, retry
            // the same range next pass.
            // Record scan health IN THE STORE, not just the log: this plugin runs
            // under ui-host, whose stderr Basecamp does not persist, so a log-only
            // diagnostic is invisible. A scan that reads nothing must not look
            // identical to a scan that found nothing:
            //   blocks=0 over a wide range  -> the range never arrived
            //   claimOps>0 with ours=0      -> matching against the wrong key
            QJsonObject scan;
            scan.insert(QStringLiteral("from"), from + 1);
            scan.insert(QStringLiteral("to"), to);
            scan.insert(QStringLiteral("ok"), blocks.success);
            scan.insert(QStringLiteral("blocks"), dbgBlocks);
            scan.insert(QStringLiteral("claimOps"), dbgClaimOps);
            scan.insert(QStringLiteral("ourClaims"), dbgOurClaims);
            scan.insert(QStringLiteral("keys"), ours.join(QLatin1Char(',')));
            scan.insert(QStringLiteral("events"), dbgEvents);
            scan.insert(QStringLiteral("eventsFailed"), dbgEvFail);
            scan.insert(QStringLiteral("matchedEvents"), dbgMatched);
            scan.insert(QStringLiteral("feeMapSize"), dbgFeeMap);
            if (!dbgOpcodes.isEmpty()) {
                scan.insert(QStringLiteral("opcodes"), dbgOpcodes);
                scan.insert(QStringLiteral("txKeys"), dbgTxKeys);
                scan.insert(QStringLiteral("ledgerShape"), dbgLedgerShape);
            }
            if (!dbgEvErr.isEmpty()) {
                scan.insert(QStringLiteral("eventsError"), dbgEvErr);
                scan.insert(QStringLiteral("badBlockId"), dbgBadId);
                scan.insert(QStringLiteral("badBlockIdLen"), dbgBadId.length());
                scan.insert(QStringLiteral("headerKeys"), dbgHdrKeys);
            }
            if (!blocks.success)
                scan.insert(QStringLiteral("error"), blocks.error.toString());
            store.insert(QStringLiteral("lastScan"), scan);
            changed = true;

            if (blocks.success) {
                store.insert(QStringLiteral("lastScannedSlot"), to);
                changed = true;
            } else {
                qWarning() << "getLeaderClaims: get_blocks(" << (from + 1) << "," << to
                           << ") failed:" << blocks.error.toString()
                           << "- watermark held at" << from;
            }
        }
    }

    // --- resolve any fee we now have the ingredients for -------------------
    // Runs every pass, not just when a block is first scanned, so a fee becomes
    // known as soon as its input note appears in the map — however long after
    // settlement that is.
    for (int i = 0; i < claims.size(); ++i) {
        QJsonObject row = claims.at(i).toObject();
        if (row.contains(QStringLiteral("fee")))
            continue;
        const QString in = row.value(QStringLiteral("feeInput")).toString();
        if (in.isEmpty() || !noteValues.contains(in))
            continue;
        const qint64 spent = static_cast<qint64>(noteValues.value(in).toDouble());
        const qint64 change = static_cast<qint64>(
            row.value(QStringLiteral("feeChange")).toDouble());
        if (spent >= change && change >= 0) {
            row.insert(QStringLiteral("fee"), spent - change);
            claims.replace(i, row);
            changed = true;
        }
    }

    // --- age out submissions that never landed ----------------------------
    // Inference, not observation: an unlanded claim produces nothing to see.
    if (libSlot > 0) {
        for (int i = 0; i < claims.size(); ++i) {
            QJsonObject row = claims.at(i).toObject();
            if (row.value(QStringLiteral("status")).toString() != QLatin1String("submitted"))
                continue;
            const int at = row.value(QStringLiteral("submittedAtSlot")).toInt();
            if (at > 0 && libSlot > at + kExpiryLookaheadSlots) {
                row.insert(QStringLiteral("status"), QStringLiteral("expired"));
                row.insert(QStringLiteral("inferred"), true);
                claims.replace(i, row);
                changed = true;
            }
        }
    }

    // Newest first. Rows arrive in two ways — prepended on submission, prepended
    // again as the chain scan discovers them — so insertion order interleaves
    // settled and pending arbitrarily. Order by the slot each row actually
    // happened at: its block slot once settled, otherwise the tip slot at
    // submission. Both are the same clock, so pending claims sort above older
    // settled ones, which is what a ledger should read like.
    {
        QList<QJsonObject> rows;
        rows.reserve(claims.size());
        for (const QJsonValue& v : claims)
            rows.append(v.toObject());
        const auto effSlot = [](const QJsonObject& r) {
            const int s = r.value(QStringLiteral("slot")).toInt();
            return s > 0 ? s : r.value(QStringLiteral("submittedAtSlot")).toInt();
        };
        std::stable_sort(rows.begin(), rows.end(),
                         [&](const QJsonObject& a, const QJsonObject& b) {
                             return effSlot(a) > effSlot(b);
                         });
        claims = QJsonArray();
        for (const QJsonObject& r : rows)
            claims.append(r);
    }

    while (claims.size() > kMaxClaimRows)
        claims.removeLast();

    if (changed) {
        // THE HANDOFF RULE. A merged row that is still `submitted` belongs to node_remote's
        // file — persisting it here would put the same claim in both files, and then each
        // side would keep re-adding what the other had already counted. Once reconciliation
        // has decided something about it (in a block, settled, or aged to expired) this
        // ledger adopts it permanently, and node_remote drops its copy on the next read
        // precisely because it now finds that tx here. One row, one owner, at every moment.
        QJsonArray persist;
        for (const QJsonValue& v : claims) {
            const QJsonObject r = v.toObject();
            if (adoptedTxs.contains(r.value(QStringLiteral("tx")).toString())
                && r.value(QStringLiteral("status")).toString() == QLatin1String("submitted"))
                continue;
            persist.append(r);
        }
        store.insert(QStringLiteral("claims"), persist);
        saveClaimStore(store);
    }

    // --- summary ----------------------------------------------------------
    qint64 claimed = 0, fees = 0;
    int settled = 0, inFlight = 0, feesKnown = 0;
    for (const QJsonValue& v : claims) {
        const QJsonObject r = v.toObject();
        const QString st = r.value(QStringLiteral("status")).toString();
        if (st == QLatin1String("settled")) {
            ++settled;
            claimed += static_cast<qint64>(r.value(QStringLiteral("reward")).toDouble());
            if (r.contains(QStringLiteral("fee"))) {
                fees += static_cast<qint64>(r.value(QStringLiteral("fee")).toDouble());
                ++feesKnown;
            }
        } else if (st == QLatin1String("submitted") || st == QLatin1String("in_block")) {
            ++inFlight;
        }
    }

    QJsonObject summary;
    summary.insert(QStringLiteral("settled"), settled);
    summary.insert(QStringLiteral("inFlight"), inFlight);
    summary.insert(QStringLiteral("claimed"), claimed);
    summary.insert(QStringLiteral("fees"), fees);
    // Net is only honest when every settled row has a known fee; otherwise the
    // UI must present it as a floor, not a total.
    summary.insert(QStringLiteral("feesComplete"), feesKnown == settled);
    summary.insert(QStringLiteral("net"), claimed - fees);
    summary.insert(QStringLiteral("historyFromSlot"),
                   store.value(QStringLiteral("historyFromSlot")).toInt());
    summary.insert(QStringLiteral("lastScannedSlot"),
                   store.value(QStringLiteral("lastScannedSlot")).toInt());
    summary.insert(QStringLiteral("libSlot"), libSlot);
    // True once the scan has caught up with LIB — until then the totals are partial.
    summary.insert(QStringLiteral("scanCaughtUp"),
                   libSlot > 0
                       && store.value(QStringLiteral("lastScannedSlot")).toInt() >= libSlot);

    QJsonObject out;
    out.insert(QStringLiteral("claims"), claims);
    out.insert(QStringLiteral("summary"), summary);

    QVariantMap res;
    res.insert(QStringLiteral("success"), true);
    res.insert(QStringLiteral("value"),
               QString::fromUtf8(QJsonDocument(out).toJson(QJsonDocument::Compact)));
    return res;
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

    // Durable store: proposals persist here so they SURVIVE the node's hourly log
    // pruning (a rotating log only retains ~10h, but leader wins are rarer than that,
    // so a log-only view loses history and flickers). Accumulate-only: we union the
    // stored history with a fresh log scan and write any newly-seen proposals back.
    const QString storePath = cfg.isEmpty() ? QString()
        : QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("proposals-history.json"));

    // 1) load persisted history first (these never expire)
    if (!storePath.isEmpty()) {
        QFile sf(storePath);
        if (sf.open(QIODevice::ReadOnly)) {
            const QJsonDocument doc = QJsonDocument::fromJson(sf.readAll());
            sf.close();
            if (doc.isArray()) {
                const QJsonArray arr = doc.array();
                for (const QJsonValue& v : arr) {
                    const QVariantMap m = v.toObject().toVariantMap();
                    const QString id = m.value(QStringLiteral("id")).toString();
                    if (id.isEmpty() || seenIds.contains(id)) continue;
                    seenIds << id;
                    out.append(m);
                }
            }
        }
    }

    // 2) scan the live logs and add any proposals not already stored
    bool changed = false;
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
                if (scannedFiles++ >= 240) break;               // bound work (logs rotate hourly)
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
                    changed = true;
                }
            }
        }
    }

    // newest first (ISO timestamps sort lexically); keep a generous durable cap
    std::sort(out.begin(), out.end(), [](const QVariant& a, const QVariant& b) {
        return a.toMap().value(QStringLiteral("time")).toString()
             > b.toMap().value(QStringLiteral("time")).toString();
    });
    while (out.size() > 500) out.removeLast();

    // 3) persist newly-seen proposals back to the durable store
    if (changed && !storePath.isEmpty()) {
        QFile sf(storePath);
        if (sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            sf.write(QJsonDocument(QJsonArray::fromVariantList(out)).toJson(QJsonDocument::Compact));
            sf.close();
        }
    }
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

    writeNodeIntent(QStringLiteral("started"));
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
    // Record intent first, so even the already-stopped early-return below leaves the
    // shared flag correct for the phone to read.
    writeNodeIntent(QStringLiteral("stopped"));

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
    } else if (r.error.toString().contains(QStringLiteral("not running"), Qt::CaseInsensitive)) {
        // The node was already down: "stop" reports it isn't running. Treat as reconciled
        // rather than an error, so we land in a known-stopped state from which Start is
        // safe again (avoids a stuck Error ⇄ "already running" loop).
        //
        // Carried over from Daniel's #45 when this file was renamed out from under it.
        // The intent guard in setError() happens to neutralise this case too — intent is
        // written "stopped" at the top of this function — but that is incidental, and a
        // reconcile this important should not depend on a guard somewhere else noticing.
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
        // RETRY. The node's API can be up before its WALLET is, so the single call fired
        // 500ms after confirmRunning() often lands too early — and this used to just return.
        // primaryAddress then stayed empty, and balanceTimer is gated on it being non-empty,
        // so the balance never appeared until something else happened to call this again.
        // That was the desktop's share of "balance arrives late after a start".
        //
        // Bounded: ~10 tries at 1.5s covers a slow wallet without spinning forever against
        // a node that genuinely has no accounts.
        if (m_accountRetries < 10) {
            ++m_accountRetries;
            QTimer::singleShot(1500, this, [this]() { refreshAccounts(); });
        }
        return;
    }
    m_accountRetries = 0;

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

    // Expose the node's primary public key (hex) for the faucet (issue #22).
    // NOTE: this is just the FIRST known address; the ordering carries no
    // guarantee, and it is NOT the key that proposes blocks or pays claim fees.
    setPrimaryAddress(list.isEmpty() ? QString() : list.first());

    // The operationally meaningful key: proposals draw from it, leader rewards
    // land in it, and a claim's fee comes out of it. Observed on this node as a
    // different key from primaryAddress with a different balance, which is why
    // the dashboard tile and the claim gate must both read THIS one.
    setLeaderKey(leaderFundingKey());

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
    // NOTE: wallet_get_balance returns a BARE NUMBER over IPC, not JSON — it
    // carries no note breakdown, so it is not a source for the fee map. Notes are
    // harvested from wallet_get_notes in getLeaderClaims() instead.
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
