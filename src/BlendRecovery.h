#pragma once
#include "BlendLifecycle.h"
#include <QString>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QLockFile>
#include <QJsonDocument>
#include <QCryptographicHash>
#include <memory>
#include <functional>
#ifdef Q_OS_UNIX
#include <fcntl.h>
#include <unistd.h>
#endif

// Deterministic recovery policy, shared verbatim by the native backend and tests.
namespace BlendRecovery {
struct Snapshot {
    bool valid = false, running = false, identity = false, online = false;
    bool present = false, pending = false, funded = false, core = false;
    QString provider, id, note, locator, tip;
    int created = -1, activity = -1, epoch = -1, withdrawal = -1;
    qint64 slot = -1, lib = -1;
    bool noteSpendable = false, bindingKnown = false;
};
enum class Action { BindOriginal, Withdraw, Declare, BindNew };
enum class Outcome { Accepted, RejectedNoSubmit, Unknown };
struct Reply { Outcome outcome = Outcome::Unknown; QString id; };
inline QString actionName(Action a) {
    switch (a) {
    case Action::BindOriginal: return "bind-original";
    case Action::Withdraw: return "withdraw";
    case Action::Declare: return "declare";
    case Action::BindNew: return "bind-new";
    }
    return {};
}
using Post = std::function<Reply(Action, const QJsonObject&)>;
class Controller {
public:
    bool open(const QString& path, const QString& scope) {
        m_path = path; m_scope = scope;
        m_lock = std::make_unique<QLockFile>(path + ".lock");
        m_lock->setStaleLockTime(0); // never evict a live controller on elapsed time
        if (path.isEmpty() || scope.isEmpty() || !m_lock->tryLock(0))
            return fail("Recovery journal is locked or inaccessible. No requests will be sent.");
        QFile f(path);
        if (!f.exists()) return true;
        if (!f.open(QIODevice::ReadOnly)) return fail("Cannot read recovery journal.");
        if (f.size() > 65536) return fail("Recovery journal exceeds its size limit. Manual review required.");
        const QByteArray bytes = f.readAll();
        const QJsonDocument doc = QJsonDocument::fromJson(bytes);
        const QJsonObject envelope = doc.object();
        const QJsonObject state = envelope.value("state").toObject();
        if (!doc.isObject() || envelope.value("version").toInt() != 1
            || envelope.value("scope").toString() != scope || !validState(state)
            || envelope.value("checksum").toString() != digest(state))
            return fail("Recovery journal is corrupt, unsupported, or belongs to another config. Manual review required; no requests sent.");
        m_state = state;
        m_diskDigest = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256);
        return true;
    }
    bool active() const { return !m_error.isEmpty() || (!m_state.isEmpty() && phase() != "complete"); }
    QString phase() const { return m_error.isEmpty() ? m_state.value("phase").toString("idle") : QStringLiteral("attention"); }
    bool paused() const { return m_state.value("paused").toBool(); }
    QString error() const { return m_error; }
    QJsonObject state() const { return m_state; }
    bool start(const Snapshot& s) {
        if (!canStart(s)) return false;
        QJsonObject st{{"phase", "preflight"}, {"authorized", true}, {"paused", false},
            {"provider", s.provider}, {"originalId", s.id}, {"originalCreated", s.created},
            {"note", s.note}, {"locator", s.locator}, {"withdrawAttempts", 0}, {"declareAttempts", 0},
            {"coverage", QJsonArray()}, {"consecutive", 0}};
        return save(st);
    }
    bool pause() {
        if (!active() || !m_error.isEmpty()) return false;
        QJsonObject st = m_state; st["paused"] = true; return save(st);
    }
    bool resume() {
        if (!active() || !paused() || !m_error.isEmpty() || phase() == "attention") return false;
        QJsonObject st = m_state; st["paused"] = false; st.remove("detail"); return save(st);
    }
    bool fail(const QString& reason) {
        m_error = reason;
        // A config/identity fault is durable, not just a process-local lock. Never
        // overwrite a corrupt, externally replaced, or deleted journal as repair.
        if (!m_state.isEmpty() && m_lock && m_lock->isLocked() && journalMatches()) {
            QJsonObject st = m_state;
            st["phase"] = "attention"; st["paused"] = true; st["detail"] = reason;
            persist(st);
        }
        return false;
    }
    bool canStart(const Snapshot& s) const {
        return !active() && s.valid && s.running && s.online && s.identity && s.present
            && !s.pending && s.withdrawal < 0 && s.created >= 0 && s.activity >= s.created + 2
            && s.epoch >= s.activity + 2 && BlendLifecycle::isId(s.provider)
            && BlendLifecycle::isId(s.id) && BlendLifecycle::isId(s.note) && !s.locator.isEmpty();
    }
    QVariantMap view(const Snapshot& s) const {
        const QString p = phase();
        const QMap<QString, QString> titles{{"idle", "Controlled Blend recovery"}, {"preflight", "Checking recovery prerequisites"},
            {"withdraw-ready", "Ready for controlled withdrawal"}, {"withdraw-pending", "Withdrawal outcome pending"},
            {"withdraw-wait", "Waiting for scheduled removal"}, {"removal-wait", "Waiting for finalized removal"},
            {"declare-pending", "Fresh declaration outcome pending"}, {"binding", "Setting fresh SDP binding"},
            {"activation", "Waiting for fresh activation"}, {"monitoring", "Monitoring consecutive renewals"},
            {"complete", "Recovery verified"}, {"attention", "Recovery needs attention"}};
        const QMap<QString, QString> details{{"idle", "Explicitly authorize one withdrawal and one fresh declaration, reusing the same collateral and address. This spends transaction fees and temporarily leaves Core."},
            {"preflight", "Verify fee funding and set the original declaration binding before withdrawal."},
            {"withdraw-ready", "The next backend tick may submit the single authorized withdrawal."},
            {"withdraw-pending", "Await canonical scheduling. A timeout or HTTP acknowledgement is not inclusion; this paid request will never be automatically retried."},
            {"withdraw-wait", QString("Withdrawal effective epoch %1. Keep the node online; collateral is not yet confirmed unlocked.").arg(m_state.value("withdrawAt").toInt(-1))},
            {"removal-wait", "Canonical absence observed; waiting for the irreversible slot barrier and the original spendable collateral before fresh declaration."},
            {"declare-pending", "Await a canonical declaration with newer created epoch and the exact original collateral/address. Same declaration ID may recur; an HTTP acknowledgement is not acceptance."},
            {"binding", "Explicitly set the accepted new declaration ID in the local SDP service."},
            {"activation", "Initial active=created+2 is baseline grace, not accepted renewal evidence. Waiting for Core activation."},
            {"monitoring", QString("%1/3 consecutive accepted renewals observed. Completion also requires runtime Core. Missing observations are not invented successes.").arg(m_state.value("consecutive").toInt())},
            {"complete", "Three consecutive accepted renewals and runtime Core observed. This is not a future Core or payout guarantee."}};
        QString detail = m_error.isEmpty() ? m_state.value("detail").toString(details.value(p)) : m_error;
        if (paused()) detail.prepend("Paused: no future mutations; already-submitted on-chain actions are not undone. ");
        if (active() && (!s.valid || !s.running || !s.online)) detail += " Node offline or telemetry unavailable; progress retained.";
        if (!m_notice.isEmpty()) detail += " " + m_notice;
        const QStringList stages{"preflight", "withdraw-ready", "withdraw-pending", "withdraw-wait", "removal-wait", "declare-pending", "binding", "activation", "monitoring", "complete"};
        const QStringList stepPhases{"preflight", "withdraw-pending", "removal-wait", "declare-pending", "binding", "activation", "monitoring"};
        const QStringList labels{"Preflight", "Withdraw", "Removal", "Fresh declaration", "Bind SDP", "Activate", "Verify renewals"};
        QVariantList steps;
        for (int n = 0; n < labels.size(); ++n) {
            const int index = stages.indexOf(stepPhases[n]), current = stages.indexOf(p);
            steps << QVariantMap{{"label", labels[n]}, {"state", p == "complete" || current > index ? "complete" : current == index ? "current" : "pending"}};
        }
        for (const QJsonValue& value : m_state.value("coverage").toArray()) {
            const QJsonObject row = value.toObject(); const QString status = row.value("status").toString();
            steps << QVariantMap{{"label", QString("Epoch %1: %2").arg(row.value("epoch").toInt()).arg(status)},
                {"state", status == "accepted" ? "complete" : status == "missed" ? "error" : "pending"}};
        }
        return {{"active", active()}, {"phase", paused() && p != "attention" ? "paused" : p}, {"stage", p},
            {"title", paused() && p != "attention" ? "Recovery paused" : titles.value(p)}, {"detail", detail},
            {"tone", p == "complete" ? "success" : p == "attention" ? "error" : paused() ? "warning" : "neutral"},
            {"steps", steps}, {"canStart", canStart(s)}, {"canPause", active() && !paused() && m_error.isEmpty() && p != "attention"},
            {"canResume", active() && paused() && m_error.isEmpty() && p != "attention"},
            {"coverage", m_state.value("coverage").toArray().toVariantList()}};
    }
    // Exactly one external action per tick. Persist the paid intent BEFORE invoking transport.
    void tick(const Snapshot& s, const Post& post) {
        if (!active() || !m_error.isEmpty() || m_ticking) return;
        if (!journalMatches()) { fail("Recovery journal changed or disappeared. Manual review required; no requests sent."); return; }
        struct Guard { bool& b; Guard(bool& v): b(v) { b = true; } ~Guard() { b = false; } } guard(m_ticking);
        if (!s.valid || !s.running || !s.online) { m_notice = "Waiting for complete Online telemetry; no removal or health inferred."; return; }
        if (!s.identity || s.provider != m_state.value("provider").toString()) { attention("Configured/runtime provider changed. Manual review required."); return; }
        if (s.epoch < m_state.value("lastEpoch").toInt(-1)
            || s.slot < m_state.value("lastSlot").toVariant().toLongLong()
            || s.lib < m_state.value("lastLib").toVariant().toLongLong()) {
            attention("Chain epoch/slot/finality regressed. Recovery stopped for manual review."); return;
        }
        QJsonObject st = m_state;
        st["lastEpoch"] = s.epoch; st["lastSlot"] = s.slot; st["lastLib"] = s.lib;
        if (st != m_state && !save(st)) return;
        m_notice.clear();
        const QString p = phase();
        const bool original = s.present && s.id == st.value("originalId").toString()
            && s.created == st.value("originalCreated").toInt();
        const bool material = !s.present || (s.note == st.value("note").toString() && s.locator == st.value("locator").toString());
        if (!material) { attention("Canonical collateral or locator changed. Recovery stopped."); return; }
        if (p == "preflight" || p == "withdraw-ready") {
            if (!original || s.withdrawal >= 0) { attention("Original declaration changed before withdrawal. No request sent."); return; }
            if (paused()) return;
            if (!s.funded) { prerequisite("SDP fee funding is unavailable. Fund the existing key, then explicitly resume."); return; }
            if (p == "preflight") {
                const Reply reply = post(Action::BindOriginal, QJsonObject{{"id", s.id}});
                if (reply.outcome == Outcome::Accepted) { st = m_state; st["phase"] = "withdraw-ready"; save(st); }
                else prerequisite("Original binding not acknowledged. Check the node, then resume; no withdrawal submitted.");
                return;
            }
            submit(Action::Withdraw, "withdraw-pending", QJsonObject{{"id", s.id}}, post);
            return;
        }
        if (p == "withdraw-pending" || p == "withdraw-wait") {
            if (s.present && !original) { attention("Declaration incarnation changed while awaiting withdrawal."); return; }
            if (original && s.withdrawal >= 0) {
                if (st.contains("withdrawAt") && st.value("withdrawAt").toInt() != s.withdrawal) { attention("Scheduled withdrawal changed."); return; }
                st["withdrawAt"] = s.withdrawal; st["phase"] = "withdraw-wait"; save(st); return;
            }
            if (original && st.contains("withdrawAt")) { attention("Scheduled withdrawal disappeared (possible reorg)."); return; }
            if (!s.present && st.contains("withdrawAt") && s.epoch >= st.value("withdrawAt").toInt()) {
                st["absenceSlot"] = s.slot; st["phase"] = "removal-wait"; save(st);
            }
            return; // unknown outcomes NEVER resubmit
        }
        if (p == "removal-wait") {
            if (s.present) { attention("Declaration reappeared after removal observation. No redeclaration sent."); return; }
            if (paused() || s.lib < st.value("absenceSlot").toVariant().toLongLong()) return;
            if (!s.funded || !s.noteSpendable) { prerequisite("Waiting for the original collateral to be spendable and SDP fee funding. Fix prerequisites, then resume."); return; }
            submit(Action::Declare, "declare-pending", QJsonObject{{"locator", st.value("locator")}, {"locked_note_id", st.value("note")}}, post);
            return;
        }
        if (p == "declare-pending") {
            if (!s.present) return;
            if (s.created <= st.value("originalCreated").toInt() || s.created < st.value("withdrawAt").toInt()
                || s.withdrawal >= 0 || (!st.value("ackId").toString().isEmpty() && s.id != st.value("ackId").toString())) {
                attention("Fresh declaration does not match the authorized new incarnation."); return;
            }
            st["newId"] = s.id; st["newCreated"] = s.created;
            st["lastActivity"] = s.created + 2; st["phase"] = "binding";
            save(st); return;
        }
        if (p == "binding" || p == "activation" || p == "monitoring") {
            if (!s.present || s.id != st.value("newId").toString() || s.created != st.value("newCreated").toInt() || s.withdrawal >= 0) {
                attention("New declaration disappeared or changed. Recovery stopped."); return;
            }
            if (s.activity < st.value("lastActivity").toInt()) { attention("Accepted activity regressed (possible reorg). No success inferred."); return; }
            if (p == "binding") {
                if (paused()) return;
                if (post(Action::BindNew, QJsonObject{{"id", s.id}}).outcome == Outcome::Accepted) {
                    st = m_state; st["phase"] = "activation"; save(st);
                } else prerequisite("New declaration binding was not acknowledged. Resume after checking the node.");
                return;
            }
            // First three distinguishable renewals (created+3,+4,+5), retained forever.
            QJsonArray coverage = st.value("coverage").toArray();
            for (int n = coverage.size(); n < 3; ++n)
                coverage.append(QJsonObject{{"epoch", s.created + 3 + n}, {"status", "pending"}});
            for (int n = 0; n < coverage.size(); ++n) {
                QJsonObject row = coverage[n].toObject(); const int epoch = row.value("epoch").toInt();
                if (s.activity == epoch) row["status"] = "accepted";
                else if (row.value("status") != "accepted" && row.value("status") != "missed" && s.epoch > epoch)
                    row["status"] = s.activity < epoch ? "missed" : "unobserved";
                coverage[n] = row;
            }
            st["coverage"] = coverage;
            const int previous = st.value("lastActivity").toInt();
            if (s.activity > s.created + 2 && s.activity > previous) {
                st["consecutive"] = s.activity == previous + 1 ? st.value("consecutive").toInt() + 1 : 1;
                st["lastActivity"] = s.activity;
            }
            if (s.epoch > s.activity + 1) st["consecutive"] = 0;
            if (s.core && s.bindingKnown && st.value("consecutive").toInt() >= 3 && s.epoch <= s.activity + 1) st["phase"] = "complete";
            else st["phase"] = s.core && s.epoch >= s.created + 2 ? "monitoring" : "activation";
            save(st);
            // Idempotent setter also restores binding after a node restart. Never a paid request.
            if (active() && !paused() && m_error.isEmpty() && !s.bindingKnown) post(Action::BindNew, QJsonObject{{"id", s.id}});
        }
    }
private:
    bool m_ticking = false;
    QString m_notice;
    void attention(const QString& detail) {
        QJsonObject st = m_state; st["phase"] = "attention"; st["paused"] = true; st["detail"] = detail; save(st);
    }
    void prerequisite(const QString& detail) {
        QJsonObject st = m_state; st["paused"] = true; st["detail"] = detail; save(st);
    }
    void submit(Action action, const QString& phase, const QJsonObject& body, const Post& post) {
        QJsonObject st = m_state;
        const QString counter = action == Action::Withdraw ? "withdrawAttempts" : "declareAttempts";
        if (st.value(counter).toInt() != st.value(counter + "Rejected").toInt()) { attention("Paid request budget consumed. No automatic retry."); return; }
        const QString retryPhase = st.value("phase").toString();
        st["phase"] = phase; st[counter] = st.value(counter).toInt() + 1;
        if (!save(st)) return;
        const Reply reply = post(action, body);
        // A nested event loop can persist Pause during transport. Never overwrite that intent.
        st = m_state;
        if (reply.outcome == Outcome::RejectedNoSubmit) {
            st[counter + "Rejected"] = st.value(counter + "Rejected").toInt() + 1;
            st["phase"] = retryPhase; st["paused"] = true;
            st["detail"] = "Request definitively rejected before submission. Fix prerequisites, then explicitly resume.";
        } else if (action == Action::Declare && BlendLifecycle::isId(reply.id)) st["ackId"] = reply.id;
        save(st); // failure retains the earlier pending record on disk
    }
    QString m_path, m_scope, m_error;
    QByteArray m_diskDigest;
    QJsonObject m_state;
    std::unique_ptr<QLockFile> m_lock;
    static QString digest(const QJsonObject& st) {
        return QString::fromLatin1(QCryptographicHash::hash(QJsonDocument(st).toJson(QJsonDocument::Compact), QCryptographicHash::Sha256).toHex());
    }
    static bool validState(const QJsonObject& st) {
        const QStringList phases{"preflight", "withdraw-ready", "withdraw-pending", "withdraw-wait", "removal-wait", "declare-pending", "binding", "activation", "monitoring", "complete", "attention"};
        return st.value("authorized").toBool() && phases.contains(st.value("phase").toString())
            && st.value("paused").isBool() && BlendLifecycle::isId(st.value("provider").toString())
            && BlendLifecycle::isId(st.value("originalId").toString())
            && BlendLifecycle::isId(st.value("note").toString()) && !st.value("locator").toString().isEmpty()
            && st.value("originalCreated").toInt(-1) >= 0 && st.value("coverage").isArray()
            && st.value("withdrawAttempts").toInt(-1) >= 0 && st.value("declareAttempts").toInt(-1) >= 0;
    }
    bool journalMatches() const {
        QFile current(m_path);
        if (m_diskDigest.isEmpty()) return !current.exists();
        return current.open(QIODevice::ReadOnly) && current.size() <= 65536
            && QCryptographicHash::hash(current.readAll(), QCryptographicHash::Sha256) == m_diskDigest;
    }
    // Low-level write with no recursive failure handler. Used to persist faults too.
    bool persist(const QJsonObject& st) {
        QSaveFile file(m_path);
        file.setDirectWriteFallback(false);
        const QByteArray bytes = QJsonDocument(QJsonObject{{"version", 1}, {"scope", m_scope}, {"state", st}, {"checksum", digest(st)}}).toJson(QJsonDocument::Compact);
        if (!file.open(QIODevice::WriteOnly) || !file.setPermissions(QFile::ReadOwner | QFile::WriteOwner)
            || file.write(bytes) != bytes.size() || !file.commit()) return false;
        m_state = st;
        m_diskDigest = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256);
#ifdef Q_OS_UNIX
        // QSaveFile syncs the file. Sync the rename's directory as well, before
        // authorizing a paid request, so the write-ahead record survives power loss.
        const QByteArray parent = QFile::encodeName(QFileInfo(m_path).absolutePath());
        const int fd = ::open(parent.constData(), O_RDONLY | O_DIRECTORY);
        if (fd < 0) return false;
        const bool synced = ::fsync(fd) == 0;
        ::close(fd);
        if (!synced) return false;
#endif
        return true;
    }
    bool save(const QJsonObject& st) {
        if (!m_error.isEmpty() || !m_lock || !m_lock->isLocked() || !validState(st)) return fail("Recovery persistence unavailable. No further requests will be sent.");
        if (!journalMatches()) return fail("Recovery journal changed or disappeared. Manual review required; no requests sent.");
        if (!persist(st)) return fail("Cannot atomically persist recovery. No further requests will be sent; review storage before reloading.");
        return true;
    }
};
}
