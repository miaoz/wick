#pragma once

#include "JournalSyncEngine.h"

#include <QObject>
#include <QString>
#include <QTimer>

#include <chrono>
#include <filesystem>
#include <memory>
#include <optional>

class AppSettings;
class JournalLibrary;

/// Owns the journal sync engine. WICK_FAKE_SYNC=1 uses FakeSyncBackend;
/// otherwise DropboxSyncBackend (OAuth PKCE + HTTP).
class JournalSyncCoordinator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool fakeSyncAvailable READ fakeSyncAvailable CONSTANT)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString accountEmail READ accountEmail NOTIFY connectedChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)

public:
    JournalSyncCoordinator(JournalLibrary *library, AppSettings *settings, QObject *parent = nullptr);

    bool fakeSyncAvailable() const { return m_fakeAvailable; }
    bool connected() const;
    QString accountEmail() const;
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
    void ensureEngine();
    void refreshStatus();
    void startPeriodicIfEnabled();
    std::string deviceID() const;
    std::filesystem::path stateDirectory() const;

    JournalLibrary *m_library = nullptr;
    AppSettings *m_settings = nullptr;
    bool m_fakeAvailable = false;
    bool m_authorizing = false;
    QString m_statusText;
    QTimer m_debounce;
    QTimer m_periodic;
    std::unique_ptr<wick::JournalSyncBackend> m_backend;
    std::unique_ptr<wick::JournalSyncEngine> m_engine;
};
