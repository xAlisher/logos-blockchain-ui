#include "BlendMutation.h"
#include <QJsonObject>
#include <iostream>
#include <cstdlib>

static void check(bool ok, const char* message)
{
    if (!ok) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}

int main()
{
    const QJsonObject previous{{"declaration_id", "old-id"}, {"removed", true},
                               {"locator", "old-locator"}, {"locked_note_id", "old-note"},
                               {"created_at", "original-time"}};
    QJsonObject pending = previous;
    pending["submission_pending"] = true;
    pending["locator"] = "new-locator";
    pending["locked_note_id"] = "new-note";
    check(BlendMutation::afterReply(previous, pending, "400") == previous,
          "definitive join rejection restores history and clears this attempt's pending flag");
    int cases = 1;
    for (const QString& code : {QString("401"), QString("403"), QString("404"),
                                QString("409"), QString("422"), QString("429")}) {
        check(BlendMutation::definitivelyRejected(code), "complete client rejection is definitive");
        check(BlendMutation::afterReply(previous, pending, code) == previous,
              "join rejection preserves the entire previous record");
        ++cases;
    }
    for (const QString& code : {QString(), QString("000"), QString("408"), QString("500"),
                                QString("502"), QString("503"), QString("504"), QString("200"),
                                QString("202"), QString("204"), QString("302"), QString("4"),
                                QString("4000"), QString("4xx"), QString(" 400")}) {
        check(!BlendMutation::definitivelyRejected(code), "uncertain or successful response must not unlock retry");
        check(BlendMutation::afterReply(previous, pending, code) == pending,
              "ambiguous delivery preserves pending flag and attempted identity");
        ++cases;
    }
    QJsonObject withdrawalPrevious = previous;
    withdrawalPrevious["declaration_id"] = "verified-id";
    withdrawalPrevious["submission_pending"] = true;
    QJsonObject withdrawalPending = withdrawalPrevious;
    withdrawalPending["withdraw_pending"] = true;
    check(BlendMutation::afterReply(withdrawalPrevious, withdrawalPending, "422") == withdrawalPrevious,
          "withdraw rejection preserves verified identity and unrelated submission flag");
    ++cases;
    check(BlendMutation::afterReply(withdrawalPrevious, withdrawalPending, "504") == withdrawalPending,
          "uncertain withdrawal preserves all state");
    ++cases;
    check(BlendMutation::afterReply({}, pending, "400").isEmpty(),
          "first rejected join leaves no phantom declaration");
    ++cases;
    std::cout << "PASS: " << cases << " mutation recovery cases\n";
}
