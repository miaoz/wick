#include "WickIpc.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QLocalServer>
#include <QLocalSocket>
#include <QStandardPaths>

WickIpc *WickIpc::s_instance = nullptr;

namespace {

bool isCallbackUrl(const QString &s)
{
    return s.startsWith(QStringLiteral("db-hm5yscsy9a11g0q:"));
}

QString commandFromArgs(const QStringList &args)
{
    const int cb = args.indexOf(QStringLiteral("--dropbox-callback"));
    if (cb >= 0 && cb + 1 < args.size() && isCallbackUrl(args.at(cb + 1)))
        return args.at(cb + 1);
    for (int i = 1; i < args.size(); ++i) {
        if (isCallbackUrl(args.at(i)))
            return args.at(i);
    }
    if (args.contains(QStringLiteral("--journal")))
        return QStringLiteral("journal");
    if (args.contains(QStringLiteral("--settings")))
        return QStringLiteral("settings");
    if (args.contains(QStringLiteral("--quit")))
        return QStringLiteral("quit");
    return {};
}

} // namespace

WickIpc::WickIpc(QObject *parent)
    : QObject(parent)
{
    s_instance = this;
}

WickIpc::~WickIpc()
{
    if (m_server) {
        m_server->close();
        QLocalServer::removeServer(socketPath());
    }
    if (s_instance == this)
        s_instance = nullptr;
}

QString WickIpc::socketPath()
{
    QString runtime = qEnvironmentVariable(QByteArrayLiteral("XDG_RUNTIME_DIR"));
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    return runtime + QStringLiteral("/wick.sock");
}

int WickIpc::send(const QByteArray &payload)
{
    QLocalSocket sock;
    sock.connectToServer(socketPath());
    if (!sock.waitForConnected(500))
        return -1;
    sock.write(payload);
    sock.flush();
    sock.waitForBytesWritten(2000);
    sock.disconnectFromServer();
    sock.waitForDisconnected(2000);
    return 0;
}

int WickIpc::maybeForwardAndExit(const QStringList &args)
{
    const QString command = commandFromArgs(args);
    if (command.isEmpty())
        return -1;
    const int rc = send(command.toUtf8());
    if (rc == 0)
        return 0;
    if (command == QLatin1String("quit"))
        return 0;
    if (isCallbackUrl(command) || command.startsWith(QLatin1String("callback "))) {
        qWarning("秉烛: no running instance to receive Dropbox callback");
        return 1;
    }
    // --journal / --settings with no instance: this process should start.
    return -1;
}

void WickIpc::listen()
{
    const QString path = socketPath();
    QLocalServer::removeServer(path);
    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!m_server->listen(path)) {
        qWarning("秉烛: cannot listen on %s (%s)", qPrintable(path),
                 qPrintable(m_server->errorString()));
        return;
    }
    connect(m_server, &QLocalServer::newConnection, this, [this]() {
        QLocalSocket *sock = m_server->nextPendingConnection();
        if (!sock)
            return;
        struct Session {
            QByteArray buf;
            bool done = false;
        };
        auto *session = new Session;
        auto finish = [this, sock, session]() {
            if (session->done)
                return;
            session->done = true;
            session->buf.append(sock->readAll());
            handlePayload(session->buf);
            delete session;
            sock->deleteLater();
        };
        connect(sock, &QLocalSocket::readyRead, this, [sock, session]() {
            if (!session->done)
                session->buf.append(sock->readAll());
        });
        connect(sock, &QLocalSocket::disconnected, this, finish);
        if (sock->bytesAvailable() > 0)
            session->buf.append(sock->readAll());
        if (sock->state() == QLocalSocket::UnconnectedState)
            finish();
    });
    writeCurrentExecutable();
}

void WickIpc::writeCurrentExecutable()
{
    const QString root = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
        + QStringLiteral("/wick");
    QDir().mkpath(root);
    QFile f(root + QStringLiteral("/current-executable"));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return;
    f.write(QCoreApplication::applicationFilePath().toUtf8());
    f.write("\n");
}

void WickIpc::handlePayload(const QByteArray &raw)
{
    const QString text = QString::fromUtf8(raw).trimmed();
    if (text.isEmpty())
        return;
    if (text == QLatin1String("journal")) {
        emit openJournalRequested();
        return;
    }
    if (text == QLatin1String("settings")) {
        emit openSettingsRequested();
        return;
    }
    if (text == QLatin1String("quit")) {
        emit quitRequested();
        return;
    }
    if (text.startsWith(QLatin1String("callback "))) {
        emit dropboxCallback(QUrl(text.mid(9).trimmed()));
        return;
    }
    if (isCallbackUrl(text)) {
        emit dropboxCallback(QUrl(text));
        return;
    }
}
