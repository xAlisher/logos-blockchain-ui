#pragma once
#include <QJsonObject>
#include <QJsonArray>
#include <QVariantMap>
#include <QRegularExpression>

// Pure, deterministic policy shared by all Blend declaration consumers. Header-only
// so the plugin and standalone Qt tests exercise exactly the same implementation.
namespace BlendLifecycle {
inline QVariantMap reduce(const QVariantMap& in)
{
    QVariantMap out{{"ok", true}, {"epoch", in.value("epoch", -1)},
        {"declarationId", in.value("declarationId", QString())}, {"created", in.value("created", -1)},
        {"active", in.value("active", -1)}, {"nonce", in.value("nonce", QString()).toString()},
        {"withdrawAt", in.value("withdrawAt", -1)}, {"mode", in.value("mode", QString())},
        {"healthyPeers", in.value("healthyPeers", -1)}, {"bindingStatus", in.value("bindingStatus", "unknown")},
        {"evidence", in.value("evidence", QString())}};
    const int epoch = out["epoch"].toInt(), created = out["created"].toInt(), active = out["active"].toInt();
    const int withdrawal = out["withdrawAt"].toInt();
    const bool declared = !out["declarationId"].toString().isEmpty();
    const bool accepted = created >= 0 && active > created + 2;
    const bool connected = in.value("core").toBool() && out["healthyPeers"].toInt() > 0;
    QString state, title, detail, tone = QStringLiteral("neutral"), action = QStringLiteral("refresh");
    auto set = [&](const char* s, const char* t, const char* d, const char* level = "neutral", const char* a = "refresh") {
        state = QString::fromLatin1(s); title = QString::fromLatin1(t); detail = QString::fromLatin1(d);
        tone = QString::fromLatin1(level); action = QString::fromLatin1(a);
    };
    if (!in.value("running").toBool())
        set("offline", "Blend is offline", "Start the node to check Blend progress.", "neutral", "none");
    else if (!in.value("mode").toString().isEmpty() && in.value("mode").toString() != "Online")
        set("bootstrap", "Waiting for Online", "Blend cannot activate while the chain is bootstrapping.");
    else if (!in.value("apiOk").toBool() || epoch < 0 || in.value("mode").toString().isEmpty()) {
        out["ok"] = false;
        set("unavailable", "Blend telemetry unavailable", "The node API did not provide a complete snapshot. No health or removal is inferred.", "warning");
    } else if (!in.value("identityOk").toBool()) {
        out["ok"] = false;
        set("identity-error", "Declaration identity uncertain", "Cannot safely identify this provider's declaration.", "error");
    } else if (!declared && in.value("removalConfirmed").toBool())
        set("removed", "Declaration removed", "The scheduled withdrawal epoch has passed and the declaration is absent from the current registry. Check the wallet for spendable stake before joining again.", "neutral", "manage");
    else if (withdrawal >= 0)
        set("withdrawal-scheduled", "Withdrawal scheduled", "The request is on chain; stake is not unlocked yet.", "warning");
    else if (in.value("withdrawPending").toBool())
        set("withdrawal-requested", "Withdrawal requested", "Awaiting on-chain inclusion. The declaration cache is retained; do not submit again.", "warning");
    else if (!declared && in.value("submissionPending").toBool())
        set("submission-pending", "Declaration submitted", "Awaiting on-chain inclusion; an HTTP acknowledgement is not activation.");
    else if (!declared)
        set("no-declaration", "Enable Blend Core", "No owned declaration was found. Review funding, stake and address prerequisites.", "neutral", "manage");
    else if (created < 0 || active < 0) {
        out["ok"] = false;
        set("unavailable", "Declaration telemetry incomplete", "Created and active epochs are required to assess activity.", "warning");
    } else if (epoch < created + 2)
        set("activation-pending", "Activation pending", "Your declaration is on chain. Core switches on two epochs after it was created. Keep the node online; there is nothing to do and no need to declare again.", "warning");
    else if (out["bindingStatus"] == "missing")
        set("binding-missing", "Local SDP binding missing", "The current node run reports no declaration_id. Repair the existing owned binding; do not redeclare.", "error", "repair");
    else if (epoch >= active + 3)
        set("lapsed", "Declaration lapsed", "First excluded epoch is active + 3 (I=2), subject to frozen snapshot lag. Core connectivity alone is not eligibility.", "error", "manage");
    else if (epoch >= active + 2)
        set("at-risk", "Activity at risk", "No newer accepted activity is visible; the next epoch may exclude this provider.", "warning");
    else if (!in.value("core").toBool() && !accepted)
        set("activation-pending", "Waiting for Core membership", "The node has aged in but is not in Core yet. The membership snapshot taken at the epoch boundary, or a network minimum-members threshold, can hold this up. Stay online; do not declare again.", "warning");
    else if (accepted && connected)
        set("healthy", "Maintaining Blend Core", "Recent accepted activity and Core connectivity are observed. This is not a payout or future eligibility guarantee.", "success");
    else if (!accepted && out["bindingStatus"] == "confirmed")
        set("binding-confirmed", "Binding confirmed; awaiting activity", "The local service accepted the binding. Wait for activity and the next epoch snapshot; no activity success is claimed.", "warning");
    else if (accepted && !connected)
        set("at-risk", "Core connectivity uncertain", "Accepted activity exists, but current Core connectivity is not healthy or is unknown.", "warning");
    else
        set("collecting", "Collecting Blend activity", "No accepted activity is visible yet. Core mode and nonce alone do not prove activity; local binding may be unknown.", "warning");
    // This engine has no runtime binding GET. An explicit idempotent setter is a
    // useful operator action when activity is missing/stale; unknown is NOT a diagnosis.
    if ((state == "collecting" || state == "at-risk") && in.value("core").toBool()
        && out["bindingStatus"] == "unknown") {
        action = QStringLiteral("repair");
        detail += QStringLiteral(" Local binding cannot be queried. You can explicitly set the existing owned declaration; this neither replays lost proofs nor changes frozen membership.");
    }
    if (in.value("busy").toBool()) action = QStringLiteral("none");
    out["state"] = state; out["title"] = title; out["detail"] = detail; out["tone"] = tone; out["action"] = action;
    out["actionLabel"] = action == "repair" ? (out["bindingStatus"] == "missing" ? "Restore activity binding" : "Set activity binding")
        : action == "manage" ? (state == "no-declaration" || state == "removed" ? "Join Core" : "Manage Blend Core") : action == "refresh" ? "Refresh" : "";
    QVariantList steps;
    const QStringList labels{"Online", "Declared", "Activated", "Connected", "Activity", "Maintaining"};
    const bool valid = out["ok"].toBool() && in.value("running").toBool() && in.value("mode") == "Online";
    const bool complete[] = {valid, valid && declared, valid && declared && in.value("core").toBool(),
        valid && connected, valid && accepted, state == "healthy"};
    bool current = false;
    for (int i = 0; i < labels.size(); ++i) {
        QString step = complete[i] ? "complete" : current ? "pending" : "current";
        if (!complete[i]) current = true;
        if (i == 4 && state == "binding-missing") step = "error";
        steps << QVariantMap{{"label", labels[i]}, {"state", step}};
    }
    out["steps"] = steps;
    return out;
}
inline int healthyPeers(const QJsonValue& peers)
{
    if (!peers.isArray()) return -1;
    int count = 0;
    for (const QJsonValue& peer : peers.toArray()) {
        const QJsonArray pair = peer.toArray();
        if (pair.size() != 2 || !pair[1].isBool()) return -1;
        if (pair[1].toBool()) ++count;
    }
    return count;
}
inline bool isId(const QString& s);
inline QString joinId(const QString& response)
{
    QString id = response.trimmed();
    if (id.startsWith('"') && id.endsWith('"')) id = id.mid(1, id.size() - 2);
    return isId(id) ? id : QString();
}
// loadedAt: timestamp of the node's own "Loaded declaration from ledger …=<our id>" log line
// (a positive proof the runtime is bound), alongside repairedAt (our explicit set-declaration-id).
// Either, when newer than any missing-binding error this run, confirms the binding.
inline QString binding(qint64 runStart, qint64 missingAt, qint64 repairedAt, qint64 loadedAt, qint64 now)
{
    if (runStart <= 0) return QStringLiteral("unknown");
    const qint64 confirmedAt = qMax(repairedAt, loadedAt);
    if (confirmedAt >= runStart && confirmedAt > missingAt && confirmedAt <= now)
        return QStringLiteral("confirmed");
    if (missingAt >= runStart && missingAt <= now && now - missingAt <= 3600000)
        return QStringLiteral("missing");
    return QStringLiteral("unknown");
}
inline bool canRepair(const QVariantMap& state)
{
    return state.value("ok").toBool() && state.value("action") == "repair"
        && (state.value("bindingStatus") == "missing" || state.value("bindingStatus") == "unknown")
        && isId(state.value("declarationId").toString())
        && state.value("withdrawAt", -1).toInt() < 0 && !state.value("withdrawPending").toBool();
}
inline bool isId(const QString& s)
{
    static const QRegularExpression re(QStringLiteral("^[0-9a-fA-F]{64}$"));
    return re.match(s).hasMatch();
}
inline QVariantMap match(const QJsonObject& declarations, const QString& provider, const QString& storedId)
{
    QVariantMap result{{"ok", false}, {"id", QString()}, {"error", QString()}};
    if (!isId(provider)) {
        result["error"] = QStringLiteral("This node's public provider identity is unavailable.");
        return result;
    }
    QStringList owned;
    for (auto it = declarations.begin(); it != declarations.end(); ++it) {
        const QJsonObject d = it.value().toObject();
        const bool ours = d.value("provider_id").toString().compare(provider, Qt::CaseInsensitive) == 0
            && d.value("service_type").toString() == QStringLiteral("BN");
        if (!storedId.isEmpty() && it.key().compare(storedId, Qt::CaseInsensitive) == 0 && !ours) {
            result["error"] = QStringLiteral("Stored declaration does not belong to this provider.");
            return result;
        }
        if (ours && isId(it.key())) owned << it.key();
    }
    if (owned.size() > 1) {
        result["error"] = QStringLiteral("Multiple declarations match this provider; ownership selection is ambiguous.");
        return result;
    }
    if (!storedId.isEmpty() && !owned.isEmpty()
        && owned.first().compare(storedId, Qt::CaseInsensitive) != 0) {
        result["error"] = QStringLiteral("Stored declaration differs from the provider's on-chain declaration.");
        return result;
    }
    result["ok"] = true;
    if (!owned.isEmpty()) {
        result["id"] = owned.first();
        result["record"] = declarations.value(owned.first()).toObject().toVariantMap();
    }
    return result;
}
}
