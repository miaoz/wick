#include "JournalLibrary.h"
#include "TimeProgress.h"
#include "TrayController.h"

#include <QApplication>
#include <QIcon>
#include <QQuickStyle>

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

    JournalLibrary library;
    library.bootstrap();

    QObject::connect(&app, &QCoreApplication::aboutToQuit, &library, &JournalLibrary::flushNow);

    TimeProgress progress;
    TrayController tray(&progress, &library);

    if (app.arguments().contains(QStringLiteral("--journal")))
        tray.openJournal();

    return app.exec();
}
