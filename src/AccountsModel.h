#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

class AccountsModel : public QAbstractListModel {
    Q_OBJECT
public:
    // label/hint/group carry the operator-facing identity of each key (Wallet, Leader
    // funding key, Blend stake key, Blend public key, …). group is "spendable" | "identity";
    // fundable rows get a Fund/balance affordance, identity rows are copy-only.
    enum Roles {
        AddressRole = Qt::UserRole + 1,
        BalanceRole,
        LabelRole,
        HintRole,
        GroupRole,
        FundableRole,
    };

    explicit AccountsModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Plain address list (legacy; leaves label/hint/group empty).
    void setAddresses(const QStringList& addresses);
    // Enriched entries: a list of maps { address, label, hint, group, fundable }. The backend
    // classifies each known key by its config role and appends the identity keys. Balances are
    // preserved across a rebuild by address.
    Q_INVOKABLE void setAccounts(const QVariantList& accounts);
    Q_INVOKABLE void setBalanceForAddress(const QString& address, const QString& balance);

private:
    struct Entry {
        QString address;
        QString balance;
        QString label;
        QString hint;
        QString group;      // "spendable" | "identity"
        bool fundable = false;
        bool operator==(const Entry& other) const {
            return address == other.address && balance == other.balance
                && label == other.label && hint == other.hint
                && group == other.group && fundable == other.fundable;
        }
    };
    QVector<Entry> m_entries;
};
