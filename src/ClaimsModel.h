#pragma once

#include <QAbstractListModel>
#include <QVector>

#include "ClaimLedger.h"

// Settled reward claims, newest first — the per-claim view of the totals on the
// Earned and Mining Rewards tiles.
//
// A model rather than a QVariantList because ui-host remotes any
// QAbstractItemModel* Q_PROPERTY as its own child source (see ui-host/main.cpp),
// so QML reaches it with logos.model("blockchain_ui", "claims") and rows arrive
// incrementally instead of the whole list being re-marshalled on every poll.
//
// NOTE for consumers: rowCount() has no NOTIFY across Qt Remote Objects, so a
// binding on it never updates. Use ListView.count or an Instantiator.
class ClaimsModel : public QAbstractListModel {
    Q_OBJECT
public:
    enum Roles {
        // "staking" | "mining" — which pipeline paid it.
        KindRole = Qt::UserRole + 1,
        // Lepta, decimal string. GROSS: the reward note carries the full
        // amount and the claim's fee is funded separately, so no row can say
        // what arrived net.
        ValueRole,
        // The wallet key it was attributed to.
        PayeeRole,
        BlockIdRole,
        TxHashRole,
        SlotRole,
        // Chain-unique, so it is a stable row identity across a rebuild.
        NullifierRole,
        // Whether the block it sits in is settled beyond reversal. False means
        // seen but not yet final — which is why it can be on this list while
        // the tile totals have not moved.
        ConfirmedRole,
        SlotsToFinalityRole,
    };

    // Scoped to one kind at construction. Staking and mining are shown on
    // different tabs and never interleave, so filtering here beats a
    // QSortFilterProxyModel on the replica side — which would be filtering a
    // list that arrives asynchronously. A mining history is a second instance
    // and a second Q_PROPERTY, nothing more.
    // Which settlement states to show. The model holds only the rows that
    // pass, so ListView.count and any "N claims" header stay honest under a
    // filter rather than counting rows nobody can see.
    //
    // Two states because the UI offers two: "show only pending" or everything.
    // A landed-only case existed and was never reachable — finality is a few
    // slots away, so it would have differed from All only briefly.
    enum Filter { All, PendingOnly };
    Q_ENUM(Filter)

    explicit ClaimsModel(ClaimLedger::Kind kind, QObject* parent = nullptr)
        : QAbstractListModel(parent), m_kind(kind) {}

    void setFilter(Filter filter);
    [[nodiscard]] Filter filter() const { return m_filter; }

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Replaces the rows with this model's kind from the ledger, newest first,
    // marking each against the finality gate. Called from the same place the
    // tiles are published, so the list and the totals can never disagree about
    // what has settled.
    void setClaims(const QVector<ClaimLedger::Record>& records, quint64 libSlot);

private:
    void rebuild();

public:

private:
    struct Row {
        ClaimLedger::Record record;
        bool confirmed = false;

        friend bool operator==(const Row& a, const Row& b)
        {
            return a.confirmed == b.confirmed && a.record == b.record;
        }
    };

    ClaimLedger::Kind m_kind = ClaimLedger::Kind::Staking;
    Filter m_filter = All;
    QVector<ClaimLedger::Record> m_source;
    quint64 m_libSlot = 0;
    // The LIB the current rows' SlotsToFinality was computed against. Separate
    // from m_libSlot so rebuild() can tell "LIB moved but no row crossed the
    // line" — which changes that role without changing any Row.
    quint64 m_rowsLibSlot = 0;
    QVector<Row> m_rows;
};
