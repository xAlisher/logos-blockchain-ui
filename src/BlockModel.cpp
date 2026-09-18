#include "BlockModel.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QJsonValue>

namespace {

QString prettify(const QJsonValue& value)
{
    if (value.isObject())
        return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Indented));
    if (value.isArray())
        return QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Indented));
    return value.toVariant().toString();
}

} // namespace

int BlockModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_entries.size();
}

QVariant BlockModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_entries.size())
        return QVariant();

    const Entry& e = m_entries.at(index.row());
    switch (role) {
    case TimestampRole:    return e.timestamp;
    case SlotRole:         return e.slot;
    case VersionRole:      return e.version;
    case ParentBlockRole:  return e.parentBlock;
    case BlockRootRole:    return e.blockRoot;
    case LeaderKeyRole:    return e.leaderKey;
    case EntropyRole:      return e.entropy;
    case ProofRole:        return e.proof;
    case VoucherCmRole:    return e.voucherCm;
    case SignatureRole:    return e.signature;
    case TxCountRole:      return e.txCount;
    case TransactionsRole: return e.transactions;
    case RawJsonRole:      return e.rawJson;
    case ParsedRole:       return e.parsed;
    case EpochRole: {      // floor(slot / epoch_length) for grouping; -1 if unknown
        bool ok = false; const qlonglong s = e.slot.toLongLong(&ok);
        return ok ? int(s / 36000) : -1;   // PREVIEW: epoch_length is the testnet const (#61)
    }
    default:               return QVariant();
    }
}

QHash<int, QByteArray> BlockModel::roleNames() const
{
    QHash<int, QByteArray> names;
    names[TimestampRole]    = "timestamp";
    names[SlotRole]         = "slot";
    names[VersionRole]      = "version";
    names[ParentBlockRole]  = "parentBlock";
    names[BlockRootRole]    = "blockRoot";
    names[LeaderKeyRole]    = "leaderKey";
    names[EntropyRole]      = "entropy";
    names[ProofRole]        = "proof";
    names[VoucherCmRole]    = "voucherCm";
    names[SignatureRole]    = "signature";
    names[TxCountRole]      = "txCount";
    names[TransactionsRole] = "transactions";
    names[RawJsonRole]      = "rawJson";
    names[ParsedRole]       = "parsed";
    names[EpochRole]        = "epoch";
    return names;
}

QVariantList BlockModel::txSeries() const
{
    // m_entries is newest-first (row 0 = newest); emit oldest→newest for a left→right heatmap.
    QVariantList out;
    for (int i = m_entries.size() - 1; i >= 0; --i) {
        const Entry& e = m_entries.at(i);
        QVariantMap m;
        m[QStringLiteral("slot")] = e.slot;
        m[QStringLiteral("txCount")] = e.txCount;
        out << m;
    }
    return out;
}

void BlockModel::appendRaw(const QString& timestamp, const QString& rawJson)
{
    Entry e;
    e.timestamp = timestamp;

    // The payload is double-encoded JSON: an outer {"block":"<json string>"}
    // whose value is itself a JSON-encoded block. Tolerate a few shapes:
    //   { "block": "<stringified block>" }   (observed)
    //   { "block": { ... } }                  (already an object)
    //   { "header": ..., "transactions": ... }(block sent directly)
    QJsonObject block;
    bool ok = false;

    QJsonParseError err{};
    const QJsonDocument outer = QJsonDocument::fromJson(rawJson.toUtf8(), &err);
    if (err.error == QJsonParseError::NoError && outer.isObject()) {
        const QJsonObject o = outer.object();
        if (o.contains(QStringLiteral("block"))) {
            const QJsonValue bv = o.value(QStringLiteral("block"));
            if (bv.isString()) {
                const QJsonDocument inner =
                    QJsonDocument::fromJson(bv.toString().toUtf8(), &err);
                if (err.error == QJsonParseError::NoError && inner.isObject()) {
                    block = inner.object();
                    ok = true;
                }
            } else if (bv.isObject()) {
                block = bv.toObject();
                ok = true;
            }
        } else if (o.contains(QStringLiteral("header"))) {
            block = o;
            ok = true;
        }
    }

    if (ok) {
        e.parsed = true;

        const QJsonObject header = block.value(QStringLiteral("header")).toObject();
        e.version = header.value(QStringLiteral("version")).toString();
        e.blockId = header.value(QStringLiteral("id")).toString();
        e.parentBlock = header.value(QStringLiteral("parent_block")).toString();

        const QJsonValue slotV = header.value(QStringLiteral("slot"));
        e.slot = slotV.isDouble()
            ? QString::number(static_cast<qlonglong>(slotV.toDouble()))
            : slotV.toString();

        e.blockRoot = header.value(QStringLiteral("block_root")).toString();

        const QJsonObject pol =
            header.value(QStringLiteral("proof_of_leadership")).toObject();
        e.proof = pol.value(QStringLiteral("proof")).toString();
        e.entropy = pol.value(QStringLiteral("entropy_contribution")).toString();
        e.leaderKey = pol.value(QStringLiteral("leader_key")).toString();
        e.voucherCm = pol.value(QStringLiteral("voucher_cm")).toString();

        e.signature = block.value(QStringLiteral("signature")).toString();

        const QJsonArray txs = block.value(QStringLiteral("transactions")).toArray();
        e.txCount = txs.size();
        for (const QJsonValue tx : txs)
            e.transactions << prettify(tx);

        e.rawJson = QString::fromUtf8(QJsonDocument(block).toJson(QJsonDocument::Indented));
    } else {
        // Keep the raw text so an unexpected format is still inspectable.
        e.parsed = false;
        e.rawJson = rawJson;
    }

    beginInsertRows(QModelIndex(), 0, 0);
    m_entries.prepend(e);
    endInsertRows();

    if (m_entries.size() > kMaxBlocks) {
        const int last = m_entries.size() - 1;
        beginRemoveRows(QModelIndex(), last, last);
        m_entries.remove(last);
        endRemoveRows();
    }

    emit countChanged();
}

QVariantMap BlockModel::findTransaction(const QString& txId) const
{
    // Normalise for comparison: trim, drop an optional 0x prefix, lowercase.
    auto normalize = [](const QString& s) {
        QString t = s.trimmed();
        if (t.startsWith(QStringLiteral("0x"), Qt::CaseInsensitive))
            t = t.mid(2);
        return t.toLower();
    };

    const QString needle = normalize(txId);
    if (needle.isEmpty())
        return QVariantMap{{"found", false}};

    for (const Entry& e : m_entries) {
        for (const QString& txJson : e.transactions) {
            QJsonParseError err{};
            const QJsonDocument doc = QJsonDocument::fromJson(txJson.toUtf8(), &err);
            if (err.error != QJsonParseError::NoError || !doc.isObject())
                continue;
            const QString id = doc.object().value(QStringLiteral("id")).toString();
            if (!id.isEmpty() && normalize(id) == needle) {
                return QVariantMap{
                    {"found", true},
                    {"value", txJson},
                    {"blockId", e.blockId},
                    {"slot", e.slot},
                    {"timestamp", e.timestamp},
                };
            }
        }
    }
    return QVariantMap{{"found", false}};
}

void BlockModel::clear()
{
    if (m_entries.isEmpty())
        return;
    beginResetModel();
    m_entries.clear();
    endResetModel();
    emit countChanged();
}
