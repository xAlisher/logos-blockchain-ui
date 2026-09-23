#include "BlendRecoverySnapshot.h"
#include <QCoreApplication>
#include <QDebug>
#include <cstdlib>
#define CHECK(x) do { if (!(x)) { qCritical() << "FAIL" << __LINE__ << #x; std::exit(1); } } while (0)
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    const QString provider(64, 'a'), id(64, 'b'), note(64, 'c');
    QJsonObject record{{"provider_id", provider}, {"service_type", "BN"}, {"created", 10}, {"active", 12},
        {"withdraw_at", QJsonValue::Null}, {"locked_note_id", note}, {"locators", QJsonArray{"/ip4/8.8.8.8/udp/3400/quic-v1"}}};
    QJsonObject registry{{id, record}};
    CHECK(BlendRecovery::registryValid(registry));
    auto s = BlendRecovery::canonical(registry, provider);
    CHECK(s.valid); CHECK(s.present); CHECK(s.note == note); CHECK(!s.locator.isEmpty());
    record["created"] = "10"; registry[id] = record;
    CHECK(!BlendRecovery::registryValid(registry));
    registry[id] = QJsonValue::Null; CHECK(!BlendRecovery::registryValid(registry));
    CHECK(!BlendRecovery::registryValid(QJsonObject{{"error", "unavailable"}}));
    CHECK(BlendRecovery::registryValid(QJsonObject{}));
    s = BlendRecovery::canonical(QJsonObject{}, provider); CHECK(s.valid); CHECK(!s.present);
    record["created"] = 10; record["locators"] = QJsonArray{"one", "two"}; registry[id] = record;
    CHECK(!BlendRecovery::canonical(registry, provider).valid); // cannot silently discard a locator
    qInfo() << "strict canonical recovery snapshots passed";
}
