#include "BlendLifecycleIO.h"
#include <QCoreApplication>
#include <QDebug>
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (argc != 2) return 2;
    const auto env = QProcessEnvironment::systemEnvironment();
    const auto get = BlendLifecycle::request(QString::fromLocal8Bit(argv[1]), env, {"/fixture"});
    if (get.value("/fixture").ok()) { qCritical() << "GET deadline was not bounded"; return 1; }
    const auto post = BlendLifecycle::request(QString::fromLocal8Bit(argv[1]), env, {"/fixture"}, "POST", "null");
    if (!post.value("/fixture").ok()) { qCritical() << "POST incorrectly used short telemetry deadline"; return 1; }
    qInfo() << "PASS bounded telemetry and longer mutation deadline";
}
