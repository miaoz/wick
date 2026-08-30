#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>

class QLocalServer;

/// Single-instance commands for the running Wick process.
///
/// The primary instance listens on `$XDG_RUNTIME_DIR/wick.sock`. A second
/// process (`wick --journal`, `wick --settings`, or a Dropbox callback URL)
/// forwards the command and exits.
class WickIpc : public QObject
{
    Q_OBJECT

public:
    explicit WickIpc(QObject *parent = nullptr);
    ~WickIpc() override;

    static WickIpc *instance() { return s_instance; }
    static QString socketPath();

    /// If `args` is a command for an already-running instance, forward it and
    /// return the process exit code. Return -1 when this process should start.
    static int maybeForwardAndExit(const QStringList &args);

    void listen();
    void writeCurrentExecutable();

signals:
    void openJournalRequested();
    void openSettingsRequested();
    void dropboxCallback(const QUrl &url);

private:
    static int send(const QByteArray &payload);
    void handlePayload(const QByteArray &raw);

    static WickIpc *s_instance;
    QLocalServer *m_server = nullptr;
};
