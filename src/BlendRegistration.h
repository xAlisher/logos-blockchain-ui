#pragma once
#include <QJsonObject>
#include <QVariantMap>

namespace BlendLifecycle {
// Call only after a successful complete registry read and verified provider match.
// Retain the old identity as history, but never infer removal from time alone.
inline QJsonObject reconcileRegistration(QJsonObject store, const QVariantMap& record,
                                        const QString& id, int epoch)
{
    if (!record.isEmpty() && !id.isEmpty()) {
        store["declaration_id"] = id;
        store["observed_on_chain"] = true;
        store["submission_pending"] = false;
        store["withdraw_removed"] = false;
        const QVariant scheduled = record.value("withdraw_at");
        if (scheduled.isValid() && !scheduled.isNull())
            store["scheduled_withdraw_at"] = scheduled.toInt();
        else
            store.remove("scheduled_withdraw_at");
    } else if (store.value("observed_on_chain").toBool()
               && store.value("scheduled_withdraw_at").isDouble()
               && epoch >= store.value("scheduled_withdraw_at").toInt()) {
        store["withdraw_pending"] = false;
        store["submission_pending"] = false;
        store["withdraw_removed"] = true;
    }
    return store;
}
}
