#include "logos_node_1click_backend.h"
#include "BlendLifecycle.h"
#include "BlendRegistration.h"
#include "BlendIdentity.h"
#include "BlendLifecycleIO.h"
#include "BlendRecoverySnapshot.h"
#include <QScopedValueRollback>
#include "logos_sdk.h"
#include "logos_api.h"
#include "logos_api_client.h"

#include <QByteArray>
#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QHostAddress>
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
#include <QUdpSocket>
#include <QEventLoop>
#include <QRandomGenerator>
#include <QUrl>
#include <QVariant>

#include <algorithm>
#include <unistd.h>   // sysconf(_SC_CLK_TCK) for /proc CPU sampling (PREVIEW #65/#66)

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
    , m_spendableModel(new AccountsModel(this))
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

    if (!envConfigPath.isEmpty()) {
        setUserConfig(toLocalPath(envConfigPath));
    } else if (!savedUserConfig.isEmpty()) {
        // Only resume a SAVED path if it (and the keystore beside it) still exist
        // on disk. A stale userConfigPath — config/keys deleted but the setting
        // left behind — otherwise routes the UI straight to the node view and
        // auto-starts a keyless node instead of first-run onboarding (#15 regression:
        // "no keys must always mean onboarding"). If the files are gone, clear the
        // stale setting and fall through so userConfig stays empty → onboarding.
        const QString p  = toLocalPath(savedUserConfig);
        const QString ks = QFileInfo(p).absoluteDir().filePath(QStringLiteral("keystore.yaml"));
        if (QFile::exists(p) && QFile::exists(ks))
            setUserConfig(p);
        else
            s.remove(QStringLiteral("userConfigPath"));
    }

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

    // PREVIEW (#65/#66): sample the blockchain_module process for CPU%/RAM while the
    // node runs. Self-liquidates when the node exposes resource stats over the API.
    m_resourceTimer = new QTimer(this);
    m_resourceTimer->setInterval(2000);
    connect(m_resourceTimer, &QTimer::timeout, this, [this]() { sampleNodeResources(); });
    m_resourceTimer->start();

    // Backend-owned: navigation destroys QML cards, not this timer or its journal.
    ensureBlendRecovery();
    connect(this, &BlockchainBackendSimpleSource::userConfigChanged, this, [this]() { ensureBlendRecovery(); });
    m_blendRecoveryTimer = new QTimer(this);
    m_blendRecoveryTimer->setInterval(5000);
    connect(m_blendRecoveryTimer, &QTimer::timeout, this, [this]() { advanceBlendRecovery(); });
    m_blendRecoveryTimer->start();
}

// PREVIEW (#65/#66): locate the sibling blockchain_module host process by scanning
// /proc for a cmdline containing "--name blockchain_module". Cached; re-scanned when
// the cached pid disappears. Linux-only (returns -1 elsewhere → tiles show "—").
qint64 LogosNode1clickBackend::findBlockchainModulePid() const
{
    if (m_nodePid > 0 && QFile::exists(QStringLiteral("/proc/%1/cmdline").arg(m_nodePid)))
        return m_nodePid;
    QDir proc(QStringLiteral("/proc"));
    const QStringList pids = proc.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString& entry : pids) {
        bool ok = false;
        const qint64 pid = entry.toLongLong(&ok);
        if (!ok || pid <= 0) continue;
        QFile f(QStringLiteral("/proc/%1/cmdline").arg(pid));
        if (!f.open(QIODevice::ReadOnly)) continue;
        QByteArray cmd = f.readAll();
        f.close();
        if (cmd.contains("blockchain_module") && cmd.contains("--name"))
            return pid;
    }
    return -1;
}

// PREVIEW (#65/#66): compute CPU% (delta of utime+stime over the sample interval)
// and RSS from /proc/<pid>/{stat,status}. Empty strings when the node isn't running
// or /proc is unavailable → the tiles fall back to "—". Self-liquidates when the
// node exposes resource stats over its API.
void LogosNode1clickBackend::sampleNodeResources()
{
    if (status() != Running) {
        m_nodePid = -1; m_prevCpuTicks = 0; m_prevSampleMs = 0; m_diskSampleTick = 0;
        if (!cpuUsage().isEmpty()) setCpuUsage(QString());
        if (!ramUsage().isEmpty()) setRamUsage(QString());
        if (!diskUsage().isEmpty()) setDiskUsage(QString());
        return;
    }
    const qint64 pid = findBlockchainModulePid();
    if (pid <= 0) { setCpuUsage(QString()); setRamUsage(QString()); return; }
    m_nodePid = pid;

    // RSS from /proc/<pid>/status (VmRSS: N kB).
    QFile stt(QStringLiteral("/proc/%1/status").arg(pid));
    if (stt.open(QIODevice::ReadOnly)) {
        const QByteArray body = stt.readAll();
        stt.close();
        const QRegularExpression re(QStringLiteral("VmRSS:\\s+(\\d+)\\s+kB"));
        const auto m = re.match(QString::fromLatin1(body));
        if (m.hasMatch()) {
            const double rssKb = m.captured(1).toDouble();
            const double mb = rssKb / 1024.0;
            QString v = mb >= 1024.0 ? QStringLiteral("%1 GB").arg(mb / 1024.0, 0, 'f', 1)
                                     : QStringLiteral("%1 MB").arg(mb, 0, 'f', 0);
            // Append % of total system RAM (/proc/meminfo MemTotal) → "106 MB / 0.2%".
            QFile mi(QStringLiteral("/proc/meminfo"));
            if (mi.open(QIODevice::ReadOnly)) {
                const QByteArray meminfo = mi.readAll(); mi.close();
                const auto mt = QRegularExpression(QStringLiteral("MemTotal:\\s+(\\d+)\\s+kB")).match(QString::fromLatin1(meminfo));
                if (mt.hasMatch()) {
                    const double totKb = mt.captured(1).toDouble();
                    if (totKb > 0) {
                        const double pct = rssKb * 100.0 / totKb;
                        v += QStringLiteral(" / %1%").arg(pct, 0, 'f', pct < 10 ? 1 : 0);
                    }
                }
            }
            setRamUsage(v);
        }
    }

    // Disk: node data-dir footprint (db + state + logs + config). Scanned every
    // ~20s (every 10th 2s tick) — cheaper than each tick for a multi-GB db.
    if (m_diskSampleTick++ % 10 == 0) {
        const QString cfg = userConfig();
        if (!cfg.isEmpty()) {
            const qint64 bytes = dirSizeBytes(QFileInfo(cfg).absolutePath());
            if (bytes >= 0) {
                const double mb = bytes / (1024.0 * 1024.0);
                setDiskUsage(mb >= 1024.0
                    ? QStringLiteral("%1 GB").arg(mb / 1024.0, 0, 'f', 1)
                    : QStringLiteral("%1 MB").arg(mb, 0, 'f', 0));
            }
        }
    }

    // CPU% from /proc/<pid>/stat fields 14 (utime) + 15 (stime), in clock ticks.
    QFile stat(QStringLiteral("/proc/%1/stat").arg(pid));
    if (!stat.open(QIODevice::ReadOnly)) return;
    const QByteArray line = stat.readAll();
    stat.close();
    // The comm field (2nd) may contain spaces/parens — parse after the trailing ')'.
    const int rp = line.lastIndexOf(')');
    if (rp < 0) return;
    const QList<QByteArray> f = line.mid(rp + 2).split(' ');
    // After ')' the next field is #3 (state); utime is #14 → index 11, stime #15 → index 12.
    if (f.size() < 13) return;
    const unsigned long long ticks = f.at(11).toULongLong() + f.at(12).toULongLong();
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (m_prevSampleMs > 0 && nowMs > m_prevSampleMs && ticks >= m_prevCpuTicks) {
        const double clk = (double) sysconf(_SC_CLK_TCK);
        const double elapsedSec = (nowMs - m_prevSampleMs) / 1000.0;
        const double busySec = (ticks - m_prevCpuTicks) / (clk > 0 ? clk : 100.0);
        // Normalise to % of the WHOLE machine (0-100), not per-core: busySec/elapsedSec
        // is per-core and exceeds 100% on a multi-core node (150% = 1.5 cores). Dividing
        // by the online CPU count gives an intuitive share of total capacity, and makes
        // the 0-100% resource cap meaningful.
        long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
        if (ncpu < 1) ncpu = 1;
        double pct = elapsedSec > 0 ? (busySec / elapsedSec) * 100.0 / (double) ncpu : 0.0;
        if (pct < 0) pct = 0;
        if (pct > 100) pct = 100;
        setCpuUsage(QStringLiteral("%1%").arg(pct, 0, 'f', pct >= 10 ? 0 : 1));
    }
    m_prevCpuTicks = ticks;
    m_prevSampleMs = nowMs;
}

// Recursively sum file sizes under `path` (the node data dir). -1 on error/missing.
qint64 LogosNode1clickBackend::dirSizeBytes(const QString& path) const
{
    if (path.isEmpty() || !QFileInfo::exists(path)) return -1;
    qint64 total = 0;
    QDirIterator it(path, QDir::Files | QDir::NoSymLinks | QDir::Hidden,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) { it.next(); total += it.fileInfo().size(); }
    return total;
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
    // Merge the module's get_time_info (#51): cryptarchia_info.slot is the TIP's
    // slot (trails the clock by up to one block); time_info carries the true
    // clock — current_slot, current_epoch, genesis, slot duration. IPC, not curl:
    // the module method exists on 0.2.2 and 0.2.3 (surface diff is empty) and
    // getLeaderClaims already consumes it for slot→wall-clock dating.
    if (r.success && m_blockchainClient) {
        const LogosResult ti = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
            BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_time_info")));
        if (ti.success) {
            const QJsonObject tio =
                QJsonDocument::fromJson(ti.value.toString().toUtf8()).object();
            if (tio.contains(QStringLiteral("current_slot"))) {
                QJsonObject payload =
                    QJsonDocument::fromJson(r.value.toString().toUtf8()).object();
                payload.insert(QStringLiteral("time_info"), tio);
                r.value = QString::fromUtf8(
                    QJsonDocument(payload).toJson(QJsonDocument::Compact));
            }
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

// On-chain SDP state for OUR declaration, matched by verified public provider identity.
// A stored ID must also match that identity. Returns { found, active(epoch), withdrawAt(epoch or -1 if null) }. The on-chain record is
// authoritative: it tells us the declaration is active and not withdrawn even when the local blend
// service isn't currently mixing (core_info null).
QVariantMap LogosNode1clickBackend::onchainBlendDecl() const
{
    QVariantMap out;
    out.insert(QStringLiteral("found"), false);
    const QJsonObject store = loadBlendDecl();
    QProcess p;
    p.setProcessEnvironment(curlEnv());
    p.start(resolveCurl(),
            {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("4"),
             QStringLiteral("http://127.0.0.1:8080/mantle/sdp/declarations")});
    if (!p.waitForFinished(5000)) { p.kill(); return out; }
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput());
    if (!doc.isObject())
        return out;
    const QJsonObject o = doc.object();
    const QVariantMap match = BlendLifecycle::match(o, blendSigningKey(), store.value("declaration_id").toString());
    out["ok"] = match.value("ok");
    out["error"] = match.value("error");
    if (!match.value("id").toString().isEmpty()) {
        const QVariantMap rec = match.value("record").toMap();
        out["found"] = true;
        out["active"] = rec.value("active", -1);
        out["created"] = rec.value("created", -1);
        out["withdrawAt"] = rec.value("withdraw_at").isNull() ? -1 : rec.value("withdraw_at").toInt();
    }
    return out;
}

// Current epoch from the node's /time/info (-1 if unavailable). Same curl path as getBlendInfo.
int LogosNode1clickBackend::currentEpochOnchain() const
{
    QProcess p;
    p.setProcessEnvironment(curlEnv());
    p.start(resolveCurl(),
            {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("3"),
             QStringLiteral("http://127.0.0.1:8080/time/info")});
    if (!p.waitForFinished(4000)) { p.kill(); return -1; }
    const QJsonDocument doc = QJsonDocument::fromJson(p.readAllStandardOutput());
    if (!doc.isObject())
        return -1;
    const QJsonValue e = doc.object().value(QStringLiteral("current_epoch"));
    return e.isDouble() ? e.toInt() : -1;
}

// Recompute blendStatus + lastBlendEvent from the node state, the blend log, and
// (once past bootstrap) the live /blend/info. Called on the dashboard's refresh
// timer while the node is Running. Cheap: one log-tail read + at most one curl.
void LogosNode1clickBackend::refreshBlendStatus()
{
    if (m_blendReading || m_blendMutation) return;
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
            } else if (!loadBlendDecl().value(QStringLiteral("declaration_id")).toString().isEmpty()) {
                // We submitted a Blend declaration but core_info is not populated. The node's real
                // blend TYPE this epoch is only ever Edge or Core — "Activating" is not a distinct
                // mode, just Edge-while-a-declaration-matures, so we never surface it. Classify by the
                // ledger's is_active rule (active + inactivity_period ≥ epoch AND withdraw_at null/future):
                //   withdrawn (epoch ≥ withdraw_at)  → Off
                //   is_active, core_info absent      → CoreDeclaredEdge (declared+live on-chain, but
                //                                       running Edge this epoch — incl. the pre-active
                //                                       "maturing to Core" window; shown edge + gold)
                //   declaration aged out / not found → Edge (the declaration is stale/gone; we just mix
                //                                       as edge — the modal/gate explains why)
                static const int kInactivity = 2;
                const QVariantMap dcl = onchainBlendDecl();
                const int ep = currentEpochOnchain();
                if (dcl.value(QStringLiteral("found")).toBool()) {
                    const int active = dcl.value(QStringLiteral("active")).toInt();
                    const int wat = dcl.value(QStringLiteral("withdrawAt")).toInt();   // -1 = null
                    const bool live = ep >= 0 && active >= 0
                                   && active + kInactivity >= ep && (wat < 0 || wat > ep);
                    if (wat >= 0 && ep >= 0 && ep >= wat) {
                        st = Off;
                        evt = QStringLiteral("Blend declaration withdrawn");
                    } else if (live) {
                        st = CoreDeclaredEdge;
                        evt = (ep >= 0 && ep < active)
                            ? QStringLiteral("declaration maturing — Core at epoch %1").arg(active)
                            : (active > 0
                                ? QStringLiteral("Core declared (active since epoch %1) · not in this epoch's Core set").arg(active)
                                : QStringLiteral("Core declared · not in this epoch's Core set"));
                    } else {
                        // Aged out (active + inactivity < epoch): the declaration is inactive, so we run
                        // as a plain Edge node until it's re-declared. Note when it went inactive (and,
                        // if withdrawing, when it clears) so the operator knows re-declare is the fix.
                        st = Edge;
                        if (active >= 0) {
                            evt = QStringLiteral("declaration inactive since epoch %1").arg(active + kInactivity);
                            if (wat >= 0)
                                evt += QStringLiteral(" · withdrawing (clears epoch %1)").arg(wat);
                            evt += QStringLiteral(" — re-declare to rejoin Core");
                        } else {
                            evt = QStringLiteral("your proposals are being mixed");
                        }
                    }
                } else {
                    // Declared locally but no matching on-chain declaration (just submitted, not landed,
                    // or fully cleared) → we mix as Edge meanwhile; the enable modal tracks the submit.
                    st = Edge;
                    evt = QStringLiteral("your proposals are being mixed");
                }
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
    setBlendCoreNodes(blendMembershipCount());   // "N core nodes" for the dashboard copy

    // Persist the blend mode for the CURRENT epoch (write-ahead, last-seen wins) so the
    // dashboard can draw a per-epoch "Blend type" strip with real history — the mode is not
    // otherwise recoverable once the node's log rotates (~10h). Only record a resolved,
    // node-up mode (skip WaitingForOnline / Unknown / errors, and skip when epoch is unknown).
    const int ep = currentEpochOnchain();
    if (ep >= 0) {
        QString mode;
        switch (st) {
        case Core:             mode = QStringLiteral("core"); break;
        case Broadcast:        mode = QStringLiteral("broadcast"); break;
        case CoreDeclaredEdge: mode = QStringLiteral("coredeclared"); break;
        case Edge:             mode = QStringLiteral("edge"); break;
        // Activating is not a persisted blend type — the node mixes as Edge while a declaration
        // matures (that window is CoreDeclaredEdge once live on-chain, Edge before), so it never
        // reaches here; kept out of the strip deliberately.
        case Off:              mode = QStringLiteral("off"); break;
        default:               mode = QString(); break;   // transient/unknown → don't record
        }
        if (!mode.isEmpty())
            recordBlendMode(ep, mode);
    }
}

int LogosNode1clickBackend::blendMembershipCount() const
{
    const QString dataHome = QString::fromUtf8(qgetenv("XDG_DATA_HOME"));
    const QString base = dataHome.isEmpty()
        ? QDir::homePath() + QStringLiteral("/.local/share") : dataHome;
    const QDir ld(base + QStringLiteral("/Logos/LogosBasecamp/logs"));
    const QFileInfoList logs = ld.entryInfoList({QStringLiteral("*.log")}, QDir::Files, QDir::Time);
    static const QRegularExpression re(QStringLiteral("membership_count=([0-9]+)"));
    for (const QFileInfo& fi : logs) {                       // newest file first
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly)) continue;
        if (f.size() > 400000) f.seek(f.size() - 400000);    // tail only
        const QString tail = QString::fromUtf8(f.readAll());
        f.close();
        int last = -1;
        auto it = re.globalMatch(tail);
        while (it.hasNext()) last = it.next().captured(1).toInt();
        if (last >= 0) return last;
    }
    return -1;
}

