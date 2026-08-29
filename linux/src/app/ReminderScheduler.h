#pragma once

#include <QObject>
#include <QTimer>

class AppSettings;
class QSystemTrayIcon;

/// Daily journal reminder via QSystemTrayIcon::showMessage (freedesktop via SNI).
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

private:
    AppSettings *m_settings = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QTimer m_timer;
};
