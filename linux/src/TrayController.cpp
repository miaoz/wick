#include "TrayController.h"

#include "JournalLibrary.h"
#include "JournalWindow.h"
#include "ProgressWindow.h"
#include "TimeProgress.h"

#include <QApplication>
#include <QIcon>
#include <QMenu>
#include <QPainter>
#include <QPalette>
#include <QPixmap>
#include <QSvgRenderer>

TrayController::TrayController(TimeProgress *progress,
                               JournalLibrary *library,
                               QObject *parent)
    : QObject(parent)
    , m_progress(progress)
    , m_library(library)
{
    m_panel = new ProgressWindow(progress);

    m_menu = new QMenu();
    m_menu->addAction(QStringLiteral("日记"), this, &TrayController::openJournal);
    m_menu->addAction(QStringLiteral("设置"), this, &TrayController::openSettings);
    m_menu->addSeparator();
    m_menu->addAction(QStringLiteral("退出"), this, &TrayController::quitApp);

    m_tray = new QSystemTrayIcon(this);
    m_tray->setIcon(makeCandleIcon());
    m_tray->setToolTip(QStringLiteral("秉烛"));
    m_tray->setContextMenu(m_menu);
    m_tray->setVisible(true);

    connect(m_tray, &QSystemTrayIcon::activated,
            this, &TrayController::onActivated);

    connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() {
        if (m_library)
            m_library->flushNow();
        if (m_journal)
            m_journal->hide();
        if (m_panel) {
            m_panel->hidePanel();
        }
        if (m_tray)
            m_tray->hide();
    });

    if (!QSystemTrayIcon::isSystemTrayAvailable()) {
        qWarning("秉烛: no StatusNotifierItem host. Run inside an Omarchy "
                 "(Hyprland + Quickshell) session so the tray candle can appear.");
    }
}

TrayController::~TrayController()
{
    if (m_tray) {
        m_tray->setContextMenu(nullptr);
        m_tray->hide();
    }
    delete m_journal;
    m_journal = nullptr;
    delete m_panel;
    m_panel = nullptr;
    delete m_menu;
    m_menu = nullptr;
}

bool TrayController::isAvailable() const
{
    return QSystemTrayIcon::isSystemTrayAvailable();
}

void TrayController::onActivated(QSystemTrayIcon::ActivationReason reason)
{
    switch (reason) {
    case QSystemTrayIcon::Trigger:
    case QSystemTrayIcon::DoubleClick:
    case QSystemTrayIcon::MiddleClick:
        if (m_panel)
            m_panel->toggleNear(m_tray ? m_tray->geometry() : QRect());
        break;
    default:
        break;
    }
}

void TrayController::openJournal()
{
    if (!m_journal)
        m_journal = new JournalWindow(m_library);
    m_journal->openOrRaise();
}

void TrayController::openSettings()
{
    qInfo("秉烛: 设置 (stage 0 stub)");
}

void TrayController::quitApp()
{
    if (m_library)
        m_library->flushNow();
    if (m_journal)
        m_journal->hide();
    if (m_panel)
        m_panel->hidePanel();
    if (m_tray)
        m_tray->hide();
    QApplication::quit();
}

QIcon TrayController::makeCandleIcon() const
{
    // Template silhouette: black SVG, painted with the palette window-text
    // so a dark bar (Omarchy) gets a light candle; setIsMask hints SNI hosts
    // that may tint symbolic pixmaps themselves.
    QSvgRenderer renderer(QStringLiteral(":/candle.svg"));
    const qreal dpr = qApp ? qApp->devicePixelRatio() : 1.0;
    const int logical = 22;
    const int px = qMax(18, static_cast<int>(qRound(logical * dpr)));

    QPixmap stencil(px, px);
    stencil.fill(Qt::transparent);
    {
        QPainter p(&stencil);
        p.setRenderHint(QPainter::Antialiasing, true);
        renderer.render(&p);
    }

    QColor tint = QColor(0xF0, 0xE3, 0xC6); // dark-paper ink-1 fallback
    if (qApp) {
        const QColor windowText = qApp->palette().color(QPalette::WindowText);
        if (windowText.isValid())
            tint = windowText;
        const QColor window = qApp->palette().color(QPalette::Window);
        // If the app palette is light-on-light or dark-on-dark, force contrast.
        if (window.lightness() < 128 && tint.lightness() < 128)
            tint = QColor(0xF0, 0xE3, 0xC6);
        else if (window.lightness() >= 128 && tint.lightness() >= 128)
            tint = QColor(0x2B, 0x20, 0x14);
    }

    QPixmap colored(px, px);
    colored.fill(Qt::transparent);
    {
        QPainter p(&colored);
        p.fillRect(colored.rect(), tint);
        p.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        p.drawPixmap(0, 0, stencil);
    }
    colored.setDevicePixelRatio(dpr);

    QIcon icon;
    icon.addPixmap(colored);
    icon.setIsMask(true);
    return icon;
}
