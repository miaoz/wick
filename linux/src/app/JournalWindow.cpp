#include "JournalWindow.h"
#include "JournalLibrary.h"

#include <QEvent>
#include <QQmlContext>
#include <QQmlError>
#include <QDebug>

JournalWindow::JournalWindow(JournalLibrary *library, QWindow *parent)
    : QQuickView(parent)
    , m_library(library)
{
    setResizeMode(QQuickView::SizeRootObjectToView);
    setTitle(QStringLiteral("秉烛日记"));
    setObjectName(QStringLiteral("wick-journal"));
    setColor(QColor(0x24, 0x1C, 0x10)); // 暗·子夜 paper
    setMinimumWidth(720);
    setMinimumHeight(480);
    resize(1280, 800);

    rootContext()->setContextProperty(QStringLiteral("journalLibrary"), m_library);
    setSource(QUrl(QStringLiteral("qrc:/qml/journal/JournalWindow.qml")));

    if (status() == QQuickView::Error) {
        const auto errs = errors();
        for (const QQmlError &err : errs)
            qWarning().noquote() << QStringLiteral("JournalWindow.qml:") << err.toString();
    }
}

void JournalWindow::openOrRaise()
{
    show();
    raise();
    requestActivate();
}

bool JournalWindow::event(QEvent *event)
{
    if (event->type() == QEvent::Close) {
        if (m_library)
            m_library->flushNow();
        hide();
        event->ignore();
        return true;
    }
    return QQuickView::event(event);
}
