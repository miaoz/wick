#include "ProgressWindow.h"

#include "AppSettings.h"
#include "TimeProgress.h"

#include <QDebug>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlError>
#include <QScreen>

#include <algorithm>

ProgressWindow::ProgressWindow(TimeProgress *progress, QWindow *parent)
    : QQuickView(parent)
{
    setResizeMode(QQuickView::SizeViewToRootObject);
    setFlags(Qt::Tool | Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
    setColor(QColor(0x24, 0x1C, 0x10)); // 暗·子夜 paper
    setTitle(QStringLiteral("秉烛"));
    setObjectName(QStringLiteral("wick-pop"));

    rootContext()->setContextProperty(QStringLiteral("timeProgress"), progress);
    rootContext()->setContextProperty(QStringLiteral("appSettings"), AppSettings::instance());
    setSource(QUrl(QStringLiteral("qrc:/qml/ProgressPanel.qml")));

    if (status() == QQuickView::Error) {
        const auto errs = errors();
        for (const QQmlError &err : errs)
            qWarning().noquote() << QStringLiteral("ProgressPanel.qml:") << err.toString();
    }
}

void ProgressWindow::toggleNear(const QRect &trayGeometry)
{
    if (isVisible()) {
        hidePanel();
        return;
    }
    placeNear(trayGeometry);
    show();
    raise();
    requestActivate();
}

void ProgressWindow::hidePanel()
{
    hide();
}

bool ProgressWindow::panelVisible() const
{
    return isVisible();
}

void ProgressWindow::placeNear(const QRect &trayGeometry)
{
    QScreen *screen = nullptr;
    if (trayGeometry.isValid() && !trayGeometry.isEmpty())
        screen = QGuiApplication::screenAt(trayGeometry.center());
    if (!screen)
        screen = QGuiApplication::primaryScreen();
    if (!screen)
        return;

    const QRect avail = screen->availableGeometry();
    QSize sz = size();
    if (sz.width() < 8 || sz.height() < 8)
        sz = QSize(352, 220);

    int x = 0;
    int y = 0;
    if (trayGeometry.isValid() && !trayGeometry.isEmpty()) {
        x = trayGeometry.right() - sz.width();
        y = trayGeometry.bottom() + 8;
        if (y + sz.height() > avail.bottom())
            y = trayGeometry.top() - sz.height() - 8;
    } else {
        // Wayland often reports empty tray geometry — pin top-right.
        x = avail.right() - sz.width() - 12;
        y = avail.top() + 44;
    }

    x = std::clamp(x, avail.left(), avail.right() - sz.width());
    y = std::clamp(y, avail.top(), avail.bottom() - sz.height());
    setPosition(x, y);
}

bool ProgressWindow::event(QEvent *event)
{
    if (event->type() == QEvent::FocusOut) {
        hidePanel();
        return true;
    }
    return QQuickView::event(event);
}
