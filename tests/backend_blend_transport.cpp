#include "BlendLifecycleIO.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QElapsedTimer>
#include <QDebug>
#include <QJsonObject>
#include <cstdlib>

static void check(bool condition, const char* message)
{
    if (!condition) { qCritical() << "FAIL:" << message; std::exit(1); }
}
int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir dir("/extra/tmp/blend-transport-XXXXXX");
    check(dir.isValid(), "fixture directory under /extra");
    const QString path = dir.filePath("curl-fixture");
    auto script = [&](const QByteArray& content) {
        QFile f(path); check(f.open(QIODevice::WriteOnly | QIODevice::Truncate), "write fixture");
        f.write(content); f.close();
        f.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    };
    // No real curl or socket is used. The fixture ignores all URL arguments.
    script("#!/bin/sh\nprintf '{\"fixture\":true}\\n200'\n");
    auto result = BlendLifecycle::request(path, QProcessEnvironment::systemEnvironment(), {"/one", "/two"});
    check(result.size() == 2 && result["/one"].ok() && result["/two"].ok(), "concurrent response framing");
    check(QJsonDocument::fromJson(result["/one"].body.toUtf8()).object().value("fixture").toBool(), "body preserved");
    script("#!/bin/sh\nprintf '{\"error\":\"fixture\"}\\n500'\n");
    result = BlendLifecycle::request(path, QProcessEnvironment::systemEnvironment(), {"/one"});
    check(!result["/one"].ok(), "HTTP errors not successful");
    script("#!/bin/sh\nexec /bin/sleep 10\n");
    int ticks = 0;
    QTimer timer;
    QObject::connect(&timer, &QTimer::timeout, [&] { ++ticks; });
    timer.start(20);
    QElapsedTimer elapsed; elapsed.start();
    result = BlendLifecycle::request(path, QProcessEnvironment::systemEnvironment(), {"/one", "/two", "/three", "/four"});
    check(elapsed.elapsed() < 2600, "parallel deadline bounded, not four sequential timeouts");
    check(ticks > 20, "Qt event dispatch stays responsive during hung requests");
    check(!result["/one"].ok(), "killed request remains unavailable");
    qInfo() << "PASS backend transport; event-loop ticks" << ticks << "elapsed ms" << elapsed.elapsed();
}
