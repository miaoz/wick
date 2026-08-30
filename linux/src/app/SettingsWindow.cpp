#include "SettingsWindow.h"

#include "AppSettings.h"
#include "ExchangeCoordinator.h"
#include "JournalLibrary.h"
#include "JournalSyncCoordinator.h"

#include <QEvent>
#include <QQmlContext>
#include <QQmlError>
#include <QDebug>

SettingsWindow::SettingsWindow(AppSettings *settings, JournalLibrary *library,
                               JournalSyncCoordinator *sync, ExchangeCoordinator *exchange,
                               QWindow *parent)
    : QQuickView(parent)
    , m_settings(settings)
{
    setResizeMode(QQuickView::SizeRootObjectToView);
    setTitle(QStringLiteral("设置"));
    setObjectName(QStringLiteral("wick-settings"));
    setColor(QColor(0x24, 0x1C, 0x10));
    setMinimumWidth(640);
    setMinimumHeight(480);
    resize(780, 580);

    rootContext()->setContextProperty(QStringLiteral("appSettings"), m_settings);
    rootContext()->setContextProperty(QStringLiteral("journalLibrary"), library);
    rootContext()->setContextProperty(QStringLiteral("syncCoordinator"), sync);
    rootContext()->setContextProperty(QStringLiteral("exchangeCoordinator"), exchange);
    setSource(QUrl(QStringLiteral("qrc:/qml/settings/SettingsWindow.qml")));

    if (status() == QQuickView::Error) {
        const auto errs = errors();
        for (const QQmlError &err : errs)
            qWarning().noquote() << QStringLiteral("SettingsWindow.qml:") << err.toString();
    }

    if (m_settings) {
        auto applyColor = [this]() {
            const bool light = m_settings->resolvedScheme() == QLatin1String("light");
            setColor(light ? QColor(0xFB, 0xF4, 0xE6) : QColor(0x24, 0x1C, 0x10));
        };
        applyColor();
        connect(m_settings, &AppSettings::appearanceChanged, this, applyColor);
        connect(m_settings, &AppSettings::phaseChanged, this, applyColor);
    }
}

void SettingsWindow::openOrRaise()
{
    show();
    raise();
    requestActivate();
}

bool SettingsWindow::event(QEvent *event)
{
    if (event->type() == QEvent::Close) {
        hide();
        event->ignore();
        return true;
    }
    return QQuickView::event(event);
}
