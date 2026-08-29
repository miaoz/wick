#pragma once

#include <QObject>
#include <QSystemTrayIcon>

class AppSettings;
class JournalLibrary;
class JournalWindow;
class ProgressWindow;
class SettingsWindow;
class TimeProgress;
class QMenu;

/// StatusNotifierItem tray candle: left click toggles the paper slip,
/// right click shows 日记 / 设置 / 退出.
class TrayController : public QObject
{
    Q_OBJECT

public:
    explicit TrayController(TimeProgress *progress,
                            JournalLibrary *library,
                            AppSettings *settings,
                            QObject *parent = nullptr);
    ~TrayController() override;

    bool isAvailable() const;
    QSystemTrayIcon *trayIcon() const { return m_tray; }

public slots:
    void openJournal();
    void openSettings();
    void quitApp();

private slots:
    void onActivated(QSystemTrayIcon::ActivationReason reason);
    void refreshTrayIcon();

private:
    QIcon makeCandleIcon() const;

    TimeProgress *m_progress = nullptr;
    JournalLibrary *m_library = nullptr;
    AppSettings *m_settings = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_menu = nullptr;
    ProgressWindow *m_panel = nullptr;
    JournalWindow *m_journal = nullptr;
    SettingsWindow *m_settingsWindow = nullptr;
};
