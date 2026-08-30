#pragma once

#include <QObject>
#include <QString>
#include <QThread>

class JournalLibrary;

class ExchangeCoordinator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString targetJournalId READ targetJournalId WRITE setTargetJournalId
               NOTIFY targetChanged)
    Q_PROPERTY(bool configured READ configured NOTIFY statusChanged)
    Q_PROPERTY(bool syncing READ syncing NOTIFY statusChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY statusChanged)
    Q_PROPERTY(QString venue READ venue NOTIFY targetChanged)
    Q_PROPERTY(QString accountLabel READ accountLabel NOTIFY targetChanged)

public:
    explicit ExchangeCoordinator(JournalLibrary *library, QObject *parent = nullptr);
    ~ExchangeCoordinator() override;

    QString targetJournalId() const { return m_targetId; }
    void setTargetJournalId(const QString &id);
    bool configured() const;
    bool syncing() const { return m_syncing; }
    QString statusText() const { return m_statusText; }
    QString lastError() const { return m_lastError; }
    QString venue() const;
    QString accountLabel() const;

    Q_INVOKABLE bool isConfigured(const QString &journalId) const;
    Q_INVOKABLE void saveBinance(const QString &journalId, const QString &apiKey, const QString &secret);
    Q_INVOKABLE void saveOKX(const QString &journalId, const QString &apiKey, const QString &secret,
                             const QString &passphrase);
    Q_INVOKABLE void saveHyperliquid(const QString &journalId, const QString &address);
    Q_INVOKABLE void disconnectJournal(const QString &journalId);
    Q_INVOKABLE void syncNow(const QString &journalId);

signals:
    void targetChanged();
    void statusChanged();

private slots:
    void onWorkerFinished(const QString &journalId, const QString &error,
                          const QString &positionsJson, int created);

private:
    void bindAndSync(const QString &journalId, const QString &venue, const QString &label,
                     const QString &blobJson);
    void refreshStatus();
    class ExchangeWorker *m_worker = nullptr;
    QThread m_thread;
    JournalLibrary *m_library = nullptr;
    QString m_targetId;
    bool m_syncing = false;
    QString m_statusText;
    QString m_lastError;
};