QString LogosNode1clickBackend::blendModeStorePath() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return {};
    return QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("blend-mode-history.json"));
}

void LogosNode1clickBackend::recordBlendMode(int epoch, const QString& mode) const
{
    const QString path = blendModeStorePath();
    if (path.isEmpty()) return;
    QJsonObject obj;
    QFile f(path);
    if (f.exists() && f.open(QIODevice::ReadOnly)) {
        obj = QJsonDocument::fromJson(f.readAll()).object();
        f.close();
    }
    const QString key = QString::number(epoch);
    if (obj.value(key).toString() == mode) return;   // unchanged → no rewrite
    obj[key] = mode;
    // Cap the store so it can't grow unbounded: keep the most recent ~200 epochs.
    if (obj.size() > 200) {
        QList<int> epochs;
        for (auto it = obj.begin(); it != obj.end(); ++it) epochs << it.key().toInt();
        std::sort(epochs.begin(), epochs.end());
        for (int i = 0; i < epochs.size() - 200; ++i) obj.remove(QString::number(epochs[i]));
    }
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
        f.close();
    }
}

QString LogosNode1clickBackend::epochHeightStorePath() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return {};
    return QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("epoch-height.json"));
}

void LogosNode1clickBackend::recordEpochHeight(int epoch, int height)
{
    // Persist the MAX height reached in each epoch (write-ahead) so the dashboard can draw
    // blocks-per-epoch (Δheight) — total network blocks aren't otherwise recoverable per epoch.
    const QString path = epochHeightStorePath();
    if (path.isEmpty() || epoch < 0 || height < 0) return;
    QJsonObject obj;
    QFile f(path);
    if (f.exists() && f.open(QIODevice::ReadOnly)) {
        obj = QJsonDocument::fromJson(f.readAll()).object();
        f.close();
    }
    const QString key = QString::number(epoch);
    if (height <= obj.value(key).toInt())   // only grow (height climbs within an epoch)
        return;
    obj[key] = height;
    if (obj.size() > 400) {
        QList<int> epochs;
        for (auto it = obj.begin(); it != obj.end(); ++it) epochs << it.key().toInt();
        std::sort(epochs.begin(), epochs.end());
        for (int i = 0; i < epochs.size() - 400; ++i) obj.remove(QString::number(epochs[i]));
    }
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
        f.close();
    }
}

QVariantMap LogosNode1clickBackend::getBlockTx()
{
    const QVariantList series = m_blockModel ? m_blockModel->txSeries() : QVariantList();
    QVariantMap res;
    res[QStringLiteral("success")] = true;
    res[QStringLiteral("value")] = QString::fromUtf8(
        QJsonDocument(QJsonArray::fromVariantList(series)).toJson(QJsonDocument::Compact));
    return res;
}

QVariantMap LogosNode1clickBackend::getEpochHeights()
{
    QVariantList out;
    const QString path = epochHeightStorePath();
    QFile f(path);
    if (!path.isEmpty() && f.exists() && f.open(QIODevice::ReadOnly)) {
        const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
        f.close();
        QList<int> epochs;
        for (auto it = obj.begin(); it != obj.end(); ++it) epochs << it.key().toInt();
        std::sort(epochs.begin(), epochs.end());
        for (int e : epochs) {
            QVariantMap row;
            row[QStringLiteral("epoch")] = e;
            row[QStringLiteral("height")] = obj.value(QString::number(e)).toInt();
            out << row;
        }
    }
    QVariantMap res;
    res[QStringLiteral("success")] = true;
    res[QStringLiteral("value")] = QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(out)).toJson(QJsonDocument::Compact));
    return res;
}

QVariantMap LogosNode1clickBackend::getBlendModeHistory()
{
    QVariantList out;
    const QString path = blendModeStorePath();
    QFile f(path);
    if (!path.isEmpty() && f.exists() && f.open(QIODevice::ReadOnly)) {
        const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
        f.close();
        QList<int> epochs;
        for (auto it = obj.begin(); it != obj.end(); ++it) epochs << it.key().toInt();
        std::sort(epochs.begin(), epochs.end());
        for (int e : epochs) {
            QVariantMap row;
            row[QStringLiteral("epoch")] = e;
            row[QStringLiteral("mode")] = obj.value(QString::number(e)).toString();
            out << row;
        }
    }
    QVariantMap res;
    res[QStringLiteral("success")] = true;
    res[QStringLiteral("value")] = QString::fromUtf8(QJsonDocument(QJsonArray::fromVariantList(out)).toJson(QJsonDocument::Compact));
    return res;
}

// ── Blend Core provider lifecycle (epic #89, #90-#96) ────────────────────────
// Proven end-to-end on sneg 2026-09-15: fund sdp funding_pk → POST /blend/join
// {locator, locked_note_id} → declaration lands in a block → active at created+2
// epochs → Mode::Core. Route strings verified against the logos-blockchain 0.2.4 tag
// (nodes/api-common/src/paths.rs): /blend/join, /blend/info, /mantle/sdp/declarations,
// /sdp/withdrawal. All HTTP to the node's local API via system curl — the app's Qt/QML
// HTTPS stack is unreliable on this AppImage (same rationale as getBlendInfo).

// One synchronous request to the node's local HTTP API. Returns the response body;
// *outCode gets the HTTP status (empty ⇒ curl couldn't run / no reply).
static QString nodeApiRequest(const QString& method, const QString& path,
                              const QString& jsonBody, QString* outCode)
{
    if (outCode) outCode->clear();
    const QString curl = resolveCurl();
    if (curl.isEmpty())
        return {};
    QStringList args{QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("8"),
                     QStringLiteral("-X"), method,
                     QStringLiteral("-w"), QStringLiteral("\n%{http_code}")};
    if (!jsonBody.isEmpty())
        args << QStringLiteral("-H") << QStringLiteral("Content-Type: application/json")
             << QStringLiteral("-d") << jsonBody;
    args << (QStringLiteral("http://127.0.0.1:8080") + path);
    QProcess p;
    p.setProcessEnvironment(curlEnv());
    p.start(curl, args);
    if (!p.waitForFinished(10000)) { p.kill(); return {}; }
    const QString out = QString::fromUtf8(p.readAllStandardOutput());
    // curl -w "\n%{http_code}" appends the status after the body.
    const int nl = out.lastIndexOf(QLatin1Char('\n'));
    if (outCode)
        *outCode = (nl >= 0 ? out.mid(nl + 1) : QString()).trimmed();
    return (nl >= 0 ? out.left(nl) : out).trimmed();
}

// Extract the node's own error text from an ErrorBody JSON (or return the raw body).
static QString nodeApiError(const QString& body, const QString& code)
{
    const QJsonDocument d = QJsonDocument::fromJson(body.toUtf8());
    if (d.isObject()) {
        const QJsonObject o = d.object();
        const QString m = o.value(QStringLiteral("error")).toString(
            o.value(QStringLiteral("message")).toString());
        if (!m.isEmpty()) return m;
    }
    if (!body.isEmpty()) return body;
    return QStringLiteral("The node returned an error (HTTP %1).").arg(code);
}

// sdp.wallet.funding_pk from the node config — the key the declaration fee is paid
// from. Same config walk as leaderFundingKey(), targeting the `sdp:` block instead of
// `leader:` (both blocks contain a `funding_pk:`, so the block boundary matters).
QString LogosNode1clickBackend::sdpFundingKey() const
{
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
        bool inSdp = false;
        for (const QString& line : lines) {
            const QString t = line.trimmed();
            // A non-indented key starts a new top-level block: enter only on `sdp:`,
            // leave on anything else (e.g. `leader:`) so we never read the wrong funding_pk.
            if (!line.startsWith(QLatin1Char(' ')) && !line.startsWith(QLatin1Char('\t'))
                && t.endsWith(QLatin1Char(':')))
                inSdp = t.startsWith(QStringLiteral("sdp:"));
            if (inSdp && t.startsWith(QStringLiteral("funding_pk:"))) {
                const auto m = hexRe.match(t);
                if (m.hasMatch()) return m.captured(0);
            }
        }
    }
    return QString();
}

// The blend listening port from the config (blend_port: N, or a /udp/<port> inside a
// blend listening_address). Falls back to 3400 — the testnet Blend default.
int LogosNode1clickBackend::blendPortFromConfig() const
{
    QStringList candidates;
    if (!generatedUserConfigPath().isEmpty()) candidates << generatedUserConfigPath();
    if (!userConfig().isEmpty())              candidates << userConfig();
    const QString dataHome = QString::fromUtf8(qgetenv("XDG_DATA_HOME"));
    const QString base = dataHome.isEmpty()
        ? QDir::homePath() + QStringLiteral("/.local/share") : dataHome;
    const QDir md(base + QStringLiteral("/Logos/LogosBasecamp/module_data/blockchain_module"));
    for (const QFileInfo& inst : md.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Time))
        candidates << inst.absoluteFilePath() + QStringLiteral("/user_config.yaml");

    static const QRegularExpression portRe(QStringLiteral("blend_port:\\s*(\\d+)"));
    static const QRegularExpression udpRe(QStringLiteral("/udp/(\\d+)/quic"));
    for (const QString& path : candidates) {
        QFile f(path);
        if (!f.exists() || !f.open(QIODevice::ReadOnly)) continue;
        const QString body = QString::fromUtf8(f.readAll());
        f.close();
        auto m = portRe.match(body);
        if (m.hasMatch()) return m.captured(1).toInt();
        // else look for a udp/quic multiaddr on a line mentioning blend.
        const QStringList lines = body.split(QLatin1Char('\n'));
        for (const QString& ln : lines) {
            if (!ln.contains(QStringLiteral("blend"), Qt::CaseInsensitive)) continue;
            const auto um = udpRe.match(ln);
            if (um.hasMatch()) return um.captured(1).toInt();
        }
    }
    return 3400;
}

// Public IP for the declaration locator. Prefer an external_address in the config;
// else resolve over curl (cached for the session). Empty if it can't be determined.
QString LogosNode1clickBackend::resolvePublicIp() const
{
    if (!m_publicIp.isEmpty())
        return m_publicIp;
    static const QRegularExpression ipRe(QStringLiteral("(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})"));

    // 1) external_address from the config, if the operator pinned one.
    QStringList candidates;
    if (!generatedUserConfigPath().isEmpty()) candidates << generatedUserConfigPath();
    if (!userConfig().isEmpty())              candidates << userConfig();
    for (const QString& path : candidates) {
        QFile f(path);
        if (!f.exists() || !f.open(QIODevice::ReadOnly)) continue;
        const QString body = QString::fromUtf8(f.readAll());
        f.close();
        for (const QString& ln : body.split(QLatin1Char('\n'))) {
            if (!ln.contains(QStringLiteral("external"), Qt::CaseInsensitive)) continue;
            const auto m = ipRe.match(ln);
            if (m.hasMatch() && m.captured(1) != QStringLiteral("127.0.0.1")) {
                m_publicIp = m.captured(1);
                return m_publicIp;
            }
        }
    }

    // 2) Resolve over the network via curl (system curl, like the faucet POST).
    const QString curl = resolveCurl();
    if (!curl.isEmpty()) {
        for (const QString& url : {QStringLiteral("https://api.ipify.org"),
                                   QStringLiteral("https://ifconfig.me/ip"),
                                   QStringLiteral("https://icanhazip.com")}) {
            QProcess p;
            p.setProcessEnvironment(curlEnv());
            p.start(curl, {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("6"), url});
            if (!p.waitForFinished(7000)) { p.kill(); continue; }
            const QString body = QString::fromUtf8(p.readAllStandardOutput()).trimmed();
            const auto m = ipRe.match(body);
            if (m.hasMatch()) {
                m_publicIp = m.captured(1);
                return m_publicIp;
            }
        }
    }
    return QString();
}

QString LogosNode1clickBackend::buildBlendLocator() const
{
    const QString ip = resolvePublicIp();
    if (ip.isEmpty())
        return QString();
    return QStringLiteral("/ip4/%1/udp/%2/quic-v1").arg(ip).arg(blendPortFromConfig());
}

