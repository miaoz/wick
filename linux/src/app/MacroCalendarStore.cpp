#include "MacroCalendarStore.h"
#include "TraderAlmanac.h"

#include <QDate>
#include <QDateTime>
#include <QTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSet>
#include <QTimeZone>
#include <QUrlQuery>

#include <algorithm>
#include <optional>

namespace {

QTimeZone shanghai()
{
    const auto tz = QTimeZone(QByteArrayLiteral("Asia/Shanghai"));
    return tz.isValid() ? tz : QTimeZone::fromSecondsAheadOfUtc(8 * 3600);
}

QPair<qint64, qint64> chinaDayRange(const QDate &day)
{
    const QDateTime start(day, QTime(0, 0), shanghai());
    return {start.toSecsSinceEpoch(), start.addDays(1).toSecsSinceEpoch()};
}

std::optional<double> jsonNumber(const QJsonValue &v)
{
    if (v.isDouble()) {
        const double d = v.toDouble();
        return d;
    }
    if (!v.isString())
        return std::nullopt;
    QString s = v.toString().trimmed();
    if (s.isEmpty())
        return std::nullopt;
    s.replace(QLatin1Char('%'), QString());
    bool ok = false;
    const double d = s.toDouble(&ok);
    return ok ? std::optional<double>(d) : std::nullopt;
}

} // namespace

MacroCalendarStore::MacroCalendarStore(QObject *parent)
    : QObject(parent)
{
    applyAlmanac();
}

void MacroCalendarStore::loadIfNeeded()
{
    if (m_loading)
        return;
    m_loading = true;
    m_error.clear();
    m_pending = 2;
    emit changed();
    fetchMacro();
    fetchEarnings();
}

void MacroCalendarStore::setSortByImportance(bool on)
{
    if (on == m_sortImportance)
        return;
    m_sortImportance = on;
    if (m_sortImportance) {
        std::sort(m_events.begin(), m_events.end(), [](const QVariant &a, const QVariant &b) {
            const auto am = a.toMap();
            const auto bm = b.toMap();
            const int ai = am.value(QStringLiteral("importance")).toInt();
            const int bi = bm.value(QStringLiteral("importance")).toInt();
            if (ai != bi)
                return ai > bi;
            return am.value(QStringLiteral("time")).toString() < bm.value(QStringLiteral("time")).toString();
        });
    } else {
        std::sort(m_events.begin(), m_events.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("time")).toString()
                < b.toMap().value(QStringLiteral("time")).toString();
        });
    }
    emit changed();
}

void MacroCalendarStore::fetchMacro()
{
    const auto range = chinaDayRange(QDate::currentDate());
    QUrl url(QStringLiteral("https://api-one-wscn.awtmt.com/apiv1/finance/macrodatas"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("start"), QString::number(range.first));
    q.addQueryItem(QStringLiteral("end"), QString::number(range.second));
    url.setQuery(q);
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "Wick/MacroCalendar");
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, range]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 0) {
            m_error = QStringLiteral("宏观日历网络错误");
        } else {
            parseMacro(reply->readAll());
            QVariantList clipped;
            for (const auto &row : m_events) {
                const qint64 t = row.toMap().value(QStringLiteral("unix")).toLongLong();
                if (t >= range.first && t < range.second)
                    clipped.push_back(row);
            }
            m_events = clipped;
        }
        finish();
    });
}

void MacroCalendarStore::fetchEarnings()
{
    const auto range = chinaDayRange(QDate::currentDate());
    QUrl url(QStringLiteral("https://api-ddc-wscn.awtmt.com/finance/report/list"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("start"), QString::number(range.first));
    q.addQueryItem(QStringLiteral("end"), QString::number(range.second));
    q.addQueryItem(QStringLiteral("country"), QStringLiteral("US,HK,CN"));
    url.setQuery(q);
    QNetworkRequest req(url);
    req.setRawHeader("User-Agent", "Wick/MacroCalendar");
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, range]() {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() >= 200)
            parseEarnings(reply->readAll());
        QVariantList clipped;
        for (const auto &row : m_earnings) {
            const qint64 t = row.toMap().value(QStringLiteral("unix")).toLongLong();
            if (t >= range.first && t < range.second)
                clipped.push_back(row);
        }
        m_earnings = clipped;
        finish();
    });
}

