#pragma once

#include <QHash>
#include <QString>
#include <QStringList>
#include <QVector>

// The app's own record of settled reward claims — both kinds the chain pays.
//
// The node has no "how much have I earned" call for either. 

// For staking,wallet_get_claimable_vouchers reports what is *unclaimed* and 
// drops to zero the moment a claim settles; 

// For mining, the counter it replaces was rebuilt from scratch on every start. 
// What the chain does have is events:
// LeaderRewardClaimed and PoWRewardClaimed each carry the reward note, so the
// settled value is on the wire. This accumulates those, one record per claim,
// and persists them so the figures survive a restart.
class ClaimLedger
{
public:
    enum class Kind {
        Staking, // LeaderRewardClaimed — minted straight to a wallet key
        Mining,  // PoWRewardClaimed — minted to a per-ticket key, then transferred
    };

    struct Record {
        Kind kind = Kind::Staking;
        QString nullifier; // voucher_nullifier | pow_nullifier — chain-unique either way
        QString value;
        QString payee; // the wallet key it was attributed to, normalized
        QString blockId;
        QString txHash;
        quint64 slot = 0;

        // For change detection in ClaimsModel. Written out rather than
        // defaulted because this is C++17; `= default` lands in C++20.
        friend bool operator==(const Record& a, const Record& b)
        {
            return a.kind == b.kind && a.nullifier == b.nullifier && a.value == b.value
                && a.payee == b.payee && a.blockId == b.blockId && a.txHash == b.txHash
                && a.slot == b.slot;
        }
        friend bool operator!=(const Record& a, const Record& b) { return !(a == b); }
    };

    // A claim this app sent and has not yet seen land. The chain is never asked
    // about it: the only thing recorded here is that we submitted it, which is
    // true whatever the chain later does. It clears when a Record arrives
    // carrying the same transaction hash, and otherwise ages out.
    //
    // Auto-claim does not come through here — the node claims unattended and
    // this app never sees the submission — so a zero is "nothing sent from
    // here", not "nothing in flight".
    struct Submission {
        Kind kind = Kind::Staking;
        QString txHash; // normalized hex; the join to Record::txHash
        // LIB when it was sent. The expiry clock is chain progress rather than
        // wall time: a node that has stopped advancing has not failed to
        // include the claim, it just has not got there yet.
        quint64 libSlotAtSubmit = 0;
    };

    struct Pending {
        struct TxClaim {
            QStringList payees;
        };

        QString blockId;
        quint64 slot = 0;
        int attempts = 0;
        QHash<QString, TxClaim> claims; // txHash -> what that transaction claims

        // Claims for a transaction, or the wildcard entry a ledger written
        // before claims were keyed by transaction leaves behind.
        [[nodiscard]] const TxClaim* claimFor(const QString& txHash) const;
    };

    // The wildcard key. Only ever written by the migration in load().
    static const QString kAnyTx;

    void load(const QString& path, const QString& chainId);
    bool save(const QString& path) const;
    bool add(const Record& record);

    // Submissions. Not finality-gated — "we sent it" is settled the moment we
    // send it, which is the whole point of showing it.
    bool addSubmission(const Submission& submission);
    // A claim we sent has been seen on chain. Answers whether one was cleared.
    bool clearSubmission(Kind kind, const QString& txHash);
    // Drop submissions LIB has moved past without ever seeing. Answers how many
    // went, so the caller can say so rather than losing them quietly.
    int expireSubmissions(quint64 libSlot, quint64 windowSlots);
    [[nodiscard]] int submittedCount(Kind kind) const;

    // Every settled claim, in the order they were found. ClaimsModel sorts.
    [[nodiscard]] const QVector<Record>& records() const { return m_records; }

    [[nodiscard]] int confirmedCount(Kind kind, quint64 libSlot) const;
    // Claims seen in a block but not yet settled beyond reversal. The
    // complement of confirmedCount, and what decides whether a "show only
    // pending" control has anything to offer.
    [[nodiscard]] int pendingCount(Kind kind, quint64 libSlot) const;
    [[nodiscard]] QString confirmedTotal(Kind kind, quint64 libSlot) const;

    [[nodiscard]] const QVector<Pending>& pending() const { return m_pending; }
    void setPending(QVector<Pending> pending) { m_pending = std::move(pending); }

    [[nodiscard]] QString countingSince() const { return m_countingSince; }
    void setCountingSince(const QString& iso) { m_countingSince = iso; }

    // Sum of two non-negative decimal integers given as text.
    [[nodiscard]] static QString addLepta(const QString& a, const QString& b);

private:
    QVector<Record> m_records;
    QHash<QString, int> m_byKey; // "<kind>:<nullifier>" -> index into m_records
    QVector<Submission> m_submissions;
    QVector<Pending> m_pending;
    QString m_chainId;
    QString m_countingSince;
};
