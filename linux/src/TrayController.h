#pragma once

#include <QObject>
#include <QSystemTrayIcon>

class AppSettings;
class ExchangeCoordinator;
class JournalLibrary;
class JournalSyncCoordinator;
class JournalWindow;
class ProgressWindow;
class SettingsWindow;
class TimeProgress;
class QMenu;

/// Owns journal/settings windows and (on non-Omarchy hosts) the SNI candle.
/// When the Omarchy `wick.progress` bar widget is installed, the Qt tray icon
/// and paper slip stay hidden — the Quickshell KeyboardPanel is the UI.
class TrayController : public QObject
{
    Q_OBJECT

public:
    explicit TrayController(TimeProgress *progress,
                            JournalLibrary *library,
                            AppSettings *settings,
                            JournalSyncCoordinator *sync = nullptr,
                            ExchangeCoordinator *exchange = nullptr,
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
    JournalSyncCoordinator *m_sync = nullptr;
    ExchangeCoordinator *m_exchange = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_menu = nullptr;
    ProgressWindow *m_panel = nullptr;
    JournalWindow *m_journal = nullptr;
    SettingsWindow *m_settingsWindow = nullptr;
};