QString LogosNode1clickBackend::blendDeclStorePath() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return {};
    return QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("blend-declaration.json"));
}

QJsonObject LogosNode1clickBackend::loadBlendDecl() const
{
    const QString p = blendDeclStorePath();
    if (p.isEmpty())
        return {};
    QFile f(p);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    return doc.isObject() ? doc.object() : QJsonObject{};
}

void LogosNode1clickBackend::saveBlendDecl(const QJsonObject& obj) const
{
    const QString p = blendDeclStorePath();
    if (p.isEmpty())
        return;
    QSaveFile f(p);   // atomic rename-over-target, like saveClaimStore()
    if (!f.open(QIODevice::WriteOnly))
        return;
    if (f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact)) < 0) {
        f.cancelWriting();
        return;
    }
    f.commit();
}

void LogosNode1clickBackend::clearBlendDecl() const
{
    const QString p = blendDeclStorePath();
    if (!p.isEmpty())
        QFile::remove(p);
}

// /proc's process start time anchors log evidence to this node run, not UI uptime.
qint64 LogosNode1clickBackend::blendRunStartedAt() const
{
    const qint64 pid = findBlockchainModulePid();
    if (pid <= 0) return 0;
    QFile process(QStringLiteral("/proc/%1/stat").arg(pid));
    QFile system(QStringLiteral("/proc/stat"));
    if (!process.open(QIODevice::ReadOnly) || !system.open(QIODevice::ReadOnly)) return 0;
    const QByteArray stat = process.readAll();
    const QList<QByteArray> fields = stat.mid(stat.lastIndexOf(')') + 2).simplified().split(' ');
    if (fields.size() <= 19) return 0;
    const QRegularExpression boot(QStringLiteral("(?:^|\n)btime (\\d+)"));
    const auto match = boot.match(QString::fromLatin1(system.readAll()));
    const long ticks = sysconf(_SC_CLK_TCK);
    if (!match.hasMatch() || ticks <= 0) return 0;
    qint64 started = match.captured(1).toLongLong() * 1000 + fields[19].toLongLong() * 1000 / ticks;
    // A module host may survive a node stop/start. Prefer the newest SDP service
    // readiness marker when present; unlike a config omission this is run evidence.
    if (!userConfig().isEmpty()) {
        const QDir logs(QFileInfo(userConfig()).absoluteDir().filePath(QStringLiteral("logs")));
        const auto files = logs.entryInfoList(QDir::Files, QDir::Time);
        static const QRegularExpression stamp(QStringLiteral("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?Z"));
        for (int i = 0; i < qMin(3, int(files.size())); ++i) {
            QFile file(files[i].absoluteFilePath());
            if (!file.open(QIODevice::ReadOnly)) continue;
            file.seek(qMax<qint64>(0, file.size() - 256 * 1024));
            for (const QString& line : QString::fromUtf8(file.readAll()).split('\n')) {
                if (!line.contains(QStringLiteral("Service 'Sdp' is ready"), Qt::CaseInsensitive)) continue;
                const auto time = stamp.match(line);
                if (time.hasMatch()) started = qMax(started, QDateTime::fromString(time.captured(), Qt::ISODateWithMs).toMSecsSinceEpoch());
            }
        }
    }
    return qMax(started, m_blendRunFloor);
}

qint64 LogosNode1clickBackend::blendMissingBindingAt(qint64 runStart) const
{
    if (runStart <= 0 || userConfig().isEmpty()) return 0;
    const QDir logs(QFileInfo(userConfig()).absoluteDir().filePath(QStringLiteral("logs")));
    const auto files = logs.entryInfoList(QDir::Files, QDir::Time);
    qint64 latest = 0;
    static const QRegularExpression timestamp(QStringLiteral("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?Z"));
    for (int i = 0; i < qMin(3, int(files.size())); ++i) {
        if (files[i].lastModified().toMSecsSinceEpoch() < runStart) continue;
        QFile file(files[i].absoluteFilePath());
        if (!file.open(QIODevice::ReadOnly)) continue;
        file.seek(qMax<qint64>(0, file.size() - 256 * 1024));
        const auto lines = QString::fromUtf8(file.readAll()).split('\n');
        for (const QString& line : lines) {
            if (!line.contains(QStringLiteral("No declaration_id set. Cannot post activity without declaration."))) continue;
            const auto time = timestamp.match(line);
            if (!time.hasMatch()) continue; // no timestamp means no current-run proof
            const qint64 at = QDateTime::fromString(time.captured(), Qt::ISODateWithMs).toMSecsSinceEpoch();
            if (at >= runStart) latest = qMax(latest, at);
        }
    }
    return latest;
}

void LogosNode1clickBackend::ensureBlendRecovery()
{
    const QString config = toLocalPath(userConfig());
    const QString scope = config.isEmpty() ? QString() : QFileInfo(config).absoluteFilePath();
    if (m_blendRecovery && scope != m_recoveryScope && (m_blendRecovery->active() || m_recoveryTick)) {
        m_blendRecovery->fail(QStringLiteral("Config changed during unfinished recovery. Original journal retained; no mutations permitted."));
        setBlendRecoveryActive(true);
        return;
    }
    if (!m_blendRecovery || scope != m_recoveryScope) {
        m_blendRecovery.reset();
        m_recoveryScope = scope;
        if (!scope.isEmpty()) {
            m_blendRecovery = std::make_unique<BlendRecovery::Controller>();
            m_blendRecovery->open(QFileInfo(scope).absoluteDir().filePath(QStringLiteral("blend-recovery.json")), scope);
        }
    }
    setBlendRecoveryActive(m_blendRecovery && m_blendRecovery->active());
}

bool LogosNode1clickBackend::blendRecoveryBlocks()
{
    ensureBlendRecovery();
    return m_recoveryTick || (m_blendRecovery && m_blendRecovery->active());
}

QVariantMap LogosNode1clickBackend::withBlendRecovery(QVariantMap lifecycle)
{
    ensureBlendRecovery();
    QVariantMap recovery = m_blendRecovery ? m_blendRecovery->view(m_recoverySnapshot)
        : BlendRecovery::Controller().view(BlendRecovery::Snapshot());
    const auto& s = m_recoverySnapshot;
    recovery["snapshot"] = QVariantMap{{"valid", s.valid}, {"running", s.running},
        {"identity", s.identity}, {"online", s.online}, {"core", s.core},
        {"present", s.present}, {"pending", s.pending}, {"provider", s.provider},
        {"id", s.id}, {"note", s.note}, {"locator", s.locator}, {"created", s.created},
        {"activity", s.activity}, {"withdrawal", s.withdrawal}, {"epoch", s.epoch},
        {"tip", s.tip}, {"slot", s.slot}, {"lib", s.lib}};
    const QJsonObject journal = m_blendRecovery ? m_blendRecovery->state() : QJsonObject();
    recovery["originalId"] = journal.value("originalId").toString();
    recovery["originalCreated"] = journal.value("originalCreated").toInt(-1);
    recovery["originalNote"] = journal.value("note").toString();
    recovery["originalLocator"] = journal.value("locator").toString();
    recovery["withdrawAt"] = journal.value("withdrawAt").toInt(-1);
    lifecycle["recovery"] = recovery;
    return lifecycle;
}

QVariantMap LogosNode1clickBackend::startBlendRecovery()
{
    if (m_recoveryTick || m_blendMutation || m_blendReading || blendRecoveryBlocks())
        return {{"ok", false}, {"error", "A Blend operation or unfinished recovery already exists."}};
    QScopedValueRollback<bool> guard(m_recoveryTick, true);
    getBlendLifecycle(); // fresh verified canonical evidence; never authorizes on read
    const bool ok = m_blendRecovery && m_blendRecovery->start(m_recoverySnapshot);
    ensureBlendRecovery();
    return {{"ok", ok}, {"error", ok ? QString() : QStringLiteral("Recovery requires a verified owned stale declaration, valid canonical collateral/address, no pending operation, and writable recovery storage.")},
        {"message", ok ? QStringLiteral("Authorized one controlled withdrawal and one fresh declaration with the same collateral and address. Backend monitoring continues across navigation. Transaction fees apply.") : QString()}};
}

QVariantMap LogosNode1clickBackend::pauseBlendRecovery()
{
    ensureBlendRecovery();
    // May run during the transport's nested event loop; the controller preserves this intent.
    const bool ok = m_blendRecovery && m_blendRecovery->pause();
    ensureBlendRecovery();
    return {{"ok", ok}, {"error", ok ? QString() : QStringLiteral("Cannot persist a pause; recovery is blocked or not active.")},
        {"message", "Pause stops future mutations, not requests already sent or on-chain actions."}};
}

QVariantMap LogosNode1clickBackend::resumeBlendRecovery()
{
    ensureBlendRecovery();
    if (m_recoveryTick || m_blendReading || m_blendMutation)
        return {{"ok", false}, {"error", "Wait for the current snapshot/request to finish."}};
    const bool ok = m_blendRecovery && m_blendRecovery->resume();
    ensureBlendRecovery();
    return {{"ok", ok}, {"error", ok ? QString() : QStringLiteral("Recovery is not resumable; attention/journal faults require manual review.")},
        {"message", "Recovery monitoring resumed. Unknown paid outcomes remain pending and are never retried."}};
}

QVariantMap LogosNode1clickBackend::dismissBlendRecovery()
{
    ensureBlendRecovery();
    if (m_recoveryTick || m_blendReading || m_blendMutation)
        return {{"ok", false}, {"error", "Wait for the current snapshot/request to finish."}};
    // Only a terminally-stopped recovery (phase "attention") is dismissable; the controller
    // guards this. Clears the retained journal so the strip stops showing "needs attention".
    const bool ok = m_blendRecovery && m_blendRecovery->dismiss();
    if (ok) setBlendRecoveryActive(false);
    ensureBlendRecovery();
    return {{"ok", ok}, {"error", ok ? QString() : QStringLiteral("Nothing to dismiss — recovery is not in a terminally-stopped state.")},
        {"message", ok ? QStringLiteral("Stopped recovery dismissed. Its on-chain actions (if any) were already final and are unchanged.") : QString()}};
}

// ── Pre-activation reachability check (epic #124) ────────────────────────────
// Bind a short-lived responder on udp/<blendPort> and ask the external prober to
// dial our public IP:port with `nonceHex`; the responder echoes the nonce so the
// prober returns a REAL reachable/not verdict. A local QEventLoop pumps the
// responder's readyRead (echo) while curl waits on the prober — no fake AutoNAT.
// Prober URL: LOGOS_BLEND_PROBER_URL env, else the default deployed endpoint.
QVariantMap LogosNode1clickBackend::checkBlendReachable(QString nonceHex)
{
    QVariantMap out;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("reachable"), false);

    static const QByteArray kMagic   = QByteArray("LOGOS-BLEND-REACH", 17) + '\0';      // 18 bytes
    static const QByteArray kMagicOk = QByteArray("LOGOS-BLEND-REACH-OK", 20) + '\0';   // 21 bytes

    const int port = blendPortFromConfig();
    const QString ip = resolvePublicIp();
    if (ip.isEmpty()) {
        out.insert(QStringLiteral("detail"), QStringLiteral("Could not resolve a public IPv4 to probe."));
        return out;
    }
    QByteArray nonce = QByteArray::fromHex(nonceHex.trimmed().toUtf8());
    if (nonce.size() < 4) {   // caller should pass one; generate a fallback
        nonce = QByteArray::number(qint64(QRandomGenerator::global()->generate64()), 16).rightJustified(16, '0').left(16);
        nonce = QByteArray::fromHex(nonce);
    }

    // Bind the responder. If the port is already held (node is Core), reachability is
    // implied by membership — report that honestly and let the UI treat it as reachable.
    QUdpSocket responder;
    if (!responder.bind(QHostAddress::AnyIPv4, static_cast<quint16>(port))) {
        out.insert(QStringLiteral("ok"), true);
        out.insert(QStringLiteral("reachable"), true);
        out.insert(QStringLiteral("detail"),
                   QStringLiteral("udp/%1 is already bound locally (the node holds it) — reachable via Core membership.").arg(port));
        return out;
    }
    const QByteArray expectProbe = kMagic + nonce;
    const QByteArray reply = kMagicOk + nonce;

    QEventLoop loop;
    QObject::connect(&responder, &QUdpSocket::readyRead, &loop, [&responder, expectProbe, reply]() {
        while (responder.hasPendingDatagrams()) {
            QByteArray dg; dg.resize(int(responder.pendingDatagramSize()));
            QHostAddress from; quint16 fromPort = 0;
            responder.readDatagram(dg.data(), dg.size(), &from, &fromPort);
            if (dg == expectProbe)
                responder.writeDatagram(reply, from, fromPort);   // nonce-bound echo
        }
    });

    // Default prober endpoint (deployed on the Hetzner VPS, epic #124). Overridable for tests.
    QString base = QString::fromUtf8(qgetenv("LOGOS_BLEND_PROBER_URL"));
    if (base.isEmpty()) base = QStringLiteral("http://65.109.51.37:8899/check");   // placeholder until DNS
    const QString url = base + QStringLiteral("?ip=%1&port=%2&nonce=%3")
                                   .arg(ip).arg(port).arg(QString::fromUtf8(nonce.toHex()));

    QProcess curl;
    curl.setProcessEnvironment(curlEnv());
    QObject::connect(&curl, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                     &loop, &QEventLoop::quit);
    QTimer::singleShot(8000, &loop, &QEventLoop::quit);   // hard cap
    curl.start(resolveCurl(), {QStringLiteral("-sS"), QStringLiteral("-m"), QStringLiteral("6"), url});
    loop.exec();   // pumps responder echo + curl completion
    if (curl.state() != QProcess::NotRunning) { curl.kill(); curl.waitForFinished(500); }

    const QByteArray body = curl.readAllStandardOutput();
    const QJsonObject o = QJsonDocument::fromJson(body).object();
    if (o.contains(QStringLiteral("reachable"))) {
        out.insert(QStringLiteral("ok"), true);
        out.insert(QStringLiteral("reachable"), o.value(QStringLiteral("reachable")).toBool());
        out.insert(QStringLiteral("detail"), o.value(QStringLiteral("detail")).toString());
    } else {
        out.insert(QStringLiteral("detail"),
                   QStringLiteral("The reachability prober didn't answer — confirm the udp/%1 forward yourself for now.").arg(port));
    }
    return out;
}

