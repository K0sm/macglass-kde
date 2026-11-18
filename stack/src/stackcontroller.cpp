// SPDX-License-Identifier: GPL-3.0-or-later
#include "stackcontroller.h"
#include "foldermodel.h"
#include "thumbprovider.h"

#include <KApplicationTrader>
#include <KConfigGroup>
#include <KIO/ApplicationLauncherJob>
#include <KIO/CopyJob>
#include <KIO/FileUndoManager>
#include <KIO/JobUiDelegateFactory>
#include <KIO/OpenFileManagerWindowJob>
#include <KIO/OpenUrlJob>
#include <KSharedConfig>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QClipboard>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDrag>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QMimeData>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QScreen>
#include <QStandardPaths>
#include <cmath>

namespace {
const QString kScriptName = QStringLiteral("macglass-stack-cursor");

// Rounded-rect pixel region (KWin's blur protocol takes regions).
QRegion roundedRegion(const QRect &r, int radius)
{
    radius = std::min({radius, r.width() / 2, r.height() / 2});
    if (radius <= 0)
        return QRegion(r);
    QRegion region(r.adjusted(0, radius, 0, -radius));
    for (int i = 0; i < radius; ++i) {
        const double dy = radius - i - 0.5;
        const int inset = int(std::ceil(radius - std::sqrt(double(radius * radius) - dy * dy)));
        region += QRect(r.left() + inset, r.top() + i, r.width() - 2 * inset, 1);
        region += QRect(r.left() + inset, r.bottom() - i, r.width() - 2 * inset, 1);
    }
    return region;
}
}

StackController::StackController(const QUrl &folder, QObject *parent)
    : QObject(parent)
    , m_model(new FolderModel(this))
{
    readConfig();
    m_fanModel = new LimitModel(m_model, m_fanMax, this);
    m_model->setFolder(folder);
    connect(m_model, &FolderModel::countChanged, this, &StackController::effectiveViewChanged);

    // Free memory when unused for a while; the dock launcher restarts us on demand.
    m_idleExit.setSingleShot(true);
    connect(&m_idleExit, &QTimer::timeout, qApp, &QCoreApplication::quit);
    if (m_idleExitMinutes > 0) {
        m_idleExit.setInterval(m_idleExitMinutes * 60 * 1000);
        m_idleExit.start();
    }

    m_cursorTimeout.setSingleShot(true);
    m_cursorTimeout.setInterval(220);
    connect(&m_cursorTimeout, &QTimer::timeout, this, [this] {
        if (m_waitingForCursor) {
            m_waitingForCursor = false;
            present(QPointF(), false);
        }
    });

    // Wayland clients cannot read the global pointer position, so a tiny
    // one-shot KWin script reports it back over D-Bus when the stack opens.
    m_cursorScript = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)
        + QStringLiteral("/macglass-stack-cursor.js");
    QFile f(m_cursorScript);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write("callDBus('org.macglass.Stack', '/Stack', 'org.macglass.Stack', 'cursorReport',"
                " workspace.cursorPos.x, workspace.cursorPos.y);\n");
    }
}

StackController::~StackController()
{
    QFile::remove(m_cursorScript);
}

void StackController::readConfig()
{
    const KConfigGroup g(KSharedConfig::openConfig(QStringLiteral("macglassstackrc")), QStringLiteral("General"));
    m_view = g.readEntry("View", QStringLiteral("auto"));
    m_fanMax = std::clamp(g.readEntry("FanMaxItems", 10), 3, 15);
    m_gridColumns = std::clamp(g.readEntry("GridColumns", 5), 3, 8);
    m_dockReserve = std::max(0, g.readEntry("DockReserve", 96));
    m_fallbackOffset = g.readEntry("FallbackAnchorOffset", 0);
    m_idleExitMinutes = std::max(0, g.readEntry("IdleExitMinutes", 20));
    m_model->setSortMode(g.readEntry("Sort", QStringLiteral("date")));
}

