#pragma once
#include "BlendRecovery.h"
#include <cmath>
#include <limits>
namespace BlendRecovery {
inline bool number(const QJsonValue& v, double maximum = 9007199254740991.0) {
    return v.isDouble() && std::isfinite(v.toDouble()) && v.toDouble() >= 0
        && v.toDouble() <= maximum && std::floor(v.toDouble()) == v.toDouble();
}
// Validate the entire dictionary before treating a missing owned record as absence.
inline bool registryValid(const QJsonObject& registry) {
    for (auto it = registry.begin(); it != registry.end(); ++it) {
        const QJsonObject d = it.value().toObject();
        if (!BlendLifecycle::isId(it.key()) || !it.value().isObject()
            || !BlendLifecycle::isId(d.value("provider_id").toString())
            || d.value("service_type").toString().isEmpty()
            || !BlendLifecycle::isId(d.value("locked_note_id").toString())
            || !number(d.value("created"), std::numeric_limits<int>::max() - 8)
            || !number(d.value("active"), std::numeric_limits<int>::max() - 8)
            || (!d.value("withdraw_at").isNull() && !number(d.value("withdraw_at"), std::numeric_limits<int>::max() - 8))
            || !d.contains("withdraw_at") || !d.value("locators").isArray() || d.value("locators").toArray().isEmpty()) return false;
        for (const QJsonValue& locator : d.value("locators").toArray())
            if (!locator.isString() || locator.toString().isEmpty()) return false;
    }
    return true;
}
inline Snapshot canonical(const QJsonObject& registry, const QString& provider) {
    Snapshot s; s.provider = provider.toLower();
    if (!registryValid(registry)) return s;
    const QVariantMap match = BlendLifecycle::match(registry, provider, {});
    if (!match.value("ok").toBool()) return s;
    s.valid = true;
    const QJsonObject d = QJsonObject::fromVariantMap(match.value("record").toMap());
    if (d.isEmpty()) return s;
    s.present = true; s.id = match.value("id").toString().toLower();
    s.created = d.value("created").toInt(); s.activity = d.value("active").toInt();
    s.withdrawal = d.value("withdraw_at").isNull() ? -1 : d.value("withdraw_at").toInt();
    s.note = d.value("locked_note_id").toString().toLower();
    const QJsonArray locators = d.value("locators").toArray();
    if (locators.size() != 1) { s.valid = false; return s; } // join accepts only one; never silently discard others
    s.locator = locators.first().toString();
    s.valid = s.activity >= s.created + 2;
    return s;
}
}
