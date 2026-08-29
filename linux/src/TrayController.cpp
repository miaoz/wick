#include "TrayController.h"

#include "AppSettings.h"
#include "JournalLibrary.h"
#include "JournalWindow.h"
#include "ProgressWindow.h"
#include "SettingsWindow.h"
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
                               AppSettings *settings,
                               QObject *parent)
    : QObject(parent)
    , m_progress(progress)
    , m_library(library)
    , m_settings(settings)
{
    m_panel = new ProgressWindow(progress);

    m_menu = new QMenu();
    m_menu->addAction(QStringLiteral("日记"), this, &TrayController::openJournal);
    m_menu->addAction(QStringLiteral("设置"), this, &TrayController::openSettings);
    m_menu->addSeparator();
    m_menu->addAction(QStringLiteral("退出"), this, &TrayController::quitApp);

    m_tray = new QSystemTrayIcon(this);
    m_tray->setIcon(makeCandleIcon());
    m_tray->setContextMenu(m_menu);
    m_tray->setVisible(true);
    refreshTrayIcon();

    connect(m_tray, &QSystemTrayIcon::activated,
            this, &TrayController::onActivated);

    if (m_progress) {
        connect(m_progress, &TimeProgress::updated,
                this, &TrayController::refreshTrayIcon);
    }
    if (m_settings) {
        connect(m_settings, &AppSettings::showMenuBarPercentageChanged,
                this, &TrayController::refreshTrayIcon);
    }

    connect(qApp, &QCoreApplication::aboutToQuit, this, [this]() {
        if (m_library)
            m_library->flushNow();
        if (m_journal)
            m_journal->hide();
        if (m_settingsWindow)
            m_settingsWindow->hide();
        if (m_panel)
            m_panel->hidePanel();
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
    delete m_settingsWindow;
    m_settingsWindow = nullptr;
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
    if (!m_settingsWindow)
        m_settingsWindow = new SettingsWindow(m_settings, m_library);
    m_settingsWindow->openOrRaise();
}

void TrayController::quitApp()
{
    if (m_library)
        m_library->flushNow();
    if (m_journal)
        m_journal->hide();
    if (m_settingsWindow)
        m_settingsWindow->hide();
    if (m_panel)
        m_panel->hidePanel();
    if (m_tray)
        m_tray->hide();
    QApplication::quit();
}

void TrayController::refreshTrayIcon()
{
    if (!m_tray)
        return;
    m_tray->setIcon(makeCandleIcon());
    QString tip = QStringLiteral("秉烛");
    if (m_progress) {
        tip += QStringLiteral(" · ") + m_progress->dayPercentText();
        if (m_settings && m_settings->isChinese())
            tip += QStringLiteral(" 剩余");
    }
    m_tray->setToolTip(tip);
}

QIcon TrayController::makeCandleIcon() const
{
    QSvgRenderer renderer(QStringLiteral(":/candle.svg"));
    const qreal dpr = qApp ? qApp->devicePixelRatio() : 1.0;
    const int logical = 22;
    const int px = qMax(18, static_cast<int>(qRound(logical * dpr)));

    const bool showPct = m_settings && m_settings->showMenuBarPercentage() && m_progress;
    const int textW = showPct ? static_cast<int>(px * 1.7) : 0;
    const int canvasW = px + textW;

    QPixmap stencil(px, px);
    stencil.fill(Qt::transparent);
    {
        QPainter p(&stencil);
        p.setRenderHint(QPainter::Antialiasing, true);
        renderer.render(&p);
    }

    QColor tint = QColor(0xF0, 0xE3, 0xC6);
    if (qApp) {
        const QColor windowText = qApp->palette().color(QPalette::WindowText);
        if (windowText.isValid())
            tint = windowText;
        const QColor window = qApp->palette().color(QPalette::Window);
        if (window.lightness() < 128 && tint.lightness() < 128)
            tint = QColor(0xF0, 0xE3, 0xC6);
        else if (window.lightness() >= 128 && tint.lightness() >= 128)
            tint = QColor(0x2B, 0x20, 0x14);
    }

    QPixmap colored(canvasW, px);
    colored.fill(Qt::transparent);
    {
        QPainter p(&colored);
        p.fillRect(QRect(0, 0, px, px), tint);
        p.setCompositionMode(QPainter::CompositionMode_DestinationIn);
        p.drawPixmap(0, 0, stencil);
        if (showPct) {
            p.setCompositionMode(QPainter::CompositionMode_SourceOver);
            p.setPen(tint);
            QFont f = p.font();
            f.setPixelSize(qMax(8, px * 9 / 22));
            f.setBold(true);
            p.setFont(f);
            const QString n = m_progress->dayPercentNumber();
            p.drawText(QRect(px - 2, 0, textW + 2, px),
                       Qt::AlignVCenter | Qt::AlignLeft,
                       n + QLatin1Char('%'));
        }
    }
    colored.setDevicePixelRatio(dpr);

    QIcon icon;
    icon.addPixmap(colored);
    icon.setIsMask(!showPct);
    return icon;
}