void LogosNode1clickBackend::readBlendRecoveryFunding(BlendRecovery::Snapshot& snapshot)
{
    snapshot.funded = false;
    snapshot.noteSpendable = false;
    if (!m_blendRecovery || !snapshot.valid) return;
    const QString funding = sdpFundingKey().toLower();
    const QString collateral = m_blendRecovery->state().value("note").toString();
    QStringList keys{funding, leaderFundingKey().toLower(), primaryAddress().toLower()};
    if (m_blockchainClient) {
        const LogosResult known = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(BLOCKCHAIN_MODULE_NAME, "wallet_get_known_addresses"));
        if (known.success) {
            for (const QVariant& key : known.value.toList()) keys << key.toString().toLower();
            keys += known.value.toStringList();
        }
    }
    keys.removeDuplicates();
    QStringList paths;
    for (const QString& key : keys) if (BlendLifecycle::isId(key) && paths.size() < 32)
        paths << QStringLiteral("/wallet/%1/balance").arg(key);
    if (paths.isEmpty()) return;
    const auto replies = BlendLifecycle::request(resolveCurl(), curlEnv(), paths);
    for (const QString& path : paths) {
        const auto reply = replies.value(path);
        const QJsonDocument doc = QJsonDocument::fromJson(reply.body.toUtf8());
        if (!reply.ok() || !doc.isObject()) continue;
        const QJsonObject wallet = doc.object();
        const QString address = wallet.value("address").toString().toLower();
        if (path != QStringLiteral("/wallet/%1/balance").arg(address) || !wallet.value("notes").isObject()
            || !BlendRecovery::number(wallet.value("balance")) || wallet.value("tip").toString() != snapshot.tip) continue;
        const QJsonObject notes = wallet.value("notes").toObject();
        bool notesValid = true, feeNote = false, collateralFound = false;
        for (auto it = notes.begin(); it != notes.end(); ++it) {
            if (!BlendLifecycle::isId(it.key()) || !BlendRecovery::number(it.value())) { notesValid = false; break; }
            if (it.value().toDouble() <= 0) continue;
            if (it.key().compare(collateral, Qt::CaseInsensitive) == 0) collateralFound = true;
            else feeNote = true;
        }
        if (!notesValid) continue;
        // Balance includes locked notes: presence is only a prerequisite, not
        // proof of unlocked collateral/fee sufficiency. Removal + LIB gate join.
        snapshot.noteSpendable = snapshot.noteSpendable || collateralFound;
        if (address == funding) snapshot.funded = wallet.value("balance").toDouble() > 0 && feeNote;
    }
}

void LogosNode1clickBackend::advanceBlendRecovery()
{
    ensureBlendRecovery();
    if (!m_blendRecovery || !m_blendRecovery->active() || !m_blendRecovery->error().isEmpty()
        || m_recoveryTick || m_blendReading || m_blendMutation) return;
    QScopedValueRollback<bool> tick(m_recoveryTick, true);
    QScopedValueRollback<bool> mutation(m_blendMutation, true);
    const QString infoPath = QStringLiteral("/cryptarchia/info");
    auto chainTip = [&]() {
        const auto reply = BlendLifecycle::request(resolveCurl(), curlEnv(), {infoPath}).value(infoPath);
        if (!reply.ok()) return QString();
        return QJsonDocument::fromJson(reply.body.toUtf8()).object().value("cryptarchia_info").toObject().value("tip").toString();
    };
    const QString before = status() == Running ? chainTip() : QString();
    getBlendLifecycle();
    BlendRecovery::Snapshot snapshot = m_recoverySnapshot;
    const QString phase = m_blendRecovery->phase();
    if (snapshot.valid && (phase == "preflight" || phase == "withdraw-ready" || phase == "removal-wait"))
        readBlendRecoveryFunding(snapshot);
    const QString after = status() == Running ? chainTip() : QString();
    snapshot.valid = snapshot.valid && BlendLifecycle::isId(before) && before == snapshot.tip && before == after;
    snapshot.running = status() == Running;
    // Check the selected config/public identity again after nested event loops.
    snapshot.identity = snapshot.identity && blendSigningKey().compare(snapshot.provider, Qt::CaseInsensitive) == 0;
    ensureBlendRecovery();
    m_blendRecovery->tick(snapshot, [this](BlendRecovery::Action action, const QJsonObject& body) {
        using namespace BlendRecovery;
        if (status() != Running || m_blendRecovery->paused() || !m_blendRecovery->error().isEmpty())
            return Reply{}; // conservative no-submit: journal remains pending, never guess delivery
        const bool join = action == Action::Declare;
        const QString path = join ? QStringLiteral("/blend/join") : action == Action::Withdraw ? QStringLiteral("/sdp/withdrawal") : QStringLiteral("/sdp/set-declaration-id");
        const QString payload = join ? QString::fromUtf8(QJsonDocument(body).toJson(QJsonDocument::Compact))
            : QStringLiteral("\"%1\"").arg(body.value("id").toString());
        const bool binding = action == Action::BindOriginal || action == Action::BindNew;
        const qint64 runStart = binding ? blendRunStartedAt() : 0;
        if (action == Action::Withdraw) {
            // The pinned engine clears the binding when it submits withdrawal.
            m_blendRepairedAt = 0;
            m_blendRepairedId.clear();
        }
        const auto reply = BlendLifecycle::request(resolveCurl(), curlEnv(), {path}, QStringLiteral("POST"), payload).value(path);
        if (binding && reply.ok()) {
            if (runStart <= 0 || runStart != blendRunStartedAt()) return Reply{};
            m_blendRepairedAt = QDateTime::currentMSecsSinceEpoch();
            m_blendRepairedId = body.value("id").toString();
        }
        // Pinned service failures return 500 and are ambiguous. Only router/extractor
        // rejects below establish no paid service invocation (408/409/429/5xx do NOT).
        const QStringList noSubmit{"400", "401", "403", "404", "405", "415", "422"};
        const Outcome outcome = reply.ok() ? Outcome::Accepted : noSubmit.contains(reply.code) ? Outcome::RejectedNoSubmit : Outcome::Unknown;
        return Reply{outcome, join ? BlendLifecycle::joinId(reply.body) : QString()};
    });
    ensureBlendRecovery();
}

QVariantMap LogosNode1clickBackend::getBlendLifecycle()
{
    // Never retain authorization/removal evidence across failed or nested reads.
    m_recoverySnapshot = BlendRecovery::Snapshot();
    m_recoverySnapshot.running = status() == Running;
    QVariantMap input{{"running", status() == Running}};
    if (status() != Running) {
        m_blendRepairedAt = 0;
        m_blendRepairedId.clear();
        return withBlendRecovery(BlendLifecycle::reduce(input));
    }
    if (m_blendReading) {
        input["evidence"] = QStringLiteral("A Blend snapshot is already in progress.");
        return withBlendRecovery(BlendLifecycle::reduce(input));
    }
    QScopedValueRollback<bool> reading(m_blendReading, true);
    const QString declarationsPath = QStringLiteral("/mantle/sdp/declarations");
    const QString timePath = QStringLiteral("/time/info"), blendPath = QStringLiteral("/blend/info");
    const QString modePath = QStringLiteral("/cryptarchia/info");
    const auto replies = BlendLifecycle::request(resolveCurl(), curlEnv(), {declarationsPath, timePath, blendPath, modePath});
    auto json = [&](const QString& path) { return QJsonDocument::fromJson(replies.value(path).body.toUtf8()); };
    const QJsonDocument declarations = json(declarationsPath);
    const QJsonObject time = json(timePath).object(), blend = json(blendPath).object(), mode = json(modePath).object();
    QJsonObject store = loadBlendDecl();
    const QString provider = blendSigningKey();
    const bool runtimeIdentityOk = !provider.isEmpty()
        && BlendLifecycle::providerFromPeerId(blend.value("node_id").toString()).compare(provider, Qt::CaseInsensitive) == 0;
    const QVariantMap identity = BlendLifecycle::match(declarations.object(), provider,
        store.value("withdraw_removed").toBool() ? QString() : store.value("declaration_id").toString());
    bool apiOk = true;
    for (const QString& path : {declarationsPath, timePath, blendPath, modePath})
        apiOk = apiOk && replies.value(path).ok() && json(path).isObject();
    const QJsonObject chain = mode.value("cryptarchia_info").toObject();
    const bool telemetryValid = apiOk
        && BlendRecovery::number(time.value("current_epoch"), std::numeric_limits<int>::max() - 8)
        && BlendLifecycle::isId(chain.value("tip").toString())
        && BlendRecovery::number(chain.value("slot"))
        && BlendRecovery::number(chain.value("lib_slot"))
        && chain.value("lib_slot").toDouble() <= chain.value("slot").toDouble()
        && chain.value("state").isString() && !chain.value("state").toString().isEmpty()
        && blend.contains("core_info")
        && (blend.value("core_info").isNull() || blend.value("core_info").isObject());
    if (telemetryValid) {
        m_recoverySnapshot = BlendRecovery::canonical(declarations.object(), provider);
        m_recoverySnapshot.identity = runtimeIdentityOk;
        m_recoverySnapshot.online = chain.value("state").toString() == QStringLiteral("Online");
        m_recoverySnapshot.core = blend.value("core_info").isObject();
        m_recoverySnapshot.epoch = time.value("current_epoch").toInt();
        m_recoverySnapshot.tip = chain.value("tip").toString();
        m_recoverySnapshot.slot = static_cast<qint64>(chain.value("slot").toDouble());
        m_recoverySnapshot.lib = static_cast<qint64>(chain.value("lib_slot").toDouble());
    }
    m_recoverySnapshot.running = status() == Running;
    input["running"] = status() == Running;
    input["apiOk"] = apiOk;
    input["identityOk"] = runtimeIdentityOk && identity.value("ok").toBool();
    input["mode"] = mode.value("cryptarchia_info").toObject().value("state").toString(mode.value("state").toString());
    input["epoch"] = time.value("current_epoch").toInt(-1);
    const QVariantMap record = identity.value("record").toMap();
    if (m_recoverySnapshot.valid && input["identityOk"].toBool()) {
        const QJsonObject reconciled = BlendLifecycle::reconcileRegistration(store, record,
            identity.value("id").toString(), input["epoch"].toInt());
        if (reconciled != store) { saveBlendDecl(reconciled); store = reconciled; }
        if (!record.isEmpty()) m_blendSubmissionPending = false;
        if (store.value("withdraw_removed").toBool()) m_blendWithdrawalPending = false;
    }
    input["removalConfirmed"] = store.value("withdraw_removed").toBool() && record.isEmpty();
    input["declarationId"] = identity.value("id");
    input["withdrawPending"] = m_blendWithdrawalPending || store.value("withdraw_pending").toBool();
    input["submissionPending"] = !store.value("withdraw_removed").toBool()
        && (m_blendSubmissionPending || !store.value("declaration_id").toString().isEmpty() || store.value("submission_pending").toBool());
    input["created"] = record.value("created", -1);
    input["active"] = record.value("active", -1);
    input["nonce"] = record.value("nonce").toString();
    input["withdrawAt"] = record.value("withdraw_at").isNull() ? -1 : record.value("withdraw_at").toInt();
    const QJsonValue core = blend.value("core_info");
    input["core"] = core.isObject();
    const QJsonValue peers = core.toObject().value("current_epoch_peers");
    input["healthyPeers"] = BlendLifecycle::healthyPeers(peers);
    const qint64 runStart = blendRunStartedAt();
    const qint64 repairedAt = m_blendRepairedId == identity.value("id").toString() ? m_blendRepairedAt : 0;
    input["bindingStatus"] = BlendLifecycle::binding(runStart, blendMissingBindingAt(runStart), repairedAt, QDateTime::currentMSecsSinceEpoch());
    m_recoverySnapshot.bindingKnown = input["bindingStatus"] == "confirmed";
    QStringList evidence;
    if (apiOk) {
        evidence << QStringLiteral("Epoch %1 · %2 · %3 healthy peers")
            .arg(input["epoch"].toInt())
            .arg(core.isObject() ? QStringLiteral("Core") : QStringLiteral("Not Core"))
            .arg(input["healthyPeers"].toInt() < 0 ? QStringLiteral("unknown") : QString::number(input["healthyPeers"].toInt()));
        if (!record.isEmpty()) evidence << QStringLiteral("Declared %1 · active %2%3 · nonce %4")
            .arg(input["created"].toInt()).arg(input["active"].toInt())
            .arg(input["active"].toInt() == input["created"].toInt() + 2 ? QStringLiteral(" (initial baseline)") : QString())
            .arg(input["nonce"].toString());
    }
    if (!apiOk) evidence << QStringLiteral("One or more local API requests failed or returned malformed JSON.");
    if (!identity.value("error").toString().isEmpty()) evidence << identity.value("error").toString();
    if (!runtimeIdentityOk) evidence << QStringLiteral("The API's public node identity does not verify against this configured provider; actions are blocked.");
    if (input["bindingStatus"] == "missing") evidence << QStringLiteral("Current-run SDP log: No declaration_id set. Cannot post activity without declaration.");
    else if (input["bindingStatus"] == "confirmed") evidence << QStringLiteral("This run acknowledged /sdp/set-declaration-id; no newer missing-binding error observed.");
    else evidence << QStringLiteral("Local SDP binding is unknown; config omission is not proof of a missing runtime binding.");
    if (!record.isEmpty()) evidence << QStringLiteral("Accepted activity requires active > created + 2; nonce also includes withdrawals. Membership uses a frozen epoch snapshot.");
    input["evidence"] = evidence.join(' ');
    // Do not hide repair from the internal guard; UI overlap is guarded separately.
    QVariantMap result = BlendLifecycle::reduce(input);
    if (result.value("state") == "removed" && input.value("withdrawPending").toBool()) {
        m_blendWithdrawalPending = false;
        QJsonObject reconciled = store;
        reconciled["withdraw_pending"] = false;
        reconciled["withdraw_removed"] = true;
        saveBlendDecl(reconciled); // retain identity/history; never clear on HTTP acknowledgement
        store = reconciled;
    }
    // Legacy submissionPending includes a confirmed stored ID for the old UI.
    // Only unresolved operations block recovery, never confirmed history.
    const bool completedSubmission = m_recoverySnapshot.valid && m_recoverySnapshot.identity
        && (m_recoverySnapshot.present || store.value("withdraw_removed").toBool());
    const bool completedWithdrawal = m_recoverySnapshot.valid && m_recoverySnapshot.identity
        && store.value("withdraw_removed").toBool();
    m_recoverySnapshot.pending = (!completedSubmission
        && (m_blendSubmissionPending || store.value("submission_pending").toBool()
            || (!store.value("declaration_id").toString().isEmpty()
                && !store.value("observed_on_chain").toBool())))
        || (!completedWithdrawal && (m_blendWithdrawalPending || store.value("withdraw_pending").toBool()))
        || (m_blendMutation && !m_recoveryTick);
    return withBlendRecovery(result);
}

