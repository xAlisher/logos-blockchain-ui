#include "AccountsModel.h"

int AccountsModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant AccountsModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();
    const Entry& e = m_entries.at(index.row());
    switch (role) {
    case AddressRole:
        return e.address;
    case BalanceRole:
        return e.balance;
    case LabelRole:
        return e.label;
    case HintRole:
        return e.hint;
    case GroupRole:
        return e.group;
    case FundableRole:
        return e.fundable;
    case Qt::DisplayRole:
        return e.address;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AccountsModel::roleNames() const
{
    QHash<int, QByteArray> names;
    names[AddressRole] = "address";
    names[BalanceRole] = "balance";
    names[LabelRole] = "label";
    names[HintRole] = "hint";
    names[GroupRole] = "group";
    names[FundableRole] = "fundable";
    return names;
}

void AccountsModel::setAddresses(const QStringList& addresses)
{
    QHash<QString, QString> balanceCache;
    for (const Entry& e : m_entries)
        balanceCache.insert(e.address, e.balance);

    QVector<Entry> newEntries;
    newEntries.reserve(addresses.size());
    for (const QString& addr : addresses) {
        Entry e;
        e.address = addr;
        e.balance = balanceCache.value(addr, QStringLiteral("---"));
        newEntries.append(e);
    }

    if (m_entries == newEntries)
        return;

    beginResetModel();
    m_entries = std::move(newEntries);
    endResetModel();
}

void AccountsModel::setAccounts(const QVariantList& accounts)
{
    QHash<QString, QString> balanceCache;
    for (const Entry& e : m_entries)
        balanceCache.insert(e.address, e.balance);

    QVector<Entry> newEntries;
    newEntries.reserve(accounts.size());
    for (const QVariant& item : accounts) {
        const QVariantMap m = item.toMap();
        Entry e;
        e.address = m.value(QStringLiteral("address")).toString();
        if (e.address.isEmpty())
            continue;
        e.label = m.value(QStringLiteral("label")).toString();
        e.hint = m.value(QStringLiteral("hint")).toString();
        e.group = m.value(QStringLiteral("group"), QStringLiteral("spendable")).toString();
        e.fundable = m.value(QStringLiteral("fundable"), false).toBool();
        // identity keys carry no balance; spendable keys keep the last fetched value
        e.balance = e.fundable || e.group == QStringLiteral("spendable")
            ? balanceCache.value(e.address, QStringLiteral("---"))
            : QString();
        newEntries.append(e);
    }

    if (m_entries == newEntries)
        return;

    beginResetModel();
    m_entries = std::move(newEntries);
    endResetModel();
}

void AccountsModel::setBalanceForAddress(const QString& address, const QString& balance)
{
    const QString valueToSet = balance.trimmed().startsWith(QStringLiteral("Error"))
        ? QStringLiteral("---")
        : balance;
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].address == address) {
            if (m_entries[i].balance != valueToSet) {
                m_entries[i].balance = valueToSet;
                const QModelIndex idx = index(i, 0);
                emit dataChanged(idx, idx, { BalanceRole });
            }
            return;
        }
    }
}