bool StackController::init()
{
    m_engine = new QQmlApplicationEngine(this);
    m_engine->addImageProvider(QStringLiteral("thumb"), new ThumbProvider);
    m_engine->rootContext()->setContextProperty(QStringLiteral("stack"), this);

    QString qmlDir = qEnvironmentVariable("MACGLASS_STACK_QML_DIR");
    if (qmlDir.isEmpty())
        qmlDir = QStringLiteral(MACGLASS_QML_DIR);
    m_engine->load(QUrl::fromLocalFile(qmlDir + QStringLiteral("/Main.qml")));
    if (m_engine->rootObjects().isEmpty())
        return false;
    m_window = qobject_cast<QQuickWindow *>(m_engine->rootObjects().constFirst());
    if (!m_window)
        return false;

    m_window->setColor(Qt::transparent);
    auto *layer = LayerShellQt::Window::get(m_window);
    // Top layer (not overlay): system surfaces such as the logout screen,
    // OSDs and notifications must always stay above the stack.
    layer->setLayer(LayerShellQt::Window::LayerTop);
    layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                                                    | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
    layer->setExclusiveZone(-1);
    // Leave the dock strip uncovered so clicking the dock icon again toggles us.
    layer->setMargins(QMargins(0, 0, 0, m_dockReserve));
    // On-demand (never exclusive) keyboard focus: we must not hold the keyboard
    // hostage. Losing focus to anything else closes the stack, like macOS.
    layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    layer->setScope(QStringLiteral("macglass-stack"));
    connect(m_window, &QWindow::activeChanged, this, [this] {
        if (!m_window)
            return;
        if (m_window->isActive()) {
            m_wasActive = true;
        } else if (m_wasActive && m_shown && !m_closing && !m_dragging) {
            requestClose();
        }
    });
    // Never stay on screen while the session/app is going away.
    connect(qApp, &QCoreApplication::aboutToQuit, this, &StackController::finishClose);
    return true;
}

QString StackController::fileManagerName() const
{
    const auto svc = KApplicationTrader::preferredService(QStringLiteral("inode/directory"));
    return svc ? svc->name() : QStringLiteral("File Manager");
}

void StackController::setView(const QString &view)
{
    static const QStringList valid = {QStringLiteral("auto"), QStringLiteral("fan"), QStringLiteral("grid"), QStringLiteral("list")};
    if (!valid.contains(view))
        return;
    m_viewOverride.clear();
    if (view != m_view) {
        m_view = view;
        KConfigGroup g(KSharedConfig::openConfig(QStringLiteral("macglassstackrc")), QStringLiteral("General"));
        g.writeEntry("View", view);
        g.sync();
        Q_EMIT viewChanged();
    }
    Q_EMIT effectiveViewChanged();
}

QString StackController::effectiveView() const
{
    const QString v = m_viewOverride.isEmpty() ? m_view : m_viewOverride;
    if (v != QLatin1String("auto"))
        return v;
    // macOS "Automatic": fan for a handful of items, grid otherwise.
    return m_model->count() <= m_fanMax ? QStringLiteral("fan") : QStringLiteral("grid");
}

void StackController::setSort(const QString &mode)
{
    m_model->setSortMode(mode);
    KConfigGroup g(KSharedConfig::openConfig(QStringLiteral("macglassstackrc")), QStringLiteral("General"));
    g.writeEntry("Sort", m_model->sortMode());
    g.sync();
}

// ---------------------------------------------------------------- D-Bus

void StackController::Toggle(const QString &view)
{
    if (m_shown && !m_closing)
        requestClose();
    else
        Show(view);
}

void StackController::Show(const QString &view)
{
    if (m_shown && !m_closing)
        return;
    m_viewOverride = (view == QLatin1String("fan") || view == QLatin1String("grid") || view == QLatin1String("list")) ? view : QString();
    queryCursorThenPresent();
}

void StackController::Hide()
{
    if (m_shown)
        requestClose();
}

void StackController::queryCursorThenPresent()
{
    m_waitingForCursor = true;
    m_cursorTimeout.start();

    QDBusInterface scripting(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), QStringLiteral("org.kde.kwin.Scripting"));
    scripting.call(QStringLiteral("unloadScript"), kScriptName);
    QDBusReply<int> id = scripting.call(QStringLiteral("loadScript"), m_cursorScript, kScriptName);
    if (!id.isValid() || id.value() < 0) {
        m_cursorTimeout.stop();
        m_waitingForCursor = false;
        present(QPointF(), false);
        return;
    }
    QDBusInterface script(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting/Script%1").arg(id.value()),
                          QStringLiteral("org.kde.kwin.Script"));
    script.asyncCall(QStringLiteral("run"));
}

void StackController::cursorReport(double x, double y)
{
    QDBusInterface(QStringLiteral("org.kde.KWin"), QStringLiteral("/Scripting"), QStringLiteral("org.kde.kwin.Scripting"))
        .asyncCall(QStringLiteral("unloadScript"), kScriptName);
    if (!m_waitingForCursor)
        return;
    m_waitingForCursor = false;
    m_cursorTimeout.stop();
    present(QPointF(x, y), true);
}

QScreen *StackController::screenAt(const QPointF &p) const
{
    for (QScreen *s : QGuiApplication::screens()) {
        if (QRectF(s->geometry()).contains(p))
            return s;
    }
    return QGuiApplication::primaryScreen();
}

