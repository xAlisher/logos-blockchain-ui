#include "ClaimsModel.h"

#include <algorithm>

int ClaimsModel::rowCount(const QModelIndex& parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_rows.size());
}

QVariant ClaimsModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_rows.size())
        return {};

    const Row& row = m_rows.at(index.row());
    switch (role) {
    case KindRole:
        return row.record.kind == ClaimLedger::Kind::Mining ? QStringLiteral("mining")
                                                            : QStringLiteral("staking");
    case ValueRole:      return row.record.value;
    case PayeeRole:      return row.record.payee;
    case BlockIdRole:    return row.record.blockId;
    case TxHashRole:     return row.record.txHash;
    // Through QVariant as a qulonglong: a slot is u64, and QML's Number would
    // start losing digits past 2^53.
    case SlotRole:       return QVariant::fromValue<qulonglong>(row.record.slot);
    case NullifierRole:  return row.record.nullifier;
    case ConfirmedRole:  return row.confirmed;
    case SlotsToFinalityRole:
        return row.confirmed || row.record.slot <= m_libSlot
            ? 0
            : static_cast<int>(row.record.slot - m_libSlot);
    default:             return {};
    }
}

QHash<int, QByteArray> ClaimsModel::roleNames() const
{
    return {
        { KindRole,      "kind" },
        { ValueRole,     "value" },
        { PayeeRole,     "payee" },
        { BlockIdRole,   "blockId" },
        { TxHashRole,    "txHash" },
        { SlotRole,      "slot" },
        { NullifierRole, "nullifier" },
        { ConfirmedRole, "confirmed" },
        { SlotsToFinalityRole, "slotsToFinality" },
    };
}

void ClaimsModel::setFilter(Filter filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    // Re-apply against what we already hold: the filter is a view of the same
    // claims, not a reason to go back to the ledger.
    rebuild();
}

void ClaimsModel::setClaims(const QVector<ClaimLedger::Record>& records, quint64 libSlot)
{
    m_source = records;
    m_libSlot = libSlot;
    rebuild();
}

void ClaimsModel::rebuild()
{
    const QVector<ClaimLedger::Record>& records = m_source;
    const quint64 libSlot = m_libSlot;

    QVector<Row> rows;
    rows.reserve(records.size());
    for (const ClaimLedger::Record& record : records) {
        if (record.kind != m_kind)
            continue;
        const bool confirmed = record.slot <= libSlot;
        if (m_filter == PendingOnly && confirmed)
            continue;
        rows.append(Row{record, confirmed});
    }

    // Newest first. The ledger appends in the order claims were found, which on
    // a catch-up replay is chain order and on a live node is arrival order —
    // neither is what a history reads as. Sorted here rather than in a proxy so
    // the remoted rows are already in display order; a QSortFilterProxyModel on
    // the replica side would sort a list that arrives asynchronously.
    std::stable_sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) {
        return a.record.slot > b.record.slot;
    });

    // Whole-list reset. The ledger is append-and-amend — a re-landed claim moves
    // to a new block — so there is no stable incremental diff to emit, and the
    // list only changes when a claim settles or LIB advances past one, which is
    // rare enough that a reset costs nothing. Skipped entirely when nothing
    // moved, which is the common case on a 2s poll.
    if (rows == m_rows) {
        if (m_libSlot != m_rowsLibSlot) {
            m_rowsLibSlot = m_libSlot;
            if (!m_rows.isEmpty()) {
                emit dataChanged(index(0, 0), index(m_rows.size() - 1, 0),
                                 { SlotsToFinalityRole });
            }
        }
        return;
    }

    m_rowsLibSlot = m_libSlot;
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
}