QVariantMap LogosNode1clickBackend::repairBlendBinding()
{
    QVariantMap out{{"ok", false}, {"error", QString()}, {"message", QString()}};
    if (blendRecoveryBlocks()) {
        out["error"] = QStringLiteral("Unfinished Blend recovery owns the declaration and binding; manual repair is blocked, including while paused.");
        return out;
    }
    if (m_blendMutation || m_blendReading) {
        out["error"] = QStringLiteral("A Blend operation is already in progress.");
        return out;
    }
    QScopedValueRollback<bool> mutation(m_blendMutation, true);
    const QVariantMap state = getBlendLifecycle(); // fresh provider verification, never trust cached ID alone
    if (!BlendLifecycle::canRepair(state) || m_blendWithdrawalPending || loadBlendDecl().value("withdraw_pending").toBool()) {
        out["error"] = QStringLiteral("Setting the binding requires a verified owned declaration, an eligible activity-setup state, and no pending withdrawal.");
        return out;
    }
    const QString id = state.value("declarationId").toString();
    const qint64 runStart = blendRunStartedAt();
    if (runStart <= 0 || status() != Running) { out["error"] = QStringLiteral("Cannot verify the current node run."); return out; }
    const QString path = QStringLiteral("/sdp/set-declaration-id");
    const auto reply = BlendLifecycle::request(resolveCurl(), curlEnv(), {path}, QStringLiteral("POST"), QStringLiteral("\"%1\"").arg(id)).value(path);
    if (!reply.ok() || blendRunStartedAt() != runStart) {
        out["error"] = reply.ok() ? QStringLiteral("The node restarted during repair; binding is unknown.") : nodeApiError(reply.body, reply.code);
        return out;
    }
    m_blendRepairedAt = QDateTime::currentMSecsSinceEpoch();
    m_blendRepairedId = id;
    out["ok"] = true;
    out["message"] = QStringLiteral("Local binding acknowledged. Await the next accepted activity and epoch snapshot; this is not activity or payout success.");
    return out;
}

#include "BlendMutation.h"

QVariantMap LogosNode1clickBackend::declareBlendCore(QString locator, QString lockedNoteId)
{
    if (blendRecoveryBlocks())
        return {{"ok", false}, {"tx", QString()}, {"error", "Unfinished Blend recovery owns this declaration; manual declaration is blocked, including while paused."}};
    QVariantMap out;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("tx"), QString());
    out.insert(QStringLiteral("error"), QString());

    if (m_blendMutation || m_blendReading || m_blendWithdrawalPending || loadBlendDecl().value("withdraw_pending").toBool()) {
        out["error"] = QStringLiteral("A Blend operation or withdrawal is already pending.");
        return out;
    }
    QScopedValueRollback<bool> mutation(m_blendMutation, true);
    const QVariantMap lifecycle = getBlendLifecycle();
    if (!lifecycle.value("ok").toBool()
        || (lifecycle.value("state") != "no-declaration" && lifecycle.value("state") != "removed")) {
        out["error"] = QStringLiteral("A declaration exists, is pending, or ownership cannot be verified. Refresh or manage the existing declaration instead.");
        return out;
    }
    QString loc = locator.trimmed();
    if (loc.isEmpty())
        loc = buildBlendLocator();
    if (loc.isEmpty()) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("Couldn't determine this node's public address for the Blend "
                                  "locator. Set external_address in the config, or check your "
                                  "internet connection, and try again."));
        return out;
    }
    const QString note = lockedNoteId.trimmed();
    if (note.isEmpty()) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("No note to lock as the provider stake — fund a node key first."));
        return out;
    }

    QJsonObject body;
    body.insert(QStringLiteral("locator"), loc);
    body.insert(QStringLiteral("locked_note_id"), note);
    const QString jsonBody =
        QString::fromUtf8(QJsonDocument(body).toJson(QJsonDocument::Compact));

    // Write ahead before POST: a timeout may still have submitted a transaction.
    // Keep the original record so a rejected attempt cannot overwrite history.
    const QJsonObject previous = loadBlendDecl();
    QJsonObject pending = previous;
    pending["submission_pending"] = true;
    pending["locked_note_id"] = note;
    pending["locator"] = loc;
    m_blendSubmissionPending = true;
    saveBlendDecl(pending);
    if (loadBlendDecl() != pending) {
        m_blendSubmissionPending = previous.value("submission_pending").toBool();
        out["error"] = QStringLiteral("Cannot persist pending declaration state. No request was sent; check local storage permissions and space.");
        return out;
    }
    QString code;
    const auto reply = BlendLifecycle::request(resolveCurl(), curlEnv(), {QStringLiteral("/blend/join")}, QStringLiteral("POST"), jsonBody).value(QStringLiteral("/blend/join"));
    const QString resp = reply.body;
    code = reply.code;
    if (BlendMutation::definitivelyRejected(code)) {
        const QJsonObject restored = BlendMutation::afterReply(previous, pending, code);
        saveBlendDecl(restored);
        m_blendSubmissionPending = restored.value("submission_pending").toBool();
        out["error"] = nodeApiError(resp, code);
        return out;
    }
    if (code.isEmpty()) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("Declaration outcome is uncertain: the node may have received the request. Pending state is retained; this operation cannot be automatically retried because it could duplicate a paid transaction. Refresh to reconcile."));
        return out;
    }
    if (!code.startsWith(QLatin1Char('2'))) {
        out.insert(QStringLiteral("error"), nodeApiError(resp, code)
                   + QStringLiteral(" Declaration outcome is uncertain. Pending state is retained; this operation cannot be automatically retried because it could duplicate a paid transaction. Refresh to reconcile."));
        return out;
    }
    // 0.2.4 returns the new DeclarationId (Option<DeclarationId>) — a hex string,
    // possibly JSON-quoted, or `null`. Strip quotes/whitespace for storage + display.
    const QString declId = BlendLifecycle::joinId(resp);
    if (declId.isEmpty()) {
        out["error"] = QStringLiteral("The node returned no declaration ID; declaration outcome is uncertain. Pending state is retained; this operation cannot be automatically retried because it could duplicate a paid transaction. Refresh to reconcile.");
        return out;
    }

    // Write-ahead: persist so Disable can withdraw this exact declaration and
    // refreshBlendStatus can report Activating until core_info populates.
    QJsonObject store;
    store.insert(QStringLiteral("declaration_id"), declId);
    store.insert(QStringLiteral("locked_note_id"), note);
    store.insert(QStringLiteral("locator"), loc);
    store.insert(QStringLiteral("created_at"),
                 QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    saveBlendDecl(store);
    m_blendSubmissionPending = false;

    out.insert(QStringLiteral("ok"), true);
    out.insert(QStringLiteral("tx"), declId);
    // Reflect the new state immediately (don't wait for the next refresh tick).
    if (status() == Running)
        setBlendStatus(Activating);
    return out;
}

QVariantMap LogosNode1clickBackend::getBlendDeclarations()
{
    QVariantMap out;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("count"), 0);
    out.insert(QStringLiteral("mineId"), QString());
    out.insert(QStringLiteral("mineCreated"), -1);
    out.insert(QStringLiteral("mineActive"), -1);
    out.insert(QStringLiteral("mineWithdrawAt"), -1);

    if (m_blendReading || m_blendMutation) {
        out["error"] = QStringLiteral("A Blend operation is already in progress.");
        return out;
    }
    QScopedValueRollback<bool> reading(m_blendReading, true);
    const QString declarationsPath = QStringLiteral("/mantle/sdp/declarations");
    const QString timePath = QStringLiteral("/time/info");
    const auto replies = BlendLifecycle::request(resolveCurl(), curlEnv(), {declarationsPath, timePath});
    const auto reply = replies.value(declarationsPath);
    if (!reply.ok()) return out;
    const QJsonDocument doc = QJsonDocument::fromJson(reply.body.toUtf8());
    if (!doc.isObject()) return out;
    const QJsonObject o = doc.object();   // { <declId>: Declaration, ... }
    out.insert(QStringLiteral("ok"), true);
    out.insert(QStringLiteral("total"), o.size());   // all BN declarations ever (incl. dead)
    // Live "Blend network size" = declarations still ACTIVE this epoch, per the ledger rule
    // is_active: active + inactivity_period(2) >= epoch AND (withdraw_at null or > epoch).
    const auto timeReply = replies.value(timePath);
    const int nowEpoch = timeReply.ok() ? QJsonDocument::fromJson(timeReply.body.toUtf8()).object().value("current_epoch").toInt(-1) : -1;
    static const int kInactivityPeriod = 2;
    int activeCount = 0;
    for (auto it = o.begin(); it != o.end(); ++it) {
        const QJsonObject d = it.value().toObject();
        if (d.value(QStringLiteral("service_type")).toString() != QStringLiteral("BN"))
            continue;
        const int a = (int) d.value(QStringLiteral("active")).toDouble(-1);
        const QJsonValue w = d.value(QStringLiteral("withdraw_at"));
        const int wat = w.isDouble() ? (int) w.toDouble() : -1;
        if (a >= 0 && nowEpoch >= 0 && a + kInactivityPeriod >= nowEpoch && (wat < 0 || wat > nowEpoch))
            ++activeCount;
    }
    // Show the live count when we know the epoch; else fall back to the raw total (never 0).
    out.insert(QStringLiteral("count"), nowEpoch >= 0 ? activeCount : o.size());
    out.insert(QStringLiteral("nowEpoch"), nowEpoch);   // for the modal's declaration-health gate

    const QVariantMap match = BlendLifecycle::match(o, blendSigningKey(), loadBlendDecl().value("declaration_id").toString());
    if (!match.value("ok").toBool()) {
        out["ok"] = false;
        out["error"] = match.value("error");
        return out;
    }
    const QString id = match.value("id").toString();
    if (!id.isEmpty()) {
        const QVariantMap d = match.value("record").toMap();
        const int active = d.value("active", -1).toInt();
        const int withdrawal = d.value("withdraw_at").isNull() ? -1 : d.value("withdraw_at").toInt();
        out["mineId"] = id;
        out["mineCreated"] = d.value("created", -1);
        out["mineActive"] = active;
        out["mineWithdrawAt"] = withdrawal;
        out["mineInactiveSince"] = active < 0 ? -1 : active + 3;
        out["mineLive"] = active >= 0 && nowEpoch >= 0 && active + 2 >= nowEpoch
            && (withdrawal < 0 || withdrawal > nowEpoch);
        // Full record fields for the Activation/Active pages' provider record + stake.
        out["mineNonce"] = d.value("nonce", -1);
        out["mineNote"] = d.value("locked_note_id").toString();
        out["mineProvider"] = d.value("provider_id").toString();
        out["mineZk"] = d.value("zk_id").toString();
        const QVariantList locs = d.value("locators").toList();
        out["mineLocator"] = locs.isEmpty() ? QString() : locs.first().toString();
    }
    return out;
}

QVariantMap LogosNode1clickBackend::withdrawBlendCore()
{
    if (blendRecoveryBlocks())
        return {{"ok", false}, {"error", "Unfinished Blend recovery owns this declaration; manual withdrawal is blocked, including while paused."}};
    QVariantMap out;
    out.insert(QStringLiteral("ok"), false);
    out.insert(QStringLiteral("error"), QString());

    if (m_blendMutation || m_blendReading || m_blendWithdrawalPending || loadBlendDecl().value("withdraw_pending").toBool()) {
        out["error"] = QStringLiteral("A Blend operation or withdrawal is already pending.");
        return out;
    }
    QScopedValueRollback<bool> mutation(m_blendMutation, true);
    const QVariantMap state = getBlendLifecycle();
    if (!state.value("ok").toBool() || state.value("withdrawAt", -1).toInt() >= 0) {
        out["error"] = QStringLiteral("Cannot verify ownership, or withdrawal is already scheduled.");
        return out;
    }
    const QString declId = state.value("declarationId").toString();
    if (declId.isEmpty()) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("Couldn't find this node's Blend declaration to withdraw — it "
                                  "may have been declared on another machine, or already withdrawn."));
        return out;
    }

    // POST /sdp/withdrawal — the body is the bare DeclarationId, JSON-encoded as a
    // quoted hex string (verified against the 0.2.4 handler: Json<DeclarationId>).
    const QString jsonBody = QStringLiteral("\"%1\"").arg(declId);
    QJsonObject previous = loadBlendDecl();
    previous["declaration_id"] = declId; // preserve verified identity even on rejection
    QJsonObject pending = previous;
    pending["withdraw_pending"] = true;
    m_blendWithdrawalPending = true;
    saveBlendDecl(pending);
    if (loadBlendDecl() != pending) {
        m_blendWithdrawalPending = previous.value("withdraw_pending").toBool();
        out["error"] = QStringLiteral("Cannot persist pending withdrawal state. No request was sent; check local storage permissions and space.");
        return out;
    }
    QString code;
    const auto reply = BlendLifecycle::request(resolveCurl(), curlEnv(), {QStringLiteral("/sdp/withdrawal")}, QStringLiteral("POST"), jsonBody).value(QStringLiteral("/sdp/withdrawal"));
    const QString resp = reply.body;
    code = reply.code;
    if (BlendMutation::definitivelyRejected(code)) {
        const QJsonObject restored = BlendMutation::afterReply(previous, pending, code);
        saveBlendDecl(restored);
        m_blendWithdrawalPending = restored.value("withdraw_pending").toBool();
        out["error"] = nodeApiError(resp, code);
        return out;
    }
    if (code.isEmpty()) {
        out.insert(QStringLiteral("error"),
                   QStringLiteral("Withdrawal outcome is uncertain: the node may have received the request. Pending state is retained; this operation cannot be automatically retried because it could duplicate a paid transaction. Refresh to reconcile."));
        return out;
    }
    if (!code.startsWith(QLatin1Char('2'))) {
        out.insert(QStringLiteral("error"), nodeApiError(resp, code)
                   + QStringLiteral(" Withdrawal outcome is uncertain. Pending state is retained; this operation cannot be automatically retried because it could duplicate a paid transaction. Refresh to reconcile."));
        return out;
    }
    // An acknowledgement is not inclusion or unlock. Preserve the exact identity
    // until a later snapshot confirms the withdrawal epoch has taken effect.
    QJsonObject store = loadBlendDecl();
    store["declaration_id"] = declId;
    store["withdraw_pending"] = true;
    saveBlendDecl(store);
    out.insert(QStringLiteral("ok"), true);
    return out;
}

QVariantMap LogosNode1clickBackend::getSdpFundingKey()
{
    QVariantMap out;
    const QString key = sdpFundingKey();
    const int port = blendPortFromConfig();
    const QString ip = resolvePublicIp();
    const QString loc = ip.isEmpty()
        ? QString()
        : QStringLiteral("/ip4/%1/udp/%2/quic-v1").arg(ip).arg(port);
    out.insert(QStringLiteral("ok"), !key.isEmpty());
    out.insert(QStringLiteral("key"), key);
    out.insert(QStringLiteral("blendPort"), port);
    out.insert(QStringLiteral("publicIp"), ip);
    out.insert(QStringLiteral("locator"), loc);
    return out;
}

