#pragma once

#include <QObject>
#include <QSystemTrayIcon>

class ProgressWindow;
class TimeProgress;
class QMenu;

/// StatusNotifierItem tray candle: left click toggles the paper slip,
/// right click shows 日记 / 设置 / 退出.
class TrayController : public QObject
{
    Q_OBJECT

public:
    explicit TrayController(TimeProgress *progress, QObject *parent = nullptr);
    ~TrayController() override;

    bool isAvailable() const;

public slots:
    void openJournal();
    void openSettings();
    void quitApp();

private slots:
    void onActivated(QSystemTrayIcon::ActivationReason reason);

private:
    QIcon makeCandleIcon() const;

    TimeProgress *m_progress = nullptr;
    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_menu = nullptr;
    ProgressWindow *m_panel = nullptr;
};
