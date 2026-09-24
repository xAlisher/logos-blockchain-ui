#pragma once
#include <QJsonObject>
#include <QString>

namespace BlendMutation {
// request() exposes an HTTP code only after curl exits successfully. A timeout
// (including HTTP 408) or server failure cannot prove non-delivery of a paid POST.
inline bool definitivelyRejected(const QString& code)
{
    return code.size() == 3 && code[0] == QLatin1Char('4')
        && code[1] >= QLatin1Char('0') && code[1] <= QLatin1Char('9')
        && code[2] >= QLatin1Char('0') && code[2] <= QLatin1Char('9')
        && code != QStringLiteral("408");
}

// Restore the pre-attempt record, not an empty record: identity, historical
// timestamps and prior flags belong to earlier operations, not this rejected POST.
inline QJsonObject afterReply(const QJsonObject& previous, const QJsonObject& pending,
                              const QString& code)
{
    return definitivelyRejected(code) ? previous : pending;
}
}