void StackController::present(const QPointF &globalCursor, bool cursorKnown)
{
    if (!m_window)
        return;
    QScreen *screen = cursorKnown ? screenAt(globalCursor) : QGuiApplication::primaryScreen();
    const QRect geo = screen->geometry();
    m_anchorX = cursorKnown ? globalCursor.x() - geo.x() : geo.width() / 2.0 + m_fallbackOffset;
    Q_EMIT anchorChanged();
    Q_EMIT effectiveViewChanged();

    m_closing = false;
    m_wasActive = false;
    m_idleExit.stop();
    if (m_window->isVisible())
        m_window->hide();
    m_window->setScreen(screen);
    LayerShellQt::Window::get(m_window)->setScreen(screen);
    m_window->setMask(QRegion());
    m_window->show();
    m_window->requestActivate();
    m_shown = true;
    Q_EMIT shownChanged();
    Q_EMIT openRequested();
}

void StackController::requestClose()
{
    if (!m_shown || m_closing)
        return;
    m_closing = true;
    Q_EMIT closeRequested();
}

void StackController::finishClose()
{
    clearBlur();
    if (m_window) {
        m_window->hide();
        m_window->releaseResources(); // drop scene-graph caches while hidden
    }
    m_closing = false;
    if (m_idleExitMinutes > 0)
        m_idleExit.start();
    m_viewOverride.clear();
    if (m_shown) {
        m_shown = false;
        Q_EMIT shownChanged();
    }
}

// ---------------------------------------------------------------- Actions

void StackController::open(const QUrl &url)
{
    auto *job = new KIO::OpenUrlJob(url);
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    job->setRunExecutables(false);
    job->start();
    requestClose();
}

void StackController::openWith(const QUrl &url)
{
    requestClose(); // the "Open With" dialog must not end up underneath our overlay
    QTimer::singleShot(200, this, [url] {
        auto *job = new KIO::ApplicationLauncherJob();
        job->setUrls({url});
        job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
        job->start();
    });
}

void StackController::reveal(const QUrl &url)
{
    KIO::highlightInFileManager({url});
    requestClose();
}

void StackController::openFolder()
{
    auto *job = new KIO::OpenUrlJob(m_model->folderUrl(), QStringLiteral("inode/directory"));
    job->setUiDelegate(KIO::createDefaultJobUiDelegate(KJobUiDelegate::AutoHandlingEnabled, nullptr));
    job->start();
    requestClose();
}

void StackController::trash(const QUrl &url)
{
    auto *job = KIO::trash({url});
    KIO::FileUndoManager::self()->recordJob(KIO::FileUndoManager::Trash, {url}, QUrl(QStringLiteral("trash:/")), job);
}

void StackController::copy(const QUrl &url)
{
    auto *mime = new QMimeData;
    mime->setUrls({url});
    mime->setText(url.isLocalFile() ? url.toLocalFile() : url.toString());
    QGuiApplication::clipboard()->setMimeData(mime);
}

void StackController::copyPath(const QUrl &url)
{
    QGuiApplication::clipboard()->setText(url.isLocalFile() ? url.toLocalFile() : url.toString());
}

void StackController::startDrag(const QUrl &url, const QString &iconName)
{
    if (!m_window)
        return;
    auto *mime = new QMimeData;
    mime->setUrls({url});

    auto *drag = new QDrag(m_window);
    drag->setMimeData(mime);
    const QPixmap pix = QIcon::fromTheme(iconName, QIcon::fromTheme(QStringLiteral("unknown"))).pixmap(64, 64);
    drag->setPixmap(pix);
    drag->setHotSpot(QPoint(pix.width() / 2, pix.height() / 2));

    // While dragging: hide our visuals, release the keyboard and let the
    // pointer reach the windows underneath (1x1 input region).
    m_dragging = true;
    Q_EMIT dragStarted();
    clearBlur();
    LayerShellQt::Window::get(m_window)->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    m_window->setMask(QRegion(0, 0, 1, 1));
    m_window->requestUpdate();

    // Safety net: a drop target that never answers must not leave us stuck.
    QTimer watchdog;
    watchdog.setSingleShot(true);
    connect(&watchdog, &QTimer::timeout, [] { QDrag::cancel(); });
    watchdog.start(60 * 1000);

    drag->exec(Qt::CopyAction | Qt::MoveAction | Qt::LinkAction, Qt::CopyAction);
    watchdog.stop();
    drag->deleteLater();
    m_dragging = false;
    if (m_window)
        LayerShellQt::Window::get(m_window)->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
    finishClose();
}

void StackController::setBlurRect(qreal x, qreal y, qreal w, qreal h, qreal radius)
{
    if (!m_window)
        return;
    const QRect r = QRectF(x, y, w, h).toAlignedRect();
    KWindowEffects::enableBlurBehind(m_window, true, roundedRegion(r, int(radius)));
}

void StackController::clearBlur()
{
    if (m_window)
        KWindowEffects::enableBlurBehind(m_window, false);
}
