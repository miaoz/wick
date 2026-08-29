#pragma once

#include <QDateTime>
#include <QObject>
#include <QString>
#include <QTimer>

/// Remaining fractions of the current local day / week / month / year.
///
/// Port of `TimeProgressCalculator` in Sources/WickSync/TimeProgress.swift:
/// `remaining = clamp((interval.end - now) / interval.duration, 0, 1)`.
/// Week starts Monday (stage 0; Mac `weekStartsOnMonday` when enabled,
/// `Calendar.firstWeekday = 2`). Local timezone, including DST length.
class TimeProgress : public QObject
{
    Q_OBJECT

    Q_PROPERTY(double dayRemaining READ dayRemaining NOTIFY updated)
    Q_PROPERTY(double weekRemaining READ weekRemaining NOTIFY updated)
    Q_PROPERTY(double monthRemaining READ monthRemaining NOTIFY updated)
    Q_PROPERTY(double yearRemaining READ yearRemaining NOTIFY updated)

    Q_PROPERTY(double dayElapsed READ dayElapsed NOTIFY updated)
    Q_PROPERTY(double weekElapsed READ weekElapsed NOTIFY updated)
    Q_PROPERTY(double monthElapsed READ monthElapsed NOTIFY updated)
    Q_PROPERTY(double yearElapsed READ yearElapsed NOTIFY updated)

    Q_PROPERTY(QString dayPercentText READ dayPercentText NOTIFY updated)
    Q_PROPERTY(QString weekPercentText READ weekPercentText NOTIFY updated)
    Q_PROPERTY(QString monthPercentText READ monthPercentText NOTIFY updated)
    Q_PROPERTY(QString yearPercentText READ yearPercentText NOTIFY updated)

    Q_PROPERTY(QString dayPercentNumber READ dayPercentNumber NOTIFY updated)

    Q_PROPERTY(int monthTicks READ monthTicks NOTIFY updated)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)

public:
    explicit TimeProgress(QObject *parent = nullptr);

    double dayRemaining() const { return m_dayRemaining; }
    double weekRemaining() const { return m_weekRemaining; }
    double monthRemaining() const { return m_monthRemaining; }
    double yearRemaining() const { return m_yearRemaining; }

    double dayElapsed() const { return 1.0 - m_dayRemaining; }
    double weekElapsed() const { return 1.0 - m_weekRemaining; }
    double monthElapsed() const { return 1.0 - m_monthRemaining; }
    double yearElapsed() const { return 1.0 - m_yearRemaining; }

    QString dayPercentText() const { return m_dayPercentText; }
    QString weekPercentText() const { return m_weekPercentText; }
    QString monthPercentText() const { return m_monthPercentText; }
    QString yearPercentText() const { return m_yearPercentText; }

    /// Hero figure: remaining percent without the `%` suffix (one decimal).
    QString dayPercentNumber() const { return m_dayPercentNumber; }

    int monthTicks() const { return m_monthTicks; }
    QString appVersion() const;

    /// Same clamp as `TimeProgressCalculator.remainingFraction`.
    static double remainingFraction(const QDateTime &start,
                                    const QDateTime &end,
                                    const QDateTime &at);

    /// Recompute from `at` (local). Used by the minute timer and tests.
    void recalculate(const QDateTime &at);

public slots:
    void tick();

signals:
    void updated();

private:
    void armMinuteTimer();
    static QString percentText(double remaining);
    static QString percentNumber(double remaining);

    QTimer m_timer;
    double m_dayRemaining = 0;
    double m_weekRemaining = 0;
    double m_monthRemaining = 0;
    double m_yearRemaining = 0;
    QString m_dayPercentText;
    QString m_weekPercentText;
    QString m_monthPercentText;
    QString m_yearPercentText;
    QString m_dayPercentNumber;
    int m_monthTicks = 31;
};
