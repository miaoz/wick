#pragma once

#include <QObject>
#include <QTimer>

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

private:
    AppSettings *m_settings = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QTimer m_timer;
};
