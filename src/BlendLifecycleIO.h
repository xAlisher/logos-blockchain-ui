#pragma once
#include <QProcess>
#include <QProcessEnvironment>
#include <QEventLoop>
#include <QTimer>
#include <QJsonDocument>
#include <QMap>
#include <memory>
#include <vector>

namespace BlendLifecycle {
struct Reply { QString body; QString code; bool ok() const { return code.startsWith('2'); } };
// Concurrent, bounded HTTP snapshot. Event dispatch stays live in the QtRO host;
// callers hold overlap/mutation guards across this nested event loop.
inline QMap<QString, Reply> request(const QString& curl, const QProcessEnvironment& env,
                                  const QString& apiBase,
                                  const QStringList& paths, const QString& method = "GET",
                                  const QString& body = {})
{
    QMap<QString, Reply> replies;
    // Telemetry is cheap; join/withdraw may build a transaction. Preserve the
    // existing eight-second mutation budget rather than applying the polling timeout.
    const bool reading = method == QStringLiteral("GET");
    QEventLoop loop;
    QTimer deadline;
    deadline.setSingleShot(true);
    QObject::connect(&deadline, &QTimer::timeout, &loop, &QEventLoop::quit);
    std::vector<std::unique_ptr<QProcess>> processes;
    int pending = paths.size();
    for (const QString& path : paths) {
        auto p = std::make_unique<QProcess>();
        p->setProcessEnvironment(env);
        QObject::connect(p.get(), &QProcess::finished, &loop, [&](int, QProcess::ExitStatus) { if (--pending == 0) loop.quit(); });
        QStringList args{"-sS", "--connect-timeout", "1", "--max-time", reading ? "1.5" : "8", "-X", method, "-w", "\n%{http_code}"};
        if (!body.isEmpty()) args << "-H" << "Content-Type: application/json" << "-d" << body;
        args << (apiBase + path);
        p->start(curl, args);
        processes.push_back(std::move(p));
    }
    deadline.start(reading ? 1800 : 8500);
    if (pending) loop.exec();
    for (int i = 0; i < paths.size(); ++i) {
        auto& p = processes[i];
        if (p->state() != QProcess::NotRunning) { p->kill(); p->waitForFinished(100); }
        const QString output = QString::fromUtf8(p->readAllStandardOutput());
        const int split = output.lastIndexOf('\n');
        Reply reply;
        if (p->exitStatus() == QProcess::NormalExit && p->exitCode() == 0 && split >= 0) {
            reply.body = output.left(split).trimmed(); reply.code = output.mid(split + 1).trimmed();
        }
        replies.insert(paths[i], reply);
    }
    return replies;
}
}