QVariantMap LogosNode1clickBackend::checkBlendPortReachable()
{
    QVariantMap out;
    const int port = blendPortFromConfig();
    out.insert(QStringLiteral("ok"), true);
    out.insert(QStringLiteral("blendPort"), port);
    // BEST-EFFORT, LOCAL ONLY. Try to bind udp/<port>: a bind that FAILS (address in
    // use) means the node — or another relay — already holds the port, i.e. a local
    // listener exists. A successful bind means nothing is listening. This cannot test
    // inbound NAT/port-forward reachability from the internet (the node binds udp/3400
    // only once it reaches Core, and a shared public IP allows one relay per port), so
    // the modal pairs this with the port-forward guide + an operator attestation.
    QUdpSocket probe;
    const bool bound = probe.bind(QHostAddress::AnyIPv4, static_cast<quint16>(port));
    if (bound) {
        probe.close();
        out.insert(QStringLiteral("listening"), false);
        out.insert(QStringLiteral("note"),
                   QStringLiteral("Nothing is listening on udp/%1 locally yet — the node binds it "
                                  "once your declaration reaches Core.").arg(port));
    } else {
        out.insert(QStringLiteral("listening"), true);
        out.insert(QStringLiteral("note"),
                   QStringLiteral("A local listener holds udp/%1. Inbound reachability from the "
                                  "internet still depends on your router's port-forward.").arg(port));
    }
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
// How far past a claim's submission slot LIB must advance -- and we must have
// SCANNED -- before absence is treated as a fact rather than a wait.
//
// A claim is included within ~20 slots or never: 7 unlanded claims were absent
// from 1,586 blocks across 6h while 40 unrelated leader-claims landed in the same
// window. So once LIB is past the submission slot the question is already decided;
// the margin is slack for block-rate jitter, not a waiting period.
//
// Calibrated against the node, not derived: on 2026-08-19 the claimable pool went
// 0 -> 7 when LIB reached 148 slots past submission, i.e. the node had released
// those reservations by then. Earlier versions waited 20000 slots (~5.5h) and then
// security_param=120 blocks (~1.6h) -- both far past the point the node had already
// answered, which is what put "Ready to claim 7" next to "Submitted 7" on screen.
static constexpr int kDecisionMarginSlots = 200;
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

// Proposals recorded in the durable store. Used ONLY as a ceiling on how many
// vouchers could have been newly earned while a claim was in flight, so that
// leadership during the wait is never mistaken for a released reservation.
// Reads the file rather than getProposals() because the caller needs a number,
// not a list, and getProposals() also rescans logs.
int LogosNode1clickBackend::proposalCount() const
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return 0;
    QFile f(QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("proposals-history.json")));
    if (!f.open(QIODevice::ReadOnly))
        return 0;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    return doc.isArray() ? doc.array().size() : 0;
}

// Count of vouchers the node currently reports as claimable.
//
// This is the ONLY authoritative statement about a reservation that we can read.
// A voucher held by an in-flight claim is reserved and therefore absent from this
// list; when the node gives up on that claim it releases the reservation and the
// voucher reappears here. So a RISE in this count, with claims outstanding, is
// direct evidence that those claims are dead -- observed, not inferred, and it
// arrives about an hour before any timer we could set. Measured 2026-08-19: the
// pool went 0 -> 7 the moment LIB passed 148 slots beyond the submission slot,
// while our 120-block timer would not have fired for another hour. The UI showed
// "Ready to claim 7" and "Submitted 7" side by side for 54 minutes -- the same
// seven vouchers in two states that cannot both be true.
//
// Returns -1 when the count is unknown, which callers MUST treat as "no evidence"
// rather than as zero.
int LogosNode1clickBackend::claimableVoucherCount()
{
    if (!m_blockchainClient || status() != BlockchainStatus::Running)
        return -1;
    const LogosResult r = result::toLogosResult(m_blockchainClient->invokeRemoteMethod(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("wallet_get_claimable_vouchers")));
    if (!r.success)
        return -1;
    const QJsonObject o = QJsonDocument::fromJson(r.value.toString().toUtf8()).object();
    // Tolerate both shapes, as everywhere else: wrapped {vouchers:[...]} and bare [...].
    if (o.contains(QStringLiteral("vouchers")))
        return o.value(QStringLiteral("vouchers")).toArray().size();
    const QJsonArray arr = QJsonDocument::fromJson(r.value.toString().toUtf8()).array();
    return arr.isEmpty() && !o.isEmpty() ? -1 : arr.size();
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

    // Pool level WITH this claim's reservation already held. The claim has just been
    // accepted, so the voucher it took is no longer claimable; anything above this
    // number later is a voucher that came back (or one newly earned -- see the
    // proposal guard in the resolve pass).
    const int poolAtSubmit = claimableVoucherCount();

    QJsonObject row;
    row.insert(QStringLiteral("tx"), txHash);
    row.insert(QStringLiteral("status"), QStringLiteral("submitted"));
    row.insert(QStringLiteral("submittedAt"),
               QDateTime::currentDateTime().toString(Qt::ISODate));
    row.insert(QStringLiteral("submittedAtSlot"), tipSlot);
    if (poolAtSubmit >= 0)
        row.insert(QStringLiteral("poolAtSubmit"), poolAtSubmit);
    row.insert(QStringLiteral("proposalsAtSubmit"), proposalCount());
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
        // Archived rows are known too — a cleared claim must not be re-adopted (#50).
        for (const QJsonValue& c : store.value(QStringLiteral("archived")).toArray())
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

    // Cleared rows (#50). Archived is still KNOWN: without this set the chain
    // scan would backfill every settled claim the user just cleared.
    QSet<QString> archivedTx;
    const QJsonArray archived = store.value(QStringLiteral("archived")).toArray();
    for (const QJsonValue& v : archived)
        archivedTx.insert(v.toObject().value(QStringLiteral("tx")).toString());

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
        constexpr int kScanVersion = 13;
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
            // Earliest slot whose get_block_events failed. The watermark must not
            // pass it: a block scanned once is never re-read, so advancing past a
            // failed-events block loses its settlements FOREVER — the 08-25 audit
            // found 20 landed claims mislabeled exactly this way (12 "expired",
            // 8 stuck "submitted") while their rewards sat in the balance.
            int firstFailedSlot = -1;
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
                        {
                            const int fs = hdr.value(QStringLiteral("slot")).toInt();
                            if (firstFailedSlot < 0 || fs < firstFailedSlot)
                                firstFailedSlot = fs;
                        }
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

                        if (!rowByTx.contains(txHash) && archivedTx.contains(txHash))
                            continue;  // cleared by the user — stay cleared (#50)
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
                // Hold the watermark BEFORE the earliest block whose events failed,
                // so that block is re-read next pass instead of its settlements
                // being lost (see firstFailedSlot above).
                const int upTo = (firstFailedSlot > 0 && firstFailedSlot <= to)
                                     ? firstFailedSlot - 1
                                     : to;
                if (upTo > from)
                    store.insert(QStringLiteral("lastScannedSlot"), upTo);
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

    // --- resolve submissions that never landed -----------------------------
    //
    // Two conditions, and BOTH must hold. Neither alone is safe:
    //
    //   (1) DECIDABLE. LIB has passed the submission slot by kDecisionMarginSlots,
    //       AND we have actually scanned that far. A claim is included within ~20
    //       slots or never (measured: 7 unlanded claims were absent from 1,586
    //       blocks over 6h), so once that window is final and read, absence is a
    //       fact rather than a wait. The scan check matters independently: without
    //       it, "not found" can mean "not looked", which is how a watermark bug
    //       once marked 126k slots read that were never fetched.
    //
    //   (2) THE POOL AGREES. The node reports more claimable vouchers than when
    //       this claim was submitted. A voucher held by an in-flight claim is
    //       reserved and absent from that list, so its reappearance is the node
    //       telling us the reservation was released -- observation, not inference.
    //
    // Condition 2 is skipped for rows written before poolAtSubmit existed, and
    // when the count is unavailable; condition 1 still gates those.
    //
    // This replaces a timer (previously security_param blocks, before that a flat
    // 20000 slots). The timer was not merely slow, it was incoherent: on 2026-08-19
    // the panel showed "Ready to claim 7" beside "Submitted 7" for 54 minutes --
    // the same seven vouchers, simultaneously available and reserved. The pool was
    // right and the timer was still counting.
    if (libSlot > 0) {
        const int scanned = store.value(QStringLiteral("lastScannedSlot")).toInt();
        const int poolNow = claimableVoucherCount();
        // An upper bound on how many of the extra vouchers are newly EARNED rather
        // than returned, so leadership during the wait cannot be mistaken for a
        // release. Proposals are the ceiling: not every proposal yields a voucher.
        const int proposalsNow = proposalCount();

        for (int i = 0; i < claims.size(); ++i) {
            QJsonObject row = claims.at(i).toObject();
            if (row.value(QStringLiteral("status")).toString() != QLatin1String("submitted"))
                continue;
            const int at = row.value(QStringLiteral("submittedAtSlot")).toInt();
            if (at <= 0)
                continue;
            const int horizon = at + kDecisionMarginSlots;
            if (libSlot < horizon || scanned < horizon)
                continue;                       // (1) not decidable yet

            if (row.contains(QStringLiteral("poolAtSubmit")) && poolNow >= 0) {
                const int was = row.value(QStringLiteral("poolAtSubmit")).toInt();
                const int earned = qMax(0, proposalsNow
                                        - row.value(QStringLiteral("proposalsAtSubmit")).toInt());
                if (poolNow - earned <= was)
                    continue;                   // (2) pool shows no returned voucher
                row.insert(QStringLiteral("resolvedBy"), QStringLiteral("pool"));
            } else {
                row.insert(QStringLiteral("resolvedBy"), QStringLiteral("finality"));
            }

            // "checking", NOT a terminal verdict. The pool inference produced 20
            // false "expired" labels on landed claims (08-25 explorer audit) — it
            // is a hint that the claim MAY have died, and the explorer pass below
            // delivers the observed verdict: settled (found) or failed (absent).
            row.insert(QStringLiteral("status"), QStringLiteral("checking"));
            row.insert(QStringLiteral("inferred"), true);
            claims.replace(i, row);
            changed = true;
        }
    }

    // --- verify unresolved claims against the public explorer ----------------
    // Settlement truth is OBSERVED, never inferred (#47). The explorer indexes
    // the canonical chain independently of this node's wallet-scan state — the
    // state whose stall caused the 08-21→08-24 incident. Rows in "checking"
    // (and legacy "expired") get a tx-by-hash lookup: found → settled (the block
    // scan backfills reward/fee when it catches up), verified absent → failed.
    // Explorer unreachable → stays "checking"; never guess.
    {
        const QString curl = resolveCurl();
        int budget = 6;  // keep each ledger pass cheap; the 20s timer drains the queue
        static qint64 s_forkFetchedAtMs = 0;
        static int s_forkId = -1;
        const QString base = QStringLiteral("https://testnet.blockchain.logos.co/web/explorer/api/v1");
        const auto httpGet = [&curl](const QString& url, int* codeOut) -> QString {
            QProcess p;
            p.setProcessEnvironment(curlEnv());
            p.start(curl, {QStringLiteral("-s"), QStringLiteral("-m"), QStringLiteral("8"),
                           QStringLiteral("-w"), QStringLiteral("\n%{http_code}"), url});
            if (!p.waitForFinished(10000)) { p.kill(); *codeOut = -1; return QString(); }
            const QString out = QString::fromUtf8(p.readAllStandardOutput());
            const int nl = out.lastIndexOf(QLatin1Char('\n'));
            *codeOut = out.mid(nl + 1).trimmed().toInt();
            return out.left(qMax(0, nl));
        };
        for (int i = 0; i < claims.size() && budget > 0 && !curl.isEmpty(); ++i) {
            QJsonObject row = claims.at(i).toObject();
            const QString st = row.value(QStringLiteral("status")).toString();
            // Eligible: unresolved rows awaiting a verdict, AND explorer-settled
            // rows still missing their reward (re-queried so the block-events
            // recovery below can price them).
            const bool unresolved = (st == QLatin1String("checking")
                                     || st == QLatin1String("expired"))
                                    && row.value(QStringLiteral("verifiedBy")).toString()
                                           != QLatin1String("explorer");
            const bool amountMissing = st == QLatin1String("settled")
                                       && row.value(QStringLiteral("verifiedBy")).toString()
                                              == QLatin1String("explorer")
                                       && !row.contains(QStringLiteral("reward"));
            // In-flight rows get promoted to "in a block, finalizing" the moment
            // the explorer sees them at the tip — true reassurance instead of an
            // anxious hour of "Claiming…" while finality catches up (26 Aug).
            // Give propagation ~2 min first; a 404 here means "not yet", never
            // "dead", so it leaves the row untouched.
            const bool inFlight = st == QLatin1String("submitted")
                && QDateTime::fromString(row.value(QStringLiteral("submittedAt")).toString(),
                                         Qt::ISODate)
                       .secsTo(QDateTime::currentDateTime()) > 120;
            if (!unresolved && !amountMissing && !inFlight)
                continue;
            const QString tx = row.value(QStringLiteral("tx")).toString();
            if (tx.size() != 64)
                continue;
            if (s_forkId < 0 || QDateTime::currentMSecsSinceEpoch() - s_forkFetchedAtMs > 60000) {
                int code = 0;
                const QString body = httpGet(base + QStringLiteral("/fork-choice"), &code);
                if (code == 200) {
                    s_forkId = QJsonDocument::fromJson(body.toUtf8())
                                   .object().value(QStringLiteral("fork")).toInt(-1);
                    s_forkFetchedAtMs = QDateTime::currentMSecsSinceEpoch();
                }
                if (s_forkId < 0)
                    break;  // explorer unreachable — leave every row as "checking"
            }
            int code = 0;
            const QString body = httpGet(base + QStringLiteral("/transactions/") + tx
                        + QStringLiteral("?fork=") + QString::number(s_forkId), &code);
            --budget;
            if (code == 404 && st == QLatin1String("submitted"))
                continue;  // not in a block YET — leave the row alone
            if (code == 200) {
                // A submitted row seen at the TIP is "in a block, finalizing" —
                // not settled (finality pending), but the reward/fee recovery
                // below applies just the same: the node has the tip block, and
                // the balance has already counted it. The finality scan flips
                // in_block → settled later.
                const bool preFinal = st == QLatin1String("submitted");
                row.insert(QStringLiteral("status"),
                           preFinal ? QStringLiteral("in_block") : QStringLiteral("settled"));
                row.insert(QStringLiteral("verifiedBy"), QStringLiteral("explorer"));
                row.remove(QStringLiteral("inferred"));
                // The explorer payload names the BLOCK; the node has that block
                // even though the scan's watermark moved past it (that's how the
                // row got lost). One targeted get_block_events recovers the
                // reward; the tx's LedgerTransfer op carries the fee ingredients.
                const QJsonObject txo = QJsonDocument::fromJson(body.toUtf8()).object();
                const QString blockId = txo.value(QStringLiteral("block_hash")).toString();
                if (!blockId.isEmpty())
                    row.insert(QStringLiteral("block"), blockId);
                if (preFinal && !blockId.isEmpty() && !row.contains(QStringLiteral("slot"))) {
                    // Block slot → the QML computes the finalize ETA against LIB.
                    int bc = 0;
                    const QString bb = httpGet(base + QStringLiteral("/blocks/") + blockId
                        + QStringLiteral("?fork=") + QString::number(s_forkId), &bc);
                    if (bc == 200) {
                        const double bslot = QJsonDocument::fromJson(bb.toUtf8())
                                                 .object().value(QStringLiteral("slot")).toDouble();
                        if (bslot > 0)
                            row.insert(QStringLiteral("slot"), bslot);
                    }
                }
                for (const QJsonValue& ov : txo.value(QStringLiteral("operations")).toArray()) {
                    const QJsonObject c = ov.toObject().value(QStringLiteral("content")).toObject();
                    const QString type = c.value(QStringLiteral("type")).toString();
                    if (type == QLatin1String("LeaderClaim")) {
                        row.insert(QStringLiteral("voucherNf"),
                                   c.value(QStringLiteral("voucher_nullifier")).toString());
                    } else if (type == QLatin1String("LedgerTransfer")) {
                        const QJsonArray in = c.value(QStringLiteral("inputs")).toArray();
                        const QJsonArray outs = c.value(QStringLiteral("outputs")).toArray();
                        if (in.size() == 1 && outs.size() == 1) {
                            row.insert(QStringLiteral("feeInput"), in.at(0).toString());
                            row.insert(QStringLiteral("feeChange"),
                                       outs.at(0).toObject().value(QStringLiteral("value")).toDouble());
                        }
                    }
                }
                if (!blockId.isEmpty() && !row.contains(QStringLiteral("reward"))) {
                    const LogosResult ev = result::toLogosResult(
                        m_blockchainClient->invokeRemoteMethod(
                            BLOCKCHAIN_MODULE_NAME, QStringLiteral("get_block_events"), blockId));
                    if (ev.success) {
                        const QJsonArray events =
                            QJsonDocument::fromJson(ev.value.toString().toUtf8()).array();
                        for (const QJsonValue& evv : events) {
                            const QJsonObject etx =
                                evv.toObject().value(QStringLiteral("Tx")).toObject();
                            if (etx.value(QStringLiteral("tx_hash")).toString() != tx)
                                continue;
                            const QJsonObject claimed =
                                etx.value(QStringLiteral("payload")).toObject()
                                   .value(QStringLiteral("LeaderRewardClaimed")).toObject();
                            if (claimed.isEmpty())
                                continue;
                            row.insert(QStringLiteral("reward"),
                                       claimed.value(QStringLiteral("utxo")).toObject()
                                              .value(QStringLiteral("note")).toObject()
                                              .value(QStringLiteral("value")).toDouble());
                            break;
                        }
                    }
                }
            } else if (code == 404) {
                row.insert(QStringLiteral("status"), QStringLiteral("failed"));
                row.insert(QStringLiteral("verifiedBy"), QStringLiteral("explorer"));
            } else {
                continue;  // transient — retry on a later pass
            }
            claims.replace(i, row);
            changed = true;
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
    int settled = 0, inFlight = 0, feesKnown = 0, checking = 0, failedVerified = 0;
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
        } else if (st == QLatin1String("checking") || st == QLatin1String("expired")) {
            ++checking;
        } else if (st == QLatin1String("failed")) {
            // Alarm only on RECENT verified failures (last 2 epochs). Historical
            // ones — e.g. the pre-rescan dead retries — are records, not a
            // condition; alarming on them would tell an operator to rescan a
            // node that is already healthy.
            const int at = r.value(QStringLiteral("submittedAtSlot")).toInt();
            if (at > 0 && libSlot > 0 && libSlot - at < 72000)
                ++failedVerified;
        }
    }

    // The alarm looks THROUGH the archive (#50): clearing the list must not
    // silence a live failure streak.
    for (const QJsonValue& v : store.value(QStringLiteral("archived")).toArray()) {
        const QJsonObject r = v.toObject();
        if (r.value(QStringLiteral("status")).toString() != QLatin1String("failed"))
            continue;
        const int at = r.value(QStringLiteral("submittedAtSlot")).toInt();
        if (at > 0 && libSlot > 0 && libSlot - at < 72000)
            ++failedVerified;
    }

    QJsonObject summary;
    summary.insert(QStringLiteral("settled"), settled);
    summary.insert(QStringLiteral("inFlight"), inFlight);
    summary.insert(QStringLiteral("checking"), checking);
    // Claims the EXPLORER confirmed absent — the only verdict that may alarm.
    // >=2 of these is the stale-wallet-state signature (08-24 incident) and the
    // UI surfaces the rescan remedy — UNLESS a claim SETTLED in the same window:
    // stale wallet state cannot settle anything, so one recent settle disproves
    // the diagnosis (26 Aug: three fee-priced-out claims false-alarmed a healthy
    // node that had settled a claim the same hour).
    {
        bool recentSettle = false;
        const auto settledRecently = [&](const QJsonArray& rows) {
            for (const QJsonValue& v : rows) {
                const QJsonObject r = v.toObject();
                const QString rs = r.value(QStringLiteral("status")).toString();
                // in_block counts too: a stale wallet's claims cannot land in a
                // block any more than they can settle.
                if (rs != QLatin1String("settled") && rs != QLatin1String("in_block"))
                    continue;
                const int at = r.value(QStringLiteral("slot")).toInt(
                    r.value(QStringLiteral("submittedAtSlot")).toInt());
                if (at > 0 && libSlot > 0 && libSlot - at < 72000)
                    return true;
            }
            return false;
        };
        recentSettle = settledRecently(claims)
                       || settledRecently(store.value(QStringLiteral("archived")).toArray());
        if (recentSettle)
            failedVerified = 0;
    }
    summary.insert(QStringLiteral("failedVerified"), failedVerified);
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

// Clear the visible claims list (#50): move every row into the store's
// `archived` array. Nothing is deleted — totals, the chain-scan backfill
// suppression and the alarm's recent-failure counting all read the archive,
// so a clear tidies the view without erasing evidence or silencing a streak.
QVariantMap LogosNode1clickBackend::clearLeaderClaims()
{
    QJsonObject store = loadClaimStore();
    QJsonArray claims = store.value(QStringLiteral("claims")).toArray();
    QJsonArray archived = store.value(QStringLiteral("archived")).toArray();
    const int moved = claims.size();
    for (const QJsonValue& v : claims)
        archived.append(v);
    store.insert(QStringLiteral("archived"), archived);
    store.insert(QStringLiteral("claims"), QJsonArray());
    store.insert(QStringLiteral("clearedAt"),
                 QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    saveClaimStore(store);
    QVariantMap res;
    res.insert(QStringLiteral("success"), true);
    res.insert(QStringLiteral("value"), QString::number(moved));
    return res;
}

// Clear the persisted proposals history (the durable proposals-history.json). Used by
// the Proposals "Clear" button and on reset/regenerate (a fresh chain or identity makes
// the old proposals stale). A subsequent getProposals() log scan repopulates only
// current-chain proposals (and after a chain reset the logs are gone too).
QVariantMap LogosNode1clickBackend::clearProposals()
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("No config loaded.")));
    const QString path = QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("proposals-history.json"));
    int removed = 0;
    QFile f(path);
    if (f.exists() && f.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
        f.close();
        if (doc.isArray()) removed = doc.array().size();
    }
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(QJsonArray()).toJson(QJsonDocument::Compact));
        f.close();
    }
    return result::toVariantMap(LogosResult{true, QVariant(QString::number(removed)), QVariant()});
}

