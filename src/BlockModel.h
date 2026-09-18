#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QVector>

// Structured model of recent blockchain blocks, fed by the backend's `newBlock`
// event. Each incoming payload is parsed once (in appendRaw) into header fields
// plus a list of prettified per-transaction JSON; unparsable payloads are kept
// as raw text (ParsedRole == false) so nothing is ever silently dropped.
//
// Newest block is row 0. Only the latest kMaxBlocks are retained.
class BlockModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Roles {
        TimestampRole = Qt::UserRole + 1,
        SlotRole,
        VersionRole,
        ParentBlockRole,
        BlockRootRole,
        LeaderKeyRole,
        EntropyRole,
        ProofRole,
        VoucherCmRole,
        SignatureRole,
        TxCountRole,
        TransactionsRole, // QStringList: prettified JSON per transaction
        RawJsonRole,      // prettified full block (or the raw payload on parse failure)
        ParsedRole,       // bool: false when the payload could not be parsed
        EpochRole,        // int: floor(slot / epoch_length); -1 if slot unknown (for grouping)
    };

    explicit BlockModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Parse a raw `newBlock` payload and insert it as the newest block (row 0),
    // evicting the oldest once kMaxBlocks is exceeded.
    Q_INVOKABLE void appendRaw(const QString& timestamp, const QString& rawJson);

    // Oldest→newest [{ slot, txCount }] for the TX-on-blocks heatmap. Read backend-side (the
    // remoted replica in QML can't call this), surfaced to the UI via getBlockTx().
    QVariantList txSeries() const;
    Q_INVOKABLE void clear();

    // Search the retained blocks for a transaction whose `id` matches `txId`
    // (case-insensitive, `0x`-tolerant). The blocks fed by the node's newBlock
    // subscription carry a per-transaction `id`; the node cannot look a mined
    // transaction up by hash (its tx-by-hash store is mempool-only and pruned
    // shortly after inclusion), so this in-memory scan is how a tx copied from
    // the blocks view is resolved. Returns { found, value, blockId, slot,
    // timestamp }; `value` is the prettified transaction JSON when found.
    QVariantMap findTransaction(const QString& txId) const;

signals:
    void countChanged();

private:
    struct Entry {
        QString timestamp;
        QString slot;
        QString version;
        QString parentBlock;
        QString blockRoot;
        QString leaderKey;
        QString entropy;
        QString proof;
        QString voucherCm;
        QString signature;
        QString blockId;
        int txCount = 0;
        QStringList transactions;
        QString rawJson;
        bool parsed = false;
    };

    static constexpr int kMaxBlocks = 100;
    QVector<Entry> m_entries;
};
