#include "BlendLifecycle.h"
#include <QCoreApplication>
#include <QDebug>
#include <cstdlib>

static void check(bool condition, const char* message)
{
    if (!condition) { qCritical() << "FAIL:" << message; std::exit(1); }
}
int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    const QString pk(64, 'a'), other(64, 'b'), id(64, '1'), foreign(64, '2');
    QJsonObject record{{"provider_id", pk}, {"service_type", "BN"}, {"created", 10},
                       {"active", 12}, {"nonce", 0}, {"withdraw_at", QJsonValue::Null},
                       {"locators", QJsonArray{"same-address"}}};
    QJsonObject records{{id, record}};
    check(BlendLifecycle::match(records, pk, {}).value("id").toString() == id,
          "provider identity discovers declaration without local cache");
    QJsonObject duplicate = record; duplicate["provider_id"] = other;
    records[foreign] = duplicate;
    check(BlendLifecycle::match(records, pk, {}).value("id").toString() == id, "duplicate locator is not ownership");
    check(!BlendLifecycle::match(records, pk, foreign).value("ok").toBool(), "stored foreign ID rejected");
    check(!BlendLifecycle::match(records, {}, id).value("ok").toBool(), "unverified provider rejected");
    records[foreign] = record;
    check(!BlendLifecycle::match(records, pk, id).value("ok").toBool(), "duplicate identity rejected even with exact ID");
    QVariantMap input{{"running", true}, {"apiOk", true}, {"identityOk", true}, {"mode", "Online"},
        {"epoch", 13}, {"declarationId", id}, {"created", 10}, {"active", 12}, {"nonce", "0"},
        {"withdrawAt", -1}, {"core", true}, {"healthyPeers", 2}, {"bindingStatus", "missing"}};
    check(BlendLifecycle::reduce(input).value("state") == "binding-missing", "Core nonce zero missing SDP binding is blocked");
    input["bindingStatus"] = "unknown";
    check(BlendLifecycle::reduce(input).value("state") == "collecting", "unknown binding is not missing");
    check(BlendLifecycle::reduce(input).value("action") == "repair", "unknown binding allows explicit idempotent setup without diagnosing it missing");
    input["epoch"] = 11;
    check(BlendLifecycle::reduce(input).value("state") == "activation-pending", "activation snapshot delay");
    input["epoch"] = 13; input["bindingStatus"] = "confirmed";
    check(BlendLifecycle::reduce(input).value("state") == "binding-confirmed", "repair ack is not activity");
    input["active"] = 13; input["nonce"] = "7";
    check(BlendLifecycle::reduce(input).value("state") == "healthy", "accepted recent activity and connectivity");
    input["epoch"] = 15;
    check(BlendLifecycle::reduce(input).value("state") == "at-risk", "last eligible epoch is at risk");
    input["epoch"] = 16;
    check(BlendLifecycle::reduce(input).value("state") == "lapsed", "first excluded epoch active plus three");
    input["withdrawPending"] = true;
    check(BlendLifecycle::reduce(input).value("state") == "withdrawal-requested", "withdraw request retained before inclusion");
    input["withdrawAt"] = 17;
    check(BlendLifecycle::reduce(input).value("state") == "withdrawal-scheduled", "withdraw schedule is not removal");
    input["epoch"] = 17;
    check(BlendLifecycle::reduce(input).value("state") == "withdrawal-scheduled", "epoch alone cannot confirm removal of a present declaration");
    input["declarationId"] = QString(); input["removalConfirmed"] = true;
    check(BlendLifecycle::reduce(input).value("state") == "removed", "scheduled epoch plus confirmed registry absence is removal");
    input["apiOk"] = false;
    check(!BlendLifecycle::reduce(input).value("ok").toBool(), "API failure never claims removal or health");
    check(BlendLifecycle::joinId("null").isEmpty(), "null join is not success");
    check(BlendLifecycle::joinId("\"" + id + "\"") == id, "JSON declaration ID accepted");
    check(BlendLifecycle::joinId("garbage").isEmpty(), "invalid join response rejected");
    // signature: binding(runStart, missingAt, repairedAt, loadedAt, now)
    check(BlendLifecycle::binding(100, 90, 0, 0, 200) == "unknown", "old-run missing log ignored");
    check(BlendLifecycle::binding(100, 110, 0, 0, 200) == "missing", "current-run SDP error proves missing");
    check(BlendLifecycle::binding(100, 110, 120, 0, 200) == "confirmed", "repair supersedes older log");
    check(BlendLifecycle::binding(130, 110, 120, 0, 200) == "unknown", "restart invalidates repair");
    check(BlendLifecycle::binding(100, 110, 0, 0, 4000000) == "unknown", "old errors expire");
    // a positive "Loaded declaration" log line this run confirms the binding (no repair offered)
    check(BlendLifecycle::binding(100, 0, 0, 150, 200) == "confirmed", "loaded-declaration log confirms binding");
    check(BlendLifecycle::binding(100, 160, 0, 150, 200) == "missing", "a newer missing error overrides an older load");
    check(BlendLifecycle::binding(100, 140, 0, 150, 200) == "confirmed", "a newer load overrides an older missing error");
    check(BlendLifecycle::binding(130, 0, 0, 120, 200) == "unknown", "load before this run does not confirm");
    QVariantMap repair{{"ok", true}, {"action", "repair"}, {"declarationId", id}, {"withdrawAt", -1}, {"bindingStatus", "missing"}};
    check(BlendLifecycle::canRepair(repair), "verified missing owned binding repair allowed");
    repair["withdrawAt"] = 20;
    check(!BlendLifecycle::canRepair(repair), "scheduled withdrawal rejects repair");
    repair["withdrawAt"] = -1; repair["withdrawPending"] = true;
    check(!BlendLifecycle::canRepair(repair), "pending withdrawal rejects repair");
    check(BlendLifecycle::healthyPeers(QJsonArray{QJsonArray{"one", true}, QJsonArray{"two", false}}) == 1, "count healthy peer booleans, not all connections");
    check(BlendLifecycle::healthyPeers(QJsonArray{"malformed"}) == -1, "malformed connectivity remains unknown");
    qInfo() << "PASS backend Blend lifecycle";
}
