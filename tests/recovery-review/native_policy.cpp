#include "BlendRecovery.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QDebug>
#include <cstdlib>

#define CHECK(x) do { if (!(x)) { qCritical() << "FAIL" << __LINE__ << #x; std::exit(1); } } while (0)
using namespace BlendRecovery;

static Snapshot fixture()
{
    Snapshot s;
    s.valid = s.running = s.identity = s.online = s.present = s.funded = s.bindingKnown = true;
    s.provider = QString(64, 'a'); s.id = QString(64, 'b'); s.note = QString(64, 'c');
    s.locator = "/ip4/192.0.2.1/udp/3400/quic-v1";
    s.created = 10; s.activity = 12; s.epoch = 18; s.slot = 1800; s.lib = 1700;
    return s;
}

static void readyToDeclare(Controller& c, Snapshot& s, const Post& post)
{
    CHECK(c.start(s)); c.tick(s, post); c.tick(s, post);
    s.withdrawal = 20; c.tick(s, post);
    s.epoch = 20; s.slot = 2000; s.lib = 1900; s.present = false;
    c.tick(s, post); CHECK(c.phase() == "removal-wait");
    s.lib = 2000; s.noteSpendable = true;
}

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir dir("/extra/tmp/recovery-review-XXXXXX"); CHECK(dir.isValid());
    auto accepted = [](Action, const QJsonObject&) { return Reply{Outcome::Accepted, {}}; };

    // Losing the JOIN reply is just as dangerous as losing withdrawal's reply.
    // Reloading the actual durable journal must never authorize a second join.
    int joins = 0;
    auto unknownJoin = [&](Action action, const QJsonObject&) {
        if (action == Action::Declare) ++joins;
        return Reply{action == Action::Declare ? Outcome::Unknown : Outcome::Accepted, {}};
    };
    Snapshot missing = fixture();
    {
        Controller c; CHECK(c.open(dir.path() + "/join.json", "fixture"));
        readyToDeclare(c, missing, unknownJoin); c.tick(missing, unknownJoin);
        CHECK(c.phase() == "declare-pending" && joins == 1);
    }
    {
        Controller c; CHECK(c.open(dir.path() + "/join.json", "fixture"));
        CHECK(c.pause()); CHECK(c.resume());
        for (int i = 0; i < 5; ++i) c.tick(missing, unknownJoin);
        CHECK(joins == 1 && c.phase() == "declare-pending");
    }

    // Time + absence is not a withdrawal confirmation if no schedule was seen.
    {
        Controller c; CHECK(c.open(dir.path() + "/absent.json", "fixture"));
        Snapshot s = fixture(); CHECK(c.start(s)); c.tick(s, accepted); c.tick(s, accepted);
        int requests = 0;
        auto counted = [&](Action, const QJsonObject&) { ++requests; return Reply{Outcome::Accepted, {}}; };
        s.present = false; s.epoch = 30; s.slot = 3000; s.lib = 2900; s.noteSpendable = true;
        c.tick(s, counted); CHECK(c.phase() == "withdraw-pending" && requests == 0);
    }

    // An operator pause during the request's nested event loop survives the reply.
    {
        Controller c; CHECK(c.open(dir.path() + "/pause.json", "fixture"));
        Snapshot s = fixture(); CHECK(c.start(s)); c.tick(s, accepted);
        int calls = 0;
        auto pauseInFlight = [&](Action action, const QJsonObject&) {
            CHECK(action == Action::Withdraw); ++calls; CHECK(c.pause());
            c.tick(s, accepted); // real controller's reentrancy guard
            return Reply{Outcome::Accepted, {}};
        };
        c.tick(s, pauseInFlight);
        CHECK(calls == 1 && c.paused() && c.phase() == "withdraw-pending");
    }

    // Scope/identity faults must survive a host restart, not resume an armed plan.
    {
        const QString path = dir.path() + "/fault.json";
        Snapshot s = fixture();
        {
            Controller c; CHECK(c.open(path, "fixture")); CHECK(c.start(s));
            c.tick(s, accepted); CHECK(c.phase() == "withdraw-ready");
            CHECK(!c.fail("Config changed during recovery"));
        }
        Controller restored; CHECK(restored.open(path, "fixture"));
        CHECK(restored.active() && restored.phase() == "attention");
        CHECK(!restored.resume());
        int requests = 0;
        restored.tick(s, [&](Action, const QJsonObject&) { ++requests; return Reply{Outcome::Accepted, {}}; });
        CHECK(requests == 0);
    }

    // User-local recovery identifiers are not world-readable. Losing the journal
    // while an authorized controller runs must not silently recreate authority.
    {
        const QString path = dir.path() + "/deleted.json";
        Controller c; CHECK(c.open(path, "fixture")); Snapshot s = fixture(); CHECK(c.start(s));
        CHECK(!(QFile::permissions(path) & (QFile::ReadGroup | QFile::ReadOther)));
        CHECK(QFile::remove(path));
        int requests = 0;
        c.tick(s, [&](Action, const QJsonObject&) { ++requests; return Reply{Outcome::Accepted, {}}; });
        CHECK(requests == 0 && c.phase() == "attention");
        CHECK(!QFile::exists(path)); // do not overwrite or silently replace evidence
    }

    // Definitively missed bootstrap evidence must not later become 'unobserved'.
    {
        Controller c; CHECK(c.open(dir.path() + "/coverage.json", "fixture"));
        Snapshot s = fixture(); readyToDeclare(c, s, accepted); c.tick(s, accepted);
        s.present = true; s.created = 20; s.activity = 22; s.withdrawal = -1;
        c.tick(s, accepted); c.tick(s, accepted);
        s.core = true; s.epoch = 24; s.slot = 2400; c.tick(s, accepted);
        CHECK(c.state().value("coverage").toArray().at(0).toObject().value("status") == "missed");
        s.epoch = 25; s.slot = 2500; s.activity = 25; c.tick(s, accepted);
        CHECK(c.state().value("coverage").toArray().at(0).toObject().value("status") == "missed");
        CHECK(c.active()); // one later activity, not three consecutive renewals
    }
    {
        Controller c; CHECK(c.open(dir.filePath("binding-current.json"), "fixture")); auto s=fixture();
        readyToDeclare(c, s, accepted); c.tick(s, accepted);
        s.present=true; s.created=20; s.activity=22; s.epoch=22; s.slot=2200; s.lib=2100;
        s.withdrawal=-1; s.core=true; s.bindingKnown=false;
        c.tick(s, accepted); c.tick(s, accepted);
        for (int epoch=23; epoch<=25; ++epoch) {
            s.epoch=s.activity=epoch; s.slot=epoch*100; s.lib=s.slot-100; c.tick(s, accepted);
        }
        CHECK(c.phase()=="monitoring"); // old renewals do not prove this run is bound
        int binds=0;
        auto countBinds=[&](Action, const QJsonObject&) { ++binds; return Reply{Outcome::Accepted,{}}; };
        s.bindingKnown=true; s.core=false; c.tick(s, countBinds);
        CHECK(c.phase()=="activation" && c.active()); // time/renewals are not runtime Core
        s.core=true; c.tick(s, countBinds);
        CHECK(c.phase()=="complete" && binds==0);
    }
    qInfo() << "Independent recovery safety policy checks passed";
}
