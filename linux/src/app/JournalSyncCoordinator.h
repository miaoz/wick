#pragma once

#include <QObject>
#include <QString>
#include <QTimer>

#include <chrono>
#include <filesystem>
#include <memory>

class AppSettings;
class JournalLibrary;
class SyncWorker;
class QThread;

/// Owns the journal sync engine on a worker thread. WICK_FAKE_SYNC=1 uses
/// FakeSyncBackend; otherwise DropboxSyncBackend (OAuth PKCE + HTTP).
class JournalSyncCoordinator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool fakeSyncAvailable READ fakeSyncAvailable CONSTANT)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString accountEmail READ accountEmail NOTIFY connectedChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)

public:
    JournalSyncCoordinator(JournalLibrary *library, AppSettings *settings, QObject *parent = nullptr);
    ~JournalSyncCoordinator() override;

    bool fakeSyncAvailable() const { return m_fakeAvailable; }
    bool connected() const { return m_connected; }
    QString accountEmail() const { return m_accountEmail; }
    QString statusText() const { return m_statusText; }

    Q_INVOKABLE void connectDropbox();
    Q_INVOKABLE void signOut();
    Q_INVOKABLE void syncNow();

    /// Persist-and-sync before quit. Never blocks longer than `timeout`.
    void syncOnceBeforeQuit(std::chrono::milliseconds timeout);

signals:
    void connectedChanged();
    void statusChanged();

private:
    void requestSync();
    void startPeriodicIfEnabled();
    std::string deviceID() const;
    std::filesystem::path stateDirectory() const;

    JournalLibrary *m_library = nullptr;
    AppSettings *m_settings = nullptr;
    bool m_fakeAvailable = false;
    bool m_authorizing = false;
    bool m_connected = false;
    QString m_accountEmail;
    QString m_statusText;
    QTimer m_debounce;
    QTimer m_periodic;
    QThread *m_thread = nullptr;
    SyncWorker *m_worker = nullptr;
};