// Blocks THIS node proposed, parsed from the node's own log. Cryptarchia leadership
// is private (each block's leader_key is per-note-derived, not a stable identity), so
// an on-chain leader_key match can't identify our blocks — but the node LOGS every block
// it produces ("proposed block HeaderId(<id>) with <n> transactions (<m> removed)"), which
// is authoritative. Same source the logos-node-dashboard uses. Returns {success, value:[…]}.
//
// tailBytes bounds how much of each log file is read: the frequent incremental
// refresh passes 1 MiB (cheap), but the scan-on-start passes 0 = WHOLE FILE so a
// proposal early in a large on-disk log is captured before it rotates off disk
// (mitigation for #88). Either way the durable store is union-only, never shrunk.
QVariantMap LogosNode1clickBackend::scanProposals(qint64 tailBytes)
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
                const qint64 tail = tailBytes > 0 ? qMin<qint64>(f.size(), tailBytes) : f.size();
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

    // 3) persist newly-seen proposals back to the durable store.
    //    DATA-LOSS GUARDS (a log-only scan must never erase accumulated history):
    //    (a) re-read the file right before writing and re-union — another refresh
    //        (onRowsInserted fires many during sync) may have added entries since
    //        step 1; without this a stale in-memory `out` would clobber them;
    //    (b) never shrink — if the on-disk set already has entries we don't, keep
    //        them; only ever write a superset;
    //    (c) write atomically via a temp file + rename so a concurrent reader can
    //        never observe a half-truncated file.
    if (changed && !storePath.isEmpty()) {
        QFile rf(storePath);
        if (rf.open(QIODevice::ReadOnly)) {
            const QJsonDocument d = QJsonDocument::fromJson(rf.readAll());
            rf.close();
            if (d.isArray()) {
                for (const QJsonValue& v : d.array()) {
                    const QVariantMap m = v.toObject().toVariantMap();
                    const QString id = m.value(QStringLiteral("id")).toString();
                    if (id.isEmpty() || seenIds.contains(id)) continue;
                    seenIds << id;
                    out.append(m);              // preserve entries added since step 1
                }
            }
        }
        std::sort(out.begin(), out.end(), [](const QVariant& a, const QVariant& b) {
            return a.toMap().value(QStringLiteral("time")).toString()
                 > b.toMap().value(QStringLiteral("time")).toString();
        });
        while (out.size() > 500) out.removeLast();
        const QString tmp = storePath + QStringLiteral(".tmp");
        QFile sf(tmp);
        if (sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            sf.write(QJsonDocument(QJsonArray::fromVariantList(out)).toJson(QJsonDocument::Compact));
            sf.flush();
            sf.close();
            QFile::remove(storePath);
            QFile::rename(tmp, storePath);      // atomic replace on the same fs
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

// Incremental refresh (frequent): only the tail of each log is read.
QVariantMap LogosNode1clickBackend::getProposals() { return scanProposals(1024 * 1024); }

// Thorough scan (scan-on-start / periodic): reads each on-disk log in full so a
// proposal early in a large file is captured before it rotates off disk (#88).
QVariantMap LogosNode1clickBackend::getProposalsFull() { return scanProposals(0); }

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
    const bool recoveryLocked = blendRecoveryBlocks();
    const bool sameRecoveryNode = m_blendRecovery
        && QFileInfo(toLocalPath(userConfig())).absoluteFilePath() == m_recoveryScope
        && !m_blendRecovery->state().value("provider").toString().isEmpty()
        && blendSigningKey().compare(m_blendRecovery->state().value("provider").toString(), Qt::CaseInsensitive) == 0;
    const bool stopped = status() == NotStarted || status() == Stopped;
    if (recoveryLocked && (!stopped || m_recoveryTick || !sameRecoveryNode)) {
        setLastErrorMessage(QStringLiteral("Unfinished Blend recovery blocks restarting a live node or changing its identity/configuration. Only the same stopped node may be explicitly started."));
        return;
    }
    m_blendRunFloor = QDateTime::currentMSecsSinceEpoch();
    m_blendRepairedAt = 0;
    m_blendRepairedId.clear();
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
    if (blendRecoveryBlocks()) {
        setLastErrorMessage(QStringLiteral("Unfinished Blend recovery blocks stopping the node, including while paused."));
        return;
    }
    m_blendRunFloor = QDateTime::currentMSecsSinceEpoch();
    m_blendRepairedAt = 0;
    m_blendRepairedId.clear();
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

    // ASYNC graceful stop — never block the UI thread. The old code called this
    // synchronously, and a WEDGED node never answers "stop", so the call hung: `status`
    // stayed Stopping forever, the onStatusChanged==Stopped handler never ran, and Stop /
    // Settings-reset / the recovery button all "did nothing". Now we fire-and-forget and
    // let the UI's stop-confirm probe decide the outcome:
    //   - node's API goes down        → the probe calls confirmStopped() (setStatus Stopped)
    //   - a clean "stop"/"not running" reply arrives first → we mark Stopped here
    //   - node never goes down (wedged) → the probe calls forceStopNow() after its deadline
    m_blockchainClient->invokeRemoteMethodAsync(
        BLOCKCHAIN_MODULE_NAME, QStringLiteral("stop"), QVariantList(),
        [this](QVariant res) {
            const LogosResult r = result::toLogosResult(res);
            if (r.success
                || r.error.toString().contains(QStringLiteral("not running"), Qt::CaseInsensitive)) {
                if (status() == Stopping)
                    setStatus(Stopped);
            }
            // A real error leaves us in Stopping; the stop-confirm probe force-kills after
            // its deadline. We do NOT force-kill here — SIGKILL leaves the module host dead
            // and un-restartable in-app, so it must be a genuine last resort, not the norm.
        });
}

// The UI's stop-confirm probe saw the node's API stop answering → it really is down,
// whatever the async "stop" reply said. Idempotent (no-op once already Stopped).
void LogosNode1clickBackend::confirmStopped()
{
    if (status() == Stopping || status() == Running || status() == Error)
        setStatus(Stopped);
}

// Last-resort force stop for a wedged node: find the process listening on the node's
// HTTP port (the in-process blockchain_module host) and SIGKILL it. Returns true only
// if it actually killed the module host (verified by cmdline), so a normal failure
// still surfaces as an error rather than silently claiming success.
bool LogosNode1clickBackend::forceStopNode()
{
    if (blendRecoveryBlocks()) return false;
    // Node HTTP port from the config's api.backend.listen_address; default 8080.
    int port = 8080;
    const QString cfg = userConfig();
    if (!cfg.isEmpty()) {
        QFile f(cfg);
        if (f.open(QIODevice::ReadOnly)) {
            const QString c = QString::fromUtf8(f.readAll());
            f.close();
            static const QRegularExpression re(QStringLiteral("listen_address:\\s*[0-9.]+:(\\d+)"));
            const QRegularExpressionMatch m = re.match(c);
            if (m.hasMatch()) port = m.captured(1).toInt();
        }
    }
    // PID listening on that TCP port.
    QProcess ss;
    ss.start(QStringLiteral("bash"), {QStringLiteral("-lc"),
        QStringLiteral("ss -H -ltnp 'sport = :%1' 2>/dev/null | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2").arg(port)});
    if (!ss.waitForFinished(3000)) { ss.kill(); ss.waitForFinished(500); return false; }
    bool ok = false;
    const int pid = QString::fromUtf8(ss.readAllStandardOutput()).trimmed().toInt(&ok);
    if (!ok || pid <= 1) return false;
    // Safety gate: only kill if this really is the blockchain module host — never some
    // unrelated process that happens to hold the port.
    QFile cl(QStringLiteral("/proc/%1/cmdline").arg(pid));
    if (!cl.open(QIODevice::ReadOnly)) return false;
    const QString cmdline = QString::fromUtf8(cl.readAll()).replace(QChar('\0'), QChar(' '));
    cl.close();
    if (!cmdline.contains(QStringLiteral("blockchain_module"))) return false;
    QProcess::execute(QStringLiteral("kill"), {QStringLiteral("-9"), QString::number(pid)});
    return true;
}

QString LogosNode1clickBackend::blendSigningKey() const
{
    // Same instance-dir walk as sdpFundingKey(), but the blend public key lives in the
    // KEYSTORE (public_keys.BlendSigning), not user_config.yaml.
    // Bind ownership to this instance only, never a neighbouring node's keystore.
    const QString cfg = userConfig().isEmpty() ? generatedUserConfigPath() : userConfig();
    if (cfg.isEmpty()) return {};
    const QStringList candidates{QFileInfo(cfg).absoluteDir().filePath(QStringLiteral("keystore.yaml"))};

    static const QRegularExpression hexRe(QStringLiteral("[0-9a-fA-F]{64}"));
    for (const QString& path : candidates) {
        QFile f(path);
        if (!f.exists() || !f.open(QIODevice::ReadOnly)) continue;
        const QStringList lines = QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'));
        f.close();
        bool inPublic = false;
        for (const QString& line : lines) {
            const QString t = line.trimmed();
            // Enter only the public_keys block; leave on any other top-level key
            // (esp. secret_keys) so we never surface a secret.
            if (!line.startsWith(QLatin1Char(' ')) && !line.startsWith(QLatin1Char('\t'))
                && t.endsWith(QLatin1Char(':')))
                inPublic = t.startsWith(QStringLiteral("public_keys:"));
            if (inPublic && t.startsWith(QStringLiteral("BlendSigning:"))) {
                const auto m = hexRe.match(t);
                if (m.hasMatch()) return m.captured(0);
            }
        }
    }
    return QString();
}

QVariantList LogosNode1clickBackend::buildAccounts(const QStringList& knownAddresses,
                                                   const QString& peerId) const
{
    const QString leaderPk = leaderFundingKey();
    const QString sdpPk = sdpFundingKey();
    const QString blendPk = blendSigningKey();
    const QString primary = knownAddresses.isEmpty() ? QString() : knownAddresses.first();

    auto mk = [](const QString& addr, const QString& label, const QString& hint,
                 const QString& group, bool fundable) {
        QVariantMap m;
        m[QStringLiteral("address")] = addr;
        m[QStringLiteral("label")] = label;
        m[QStringLiteral("hint")] = hint;
        m[QStringLiteral("group")] = group;
        m[QStringLiteral("fundable")] = fundable;
        return QVariant(m);
    };

    // ── Spendable: the wallet's known keys, labelled by their config role ──
    QVariantList out;
    for (const QString& addr : knownAddresses) {
        if (!leaderPk.isEmpty() && addr == leaderPk)
            out << mk(addr, tr("Leader funding key"),
                      tr("Funds block proposals — fund this to earn"),
                      QStringLiteral("spendable"), true);
        else if (!sdpPk.isEmpty() && addr == sdpPk)
            out << mk(addr, tr("Blend stake key"),
                      tr("Pays your Blend Core declaration stake"),
                      QStringLiteral("spendable"), true);
        else if (addr == primary)
            out << mk(addr, tr("Wallet"),
                      tr("Your spendable balance — faucet funds land here"),
                      QStringLiteral("spendable"), true);
        else
            out << mk(addr, tr("Wallet"),
                      tr("Another spendable key in your wallet"),
                      QStringLiteral("spendable"), true);
    }

    // ── Identity: signing keys, copy-only (no balance / no Fund) ──
    if (!blendPk.isEmpty() && !knownAddresses.contains(blendPk))
        out << mk(blendPk, tr("Blend public key"),
                  tr("Your node's Blend signing identity — matches the on-chain declaration"),
                  QStringLiteral("identity"), false);

    if (!peerId.isEmpty())
        out << mk(peerId, tr("Network key"),
                  tr("Your node's peer identity on the network"),
                  QStringLiteral("identity"), false);

    return out;
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

    // Enrich with per-key labels/hints/group (Spendable vs Identity) classified from the
    // node config + keystore, so the wallet view names each key instead of showing bare hex.
    // The network peer id (get_peer_id, derived from the node key, available even when the
    // node is down) becomes the "Network key" identity row.
    QString peerId;
    const QVariantMap pidRes = getPeerId();
    if (pidRes.value(QStringLiteral("success")).toBool())
        peerId = pidRes.value(QStringLiteral("value")).toString();
    const QVariantList all = buildAccounts(list, peerId);
    m_accountsModel->setAccounts(all);
    // Transfer / Channel-Deposit pickers see only spendable keys — never a signing key.
    QVariantList spendable;
    for (const QVariant& a : all)
        if (a.toMap().value(QStringLiteral("group")).toString() == QStringLiteral("spendable"))
            spendable << a;
    m_spendableModel->setAccounts(spendable);

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
    if (blendRecoveryBlocks())
        return result::toVariantMap(result::err(QStringLiteral("Unfinished Blend recovery blocks config/identity generation, including while paused.")));
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

    // initial_peers: use what the caller passed; if none survive, fall back to known-good bootstrap
    // peers so a fresh node NEVER ships an empty peer list. Empty initial_peers → empty
    // bootstrap.ibd.peers (injectIbdPeersFromInitialPeers has nothing to copy) → the node stalls in
    // ProlongedBootstrapPeriod with ParentMissing on restart. See #106. (Testnet fallback; refresh the
    // list if these seed nodes change.)
    QVariantList peersList;
    for (const QString& p : initialPeers) {
        if (!p.trimmed().isEmpty())
            peersList.append(p.trimmed());
    }
    if (peersList.isEmpty()) {
        static const char* const kDefaultBootstrapPeers[] = {
            "/ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWFrouXfmrR4nsLMtE7wu15DoMJ6VtoUtHinREZCvbWHar",
            "/ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWJRGau8M1rjT7R5e4YYsgdFhsMX35nRDtMwCDjxQkXAHz",
            "/ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWQXJavMDTRscjauFSgVAB1VLB6Rzpy2uY5SU9Tk7927tb"
        };
        for (const char* p : kDefaultBootstrapPeers) peersList.append(QString::fromLatin1(p));
    }
    normalized.insert("initial_peers", peersList);
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
    if (blendRecoveryBlocks())
        return result::toVariantMap(result::err(QStringLiteral("Unfinished Blend recovery blocks chain-state reset, including while paused.")));
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

    // A reset re-IBDs from genesis; the old proposals/claims history is stale → clear it.
    QFile::remove(dir.filePath(QStringLiteral("proposals-history.json")));
    QFile::remove(dir.filePath(QStringLiteral("claims-history.json")));

    setStatus(NotStarted);
    return result::toVariantMap(
        LogosResult{true, QVariant(removed.join(", ")), QVariant()});
}

// Last-resort stop, called by the UI's stop-confirm probe after its deadline when a wedged
// node never actually went down. SIGKILL the module host bound to the node's port, then mark
// Stopped (which lets the stop→wipe→start orchestration proceed). The host is dead afterward
// and only a Basecamp reopen respawns it, so a following in-app Start will fail until then.
void LogosNode1clickBackend::forceStopNow()
{
    if (blendRecoveryBlocks()) {
        setLastErrorMessage(QStringLiteral("Unfinished Blend recovery blocks force-stop, including while paused."));
        return;
    }
    writeNodeIntent(QStringLiteral("stopped"));
    forceStopNode();
    setStatus(Stopped);
}

// PREVIEW (#81): copy the node config (and keystore, if present) beside itself with a
// timestamp. A real workaround for the Settings "Back up config" action until the node
// offers one. Returns the backup path in `value`.
QVariantMap LogosNode1clickBackend::backupUserConfig()
{
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("No config loaded — nothing to back up.")));
    QFileInfo fi(cfg);
    if (!fi.exists())
        return result::toVariantMap(result::err(QStringLiteral("Config file not found: %1").arg(cfg)));
    const QString ts = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    const QDir dir = fi.absoluteDir();
    QStringList made;
    const QStringList names{fi.fileName(), QStringLiteral("keystore.yaml")};
    for (const QString& name : names) {
        const QString src = dir.filePath(name);
        if (!QFile::exists(src)) continue;
        QFileInfo sfi(name);
        const QString suffix = sfi.suffix().isEmpty() ? QStringLiteral("bak") : sfi.suffix();
        const QString dst = dir.filePath(QStringLiteral("%1_backup_%2.%3").arg(sfi.completeBaseName(), ts, suffix));
        if (QFile::copy(src, dst)) made.append(QFileInfo(dst).fileName());
    }
    if (made.isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("Backup failed (nothing copied).")));
    return result::toVariantMap(LogosResult{true, QVariant(dir.filePath(made.first())), QVariant()});
}