void MacroCalendarStore::parseMacro(const QByteArray &body)
{
    const auto doc = QJsonDocument::fromJson(body);
    const auto items = doc.object().value(QStringLiteral("data")).toObject().value(QStringLiteral("items")).toArray();
    QVariantList out;
    QSet<QString> seen;
    for (const auto &v : items) {
        const auto o = v.toObject();
        if (!o.contains(QStringLiteral("public_date")))
            continue;
        const qint64 publicDate = static_cast<qint64>(o.value(QStringLiteral("public_date")).toDouble());
        QString title = o.value(QStringLiteral("title")).toString().trimmed();
        if (title.isEmpty())
            title = o.value(QStringLiteral("country")).toString().trimmed();
        if (title.isEmpty())
            continue;
        QString calendarKey = o.value(QStringLiteral("calendar_key")).toString().trimmed();
        QString id = calendarKey;
        if (id.isEmpty()) {
            if (o.contains(QStringLiteral("id")))
                id = QString::number(static_cast<qint64>(o.value(QStringLiteral("id")).toDouble()));
            else
                id = QString::number(publicDate) + QLatin1Char('-') + title;
        }
        const QString country = o.value(QStringLiteral("country")).toString().trimmed();
        const QString dedup = QString::number(publicDate) + QLatin1Char('|') + country + QLatin1Char('|') + title;
        if (seen.contains(dedup))
            continue;
        seen.insert(dedup);

        QVariantMap row;
        row.insert(QStringLiteral("id"), id);
        const QDateTime dt = QDateTime::fromSecsSinceEpoch(publicDate, shanghai());
        row.insert(QStringLiteral("time"), dt.toString(QStringLiteral("HH:mm")));
        row.insert(QStringLiteral("unix"), publicDate);
        row.insert(QStringLiteral("country"), country);
        row.insert(QStringLiteral("title"), title);
        row.insert(QStringLiteral("importance"), o.value(QStringLiteral("importance")).toInt());
        const auto actual = jsonNumber(o.value(QStringLiteral("actual")));
        const auto forecast = jsonNumber(o.value(QStringLiteral("forecast")));
        auto previous = jsonNumber(o.value(QStringLiteral("revised")));
        if (!previous)
            previous = jsonNumber(o.value(QStringLiteral("previous")));
        QStringList bits;
        if (actual)
            bits << QStringLiteral("今 ") + QString::number(*actual, 'g', 6);
        if (forecast)
            bits << QStringLiteral("预 ") + QString::number(*forecast, 'g', 6);
        if (previous)
            bits << QStringLiteral("前 ") + QString::number(*previous, 'g', 6);
        row.insert(QStringLiteral("values"), bits.join(QStringLiteral("  ")));
        out.push_back(row);
    }
    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("time")).toString()
            < b.toMap().value(QStringLiteral("time")).toString();
    });
    m_events = out;
}

void MacroCalendarStore::parseEarnings(const QByteArray &body)
{
    const auto doc = QJsonDocument::fromJson(body);
    const auto data = doc.object().value(QStringLiteral("data")).toObject();
    const auto fields = data.value(QStringLiteral("fields")).toArray();
    const auto items = data.value(QStringLiteral("items")).toArray();
    QStringList names;
    for (const auto &f : fields)
        names.push_back(f.toString());
    QVariantList out;
    for (const auto &rowV : items) {
        const auto arr = rowV.toArray();
        if (arr.size() != names.size())
            continue;
        QVariantMap col;
        for (int i = 0; i < names.size(); ++i)
            col.insert(names.at(i), arr.at(i).toVariant());
        const QString code = col.value(QStringLiteral("code")).toString();
        const QString name = col.value(QStringLiteral("company_name")).toString();
        if (code.isEmpty() || name.isEmpty())
            continue;
        bool ok = false;
        const qint64 ts = col.value(QStringLiteral("public_date")).toLongLong(&ok);
        if (!ok)
            continue;
        QString call = col.value(QStringLiteral("earnings_call_time")).toString();
        QString mark = QStringLiteral("未定");
        if (call == QLatin1String("BMO"))
            mark = QStringLiteral("盘前");
        else if (call == QLatin1String("AMC"))
            mark = QStringLiteral("盘后");
        QVariantMap row;
        row.insert(QStringLiteral("id"), col.value(QStringLiteral("id")).toString().isEmpty()
                                             ? (QString::number(ts) + QLatin1Char('-') + code)
                                             : col.value(QStringLiteral("id")).toString());
        row.insert(QStringLiteral("unix"), ts);
        row.insert(QStringLiteral("code"), code);
        row.insert(QStringLiteral("company"), name);
        row.insert(QStringLiteral("mark"), mark);
        const double eps = col.value(QStringLiteral("eps_estimate")).toDouble();
        row.insert(QStringLiteral("eps"), eps == 0 ? QString() : QStringLiteral("EPS ") + QString::number(eps, 'g', 4));
        out.push_back(row);
    }
    m_earnings = out;
}

void MacroCalendarStore::finish()
{
    if (--m_pending > 0)
        return;
    m_loading = false;
    applyAlmanac();
    emit changed();
}

void MacroCalendarStore::applyAlmanac()
{
    bool highVol = false;
    for (const auto &row : m_events) {
        const auto m = row.toMap();
        if (m.value(QStringLiteral("importance")).toInt() >= 2) {
            highVol = true;
            break;
        }
        const QString t = m.value(QStringLiteral("title")).toString().toUpper();
        if (t.contains(QLatin1String("CPI")) || t.contains(QLatin1String("FOMC"))
            || t.contains(QStringLiteral("非农")) || t.contains(QStringLiteral("利率决议"))
            || t.contains(QLatin1String("FED RATE")) || t.contains(QLatin1String("NON-FARM"))
            || t.contains(QLatin1String("GDP"))) {
            highVol = true;
            break;
        }
    }
    const auto e = wick::traderAlmanac(QDate::currentDate(), highVol);
    m_yi = e.yi;
    m_ji = e.ji;
    m_seal = e.seal;
    m_lucky = e.lucky;
    m_sha = e.sha;
    const int wd = QDate::currentDate().dayOfWeek();
    m_weekend = (wd == 6 || wd == 7);
}
