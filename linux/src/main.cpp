#include "AppSettings.h"
#include "DropboxAuthSession.h"
#include "ExchangeCoordinator.h"
#include "JournalLibrary.h"
#include "JournalSyncCoordinator.h"
#include "ReminderScheduler.h"
#include "TimeProgress.h"
#include "TrayController.h"
#include "WickIpc.h"

#include <QApplication>
#include <QIcon>
#include <QQuickStyle>
#include <QCoreApplication>

#include <chrono>

#ifndef WICK_VERSION
#define WICK_VERSION "0.1.0"
#endif

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("秉烛"));
    app.setApplicationDisplayName(QStringLiteral("秉烛"));
    app.setApplicationVersion(QStringLiteral(WICK_VERSION));
    app.setOrganizationName(QStringLiteral("wick"));
    app.setOrganizationDomain(QStringLiteral("wick"));
    app.setDesktopFileName(QStringLiteral("wick"));
    app.setQuitOnLastWindowClosed(false);
    app.setWindowIcon(QIcon(QStringLiteral(":/candle.svg")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    if (const int cb = WickIpc::maybeForwardAndExit(app.arguments()); cb >= 0)
        return cb;

    AppSettings *settings = AppSettings::instance();

    JournalLibrary library;
    library.bootstrap();

    JournalSyncCoordinator sync(&library, settings);
    ExchangeCoordinator exchange(&library);

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &library, [&library, &sync]() {
        library.flushNow();
        sync.syncOnceBeforeQuit(std::chrono::milliseconds(8000));
    });

    TimeProgress progress;
    progress.setWeekStartsOnMonday(settings->weekStartsOnMonday());
    QObject::connect(settings, &AppSettings::weekStartsOnMondayChanged, &progress, [settings, &progress]() {
        progress.setWeekStartsOnMonday(settings->weekStartsOnMonday());
    });

    TrayController tray(&progress, &library, settings, &sync, &exchange);

    WickIpc ipc;
    ipc.listen();
    QObject::connect(&ipc, &WickIpc::openJournalRequested, &tray, &TrayController::openJournal);
    QObject::connect(&ipc, &WickIpc::openSettingsRequested, &tray, &TrayController::openSettings);
    QObject::connect(&ipc, &WickIpc::quitRequested, &tray, &TrayController::quitApp);

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
