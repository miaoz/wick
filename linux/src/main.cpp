#include "AppSettings.h"
#include "JournalLibrary.h"
#include "JournalSyncCoordinator.h"
#include "ReminderScheduler.h"
#include "TimeProgress.h"
#include "TrayController.h"

#include <QApplication>
#include <QIcon>
#include <QQuickStyle>
#include <QCoreApplication>

#include <chrono>

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("秉烛"));
    app.setApplicationDisplayName(QStringLiteral("秉烛"));
    app.setApplicationVersion(QStringLiteral("0.1.0"));
    app.setOrganizationName(QStringLiteral("wick"));
    app.setOrganizationDomain(QStringLiteral("wick"));
    app.setDesktopFileName(QStringLiteral("wick"));
    app.setQuitOnLastWindowClosed(false);
    app.setWindowIcon(QIcon(QStringLiteral(":/candle.svg")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    AppSettings *settings = AppSettings::instance();

    JournalLibrary library;
    library.bootstrap();

    JournalSyncCoordinator sync(&library, settings);

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &library, [&library, &sync]() {
        library.flushNow();
        sync.syncOnceBeforeQuit(std::chrono::milliseconds(8000));
    });

    TimeProgress progress;
    progress.setWeekStartsOnMonday(settings->weekStartsOnMonday());
    QObject::connect(settings, &AppSettings::weekStartsOnMondayChanged, &progress, [settings, &progress]() {
        progress.setWeekStartsOnMonday(settings->weekStartsOnMonday());
    });

    TrayController tray(&progress, &library, settings, &sync);

    ReminderScheduler reminder(settings, tray.trayIcon());
    QObject::connect(&reminder, &ReminderScheduler::openJournalRequested,
                     &tray, &TrayController::openJournal);

    if (settings->checkForUpdatesAutomatically())
        settings->checkForUpdates();

    if (app.arguments().contains(QStringLiteral("--journal")))
        tray.openJournal();
    if (app.arguments().contains(QStringLiteral("--settings")))
        tray.openSettings();

    return app.exec();
}
