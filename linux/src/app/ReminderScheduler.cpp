#include "ReminderScheduler.h"

#include "AppSettings.h"

#include <QDateTime>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QSystemTrayIcon>

#include <algorithm>

ReminderScheduler::ReminderScheduler(AppSettings *settings,
                                     QSystemTrayIcon *tray,
                                     QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_tray(tray)
{
    m_timer.setSingleShot(true);
    m_timer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_timer, &QTimer::timeout, this, &ReminderScheduler::fire);
    if (m_settings) {
        connect(m_settings, &AppSettings::reminderChanged,
                this, &ReminderScheduler::reschedule);
        connect(m_settings, &AppSettings::languageChanged,
                this, &ReminderScheduler::reschedule);
    }
    if (m_tray) {
        connect(m_tray, &QSystemTrayIcon::messageClicked,
                this, &ReminderScheduler::openJournalRequested);
    }

    QDBusConnection::sessionBus().connect(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("ActionInvoked"),
        this,
        SLOT(onNotificationAction(uint,QString))
    );

    reschedule();
}

void ReminderScheduler::reschedule()
{
    m_timer.stop();
    if (!m_settings || !m_settings->reminderEnabled())
        return;

    const QDateTime now = QDateTime::currentDateTime();
    QDateTime next = now;
    next.setTime(QTime(m_settings->reminderHour(), m_settings->reminderMinute(), 0));
    if (next <= now)
        next = next.addDays(1);

    const qint64 ms = now.msecsTo(next);
    m_timer.start(static_cast<int>(std::min<qint64>(ms, 24LL * 60 * 60 * 1000)));
}

void ReminderScheduler::fire()
{
    if (!m_settings || !m_settings->reminderEnabled())
        return;

    const QString title = m_settings->t(QStringLiteral("该写日记了"),
                                        QStringLiteral("Time to journal"));
    const QString body = m_settings->t(
        QStringLiteral("记下今天想留住的内容。"),
        QStringLiteral("Write today’s entry."));

    bool dbusSent = false;
    QDBusInterface iface(QStringLiteral("org.freedesktop.Notifications"),
                         QStringLiteral("/org/freedesktop/Notifications"),
                         QStringLiteral("org.freedesktop.Notifications"),
                         QDBusConnection::sessionBus());
    if (iface.isValid()) {
        QVariantMap hints;
        hints.insert(QStringLiteral("urgency"), 1);
        QStringList actions;
        actions << QStringLiteral("default") << QStringLiteral("")
                << QStringLiteral("open") << m_settings->t(QStringLiteral("打开日记"), QStringLiteral("Open Journal"));
        
        QVariantList args;
        args << QStringLiteral("Wick")            // app_name
             << static_cast<quint32>(0)           // replaces_id
             << QStringLiteral("wick")            // app_icon
             << title                             // summary
             << body                              // body
             << actions                           // actions
             << hints                             // hints
             << static_cast<qint32>(8000);        // timeout (ms)

        QDBusReply<uint> reply = iface.callWithArgumentList(QDBus::AutoDetect, QStringLiteral("Notify"), args);
        if (reply.isValid())
            dbusSent = true;
    }

    if (!dbusSent && m_tray)
        m_tray->showMessage(title, body, QSystemTrayIcon::Information, 8000);

    reschedule();
}

void ReminderScheduler::onNotificationAction(uint, const QString &action)
{
    if (action == QLatin1String("default") || action == QLatin1String("open"))
        emit openJournalRequested();
}
