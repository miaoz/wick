#pragma once

#include <QQuickView>
#include <QRect>

class TimeProgress;

/// Frameless floating paper slip. Wayland layer-shell can wait; this is still
/// a Tool window (no taskbar, stays on top). Position near the tray, or
/// top-right of the screen if the tray geometry is empty (common on Wayland).
class ProgressWindow : public QQuickView
{
    Q_OBJECT

public:
    explicit ProgressWindow(TimeProgress *progress, QWindow *parent = nullptr);

    void toggleNear(const QRect &trayGeometry);
    void hidePanel();
    bool panelVisible() const;

private:
    void placeNear(const QRect &trayGeometry);
};
