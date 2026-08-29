#include "TimeProgress.h"
#include "TrayController.h"

#include <QApplication>
#include <QIcon>

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

    TimeProgress progress;
    TrayController tray(&progress);
    Q_UNUSED(tray);

    return app.exec();
}
