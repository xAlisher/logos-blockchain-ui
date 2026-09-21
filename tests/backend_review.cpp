// Supplemental review regressions: synthetic public evidence, no network or node.
#include "BlendLifecycle.h"
#include "BlendRegistration.h"
#include <QCoreApplication>
#include <QDebug>
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    int failures = 0;
    auto check = [&](bool ok, const char* text) { if (!ok) { ++failures; qWarning() << "FAIL" << text; } };
    QVariantMap input{{"running", true}, {"apiOk", true}, {"identityOk", true}, {"mode", "Online"},
        {"epoch", 13}, {"declarationId", QString(64, '1')}, {"created", 10}, {"active", 12}, {"nonce", "1"},
        {"withdrawAt", -1}, {"core", false}, {"healthyPeers", 0}, {"bindingStatus", "unknown"}};
    const auto vm = BlendLifecycle::reduce(input);
    check(vm["state"] == "activation-pending", "not-Core cannot claim to be collecting Core activity");
    check(vm["steps"].toList()[2].toMap()["state"] != "complete", "epoch age alone is not observed activation/membership");
    input["core"] = true; input["withdrawAt"] = 14; input["epoch"] = 14;
    check(BlendLifecycle::reduce(input)["state"] != "removed", "scheduled epoch plus still-present declaration is not confirmed removal");
    QJsonObject cache{{"declaration_id", QString(64, '1')}, {"withdraw_pending", true}};
    const QVariantMap record{{"withdraw_at", 15}};
    cache = BlendLifecycle::reconcileRegistration(cache, record, QString(64, '1'), 14);
    check(!cache["withdraw_removed"].toBool(), "scheduled withdrawal is retained");
    auto absentEarly = BlendLifecycle::reconcileRegistration(cache, {}, {}, 14);
    check(!absentEarly["withdraw_removed"].toBool(), "early absence is not confirmed removal");
    cache = BlendLifecycle::reconcileRegistration(cache, {}, {}, 15);
    check(cache["withdraw_removed"].toBool() && !cache["withdraw_pending"].toBool(), "scheduled removal releases the pending guard");
    cache = BlendLifecycle::reconcileRegistration(cache, {{"withdraw_at", QVariant()}}, QString(64, '2'), 17);
    check(cache["declaration_id"].toString() == QString(64, '2') && !cache["withdraw_removed"].toBool(), "fresh registration replaces retired history");
    qInfo() << "Review regressions:" << failures << "failures";
    return failures ? 1 : 0;
}
