#include "DropboxAuthSession.h"

#include "JournalSyncBackend.h"
#include "WickIpc.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

void DropboxAuthSession::ensureMimeDefault() {
    const QString apps = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
    if (apps.isEmpty())
        return;
    QDir().mkpath(apps);
    const QString desktopPath = apps + QStringLiteral("/wick.desktop");
    const QString exec = QCoreApplication::applicationFilePath();
    const QString contents = QStringLiteral(
                                 "[Desktop Entry]\n"
                                 "Type=Application\n"
                                 "Name=秉烛\n"
                                 "Name[en]=Wick\n"
                                 "Comment=秉烛而记,落子无悔\n"
                                 "Exec=%1 %u\n"
                                 "Icon=wick\n"
                                 "Terminal=false\n"
                                 "Categories=Office;Utility;Finance;\n"
                                 "StartupNotify=false\n"
                                 "StartupWMClass=wick\n"
                                 "MimeType=x-scheme-handler/db-hm5yscsy9a11g0q;\n"
                                 "Actions=journal;settings;\n"
                                 "\n"
                                 "[Desktop Action journal]\n"
                                 "Name=日记\n"
                                 "Name[en]=Journal\n"
                                 "Exec=%1 --journal\n"
                                 "\n"
                                 "[Desktop Action settings]\n"
                                 "Name=设置\n"
                                 "Name[en]=Settings\n"
                                 "Exec=%1 --settings\n")
                                 .arg(exec);
    QFile f(desktopPath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        f.write(contents.toUtf8());
        f.close();
    }

    QProcess mime;
    mime.start(QStringLiteral("xdg-mime"),
               {QStringLiteral("default"), QStringLiteral("wick.desktop"),
                QStringLiteral("x-scheme-handler/db-hm5yscsy9a11g0q")});
    mime.waitForFinished(3000);

    QProcess update;
    update.start(QStringLiteral("update-desktop-database"), {apps});
    update.waitForFinished(3000);
}

QUrl DropboxAuthSession::run(const QUrl& authorizeUrl, const QString& callbackScheme) {
    (void)callbackScheme;
    ensureMimeDefault();

    auto *ipc = WickIpc::instance();
    if (!ipc) {
        throw wick::SyncBackendError::transport("no running Wick instance for OAuth callback");
    }

    if (!QDesktopServices::openUrl(authorizeUrl)) {
        throw wick::SyncBackendError::transport("cannot open browser for Dropbox sign-in");
    }

    QEventLoop loop;
    QUrl result;
    QObject::connect(ipc, &WickIpc::dropboxCallback, &loop, [&](const QUrl &url) {
        result = url;
        loop.quit();
    });

    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&timeout, &QTimer::timeout, &loop, [&loop]() { loop.quit(); });
    timeout.start(5 * 60 * 1000);
    loop.exec();

    if (!result.isValid() || result.isEmpty())
        throw wick::SyncBackendError::authorizationCancelled();
    return result;
}
