#pragma once

#include <QObject>
#include <QString>

#include <filesystem>
#include <memory>
#include <string>

class JournalLibrary;
class LocalSourceProxy;

namespace wick {
class JournalSyncBackend;
class JournalSyncEngine;
}

/// Runs JournalSyncEngine on a worker thread so journal switching never waits
/// on Dropbox HTTP. JournalLibrary calls are marshaled back to the GUI thread.
class SyncWorker : public QObject
{
    Q_OBJECT

public:
    SyncWorker(JournalLibrary *library,
               bool fake,
               std::string deviceId,
               std::filesystem::path stateDir,
               QObject *parent = nullptr);
    ~SyncWorker() override;

public slots:
    void startEngine();
    void syncActive();
    void pullAll();
    void queueJournalDeletion(const QString &id);
    void signOut();

signals:
    void statusTextChanged(const QString &text);
    void authorizedChanged(bool connected, const QString &email);
    void syncingChanged(bool syncing);

private:
    void emitStatus();
    void pullAllInternal();
    int autoImport();

    JournalLibrary *m_library = nullptr;
    bool m_fake = false;
    bool m_isSyncing = false;
    std::string m_deviceId;
    std::filesystem::path m_stateDir;
    std::unique_ptr<LocalSourceProxy> m_proxy;
    std::unique_ptr<wick::JournalSyncBackend> m_backend;
    std::unique_ptr<wick::JournalSyncEngine> m_engine;
};
