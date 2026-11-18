// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "foldermodel.h"

#include <QAbstractItemModel>
#include <QObject>
#include <QPointer>
#include <QTimer>
#include <QUrl>

class QQmlApplicationEngine;
class QQuickWindow;
class QScreen;

class StackController : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.macglass.Stack")

    Q_PROPERTY(FolderModel *model READ model CONSTANT)
    Q_PROPERTY(QAbstractItemModel *fanModel READ fanModel CONSTANT)
    Q_PROPERTY(QString view READ view WRITE setView NOTIFY viewChanged)
    Q_PROPERTY(QString effectiveView READ effectiveView NOTIFY effectiveViewChanged)
    Q_PROPERTY(qreal anchorX READ anchorX NOTIFY anchorChanged)
    Q_PROPERTY(bool shown READ shown NOTIFY shownChanged)
    Q_PROPERTY(int fanMax READ fanMax CONSTANT)
    Q_PROPERTY(int gridColumns READ gridColumns CONSTANT)
    Q_PROPERTY(QString fileManagerName READ fileManagerName CONSTANT)

public:
    explicit StackController(const QUrl &folder, QObject *parent = nullptr);
    ~StackController() override;

    bool init();

    FolderModel *model() const { return m_model; }
    QAbstractItemModel *fanModel() const { return m_fanModel; }
    QString view() const { return m_view; }
    void setView(const QString &view);
    QString effectiveView() const;
    qreal anchorX() const { return m_anchorX; }
    bool shown() const { return m_shown; }
    int fanMax() const { return m_fanMax; }
    int gridColumns() const { return m_gridColumns; }
    QString fileManagerName() const;

    // ---- D-Bus API (org.macglass.Stack at /Stack) ----
public Q_SLOTS:
    Q_SCRIPTABLE void Toggle(const QString &view);
    Q_SCRIPTABLE void Show(const QString &view);
    Q_SCRIPTABLE void Hide();
    Q_SCRIPTABLE void OpenFolder() { openFolder(); }
    // Called back by a one-shot KWin script (KWin sends ints; accept doubles too).
    Q_SCRIPTABLE void cursorReport(double x, double y);
    Q_SCRIPTABLE void cursorReport(int x, int y) { cursorReport(double(x), double(y)); }

    // ---- QML API ----
public:
    Q_INVOKABLE void open(const QUrl &url);
    Q_INVOKABLE void openWith(const QUrl &url);
    Q_INVOKABLE void reveal(const QUrl &url);
    Q_INVOKABLE void openFolder();
    Q_INVOKABLE void trash(const QUrl &url);
    Q_INVOKABLE void copy(const QUrl &url);
    Q_INVOKABLE void copyPath(const QUrl &url);
    Q_INVOKABLE void startDrag(const QUrl &url, const QString &iconName);
    Q_INVOKABLE void setSort(const QString &mode);
    Q_INVOKABLE void setBlurRect(qreal x, qreal y, qreal w, qreal h, qreal radius);
    Q_INVOKABLE void clearBlur();
    Q_INVOKABLE void finishClose(); // QML calls this when the close animation ends

Q_SIGNALS:
    void viewChanged();
    void effectiveViewChanged();
    void anchorChanged();
    void shownChanged();
    void openRequested();  // QML: play opening animation
    void closeRequested(); // QML: play closing animation, then finishClose()
    void dragStarted();    // QML: hide visuals instantly

private:
    void queryCursorThenPresent();
    void present(const QPointF &globalCursor, bool cursorKnown);
    QScreen *screenAt(const QPointF &p) const;
    void requestClose();
    void readConfig();

    FolderModel *m_model;
    QAbstractItemModel *m_fanModel = nullptr;
    QQmlApplicationEngine *m_engine = nullptr;
    QPointer<QQuickWindow> m_window;
    QTimer m_cursorTimeout;
    QTimer m_idleExit;
    bool m_waitingForCursor = false;
    bool m_shown = false;
    bool m_closing = false;
    bool m_dragging = false;
    bool m_wasActive = false;
    qreal m_anchorX = 0;
    QString m_view = QStringLiteral("auto");
    QString m_viewOverride;
    int m_fanMax = 10;
    int m_gridColumns = 5;
    int m_dockReserve = 96;
    int m_fallbackOffset = 0;
    int m_idleExitMinutes = 20;
    QString m_cursorScript;
};
