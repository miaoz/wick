#include "DropboxAuthSession.h"

#include "JournalSyncBackend.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QLocalServer>
#include <QLocalSocket>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

namespace {

bool isCallbackUrl(const QString& s) {
    return s.startsWith(QStringLiteral("db-hm5yscsy9a11g0q:"));
}

} // namespace

QString DropboxAuthSession::socketPath() {
    QString runtime = qEnvironmentVariable(QByteArrayLiteral("XDG_RUNTIME_DIR"));
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    return runtime + QStringLiteral("/wick-dropbox-auth.sock");
}

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
                                 "Exec=%1 --dropbox-callback %u\n"
                                 "Icon=wick\n"
                                 "Terminal=false\n"
                                 "Categories=Office;Utility;Finance;\n"
                                 "StartupNotify=false\n"
                                 "StartupWMClass=wick\n"
                                 "MimeType=x-scheme-handler/db-hm5yscsy9a11g0q;\n")
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

int DropboxAuthSession::forwardCallback(const QString& url) {
    QLocalSocket sock;
    sock.connectToServer(socketPath());
    if (!sock.waitForConnected(2000)) {
        qWarning("秉烛: no running instance to receive Dropbox callback (%s)",
                 qPrintable(sock.errorString()));
        return 1;
    }
    sock.write(url.toUtf8());
    sock.flush();
    sock.waitForBytesWritten(2000);
    sock.disconnectFromServer();
    sock.waitForDisconnected(2000);
    return 0;
}

int DropboxAuthSession::maybeForwardAndExit(const QStringList& args) {
    const int cb = args.indexOf(QStringLiteral("--dropbox-callback"));
    if (cb >= 0 && cb + 1 < args.size() && isCallbackUrl(args.at(cb + 1)))
        return forwardCallback(args.at(cb + 1));
    for (int i = 1; i < args.size(); ++i) {
        if (isCallbackUrl(args.at(i)))
            return forwardCallback(args.at(i));
    }
    return -1;
}

QUrl DropboxAuthSession::run(const QUrl& authorizeUrl, const QString& callbackScheme) {
    (void)callbackScheme;
    ensureMimeDefault();

    const QString path = socketPath();
    QLocalServer::removeServer(path);
    QLocalServer server;
    if (!server.listen(path)) {
        throw wick::SyncBackendError::transport(
            std::string("cannot listen for OAuth callback: ") + server.errorString().toStdString());
    }

    if (!QDesktopServices::openUrl(authorizeUrl)) {
        server.close();
        QLocalServer::removeServer(path);
        throw wick::SyncBackendError::transport("cannot open browser for Dropbox sign-in");
    }

    QEventLoop loop;
    QUrl result;
    QByteArray buf;
    QObject::connect(&server, &QLocalServer::newConnection, &loop, [&]() {
        QLocalSocket* sock = server.nextPendingConnection();
        if (!sock)
            return;
        QObject::connect(sock, &QLocalSocket::readyRead, &loop, [sock, &buf]() {
            buf.append(sock->readAll());
        });
        QObject::connect(sock, &QLocalSocket::disconnected, &loop, [sock, &buf, &result, &loop]() {
            buf.append(sock->readAll());
            const QString text = QString::fromUtf8(buf.trimmed());
            if (!text.isEmpty())
                result = QUrl(text);
            sock->deleteLater();
            loop.quit();
        });
        if (sock->bytesAvailable() > 0)
            buf.append(sock->readAll());
    });

    QTimer timeout;
    timeout.setSingleShot(true);
    QObject::connect(&timeout, &QTimer::timeout, &loop, [&loop]() { loop.quit(); });
    timeout.start(5 * 60 * 1000);
    loop.exec();

    server.close();
    QLocalServer::removeServer(path);

    if (!result.isValid() || result.isEmpty())
        throw wick::SyncBackendError::authorizationCancelled();
    return result;
}
