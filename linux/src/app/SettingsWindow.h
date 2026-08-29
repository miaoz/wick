#pragma once

#include <QQuickView>

class AppSettings;
class JournalLibrary;

class SettingsWindow : public QQuickView
{
    Q_OBJECT

public:
    SettingsWindow(AppSettings *settings, JournalLibrary *library, QWindow *parent = nullptr);

    void openOrRaise();

protected:
    bool event(QEvent *event) override;

private:
    AppSettings *m_settings = nullptr;
};
