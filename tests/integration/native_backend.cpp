// REAL packaged implementation, SYNTHETIC public-only node responses.
#include <QCoreApplication>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include "rep_BlockchainBackend_source.h"
#include "logos_ui_plugin_context.h"
#include "AccountsModel.h"
#include "BlockModel.h"
// Test-only cached-PID seeding prevents the real implementation's process scanner
// from selecting a live node. Dependencies are included first so only this class's
// access labels change; layout and every production method remain unchanged.
#define private public
#include "logos_node_1click_backend.h"
#undef private
#include <QDir>
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaMethod>
#include <QTimer>
#include <iostream>
#include <stdexcept>

static void require(bool pass, const QString& message)
{
    if (!pass) throw std::runtime_error(message.toStdString());
}
static QJsonObject readJson(const QString& path)
{
    QFile file(path);
    require(file.open(QIODevice::ReadOnly), "Cannot open fixture " + path);
    QJsonParseError error;
    auto doc = QJsonDocument::fromJson(file.readAll(), &error);
    require(error.error == QJsonParseError::NoError && doc.isObject(), "Invalid fixture JSON");
    return doc.object();
}
static QVariantMap invoke(QObject* object, const char* name)
{
    const QByteArray signature = QByteArray(name) + "()";
    const int index = object->metaObject()->indexOfMethod(signature);
    require(index >= 0, "Packaged backend missing QtRO slot: " + signature);
    const auto method = object->metaObject()->method(index);
    require(method.returnMetaType() == QMetaType::fromType<QVariantMap>(),
            "QtRO return type must be QVariantMap: " + signature);
    QVariantMap result;
    require(method.invoke(object, Qt::DirectConnection, Q_RETURN_ARG(QVariantMap, result)),
            "Metaobject invocation failed: " + signature);
    return result;
}
// Only expose generated protected setters; no behavior or virtual overrides.
class HarnessBackend final : public LogosNode1clickBackend {
public:
    using LogosNode1clickBackend::setStatus;
    using LogosNode1clickBackend::setGeneratedUserConfigPath;
};
int main(int argc, char** argv)
{
    try {
        const QString root = QString::fromUtf8(qgetenv("BLEND_FIXTURE_ROOT"));
        require(root.startsWith("/extra/") && QFile::exists(root + "/SYNTHETIC_FIXTURE"),
                "Must run via isolated fixture runner");
        require(qgetenv("BLEND_NETWORK_BLOCKED") == "seccomp", "Network sandbox required");
        require(QDir::currentPath() == root, "Working directory is not isolated");
        QCoreApplication app(argc, argv);
        const QJsonObject test = readJson(root + "/case.json");
        HarnessBackend backend;
        // Constructor starts the resource timer even without onContextReady. Stop it
        // before any process wait/event dispatch: never scan real node processes.
        for (auto* timer : backend.findChildren<QTimer*>()) timer->stop();
        require(!backend.isContextReady(), "Framework must remain disconnected");
        backend.setUserConfig(root + "/user_config.yaml");
        backend.setGeneratedUserConfigPath(root + "/user_config.yaml");
        backend.setStatus(test.value("running").toBool(true)
                          ? BlockchainBackendSource::Running : BlockchainBackendSource::NotStarted);
        backend.m_nodePid = QCoreApplication::applicationPid();
        if (test.value("missingBinding").toBool()) {
            require(QDir().mkpath(root + "/logs"), "Cannot create synthetic logs");
            QFile log(root + "/logs/synthetic.log");
            require(log.open(QIODevice::WriteOnly), "Cannot create synthetic log");
            const QByteArray line = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs).toUtf8()
                + " SYNTHETIC sdp: No declaration_id set. Cannot post activity without declaration.\n";
            require(log.write(line) == line.size(), "Cannot write synthetic binding evidence");
            log.close();
        }
        // Check both packaged methods and the independently regenerated .rep source.
        require(BlockchainBackendSource::staticMetaObject.indexOfMethod("getBlendLifecycle()") >= 0,
                "Generated QtRO source lacks lifecycle contract");
        require(BlockchainBackendSource::staticMetaObject.indexOfMethod("repairBlendBinding()") >= 0,
                "Generated QtRO source lacks repair contract");
        QVariantMap lifecycle = invoke(&backend, "getBlendLifecycle");
        const QStringList fields{"ok", "state", "title", "detail", "tone", "epoch", "declarationId",
            "created", "active", "nonce", "withdrawAt", "mode", "healthyPeers", "bindingStatus",
            "action", "actionLabel", "steps", "evidence"};
        for (const auto& field : fields) require(lifecycle.contains(field), "Missing lifecycle field " + field);
        require(lifecycle.value("nonce").metaType() == QMetaType::fromType<QString>(), "nonce must remain a string");
        require(lifecycle.value("steps").toList().size() == 6, "Expected six progress stages");
        const QString expected = test.value("state").toString();
        require(lifecycle.value("state").toString() == expected,
            "Expected " + expected + ", got " + QString::fromUtf8(QJsonDocument::fromVariant(lifecycle).toJson(QJsonDocument::Compact)));
        QVariantMap repair;
        if (test.value("storageFailure").toBool()) {
            require(QFile::remove(root + "/blend-declaration.json"), "Cannot remove fixture cache");
            require(QDir().mkdir(root + "/blend-declaration.json"), "Cannot obstruct fixture cache path");
            const QVariantMap rejected = invoke(&backend, "withdrawBlendCore");
            require(!rejected.value("ok").toBool()
                && rejected.value("error").toString().contains("Cannot persist"),
                "Storage failure must prevent any withdrawal request");
        }
        if (test.contains("repairOk")) {
            repair = invoke(&backend, "repairBlendBinding");
            for (const auto& key : {"ok", "error", "message"})
                require(repair.contains(key), QString("Repair lacks ") + key);
            require(repair.value("ok").toBool() == test.value("repairOk").toBool(),
                "Unexpected repair result: " + QString::fromUtf8(QJsonDocument::fromVariant(repair).toJson(QJsonDocument::Compact)));
            if (repair.value("ok").toBool()) {
                lifecycle = invoke(&backend, "getBlendLifecycle");
                require(lifecycle.value("bindingStatus").toString() == "confirmed", "Repair acknowledgement not retained for this run");
                require(lifecycle.value("state").toString() != "healthy", "Acknowledgement must not imply accepted activity");
            }
        }
        const QJsonObject report{{"case", test.value("name")}, {"syntheticFixtures", true},
            {"lifecycle", QJsonObject::fromVariantMap(lifecycle)}, {"repair", QJsonObject::fromVariantMap(repair)}};
        std::cout << QJsonDocument(report).toJson(QJsonDocument::Compact).constData() << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return 1;
    }
}