// Copy the keystore.yaml (beside the node config) to a user-chosen path — the Settings
// "Download keystore.yaml" action. Overwrites the destination if the user picked one.
QVariantMap LogosNode1clickBackend::saveKeystore(QString destPath)
{
    // Save-as can overwrite identity/config material through an arbitrary destination.
    if (blendRecoveryBlocks())
        return result::toVariantMap(result::err(QStringLiteral("Unfinished Blend recovery blocks keystore export/overwrite, including while paused.")));
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("No config loaded — can't locate the keystore.")));
    const QDir dir = QFileInfo(cfg).absoluteDir();
    const QString keystore = dir.filePath(QStringLiteral("keystore.yaml"));
    if (!QFile::exists(keystore))
        return result::toVariantMap(result::err(QStringLiteral("No keystore found yet — start the node once to create it.")));
    if (destPath.trimmed().isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("No destination chosen.")));
    // A Save-As dialog already prompts on overwrite; honor the user's choice here.
    if (QFile::exists(destPath) && !QFile::remove(destPath))
        return result::toVariantMap(result::err(QStringLiteral("Could not overwrite the existing file: %1").arg(destPath)));
    if (!QFile::copy(keystore, destPath))
        return result::toVariantMap(result::err(QStringLiteral("Could not write the keystore to: %1").arg(destPath)));
    return result::toVariantMap(LogosResult{true, QVariant(destPath), QVariant()});
}

// PREVIEW (#81): back up then remove the keystore so the node mints a fresh identity on
// the next start. The backup keeps the old identity recoverable. A workaround for the
// Settings "Regenerate keys" action until the node exposes a safe key-rotation API.
QVariantMap LogosNode1clickBackend::regenerateNodeKeys()
{
    if (blendRecoveryBlocks())
        return result::toVariantMap(result::err(QStringLiteral("Unfinished Blend recovery blocks identity/key replacement, including while paused.")));
    if (status() == Running || status() == Starting || status() == Stopping)
        return result::toVariantMap(result::err(QStringLiteral("Stop the node before regenerating keys.")));
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("No config loaded.")));
    const QDir dir = QFileInfo(cfg).absoluteDir();
    const QString keystore = dir.filePath(QStringLiteral("keystore.yaml"));
    if (!QFile::exists(keystore))
        return result::toVariantMap(result::err(QStringLiteral("No keystore found to regenerate.")));
    const QString ts = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    const QString backup = dir.filePath(QStringLiteral("keystore_backup_%1.yaml").arg(ts));
    if (!QFile::copy(keystore, backup))
        return result::toVariantMap(result::err(QStringLiteral("Could not back up the keystore — aborting.")));
    if (!QFile::remove(keystore))
        return result::toVariantMap(result::err(QStringLiteral("Backed up but could not remove the old keystore.")));
    // New identity → the old proposals/claims history no longer belongs to this node.
    QFile::remove(dir.filePath(QStringLiteral("proposals-history.json")));
    QFile::remove(dir.filePath(QStringLiteral("claims-history.json")));
    setStatus(NotStarted);
    return result::toVariantMap(LogosResult{true, QVariant(backup), QVariant()});
}

QVariantMap LogosNode1clickBackend::pruneLogs(QString capGb)
{
    // Disk-cap enforcement (Settings): when the node data-dir exceeds the cap, delete
    // the OLDEST rotated log files to reclaim space. Never touches the current (newest)
    // log the node is writing to, nor the chain db/state — so this is safe while the
    // node runs. If db+state alone exceed the cap, logs are all we can free from here.
    const QString cfg = userConfig();
    if (cfg.isEmpty())
        return result::toVariantMap(result::err(QStringLiteral("No config loaded.")));
    bool ok = false;
    const double gb = capGb.toDouble(&ok);
    if (!ok || gb <= 0.0)
        return result::toVariantMap(result::err(QStringLiteral("Invalid disk cap.")));
    const qint64 capBytes = static_cast<qint64>(gb * 1024.0 * 1024.0 * 1024.0);
    const QString dataDir = QFileInfo(cfg).absolutePath();
    qint64 current = dirSizeBytes(dataDir);
    if (current < 0 || current <= capBytes)
        return result::toVariantMap(LogosResult{true, QVariant(QStringLiteral("0")), QVariant()});
    const QDir logsDir(QDir(dataDir).filePath(QStringLiteral("logs")));
    if (!logsDir.exists())
        return result::toVariantMap(LogosResult{true, QVariant(QStringLiteral("0")), QVariant()});
    // Newest first; drop the current log (index 0) from the deletion candidates.
    QFileInfoList files = logsDir.entryInfoList(QDir::Files, QDir::Time);
    if (!files.isEmpty()) files.removeFirst();
    qint64 freed = 0;
    // Delete oldest-first (from the tail) while still over the cap; subtract as we go
    // so we don't rescan the whole dir per file.
    for (int i = files.size() - 1; i >= 0 && current > capBytes; --i) {
        const qint64 sz = files.at(i).size();
        if (QFile::remove(files.at(i).absoluteFilePath())) { freed += sz; current -= sz; }
    }
    return result::toVariantMap(LogosResult{true, QVariant(QString::number(freed)), QVariant()});
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
