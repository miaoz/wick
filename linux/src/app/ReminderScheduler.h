#pragma once

#include <QObject>
#include <QTimer>
#include <unordered_set>

class AppSettings;
class QSystemTrayIcon;

/// Daily journal reminder via org.freedesktop.Notifications D-Bus and QSystemTrayIcon.
class ReminderScheduler : public QObject
{
    Q_OBJECT

public:
    ReminderScheduler(AppSettings *settings, QSystemTrayIcon *tray, QObject *parent = nullptr);

signals:
    void openJournalRequested();

private slots:
    void reschedule();
    void fire();
    void onNotificationAction(uint id, const QString &action);
    void onNotificationClosed(uint id, uint reason);

private:
    AppSettings *m_settings = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QTimer m_timer;
    std::unordered_set<uint> m_sentNotificationIds;
};
