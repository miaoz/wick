#pragma once

#include <QQuickView>

class AppSettings;
class ExchangeCoordinator;
class JournalLibrary;
class JournalSyncCoordinator;

class SettingsWindow : public QQuickView
{
    Q_OBJECT

public:
    SettingsWindow(AppSettings *settings, JournalLibrary *library,
                   JournalSyncCoordinator *sync = nullptr,
                   ExchangeCoordinator *exchange = nullptr, QWindow *parent = nullptr);

    void openOrRaise();

protected:
    bool event(QEvent *event) override;

private:
    AppSettings *m_settings = nullptr;
};
