#include "TimeProgress.h"

#include <QCoreApplication>
#include <algorithm>
#include <QLocale>

TimeProgress::TimeProgress(QObject *parent)
    : QObject(parent)
{
    m_timer.setSingleShot(true);
    m_timer.setTimerType(Qt::VeryCoarseTimer);
    connect(&m_timer, &QTimer::timeout, this, &TimeProgress::tick);
    recalculate(QDateTime::currentDateTime());
    armMinuteTimer();
}

void TimeProgress::setWeekStartsOnMonday(bool monday)
{
    if (m_weekStartsOnMonday == monday)
        return;
    m_weekStartsOnMonday = monday;
    recalculate(QDateTime::currentDateTime());
}

QString TimeProgress::appVersion() const
{
    const QString v = QCoreApplication::applicationVersion();
    return v.isEmpty() ? QStringLiteral("0.1.0") : v;
}

double TimeProgress::remainingFraction(const QDateTime &start,
                                       const QDateTime &end,
                                       const QDateTime &at)
{
    const qint64 durationMs = start.msecsTo(end);
    if (durationMs <= 0)
        return 0.0;
    const qint64 remainingMs = at.msecsTo(end);
    const double fraction = static_cast<double>(remainingMs) / static_cast<double>(durationMs);
    return std::clamp(fraction, 0.0, 1.0);
}

QString TimeProgress::percentText(double remaining)
{
    return percentNumber(remaining) + QLatin1Char('%');
}

QString TimeProgress::percentNumber(double remaining)
{
    // Matches Swift `.percent.precision(.fractionLength(1))`.
    return QString::number(remaining * 100.0, 'f', 1);
}

void TimeProgress::recalculate(const QDateTime &at)
{
    const QDate date = at.date();

    // QDate::startOfDay() is local timezone — same as Swift Calendar.current.
    const QDateTime dayStart = date.startOfDay();
    const QDateTime dayEnd = date.addDays(1).startOfDay();

    // Qt: dayOfWeek() is 1 = Monday … 7 = Sunday.
    int first = 1; // Monday
    if (!m_weekStartsOnMonday) {
        const int loc = static_cast<int>(QLocale().firstDayOfWeek()); // 1=Mon … 7=Sun
        if (loc >= 1 && loc <= 7)
            first = loc;
    }
    const int delta = (date.dayOfWeek() - first + 7) % 7;
    const QDate weekBegin = date.addDays(-delta);
    const QDateTime weekStart = weekBegin.startOfDay();
    const QDateTime weekEnd = weekBegin.addDays(7).startOfDay();

    const QDate monthFirst(date.year(), date.month(), 1);
    const QDateTime monthStart = monthFirst.startOfDay();
    const QDateTime monthEnd = monthFirst.addMonths(1).startOfDay();

    const QDate yearFirst(date.year(), 1, 1);
    const QDateTime yearStart = yearFirst.startOfDay();
    const QDateTime yearEnd = yearFirst.addYears(1).startOfDay();

    m_dayRemaining = remainingFraction(dayStart, dayEnd, at);
    m_weekRemaining = remainingFraction(weekStart, weekEnd, at);
    m_monthRemaining = remainingFraction(monthStart, monthEnd, at);
    m_yearRemaining = remainingFraction(yearStart, yearEnd, at);

    m_dayPercentText = percentText(m_dayRemaining);
    m_weekPercentText = percentText(m_weekRemaining);
    m_monthPercentText = percentText(m_monthRemaining);
    m_yearPercentText = percentText(m_yearRemaining);
    m_dayPercentNumber = percentNumber(m_dayRemaining);
    m_monthTicks = date.daysInMonth();

    emit updated();
}

void TimeProgress::tick()
{
    recalculate(QDateTime::currentDateTime());
    armMinuteTimer();
}

void TimeProgress::armMinuteTimer()
{
    const QTime t = QTime::currentTime();
    const int msIntoMinute = (t.second() * 1000) + t.msec();
    const int msUntilNext = 60'000 - msIntoMinute;
    m_timer.start(std::max(msUntilNext, 250));
}
