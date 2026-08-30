#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QNetworkAccessManager>

/// Inspector feed: WallStreetCN macro + earnings (same endpoints as macOS).
class MacroCalendarStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool loading READ loading NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantList events READ events NOTIFY changed)
    Q_PROPERTY(QVariantList earnings READ earnings NOTIFY changed)
    Q_PROPERTY(QString yi READ yi NOTIFY changed)
    Q_PROPERTY(QString ji READ ji NOTIFY changed)
    Q_PROPERTY(QString seal READ seal NOTIFY changed)
    Q_PROPERTY(QString lucky READ lucky NOTIFY changed)
    Q_PROPERTY(QString sha READ sha NOTIFY changed)
    Q_PROPERTY(bool isWeekend READ isWeekend NOTIFY changed)

public:
    explicit MacroCalendarStore(QObject *parent = nullptr);

    bool loading() const { return m_loading; }
    QString error() const { return m_error; }
    QVariantList events() const { return m_events; }
    QVariantList earnings() const { return m_earnings; }
    QString yi() const { return m_yi; }
    QString ji() const { return m_ji; }
    QString seal() const { return m_seal; }
    QString lucky() const { return m_lucky; }
    QString sha() const { return m_sha; }
    bool isWeekend() const { return m_weekend; }

    Q_INVOKABLE void loadIfNeeded();
    Q_INVOKABLE void setSortByImportance(bool on);
    Q_INVOKABLE QString copyAlmanacCard();

signals:
    void changed();

private:
    void fetchMacro();
    void fetchEarnings();
    void finish();
    void applyAlmanac();
    void parseMacro(const QByteArray &body);
    void parseEarnings(const QByteArray &body);

    QNetworkAccessManager m_nam;
    bool m_loading = false;
    bool m_sortImportance = false;
    bool m_weekend = false;
    int m_pending = 0;
    QString m_error;
    QVariantList m_events;
    QVariantList m_earnings;
    QString m_yi;
    QString m_ji;
    QString m_seal;
    QString m_lucky;
    QString m_sha;
};
