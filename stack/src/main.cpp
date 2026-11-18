// SPDX-License-Identifier: GPL-3.0-or-later
// macglass-stack — macOS-style Downloads stack for KDE Plasma (Wayland).
//
//   macglass-stack [--toggle|--show|--hide] [--view fan|grid|list|auto] [--daemon]
//
// The first invocation becomes a small resident service (org.macglass.Stack);
// later invocations just forward their command over D-Bus and exit.
#include "stackcontroller.h"

#include <KConfigGroup>
#include <KSharedConfig>
#include <QApplication>
#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QQuickStyle>
#include <QStandardPaths>

static const QString kService = QStringLiteral("org.macglass.Stack");

static QString commandFrom(int argc, char **argv, QString *view)
{
    QString cmd = QStringLiteral("Toggle");
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromLocal8Bit(argv[i]);
        if (a == QLatin1String("--show"))
            cmd = QStringLiteral("Show");
        else if (a == QLatin1String("--hide"))
            cmd = QStringLiteral("Hide");
        else if (a == QLatin1String("--open-folder"))
            cmd = QStringLiteral("OpenFolder");
        else if (a == QLatin1String("--daemon"))
            cmd = QString();
        else if (a == QLatin1String("--view") && i + 1 < argc)
            *view = QString::fromLocal8Bit(argv[++i]);
    }
    return cmd;
}

int main(int argc, char **argv)
{
    QString view;
    const QString cmd = commandFrom(argc, argv, &view);

    // A transient overlay has no state to save: opt out of session management
    // so logout never waits for us.
    qunsetenv("SESSION_MANAGER");

    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("macglass-stack"));
    app.setApplicationVersion(QStringLiteral(MACGLASS_VERSION));
    app.setOrganizationDomain(QStringLiteral("macglass.org"));
    app.setDesktopFileName(QStringLiteral("org.macglass.DownloadsStack"));
    app.setQuitOnLastWindowClosed(false);
    // KIO jobs hold QEventLoopLockers; when the last one finishes Qt would quit
    // a window-less app. We are a resident service, so disable that.
    app.setQuitLockEnabled(false);

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("macOS-style Downloads stack for KDE Plasma"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addOptions({
        {QStringLiteral("toggle"), QStringLiteral("Open or close the stack (default).")},
        {QStringLiteral("show"), QStringLiteral("Open the stack.")},
        {QStringLiteral("hide"), QStringLiteral("Close the stack.")},
        {QStringLiteral("open-folder"), QStringLiteral("Open the stack's folder in the file manager.")},
        {QStringLiteral("daemon"), QStringLiteral("Start in the background without opening.")},
        {QStringLiteral("view"), QStringLiteral("Display mode for this opening."), QStringLiteral("fan|grid|list|auto")},
    });
    parser.process(app);

    // Single instance: if the service already exists, forward the command and exit.
    auto bus = QDBusConnection::sessionBus();
    if (bus.interface() && bus.interface()->isServiceRegistered(kService)) {
        if (!cmd.isEmpty()) {
            auto msg = QDBusMessage::createMethodCall(kService, QStringLiteral("/Stack"), kService, cmd);
            if (cmd == QLatin1String("Toggle") || cmd == QLatin1String("Show"))
                msg << view;
            bus.call(msg, QDBus::Block, 2000);
        }
        return 0;
    }

    if (QQuickStyle::name().isEmpty())
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    // Folder: $MACGLASS_STACK_FOLDER (testing) > [General] Folder= in macglassstackrc > XDG Downloads.
    QString path = qEnvironmentVariable("MACGLASS_STACK_FOLDER");
    if (path.isEmpty())
        path = KConfigGroup(KSharedConfig::openConfig(QStringLiteral("macglassstackrc")), QStringLiteral("General"))
                   .readPathEntry("Folder", QString());
    if (path.isEmpty())
        path = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    const QUrl folder = QUrl::fromLocalFile(path);
    StackController controller(folder);
    if (!controller.init())
        return 1;

    if (!bus.registerService(kService)) {
        qWarning("macglass-stack: could not register %s (%s)", qPrintable(kService), qPrintable(bus.lastError().message()));
        return 0; // most likely lost a start-up race; the other instance handles it
    }
    bus.registerObject(QStringLiteral("/Stack"), &controller, QDBusConnection::ExportScriptableSlots);

    if (cmd == QLatin1String("Toggle") || cmd == QLatin1String("Show"))
        QMetaObject::invokeMethod(&controller, [&] { controller.Show(view); }, Qt::QueuedConnection);
    else if (cmd == QLatin1String("OpenFolder"))
        QMetaObject::invokeMethod(&controller, [&] { controller.OpenFolder(); }, Qt::QueuedConnection);

    return app.exec();
}
