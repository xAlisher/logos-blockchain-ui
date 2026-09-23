#include "BlendRecovery.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDebug>
#include <cstdlib>
#define CHECK(x) do { if (!(x)) { qCritical() << "FAIL" << __LINE__ << #x; std::exit(1); } } while (0)
using namespace BlendRecovery;
Snapshot stale()
{
    Snapshot s;
    s.valid = true; s.running = true; s.identity = true; s.online = true; s.bindingKnown = true;
    s.provider = QString(64, 'a'); s.id = QString(64, 'b');
    s.note = QString(64, 'c'); s.locator = "/ip4/8.8.8.8/udp/3400/quic-v1";
    s.created = 10; s.activity = 12; s.epoch = 18; s.slot = 1800; s.lib = 1700;
    s.present = true; s.funded = true;
    return s;
}
int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir dir("/extra/tmp/blend-recovery-test-XXXXXX"); CHECK(dir.isValid());
    Controller c; CHECK(c.open(dir.path() + "/recovery.json", "fixture-config"));
    Snapshot s = stale();
    CHECK(!c.active()); CHECK(c.canStart(s)); // reading must not authorize
    CHECK(!c.active());
    s.identity = false; CHECK(!c.canStart(s)); s = stale();
    s.pending = true; CHECK(!c.canStart(s)); s = stale();
    s.epoch = 12; CHECK(!c.canStart(s)); s = stale();
    s.note.clear(); CHECK(!c.canStart(s));
    CHECK(c.start(stale())); CHECK(c.active()); CHECK(!c.canStart(stale()));
    CHECK(c.phase() == "preflight");
    CHECK(c.pause()); CHECK(c.active()); CHECK(c.paused());
    CHECK(c.resume()); CHECK(!c.paused());
    Controller competing; CHECK(!competing.open(dir.path() + "/recovery.json", "fixture-config"));
    CHECK(competing.active()); CHECK(!competing.start(stale()));
    {
        Controller persisted; CHECK(persisted.open(dir.path() + "/other.json", "fixture-config"));
        CHECK(persisted.start(stale())); CHECK(persisted.pause());
    }
    {
        Controller persisted; CHECK(persisted.open(dir.path() + "/other.json", "fixture-config"));
        CHECK(persisted.active()); CHECK(persisted.paused());
    }
    {
        Controller wrongScope; CHECK(!wrongScope.open(dir.path() + "/other.json", "different-config"));
        CHECK(wrongScope.active()); CHECK(!wrongScope.resume());
    }
    QFile corrupt(dir.path() + "/bad.json"); CHECK(corrupt.open(QIODevice::WriteOnly));
    corrupt.write("{broken"); corrupt.close();
    Controller bad; CHECK(!bad.open(corrupt.fileName(), "fixture-config")); CHECK(bad.active());
    CHECK(!bad.start(stale())); CHECK(!bad.resume());
    // The same controller executes production transitions; callbacks replace only transport.
    QStringList calls;
    auto post = [&](Action a, const QJsonObject& body) {
        calls << actionName(a);
        if (a == Action::Declare) { CHECK(body.value("locked_note_id") == stale().note); CHECK(body.value("locator") == stale().locator); }
        return Reply{Outcome::Accepted, QString()};
    };
    s = stale();
    c.tick(s, post); CHECK(c.phase() == "withdraw-ready"); CHECK(calls == QStringList{"bind-original"});
    c.tick(s, post); CHECK(c.phase() == "withdraw-pending"); CHECK(calls.last() == "withdraw");
    c.tick(s, post); CHECK(calls.size() == 2); // ack is not inclusion, never retry
    s.withdrawal = 20; c.tick(s, post); CHECK(c.phase() == "withdraw-wait");
    s.epoch = 20; s.slot = 2000; s.lib = 1900; s.present = false;
    c.tick(s, post); CHECK(c.phase() == "removal-wait"); CHECK(calls.size() == 2);
    c.tick(s, post); CHECK(calls.size() == 2); // irreversible slot barrier
    s.lib = 2000; s.noteSpendable = true;
    c.tick(s, post); CHECK(c.phase() == "declare-pending"); CHECK(calls.last() == "declare");
    c.tick(s, post); CHECK(calls.size() == 3);
    s.present = true; s.withdrawal = -1; s.created = 20; s.activity = 22;
    c.tick(s, post); CHECK(c.phase() == "binding"); // SAME ID, NEW incarnation
    c.tick(s, post); CHECK(c.phase() == "activation"); CHECK(calls.last() == "bind-new");
    s.core = true; s.epoch = 22; s.slot = 2200; c.tick(s, post);
    CHECK(c.active()); // baseline+Core does not complete
    for (int epoch = 23; epoch <= 25; ++epoch) {
        s.epoch = epoch; s.slot = epoch * 100; s.activity = epoch;
        c.tick(s, post);
    }
    CHECK(!c.active()); CHECK(c.phase() == "complete");
    CHECK(c.state().value("coverage").toArray().size() == 3);
    CHECK(calls.count("withdraw") == 1); CHECK(calls.count("declare") == 1);
    const QVariantMap view = c.view(s);
    for (const QString& key : {"active", "phase", "title", "detail", "tone", "steps", "canStart", "canPause", "canResume"}) CHECK(view.contains(key));
    CHECK(view.value("phase") == "complete");
    // Unknown paid outcome survives process/controller reload, never retried.
    const QString pendingPath = dir.path() + "/pending.json";
    int withdrawals = 0;
    auto unknown = [&](Action a, const QJsonObject&) {
        if (a == Action::Withdraw) ++withdrawals;
        return Reply{a == Action::Withdraw ? Outcome::Unknown : Outcome::Accepted, {}};
    };
    {
        Controller pending; CHECK(pending.open(pendingPath, "fixture-config")); CHECK(pending.start(stale()));
        pending.tick(stale(), unknown); pending.tick(stale(), unknown); CHECK(withdrawals == 1);
    }
    {
        Controller pending; CHECK(pending.open(pendingPath, "fixture-config"));
        for (int n = 0; n < 4; ++n) pending.tick(stale(), unknown);
        CHECK(withdrawals == 1); CHECK(pending.phase() == "withdraw-pending");
        CHECK(pending.pause()); pending.tick(stale(), unknown); CHECK(pending.resume());
        pending.tick(stale(), unknown); CHECK(withdrawals == 1);
        Snapshot changed = stale(); changed.provider = QString(64, 'd');
        pending.tick(changed, unknown); CHECK(pending.phase() == "attention");
        CHECK(!pending.resume()); CHECK(!pending.view(changed).value("canResume").toBool());
    }
    // Disk failure before write-ahead must suppress the paid request.
    {
        const QString path = dir.path() + "/unwritable.json";
        Controller disk; CHECK(disk.open(path, "fixture-config")); CHECK(disk.start(stale()));
        disk.tick(stale(), unknown); CHECK(disk.phase() == "withdraw-ready");
        CHECK(QFile::remove(path)); CHECK(QDir().mkdir(path));
        disk.tick(stale(), unknown); CHECK(withdrawals == 1); CHECK(disk.phase() == "attention");
    }
    qInfo() << "backend recovery persisted sequence and safety tests passed";
}
