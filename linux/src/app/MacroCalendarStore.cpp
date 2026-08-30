#include "MacroCalendarStore.h"
#include "LunarCalendar.h"
#include "TraderAlmanac.h"

#include <QClipboard>
#include <QDate>
#include <QDateTime>
#include <QFont>
#include <QGuiApplication>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPainter>
#include <QSet>
#include <QTime>
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

QString MacroCalendarStore::copyAlmanacCard()
{
    const int width = 560;
    const int height = 760;
    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(QColor(0x18, 0x14, 0x12));

    QPainter p(&image);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::TextAntialiasing);

    QRect cardRect(20, 20, width - 40, height - 40);
    p.setBrush(QColor(0x23, 0x1C, 0x18));
    p.setPen(QPen(QColor(0x4A, 0x3E, 0x34), 1));
    p.drawRoundedRect(cardRect, 8, 8);

    QFont headerFont(QStringLiteral("Noto Serif CJK SC, Songti SC, serif"), 11, QFont::Bold);
    p.setFont(headerFont);
    p.setPen(QColor(0xE0, 0x9A, 0x3C));
    p.drawText(cardRect.adjusted(24, 20, -24, 0), Qt::AlignLeft | Qt::AlignTop, QStringLiteral("秉烛 · 交易日历"));

    const QDate today = QDate::currentDate();
    QFont dateFont(QStringLiteral("Inter, Noto Sans CJK SC, sans-serif"), 26, QFont::Black);
    p.setFont(dateFont);
    p.setPen(QColor(0xF0, 0xE6, 0xDA));
    QString dateStr = QString::number(today.month()) + QStringLiteral("月") + QString::number(today.day()) + QStringLiteral("日");
    p.drawText(QRect(44, 75, 300, 40), Qt::AlignLeft | Qt::AlignVCenter, dateStr);

    QFont subFont(QStringLiteral("Noto Serif CJK SC, Songti SC, serif"), 11);
    p.setFont(subFont);
    p.setPen(QColor(0xB8, 0xAA, 0x98));
    QString lunarStr = wick::lunarLine(today);
    p.drawText(QRect(44, 118, 400, 22), Qt::AlignLeft | Qt::AlignVCenter, lunarStr);

    if (!m_seal.isEmpty()) {
        QRect sealRect(width - 96, 75, 46, 46);
        p.setBrush(QColor(0xB0, 0x34, 0x1E));
        p.setPen(Qt::NoPen);
        p.drawRoundedRect(sealRect, 5, 5);
        p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 13, QFont::Bold));
        p.setPen(QColor(0xFA, 0xEB, 0xD7));
        p.drawText(sealRect, Qt::AlignCenter, m_seal);
    }

    p.setPen(QPen(QColor(0x3E, 0x33, 0x2A), 1));
    p.drawLine(44, 154, width - 44, 154);

    int y = 172;

    p.setPen(Qt::NoPen);
    p.setBrush(QColor(0x3E, 0x5C, 0x50));
    p.drawRoundedRect(QRect(44, y, 30, 22), 3, 3);
    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 10, QFont::Bold));
    p.setPen(QColor(0xFA, 0xEB, 0xD7));
    p.drawText(QRect(44, y, 30, 22), Qt::AlignCenter, QStringLiteral("宜"));
    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 11));
    p.setPen(QColor(0xF0, 0xE6, 0xDA));
    p.drawText(QRect(84, y, width - 128, 24), Qt::AlignLeft | Qt::AlignVCenter, m_yi);
    y += 34;

    p.setPen(Qt::NoPen);
    p.setBrush(QColor(0xB0, 0x34, 0x1E));
    p.drawRoundedRect(QRect(44, y, 30, 22), 3, 3);
    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 10, QFont::Bold));
    p.setPen(QColor(0xFA, 0xEB, 0xD7));
    p.drawText(QRect(44, y, 30, 22), Qt::AlignCenter, QStringLiteral("忌"));
    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 11));
    p.setPen(QColor(0xF0, 0xE6, 0xDA));
    p.drawText(QRect(84, y, width - 128, 24), Qt::AlignLeft | Qt::AlignVCenter, m_ji);
    y += 38;

    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 9));
    p.setPen(QColor(0x8A, 0x7E, 0x72));
    QString meta = QStringLiteral("吉神: ") + (m_lucky.isEmpty() ? QStringLiteral("—") : m_lucky)
                 + QStringLiteral("  |  煞方: ") + (m_sha.isEmpty() ? QStringLiteral("—") : m_sha);
    p.drawText(QRect(44, y, width - 88, 18), Qt::AlignLeft | Qt::AlignVCenter, meta);
    y += 28;

    p.setPen(QPen(QColor(0x3E, 0x33, 0x2A), 1));
    p.drawLine(44, y, width - 44, y);
    y += 16;

    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 11, QFont::Bold));
    p.setPen(QColor(0xE0, 0x9A, 0x3C));
    p.drawText(QRect(44, y, 200, 22), Qt::AlignLeft | Qt::AlignVCenter, QStringLiteral("今日宏观事件"));
    y += 30;

    int eventCount = 0;
    p.setFont(QFont(QStringLiteral("Noto Sans CJK SC, Inter, sans-serif"), 10));
    for (const auto &row : m_events) {
        if (++eventCount > 6)
            break;
        const auto map = row.toMap();
        const QString time = map.value(QStringLiteral("time")).toString();
        const QString title = map.value(QStringLiteral("title")).toString();
        const QString val = map.value(QStringLiteral("actual")).toString();

        p.setPen(QColor(0x8A, 0x7E, 0x72));
        p.drawText(QRect(44, y, 46, 20), Qt::AlignLeft | Qt::AlignVCenter, time.isEmpty() ? QStringLiteral("当日") : time);

        p.setPen(QColor(0xF0, 0xE6, 0xDA));
        p.drawText(QRect(96, y, width - 190, 20), Qt::AlignLeft | Qt::AlignVCenter, p.fontMetrics().elidedText(title, Qt::ElideRight, width - 190));

        if (!val.isEmpty()) {
            p.setPen(QColor(0xE0, 0x9A, 0x3C));
            p.drawText(QRect(width - 94, y, 50, 20), Qt::AlignRight | Qt::AlignVCenter, val);
        }
        y += 24;
    }
    if (eventCount == 0) {
        p.setPen(QColor(0x8A, 0x7E, 0x72));
        p.drawText(QRect(44, y, width - 88, 20), Qt::AlignLeft | Qt::AlignVCenter, m_weekend ? QStringLiteral("周末休市") : QStringLiteral("本日无重要事件"));
    }

    p.setFont(QFont(QStringLiteral("Noto Serif CJK SC, serif"), 9));
    p.setPen(QColor(0x5A, 0x4E, 0x44));
    p.drawText(QRect(44, height - 50, width - 88, 18), Qt::AlignCenter, QStringLiteral("Wick · 秉烛日记"));

    p.end();

    QClipboard *cb = QGuiApplication::clipboard();
    if (cb)
        cb->setImage(image);

    return QStringLiteral("已复制日历卡片到剪贴板");
}
