#pragma once

#include <QQuickView>

class JournalLibrary;

/// Normal Qt window Hyprland can tile. Paper identity lives in the QML content,
/// not in window chrome (no frameless, no traffic lights).
class JournalWindow : public QQuickView
{
    Q_OBJECT

public:
    explicit JournalWindow(JournalLibrary *library, QWindow *parent = nullptr);

    void openOrRaise();

protected:
    bool event(QEvent *event) override;

private:
    JournalLibrary *m_library = nullptr;
};
