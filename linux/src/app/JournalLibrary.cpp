#include "JournalLibrary.h"
#include "AppSettings.h"
#include "JournalSyncEncoding.h"
#include "LunarCalendar.h"
#include "SymbolTagMatcher.h"

#include <QDateTime>
#include <QHash>
#include <QLocale>
#include <QTimeZone>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <set>
#include <variant>

using wick::JournalCatalogLoader;
using wick::JournalCatalogSnapshot;
using wick::JournalDayKey;
using wick::JournalEntry;
using wick::JournalExchangeBinding;
using wick::JournalFileStore;
using wick::JournalImageFilename;
using wick::JournalInfo;
using wick::JournalItem;
using wick::JournalReview;
using wick::JournalReviewVerdict;
using wick::SymbolTagMatcher;
using wick::TimePoint;
using wick::TradingPosition;
using wick::TradingPositionSide;
using wick::TradingPositionSnapshot;
using wick::Uuid;

namespace {

QString qs(const std::string &s)
{
    return QString::fromStdString(s);
}

std::string ss(const QString &s)
{
    return s.toStdString();
}

std::optional<Uuid> parseUuid(const QString &id)
{
    return Uuid::parse(ss(id));
}

bool containsInsensitive(const QString &hay, const QString &needle)
{
    return hay.contains(needle, Qt::CaseInsensitive);
}

} // namespace

JournalLibrary::JournalLibrary(QObject *parent)
    : JournalLibrary(wick::JournalPaths::defaultPaths(), parent)
{
}

JournalLibrary::JournalLibrary(wick::JournalPaths paths, QObject *parent)
    : QObject(parent)
    , m_paths(std::move(paths))
    , m_calendarMonth(QDate::currentDate())
{
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(400);
    connect(&m_saveTimer, &QTimer::timeout, this, &JournalLibrary::flushNow);

    if (auto *app = AppSettings::instance()) {
        connect(app, &AppSettings::languageChanged, this, [this]() {
            emit selectionChanged();
            emit daysChanged();
            emit calendarChanged();
            emit savedStateChanged();
            emit journalsChanged();
        });
    }
}

void JournalLibrary::bootstrap()
{
    std::error_code ec;
    std::filesystem::create_directories(m_paths.librariesRoot, ec);

    const auto outcome = JournalCatalogLoader::load(
        m_paths.catalogURL(),
        m_paths.catalogBackupURL(),
        JournalCatalogSnapshot::currentVersion);

    if (std::holds_alternative<JournalCatalogLoader::Missing>(outcome)) {
        seedDefaultJournal();
    } else if (const auto *loaded = std::get_if<JournalCatalogLoader::Loaded>(&outcome)) {
        applyCatalog(loaded->catalog, false);
    } else if (const auto *restored = std::get_if<JournalCatalogLoader::RestoredFromBackup>(&outcome)) {
        applyCatalog(restored->catalog, true);
    } else if (std::holds_alternative<JournalCatalogLoader::Corrupt>(outcome)) {
        enterCatalogReadOnly(QStringLiteral("目录损坏，已只读保护（未改写 catalog.json）"));
    } else if (const auto *ver = std::get_if<JournalCatalogLoader::UnsupportedVersion>(&outcome)) {
        enterCatalogReadOnly(
            QStringLiteral("目录版本过新（v%1），已只读保护").arg(ver->version));
    }

    m_calendarMonth = QDate(QDate::currentDate().year(), QDate::currentDate().month(), 1);
    emit journalsChanged();
    emit tagsChanged();
    emit daysChanged();
    emit itemsChanged();
    emit calendarChanged();
    emit selectionChanged();
    emit readOnlyChanged();
    emit bannersChanged();
    emit savedStateChanged();
    emit journalContentChanged();
}

void JournalLibrary::seedDefaultJournal()
{
    JournalInfo info;
    info.id = Uuid::generate();
    info.name = "日记";
    info.createdAt = nowTp();
    info.updatedAt = info.createdAt;

    m_catalog.version = JournalCatalogSnapshot::currentVersion;
    m_catalog.activeJournalID = info.id;
    m_catalog.journals = {info};
    m_catalogReadOnly = false;

    writeCatalog();
    m_paths.ensureJournalDirectories(info.id);

    JournalFileStore seed(m_paths.journalDirectory(info.id));
    seed.ensureDirectories();
    seed.entries.clear();
    seed.persist();

    bindActive(info.id);
}

void JournalLibrary::applyCatalog(const JournalCatalogSnapshot &catalog, bool restoredFromBackup)
{
    m_catalogReadOnly = false;
    m_catalog = catalog;
    m_errorBanner.clear();
    if (restoredFromBackup) {
        m_restoreBanner = QStringLiteral("已从 catalog.json.bak 恢复目录");
        writeCatalog();
    } else {
        m_restoreBanner.clear();
    }

    bool found = false;
    for (const auto &j : m_catalog.journals) {
        if (j.id == m_catalog.activeJournalID) {
            found = true;
            break;
        }
    }
    if (!found) {
        if (!m_catalog.journals.empty())
            m_catalog.activeJournalID = m_catalog.journals.front().id;
        else {
            seedDefaultJournal();
            return;
        }
    }

    for (const auto &j : m_catalog.journals)
        m_paths.ensureJournalDirectories(j.id);

    bindActive(m_catalog.activeJournalID);
}

void JournalLibrary::enterCatalogReadOnly(const QString &message)
{
    m_catalogReadOnly = true;
    m_errorBanner = message;
    m_restoreBanner.clear();
    m_catalog = {};
    m_store.reset();
    m_selectedEntryId.clear();
    m_savedState = QStringLiteral("只读");
}

void JournalLibrary::bindActive(const Uuid &id)
{
    m_store = std::make_unique<JournalFileStore>(m_paths.journalDirectory(id));
    m_store->load();
    if (m_store->isReadOnlyDueToLoadFailure) {
        const QString detail = m_store->loadFailureMessage
            ? qs(*m_store->loadFailureMessage)
            : QStringLiteral("journal.json 损坏");
        m_errorBanner = QStringLiteral("日记只读：") + detail;
        m_savedState = QStringLiteral("只读");
    } else if (m_store->didRestoreFromBackup) {
        m_restoreBanner = QStringLiteral("已从 journal.json.bak 恢复");
        m_savedState = QStringLiteral("已自动保存");
    } else {
        if (!m_catalogReadOnly)
            m_errorBanner.clear();
        m_savedState.clear();
    }
    refreshTradingPositions();
    ensureSelection();
}

void JournalLibrary::refreshTradingPositions()
{
    m_tradingPositions.clear();
    if (!m_catalog.journals.empty()) {
        const auto path = m_paths.tradingJSON(m_catalog.activeJournalID);
        std::error_code ec;
        if (std::filesystem::exists(path, ec)) {
            const auto bytes = wick::readFileBytes(path);
            if (bytes) {
                const auto snap = wick::TradingPositionSnapshot::decode(*bytes);
                if (snap)
                    m_tradingPositions = snap->positions;
            }
        }
    }
    emit itemsChanged();
    emit journalsChanged();
    emit calendarChanged();
}

bool JournalLibrary::writeCatalog()
{
    if (m_catalogReadOnly)
        return false;
    return wick::persistCatalog(m_paths.librariesRoot, m_catalog);
}

void JournalLibrary::persistActive()
{
    if (!m_store || isReadOnly())
        return;
    m_store->persist();
    m_dirty = false;
    if (!m_store->isReadOnlyDueToLoadFailure)
        m_savedState = QStringLiteral("已自动保存");
    emit savedStateChanged();
    emit journalContentChanged();
}

void JournalLibrary::schedulePersist()
{
    if (isReadOnly())
        return;
    m_dirty = true;
    m_saveTimer.start();
    emit journalContentChanged();
}

void JournalLibrary::flushNow()
{
    m_saveTimer.stop();
    if (m_dirty)
        persistActive();
}

void JournalLibrary::persistSoon()
{
    schedulePersist();
}

TimePoint JournalLibrary::nowTp() const
{
    return std::chrono::system_clock::now();
}

int JournalLibrary::tzOffsetSeconds() const
{
    return QDateTime::currentDateTime().offsetFromUtc();
}

QDate JournalLibrary::dateOf(TimePoint tp) const
{
    const QDateTime utc = QDateTime::fromSecsSinceEpoch(wick::unixFromTime(tp), QTimeZone::UTC);
    return utc.toLocalTime().date();
}

QDate JournalLibrary::dateOf(const JournalEntry &entry) const
{
    return dateOf(entry.date);
}

TimePoint JournalLibrary::startOfDay(const QDate &date) const
{
    const QDateTime local = date.startOfDay();
    return wick::timeFromUnix(local.toSecsSinceEpoch());
}

std::string JournalLibrary::dayKeyOf(const QDate &date) const
{
    return JournalDayKey::make(startOfDay(date), tzOffsetSeconds());
}

std::string JournalLibrary::dayKeyOf(const JournalEntry &entry) const
{
    return JournalDayKey::make(entry.date, tzOffsetSeconds());
}

QString JournalLibrary::weekdayName(const QDate &date) const
{
    const int d = date.dayOfWeek();
    if (d < 1 || d > 7)
        return {};
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    if (zh) {
        static const char *kNames[] = {"", "周一", "周二", "周三", "周四", "周五", "周六", "周日"};
        return QString::fromUtf8(kNames[d]);
    } else {
        static const char *kNamesEn[] = {"", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
        return QString::fromUtf8(kNamesEn[d]);
    }
}

QString JournalLibrary::bigDateLabel(const QDate &date) const
{
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    if (zh)
        return QStringLiteral("%1月%2日").arg(date.month()).arg(date.day());
    return QLocale(QLocale::English, QLocale::UnitedStates).toString(date, QStringLiteral("MMM d"));
}

QString JournalLibrary::monthLabel(int month) const
{
    if (month < 1 || month > 12)
        return {};
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    if (zh) {
        static const char *kNames[] = {
            "", "一月", "二月", "三月", "四月", "五月", "六月",
            "七月", "八月", "九月", "十月", "十一月", "十二月"};
        return QString::fromUtf8(kNames[month]);
    } else {
        static const char *kNamesEn[] = {
            "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
        return QString::fromUtf8(kNamesEn[month]);
    }
}

QString JournalLibrary::lunarLineFor(const QDate &date) const
{
    return wick::lunarLine(date);
}

JournalEntry *JournalLibrary::selectedEntry()
{
    if (!m_store || m_selectedEntryId.isEmpty())
        return nullptr;
    const auto id = parseUuid(m_selectedEntryId);
    if (!id)
        return nullptr;
    for (auto &e : m_store->entries) {
        if (e.id == *id)
            return &e;
    }
    return nullptr;
}

const JournalEntry *JournalLibrary::selectedEntry() const
{
    return const_cast<JournalLibrary *>(this)->selectedEntry();
}

std::pair<JournalEntry *, JournalItem *> JournalLibrary::findItemAndEntry(const QString &itemId)
{
    if (!m_store)
        return {nullptr, nullptr};
    const auto id = parseUuid(itemId);
    if (!id)
        return {nullptr, nullptr};
    auto *sel = selectedEntry();
    if (sel) {
        for (auto &item : sel->items) {
            if (item.id == *id)
                return {sel, &item};
        }
    }
    for (auto &entry : m_store->entries) {
        for (auto &item : entry.items) {
            if (item.id == *id)
                return {&entry, &item};
        }
    }
    return {nullptr, nullptr};
}

JournalItem *JournalLibrary::findItem(const QString &itemId)
{
    return findItemAndEntry(itemId).second;
}

const JournalItem *JournalLibrary::findItem(const QString &itemId) const
{
    return const_cast<JournalLibrary *>(this)->findItem(itemId);
}

bool JournalLibrary::itemIsEmpty(const JournalItem &item) const
{
    auto blank = [](const std::string &s) {
        return QString::fromStdString(s).trimmed().isEmpty();
    };
    return blank(item.tag) && blank(item.body) && !item.review && item.imageFilenames.empty();
}

bool JournalLibrary::itemMatchesSearch(const JournalEntry &entry, const JournalItem &item) const
{
    const QString q = m_searchText.trimmed();
    if (q.isEmpty())
        return true;
    if (containsInsensitive(qs(entry.title), q))
        return true;
    if (containsInsensitive(qs(item.tag), q))
        return true;
    if (containsInsensitive(qs(item.body), q))
        return true;
    if (item.review && containsInsensitive(qs(item.review->note), q))
        return true;
    return false;
}

bool JournalLibrary::entryMatchesSearch(const JournalEntry &entry) const
{
    if (m_searchText.trimmed().isEmpty())
        return true;
    if (containsInsensitive(qs(entry.title), m_searchText.trimmed()))
        return true;
    for (const auto &item : entry.items) {
        if (itemMatchesSearch(entry, item))
            return true;
    }
    return false;
}

bool JournalLibrary::isReadOnly() const
{
    if (m_catalogReadOnly)
        return true;
    if (m_store && m_store->isReadOnlyDueToLoadFailure)
        return true;
    return false;
}

QString JournalLibrary::activeJournalId() const
{
    if (m_catalog.journals.empty())
        return {};
    return qs(m_catalog.activeJournalID.toString());
}

QString JournalLibrary::activeJournalName() const
{
    for (const auto &j : m_catalog.journals) {
        if (j.id == m_catalog.activeJournalID)
            return qs(j.name);
    }
    return {};
}

QString JournalLibrary::selectedDayKey() const
{
    const auto *e = selectedEntry();
    if (!e)
        return {};
    return qs(dayKeyOf(*e));
}

bool JournalLibrary::hasSelectedDay() const
{
    return selectedEntry() != nullptr;
}

QVariantList JournalLibrary::journals() const
{
    QVariantList out;
    for (const auto &j : m_catalog.journals) {
        QVariantMap row;
        row.insert(QStringLiteral("id"), qs(j.id.toString()));
        row.insert(QStringLiteral("name"), qs(j.name));
        int count = 0;
        if (m_store && j.id == m_catalog.activeJournalID)
            count = static_cast<int>(m_store->entries.size());
        else
            count = JournalFileStore::entryCountOnDisk(m_paths.journalDirectory(j.id));
        row.insert(QStringLiteral("entryCount"), count);
        row.insert(QStringLiteral("isActive"), j.id == m_catalog.activeJournalID);

        int posCount = 0;
        if (j.id == m_catalog.activeJournalID) {
            posCount = static_cast<int>(m_tradingPositions.size());
        } else {
            const auto path = m_paths.tradingJSON(j.id);
            std::error_code ec;
            if (std::filesystem::exists(path, ec)) {
                const auto bytes = wick::readFileBytes(path);
                if (bytes) {
                    const auto snap = wick::TradingPositionSnapshot::decode(*bytes);
                    if (snap)
                        posCount = static_cast<int>(snap->positions.size());
                }
            }
        }
        row.insert(QStringLiteral("positionsCount"), posCount);

        const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
        QString statsText;
        if (zh) {
            statsText = QStringLiteral("%1 篇").arg(count);
            if (posCount > 0)
                statsText += QStringLiteral(" · %1 仓").arg(posCount);
        } else {
            statsText = (count == 1) ? QStringLiteral("1 entry") : QStringLiteral("%1 entries").arg(count);
            if (posCount > 0)
                statsText += QStringLiteral(" · %1 pos").arg(posCount);
        }
        row.insert(QStringLiteral("statsText"), statsText);
        row.insert(QStringLiteral("todayMark"), zh ? QStringLiteral("今") : QStringLiteral("NOW"));

        if (j.exchangeBinding) {
            row.insert(QStringLiteral("exchangeBound"), true);
            row.insert(QStringLiteral("venue"),
                       qs(std::string(wick::toString(j.exchangeBinding->venue))));
            row.insert(QStringLiteral("accountLabel"), qs(j.exchangeBinding->accountLabel));
        } else {
            row.insert(QStringLiteral("exchangeBound"), false);
            row.insert(QStringLiteral("venue"), QString());
            row.insert(QStringLiteral("accountLabel"), QString());
        }
        out.push_back(row);
    }
    return out;
}

QVariantList JournalLibrary::tags() const
{
    QVariantList out;
    if (!m_store)
        return out;
    QStringList seen;
    QStringList lower;
    for (const auto &e : m_store->entries) {
        for (const auto &item : e.items) {
            const QString tag = qs(item.tag).trimmed();
            if (tag.isEmpty())
                continue;
            const QString key = tag.toLower();
            if (lower.contains(key))
                continue;
            lower.push_back(key);
            seen.push_back(tag);
        }
    }
    std::sort(seen.begin(), seen.end(), [](const QString &a, const QString &b) {
        return a.localeAwareCompare(b) < 0;
    });
    for (const auto &t : seen) {
        QVariantMap row;
        row.insert(QStringLiteral("tag"), t);
        out.push_back(row);
    }
    return out;
}

QVariantList JournalLibrary::days() const
{
    QVariantList out;
    if (!m_store)
        return out;

    std::vector<const JournalEntry *> rows;
    for (const auto &e : m_store->entries) {
        if (entryMatchesSearch(e))
            rows.push_back(&e);
    }
    std::sort(rows.begin(), rows.end(), [](const JournalEntry *a, const JournalEntry *b) {
        return a->date > b->date;
    });

    const bool hasTrading = !m_tradingPositions.empty();
    std::unordered_map<std::string, int> closedByDay;
    std::unordered_map<std::string, int> openByDay;
    std::unordered_map<std::string, double> pnlByDay;
    std::unordered_set<std::string> daysWithPnl;

    for (const auto &p : m_tradingPositions) {
        const std::string posDayKey = JournalDayKey::make(wick::timeFromUnix(p.openTime / 1000), tzOffsetSeconds());
        if (p.isClosed()) {
            closedByDay[posDayKey]++;
            const double net = p.netPnl();
            pnlByDay[posDayKey] += net;
            daysWithPnl.insert(posDayKey);
        } else {
            openByDay[posDayKey]++;
        }
    }

    int lastYear = 0;
    int lastMonth = 0;
    for (const auto *e : rows) {
        const QDate d = dateOf(*e);
        const std::string dayKey = dayKeyOf(*e);
        QVariantMap row;
        row.insert(QStringLiteral("entryId"), qs(e->id.toString()));
        row.insert(QStringLiteral("dayKey"), qs(dayKey));
        row.insert(QStringLiteral("dateLabel"), bigDateLabel(d));
        row.insert(QStringLiteral("weekday"), weekdayName(d));
        row.insert(QStringLiteral("lunar"), wick::lunarLine(d));
        const bool isToday = (d == QDate::currentDate());
        row.insert(QStringLiteral("isToday"), isToday);
        row.insert(QStringLiteral("reviewEligible"), d < QDate::currentDate());
        double burn = 0.0;
        if (isToday) {
            const QDateTime start = d.startOfDay();
            const QDateTime end = d.addDays(1).startOfDay();
            const QDateTime now = QDateTime::currentDateTime();
            const qint64 dur = start.msecsTo(end);
            burn = (dur > 0) ? std::clamp(static_cast<double>(start.msecsTo(now)) / static_cast<double>(dur), 0.0, 1.0) : 0.0;
        } else {
            burn = (d < QDate::currentDate()) ? 1.0 : 0.0;
        }
        row.insert(QStringLiteral("burnElapsed"), burn);
        row.insert(QStringLiteral("savedState"), pageSavedState());
        row.insert(QStringLiteral("items"), itemsForEntry(*e));

        const int itemCount = static_cast<int>(e->items.size());
        row.insert(QStringLiteral("itemCount"), itemCount);
        row.insert(QStringLiteral("year"), d.year());
        row.insert(QStringLiteral("monthLabel"), monthLabel(d.month()));
        const bool header = (d.year() != lastYear || d.month() != lastMonth);
        row.insert(QStringLiteral("showMonthHeader"), header);
        lastYear = d.year();
        lastMonth = d.month();

        const int closed = closedByDay[dayKey];
        const int opened = openByDay[dayKey];
        row.insert(QStringLiteral("closedPositions"), closed);
        row.insert(QStringLiteral("openPositions"), opened);

        const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
        QString statsLine;
        if (hasTrading) {
            if (closed > 0 && opened > 0) {
                statsLine = zh ? QStringLiteral("%1 条 · %2 笔已平仓 · %3 笔持仓中").arg(itemCount).arg(closed).arg(opened)
                               : QStringLiteral("%1 items · %2 closed · %3 open").arg(itemCount).arg(closed).arg(opened);
            } else if (closed > 0) {
                statsLine = zh ? QStringLiteral("%1 条 · %2 笔已平仓").arg(itemCount).arg(closed)
                               : QStringLiteral("%1 items · %2 closed").arg(itemCount).arg(closed);
            } else if (opened > 0) {
                statsLine = zh ? QStringLiteral("%1 条 · %2 笔持仓中").arg(itemCount).arg(opened)
                               : QStringLiteral("%1 items · %2 open").arg(itemCount).arg(opened);
            } else {
                statsLine = zh ? QStringLiteral("%1 条 · 无持仓").arg(itemCount)
                               : QStringLiteral("%1 items · flat").arg(itemCount);
            }
        } else {
            statsLine = zh ? QStringLiteral("%1 条").arg(itemCount)
                           : (itemCount == 1 ? QStringLiteral("1 item") : QStringLiteral("%1 items").arg(itemCount));
        }
        row.insert(QStringLiteral("statsLine"), statsLine);

        if (daysWithPnl.find(dayKey) != daysWithPnl.end()) {
            row.insert(QStringLiteral("hasPnl"), true);
            const double pnl = pnlByDay[dayKey];
            row.insert(QStringLiteral("dayPnl"), pnl);
            const QString sign = (pnl >= 0) ? QStringLiteral("+") : QStringLiteral("-");
            row.insert(QStringLiteral("pnlText"), sign + QString::number(std::abs(pnl), 'f', 2) + QStringLiteral(" USDT"));
        } else {
            row.insert(QStringLiteral("hasPnl"), false);
            row.insert(QStringLiteral("dayPnl"), 0.0);
            row.insert(QStringLiteral("pnlText"), QString());
        }

        bool hasCorrect = false;
        bool hasWrong = false;
        for (const auto &item : e->items) {
            if (!item.review)
                continue;
            if (item.review->verdict == JournalReviewVerdict::correct)
                hasCorrect = true;
            else
                hasWrong = true;
        }
        row.insert(QStringLiteral("hasCorrect"), hasCorrect);
        row.insert(QStringLiteral("hasWrong"), hasWrong);
        row.insert(QStringLiteral("hasVerdicts"), hasCorrect || hasWrong);
        row.insert(QStringLiteral("isSelected"), qs(e->id.toString()) == m_selectedEntryId);
        out.push_back(row);
    }
    return out;
}

static QString formatPrice(double price)
{
    if (std::abs(price) >= 1000)
        return QString::number(price, 'f', 1);
    if (std::abs(price) >= 1)
        return QString::number(price, 'f', 2);
    if (std::abs(price) >= 0.01)
        return QString::number(price, 'f', 4);
    return QString::number(price, 'g', 6);
}

static QString formatQty(double qty)
{
    if (std::abs(qty - std::round(qty)) < 1e-5)
        return QString::number(static_cast<qint64>(std::round(qty)));
    if (std::abs(qty) >= 100)
        return QString::number(qty, 'f', 1);
    if (std::abs(qty) >= 1)
        return QString::number(qty, 'f', 3);
    return QString::number(qty, 'g', 4);
}

static QString formatCurrency(double val)
{
    return QString::number(val, 'f', 2);
}

QVariantList JournalLibrary::itemsForEntry(const JournalEntry &entry) const
{
    QVariantList out;
    const std::string tradingDayKey = dayKeyOf(entry);
    const auto &items = entry.items;

    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    int index = 0;
    for (const auto &item : items) {
        ++index;
        if (!itemMatchesSearch(entry, item))
            continue;
        QVariantMap row;
        row.insert(QStringLiteral("itemId"), qs(item.id.toString()));
        row.insert(QStringLiteral("entryId"), qs(entry.id.toString()));
        row.insert(QStringLiteral("index"), index);
        row.insert(QStringLiteral("indexLabel"), zh ? QStringLiteral("条目 %1").arg(index) : QStringLiteral("Item %1").arg(index));
        row.insert(QStringLiteral("tag"), qs(item.tag));
        row.insert(QStringLiteral("body"), qs(item.body));
        QString verdict;
        QString note;
        if (item.review) {
            verdict = (item.review->verdict == JournalReviewVerdict::correct)
                ? QStringLiteral("correct")
                : QStringLiteral("wrong");
            note = qs(item.review->note);
        }
        row.insert(QStringLiteral("review"), verdict);
        row.insert(QStringLiteral("reviewNote"), note);
        row.insert(QStringLiteral("isEmpty"), itemIsEmpty(item));

        QVariantList posList;
        int posIdx = 0;
        for (const auto &p : m_tradingPositions) {
            const std::string posDayKey = JournalDayKey::make(wick::timeFromUnix(p.openTime / 1000), tzOffsetSeconds());
            if (posDayKey != tradingDayKey)
                continue;

            const auto itFirst = std::find_if(items.begin(), items.end(), [&](const JournalItem &cand) {
                return SymbolTagMatcher::matches(cand.tag, p.symbol);
            });
            if (itFirst == items.end() || itFirst->id != item.id)
                continue;

            QVariantMap pRow;
            pRow.insert(QStringLiteral("id"), QString::fromStdString(p.id));
            pRow.insert(QStringLiteral("symbol"), QString::fromStdString(p.symbol));
            pRow.insert(QStringLiteral("isLong"), p.side == TradingPositionSide::longSide);
            pRow.insert(QStringLiteral("laneLabel"), p.side == TradingPositionSide::longSide
                        ? (zh ? QStringLiteral("多") : QStringLiteral("Long"))
                        : (zh ? QStringLiteral("空") : QStringLiteral("Short")));

            QString header = QString::fromStdString(p.symbol);
            if (!header.endsWith(QStringLiteral("永续")) && !header.endsWith(QStringLiteral("PERP")) && !header.contains(QLatin1Char(' ')))
                header += zh ? QStringLiteral(" 永续") : QStringLiteral(" PERP");
            pRow.insert(QStringLiteral("headerTitle"), header);

            const QDateTime openDt = QDateTime::fromMSecsSinceEpoch(p.openTime);
            QString dateRange = openDt.toString(QStringLiteral("MM-dd HH:mm"));
            if (p.closeTime.has_value()) {
                const QDateTime closeDt = QDateTime::fromMSecsSinceEpoch(*p.closeTime);
                dateRange += QStringLiteral(" → ") + closeDt.toString(QStringLiteral("MM-dd HH:mm"));
            }
            pRow.insert(QStringLiteral("dateRange"), dateRange);

            QString priceText = formatPrice(p.entryPrice);
            if (p.exitPrice.has_value())
                priceText += QStringLiteral(" → ") + formatPrice(*p.exitPrice);
            pRow.insert(QStringLiteral("priceText"), priceText);

            const QString quote = QString::fromStdString(p.quoteAsset());
            const QString base = QString::fromStdString(SymbolTagMatcher::baseAsset(p.symbol));
            QString sizeText = formatQty(p.peakSize) + QStringLiteral(" ") + base;
            sizeText += QStringLiteral(" · ") + QString::fromStdString(p.durationText(zh));
            pRow.insert(QStringLiteral("sizeText"), sizeText);

            const double comm = p.commissionTotal();
            QString commText = (comm >= 0 ? QStringLiteral("+") : QStringLiteral("−")) + formatCurrency(std::abs(comm));
            QString fundText = (p.fundingPnl >= 0 ? QStringLiteral("+") : QStringLiteral("−")) + formatCurrency(std::abs(p.fundingPnl));
            pRow.insert(QStringLiteral("feesText"), commText + QStringLiteral(" · ") + fundText);
            pRow.insert(QStringLiteral("commissionTotal"), comm);
            pRow.insert(QStringLiteral("fundingPnl"), p.fundingPnl);

            const double net = p.netPnl();
            pRow.insert(QStringLiteral("realizedPnl"), p.realizedPnl);
            pRow.insert(QStringLiteral("netPnl"), net);
            QString netText = (net >= 0 ? QStringLiteral("+") : QStringLiteral("−")) + formatCurrency(std::abs(net)) + QStringLiteral(" ") + quote;
            pRow.insert(QStringLiteral("netPnlText"), netText);
            pRow.insert(QStringLiteral("isClosed"), p.isClosed());
            pRow.insert(QStringLiteral("tilt"), (posIdx % 2 == 0) ? -0.4 : 0.5);

            posList.push_back(pRow);
            ++posIdx;
        }
        row.insert(QStringLiteral("positions"), posList);
        out.push_back(row);
    }
    return out;
}

QVariantList JournalLibrary::items() const
{
    const auto *entry = selectedEntry();
    if (!entry)
        return {};
    return itemsForEntry(*entry);
}

QVariantList JournalLibrary::calendarDays() const
{
    QVariantList out;
    if (!m_calendarMonth.isValid())
        return out;

    const QDate first(m_calendarMonth.year(), m_calendarMonth.month(), 1);
    const int leading = (first.dayOfWeek() + 6) % 7; // Monday = 0
    const int dim = first.daysInMonth();
    const QDate today = QDate::currentDate();

    // 1. Trading positions realized PnL by day key
    QHash<QString, double> pnlByDay;
    QSet<QString> hasTradingDay;
    for (const auto &p : m_tradingPositions) {
        if (!p.isClosed())
            continue;
        const std::string posDayKey = JournalDayKey::make(wick::timeFromUnix(p.openTime / 1000), tzOffsetSeconds());
        const QString key = QString::fromStdString(posDayKey);
        hasTradingDay.insert(key);
        pnlByDay[key] += p.netPnl();
    }

    // 2. Journal review verdicts and entries by day key
    QHash<QString, QString> reviewStateByKey;
    QSet<QString> hasJournalEntryDay;
    if (m_store) {
        for (const auto &e : m_store->entries) {
            const QString key = qs(dayKeyOf(e));
            hasJournalEntryDay.insert(key);
            bool hasCorrect = false;
            bool hasWrong = false;
            for (const auto &item : e.items) {
                if (!item.review)
                    continue;
                if (item.review->verdict == JournalReviewVerdict::correct)
                    hasCorrect = true;
                else
                    hasWrong = true;
            }
            if (hasWrong)
                reviewStateByKey.insert(key, QStringLiteral("down"));
            else if (hasCorrect)
                reviewStateByKey.insert(key, QStringLiteral("up"));
        }
    }

    const int cells = leading + dim;
    const int rows = ((cells + 6) / 7) * 7;
    for (int i = 0; i < rows; ++i) {
        QVariantMap cell;
        if (i < leading || i >= leading + dim) {
            cell.insert(QStringLiteral("inMonth"), false);
            cell.insert(QStringLiteral("dayNumber"), QString());
            cell.insert(QStringLiteral("dayKey"), QString());
            cell.insert(QStringLiteral("state"), QStringLiteral("empty"));
            cell.insert(QStringLiteral("isToday"), false);
            cell.insert(QStringLiteral("isFuture"), false);
            out.push_back(cell);
            continue;
        }
        const QDate d(first.year(), first.month(), i - leading + 1);
        const QString key = qs(dayKeyOf(d));
        cell.insert(QStringLiteral("inMonth"), true);
        cell.insert(QStringLiteral("dayNumber"), QString::number(d.day()));
        cell.insert(QStringLiteral("dayKey"), key);

        // State priority matching macOS JournalPnlCalendarView:
        // 1) Trading realized PnL: up / down
        // 2) Review verdict: up / down
        // 3) Journal entry exists: journaled
        // 4) Otherwise: empty
        QString state = QStringLiteral("empty");
        if (hasTradingDay.contains(key)) {
            state = (pnlByDay.value(key) >= 0) ? QStringLiteral("up") : QStringLiteral("down");
        } else if (reviewStateByKey.contains(key)) {
            state = reviewStateByKey.value(key);
        } else if (hasJournalEntryDay.contains(key)) {
            state = QStringLiteral("journaled");
        }

        cell.insert(QStringLiteral("state"), state);
        cell.insert(QStringLiteral("isToday"), d == today);
        cell.insert(QStringLiteral("isFuture"), d > today);
        cell.insert(QStringLiteral("hasEntry"), hasJournalEntryDay.contains(key));
        out.push_back(cell);
    }
    return out;
}

QString JournalLibrary::pageDateLabel() const
{
    const auto *e = selectedEntry();
    return e ? bigDateLabel(dateOf(*e)) : QString();
}

QString JournalLibrary::pageWeekday() const
{
    const auto *e = selectedEntry();
    return e ? weekdayName(dateOf(*e)) : QString();
}

QString JournalLibrary::pageLunar() const
{
    const auto *e = selectedEntry();
    return e ? wick::lunarLine(dateOf(*e)) : QString();
}

bool JournalLibrary::pageHasPnl() const
{
    const auto *e = selectedEntry();
    if (!e)
        return false;
    const std::string dayKey = dayKeyOf(*e);
    for (const auto &p : m_tradingPositions) {
        const std::string posDayKey = JournalDayKey::make(wick::timeFromUnix(p.openTime / 1000), tzOffsetSeconds());
        if (posDayKey == dayKey && p.isClosed())
            return true;
    }
    return false;
}

double JournalLibrary::pagePnl() const
{
    const auto *e = selectedEntry();
    if (!e)
        return 0.0;
    const std::string dayKey = dayKeyOf(*e);
    double sum = 0.0;
    for (const auto &p : m_tradingPositions) {
        const std::string posDayKey = JournalDayKey::make(wick::timeFromUnix(p.openTime / 1000), tzOffsetSeconds());
        if (posDayKey == dayKey && p.isClosed())
            sum += p.netPnl();
    }
    return sum;
}

QString JournalLibrary::pagePnlText() const
{
    if (!pageHasPnl())
        return QString();
    const double val = pagePnl();
    const QString sign = (val >= 0) ? QStringLiteral("+") : QStringLiteral("-");
    return sign + QString::number(std::abs(val), 'f', 2) + QStringLiteral(" USDT");
}

QString JournalLibrary::selectedDayStamp() const
{
    const auto *e = selectedEntry();
    const QDate d = e ? dateOf(*e) : QDate::currentDate();
    const QString day = bigDateLabel(d);
    const QString weekday = weekdayName(d);
    return day + QStringLiteral(" · ") + weekday;
}

QString JournalLibrary::pageSavedState() const
{
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    if (isReadOnly())
        return zh ? QStringLiteral("只读") : QStringLiteral("Read-only");
    if (!zh && m_savedState == QLatin1String("已保存"))
        return QStringLiteral("Saved");
    if (!zh && m_savedState == QLatin1String("保存中…"))
        return QStringLiteral("Saving…");
    return m_savedState;
}

double JournalLibrary::pageBurnElapsed() const
{
    const auto *e = selectedEntry();
    if (!e)
        return 0;
    const QDate d = dateOf(*e);
    const QDate today = QDate::currentDate();
    if (d == today) {
        const QDateTime start = today.startOfDay();
        const QDateTime end = today.addDays(1).startOfDay();
        const QDateTime now = QDateTime::currentDateTime();
        const qint64 dur = start.msecsTo(end);
        if (dur <= 0)
            return 0;
        return std::clamp(static_cast<double>(start.msecsTo(now)) / static_cast<double>(dur), 0.0, 1.0);
    }
    return d < today ? 1.0 : 0.0;
}

bool JournalLibrary::pageIsToday() const
{
    const auto *e = selectedEntry();
    return e && dateOf(*e) == QDate::currentDate();
}

bool JournalLibrary::pageReviewEligible() const
{
    const auto *e = selectedEntry();
    return e && dateOf(*e) < QDate::currentDate();
}

QString JournalLibrary::todayDateLabel() const
{
    return bigDateLabel(QDate::currentDate());
}

QString JournalLibrary::todayWeekday() const
{
    return weekdayName(QDate::currentDate());
}

QString JournalLibrary::todayLunar() const
{
    return wick::lunarLine(QDate::currentDate());
}

bool JournalLibrary::todayIsWeekend() const
{
    const int d = QDate::currentDate().dayOfWeek();
    return d == 6 || d == 7;
}

QString JournalLibrary::calendarMonthLabel() const
{
    const bool zh = AppSettings::instance() ? AppSettings::instance()->isChinese() : true;
    if (zh)
        return QStringLiteral("%1年%2月").arg(m_calendarMonth.year()).arg(m_calendarMonth.month());
    return QLocale(QLocale::English, QLocale::UnitedStates).toString(m_calendarMonth, QStringLiteral("MMMM yyyy"));
}

bool JournalLibrary::hasCalendarMonthPnl() const
{
    if (!m_calendarMonth.isValid())
        return false;
    for (const auto &p : m_tradingPositions) {
        if (!p.isClosed())
            continue;
        const QDateTime dt = QDateTime::fromMSecsSinceEpoch(p.openTime);
        if (dt.date().year() == m_calendarMonth.year() && dt.date().month() == m_calendarMonth.month()) {
            return true;
        }
    }
    return false;
}

double JournalLibrary::calendarMonthPnl() const
{
    if (!m_calendarMonth.isValid())
        return 0.0;
    double total = 0.0;
    for (const auto &p : m_tradingPositions) {
        if (!p.isClosed())
            continue;
        const QDateTime dt = QDateTime::fromMSecsSinceEpoch(p.openTime);
        if (dt.date().year() == m_calendarMonth.year() && dt.date().month() == m_calendarMonth.month()) {
            total += p.netPnl();
        }
    }
    return total;
}

QString JournalLibrary::calendarMonthPnlText() const
{
    if (!hasCalendarMonthPnl())
        return QString();
    const double val = calendarMonthPnl();
    const QString sign = (val >= 0) ? QStringLiteral("+") : QStringLiteral("−");
    return QStringLiteral("%1%2 USDT").arg(sign).arg(QString::number(std::abs(val), 'f', 2));
}

void JournalLibrary::setColumnMode(int mode)
{
    mode = std::clamp(mode, 0, 2);
    if (mode == m_columnMode)
        return;
    m_columnMode = mode;
    emit layoutChanged();
}

void JournalLibrary::setInspectorVisible(bool visible)
{
    if (visible == m_inspectorVisible)
        return;
    m_inspectorVisible = visible;
    emit layoutChanged();
}

void JournalLibrary::cycleColumns()
{
    setColumnMode((m_columnMode + 1) % 3);
}

void JournalLibrary::toggleInspector()
{
    setInspectorVisible(!m_inspectorVisible);
}

void JournalLibrary::setSearchText(const QString &text)
{
    if (text == m_searchText)
        return;
    m_searchText = text;
    emit searchTextChanged();
    emit daysChanged();
    emit itemsChanged();
    ensureSelection();
    emit selectionChanged();
}

void JournalLibrary::ensureSelection()
{
    if (!m_store) {
        m_selectedEntryId.clear();
        return;
    }
    if (!m_selectedEntryId.isEmpty()) {
        const auto id = parseUuid(m_selectedEntryId);
        if (id) {
            for (const auto &e : m_store->entries) {
                if (e.id == *id && entryMatchesSearch(e))
                    return;
            }
        }
    }
    for (const auto &e : m_store->entries) {
        if (entryMatchesSearch(e)) {
            m_selectedEntryId = qs(e.id.toString());
            return;
        }
    }
    m_selectedEntryId.clear();
}

void JournalLibrary::rebuildAfterStructuralChange()
{
    emit journalsChanged();
    emit tagsChanged();
    emit daysChanged();
    emit itemsChanged();
    emit calendarChanged();
    emit selectionChanged();
    emit savedStateChanged();
}

QString JournalLibrary::uniquifyName(const QString &base) const
{
    return uniquifyName(base, wick::Uuid{});
}

QString JournalLibrary::uniquifyName(const QString &base, const wick::Uuid &excluding) const
{
    QString name = base.trimmed();
    if (name.isEmpty())
        name = QStringLiteral("日记");
    auto taken = [&](const QString &n) {
        for (const auto &j : m_catalog.journals) {
            if (j.id == excluding)
                continue;
            if (QString::fromStdString(j.name).compare(n, Qt::CaseInsensitive) == 0)
                return true;
        }
        return false;
    };
    if (!taken(name))
        return name;
    int i = 2;
    while (taken(name + QLatin1Char(' ') + QString::number(i)))
        ++i;
    return name + QLatin1Char(' ') + QString::number(i);
}

bool JournalLibrary::hasJournal(const Uuid &id) const
{
    for (const auto &j : m_catalog.journals) {
        if (j.id == id)
            return true;
    }
    return false;
}

std::vector<Uuid> JournalLibrary::journalIds() const
{
    std::vector<Uuid> ids;
    ids.reserve(m_catalog.journals.size());
    for (const auto &j : m_catalog.journals)
        ids.push_back(j.id);
    return ids;
}

std::optional<JournalInfo> JournalLibrary::registerRemoteJournal(const Uuid &id, const QString &name)
{
    if (m_catalogReadOnly)
        return std::nullopt;
    for (const auto &j : m_catalog.journals) {
        if (j.id == id)
            return j;
    }

    JournalInfo info;
    info.id = id;
    info.name = ss(uniquifyName(name, id));
    info.createdAt = nowTp();
    info.updatedAt = info.createdAt;
    m_paths.ensureJournalDirectories(info.id);
    JournalFileStore seed(m_paths.journalDirectory(info.id));
    seed.ensureDirectories();
    seed.entries.clear();
    seed.persist();

    m_catalog.journals.push_back(info);
    writeCatalog();
    emit journalsChanged();
    emit journalContentChanged();
    return info;
}

void JournalLibrary::selectJournal(const QString &id)
{
    if (m_catalogReadOnly)
        return;
    const auto parsed = parseUuid(id);
    if (!parsed)
        return;
    if (*parsed == m_catalog.activeJournalID)
        return;
    bool found = false;
    for (const auto &j : m_catalog.journals) {
        if (j.id == *parsed) {
            found = true;
            break;
        }
    }
    if (!found)
        return;
    flushNow();
    m_catalog.activeJournalID = *parsed;
    writeCatalog();
    bindActive(*parsed);
    rebuildAfterStructuralChange();
    emit readOnlyChanged();
    emit bannersChanged();
    emit activeJournalChanged();
}

void JournalLibrary::addJournal(const QString &name)
{
    if (m_catalogReadOnly)
        return;
    flushNow();
    JournalInfo info;
    info.id = Uuid::generate();
    info.name = ss(uniquifyName(name));
    info.createdAt = nowTp();
    info.updatedAt = info.createdAt;
    m_paths.ensureJournalDirectories(info.id);
    JournalFileStore seed(m_paths.journalDirectory(info.id));
    seed.ensureDirectories();
    seed.entries.clear();
    seed.persist();

    m_catalog.journals.push_back(info);
    m_catalog.activeJournalID = info.id;
    writeCatalog();
    bindActive(info.id);
    rebuildAfterStructuralChange();
    emit readOnlyChanged();
    emit bannersChanged();
    emit activeJournalChanged();
}

bool JournalLibrary::renameJournal(const QString &id, const QString &name)
{
    if (m_catalogReadOnly)
        return false;
    const auto parsed = parseUuid(id);
    if (!parsed)
        return false;
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty())
        return false;
    const QString resolved = uniquifyName(trimmed, *parsed);
    for (auto &j : m_catalog.journals) {
        if (j.id != *parsed)
            continue;
        if (j.name == ss(resolved))
            return true;
        j.name = ss(resolved);
        j.updatedAt = nowTp();
        if (!writeCatalog())
            return false;
        emit journalsChanged();
        return true;
    }
    return false;
}

bool JournalLibrary::deleteJournal(const QString &id)
{
    if (m_catalogReadOnly)
        return false;
    const auto parsed = parseUuid(id);
    if (!parsed)
        return false;
    if (m_catalog.journals.size() <= 1)
        return false;
    bool found = false;
    for (const auto &j : m_catalog.journals) {
        if (j.id == *parsed) {
            found = true;
            break;
        }
    }
    if (!found)
        return false;

    flushNow();
    const auto original = m_catalog;
    const bool wasActive = m_catalog.activeJournalID == *parsed;
    const auto dir = m_paths.journalDirectory(*parsed);
    const auto quarantine =
        m_paths.librariesRoot / (".WickJournalQuarantine-" + Uuid::generate().toString());

    std::error_code ec;
    bool moved = false;
    if (std::filesystem::exists(dir, ec)) {
        std::filesystem::rename(dir, quarantine, ec);
        if (ec)
            return false;
        moved = true;
    }

    m_catalog.journals.erase(std::remove_if(m_catalog.journals.begin(), m_catalog.journals.end(),
                                            [&](const JournalInfo &j) { return j.id == *parsed; }),
                             m_catalog.journals.end());
    if (wasActive && !m_catalog.journals.empty()) {
        auto best = m_catalog.journals.begin();
        for (auto it = m_catalog.journals.begin(); it != m_catalog.journals.end(); ++it) {
            if (it->updatedAt > best->updatedAt)
                best = it;
        }
        m_catalog.activeJournalID = best->id;
    }

    if (!writeCatalog()) {
        m_catalog = original;
        if (moved)
            std::filesystem::rename(quarantine, dir, ec);
        return false;
    }
    if (moved)
        std::filesystem::remove_all(quarantine, ec);

    if (wasActive) {
        bindActive(m_catalog.activeJournalID);
        emit activeJournalChanged();
        emit readOnlyChanged();
        emit bannersChanged();
    }
    rebuildAfterStructuralChange();
    return true;
}

bool JournalLibrary::moveJournal(int fromIndex, int toIndex)
{
    if (m_catalogReadOnly)
        return false;
    const int count = static_cast<int>(m_catalog.journals.size());
    if (fromIndex < 0 || fromIndex >= count)
        return false;
    if (toIndex < 0 || toIndex >= count)
        return false;
    if (fromIndex == toIndex)
        return true;

    auto moving = m_catalog.journals[static_cast<size_t>(fromIndex)];
    m_catalog.journals.erase(m_catalog.journals.begin() + fromIndex);
    m_catalog.journals.insert(m_catalog.journals.begin() + toIndex, moving);

    if (!writeCatalog())
        return false;
    emit journalsChanged();
    return true;
}

void JournalLibrary::setExchangeBinding(const Uuid &id, std::optional<JournalExchangeBinding> binding)
{
    if (m_catalogReadOnly)
        return;
    for (auto &j : m_catalog.journals) {
        if (j.id != id)
            continue;
        j.exchangeBinding = std::move(binding);
        j.updatedAt = nowTp();
        writeCatalog();
        emit journalsChanged();
        return;
    }
}

int JournalLibrary::ensurePositionEntries(
    const Uuid &journalID,
    const std::vector<std::pair<QDate, std::vector<JournalItem>>> &skeletons)
{
    if (m_catalogReadOnly || skeletons.empty())
        return 0;
    bool inCatalog = false;
    for (const auto &j : m_catalog.journals) {
        if (j.id == journalID) {
            inCatalog = true;
            break;
        }
    }
    if (!inCatalog)
        return 0;

    const bool active = m_store && journalID == m_catalog.activeJournalID;
    if (active && isReadOnly())
        return 0;

    std::vector<JournalEntry> *entries = nullptr;
    std::unique_ptr<JournalFileStore> owned;
    if (active) {
        entries = &m_store->entries;
    } else {
        const auto dir = m_paths.journalDirectory(journalID);
        std::error_code ec;
        const bool hasPrimary = std::filesystem::exists(dir / "journal.json", ec);
        const bool hasBak = std::filesystem::exists(dir / "journal.json.bak", ec);
        std::vector<JournalEntry> loaded;
        if (hasPrimary || hasBak) {
            auto fromDisk = JournalFileStore::loadEntriesReadOnly(dir);
            if (!fromDisk)
                return 0;
            loaded = std::move(*fromDisk);
        }
        owned = std::make_unique<JournalFileStore>(dir);
        owned->ensureDirectories();
        owned->entries = std::move(loaded);
        entries = &owned->entries;
    }

    auto dateOfEntry = [this](const JournalEntry &e) { return dateOf(e); };
    const TimePoint now = nowTp();
    int added = 0;
    for (const auto &skeleton : skeletons) {
        if (skeleton.second.empty())
            continue;
        const QDate day = skeleton.first;
        auto it = std::find_if(entries->begin(), entries->end(),
                               [&](const JournalEntry &e) { return dateOfEntry(e) == day; });
        if (it != entries->end()) {
            std::set<Uuid> existing;
            for (const auto &item : it->items)
                existing.insert(item.id);
            std::vector<JournalItem> additions;
            for (const auto &item : skeleton.second) {
                if (!existing.count(item.id))
                    additions.push_back(item);
            }
            if (additions.empty())
                continue;
            const bool allEmpty = std::all_of(it->items.begin(), it->items.end(),
                                              [](const JournalItem &item) { return item.isEmpty(); });
            if (allEmpty)
                it->items.clear();
            it->items.insert(it->items.end(), additions.begin(), additions.end());
            it->updatedAt = now;
            ++added;
        } else {
            JournalEntry entry;
            entry.id = Uuid::generate();
            entry.date = startOfDay(day);
            entry.items = skeleton.second;
            entry.createdAt = now;
            entry.updatedAt = now;
            entries->insert(entries->begin(), std::move(entry));
            ++added;
        }
    }
    if (added == 0)
        return 0;

    if (active) {
        persistActive();
        rebuildAfterStructuralChange();
    } else {
        owned->persist();
        emit journalsChanged();
        emit journalContentChanged();
    }
    return added;
}

void JournalLibrary::selectDay(const QString &entryId)
{
    m_selectedEntryId = entryId;
    emit selectionChanged();
    emit daysChanged();
    emit itemsChanged();
}

void JournalLibrary::openOrCreateToday()
{
    if (m_catalogReadOnly)
        return;
    if (!m_store) {
        if (m_catalog.journals.empty())
            return;
        bindActive(m_catalog.activeJournalID);
    }
    const QDate today = QDate::currentDate();
    const std::string key = dayKeyOf(today);
    for (const auto &e : m_store->entries) {
        if (dayKeyOf(e) == key) {
            m_searchText.clear();
            emit searchTextChanged();
            m_selectedEntryId = qs(e.id.toString());
            rebuildAfterStructuralChange();
            return;
        }
    }
    if (isReadOnly())
        return;

    JournalEntry entry;
    entry.id = Uuid::generate();
    entry.date = startOfDay(today);
    entry.title.clear();
    entry.createdAt = nowTp();
    entry.updatedAt = entry.createdAt;
    JournalItem item;
    item.id = Uuid::generate();
    entry.items.push_back(item);
    m_store->entries.insert(m_store->entries.begin(), entry);
    m_searchText.clear();
    emit searchTextChanged();
    m_selectedEntryId = qs(entry.id.toString());
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::addItem()
{
    addItemTo(m_selectedEntryId);
}

void JournalLibrary::addItemTo(const QString &entryId)
{
    if (isReadOnly() || !m_store)
        return;
    JournalEntry *target = nullptr;
    if (entryId.isEmpty()) {
        target = selectedEntry();
    } else {
        const auto id = parseUuid(entryId);
        if (id) {
            for (auto &entry : m_store->entries) {
                if (entry.id == *id) {
                    target = &entry;
                    break;
                }
            }
        }
    }
    if (!target)
        return;
    JournalItem item;
    item.id = Uuid::generate();
    target->items.push_back(item);
    target->updatedAt = nowTp();
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::deleteItem(const QString &itemId)
{
    if (isReadOnly() || !m_store)
        return;
    const auto id = parseUuid(itemId);
    if (!id)
        return;
    for (auto eIt = m_store->entries.begin(); eIt != m_store->entries.end(); ++eIt) {
        auto it = std::find_if(eIt->items.begin(), eIt->items.end(),
                               [&](const JournalItem &item) { return item.id == *id; });
        if (it != eIt->items.end()) {
            for (const auto &fn : it->imageFilenames) {
                m_store->removeImage(fn, eIt->id, *id);
            }
            eIt->items.erase(it);
            if (eIt->items.empty()) {
                const Uuid entryId = eIt->id;
                m_store->entries.erase(eIt);
                if (m_selectedEntryId == qs(entryId.toString())) {
                    m_selectedEntryId.clear();
                    ensureSelection();
                }
            } else {
                eIt->updatedAt = nowTp();
            }
            persistActive();
            rebuildAfterStructuralChange();
            return;
        }
    }
}

void JournalLibrary::deleteEmptyItem(const QString &itemId)
{
    if (isReadOnly() || !m_store)
        return;
    const auto [entry, item] = findItemAndEntry(itemId);
    if (!entry || !item)
        return;
    if (!itemIsEmpty(*item))
        return;
    deleteItem(itemId);
}

void JournalLibrary::deleteSelectedDay()
{
    if (isReadOnly() || !m_store)
        return;
    auto *entry = selectedEntry();
    if (!entry)
        return;
    const Uuid entryId = entry->id;
    m_store->entries.erase(
        std::remove_if(m_store->entries.begin(), m_store->entries.end(),
                       [&](const JournalEntry &e) { return e.id == entryId; }),
        m_store->entries.end());
    m_selectedEntryId.clear();
    ensureSelection();
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::deleteDay(const QString &entryId)
{
    if (isReadOnly() || !m_store)
        return;
    const auto id = parseUuid(entryId);
    if (!id)
        return;
    m_store->entries.erase(
        std::remove_if(m_store->entries.begin(), m_store->entries.end(),
                       [&](const JournalEntry &e) { return e.id == *id; }),
        m_store->entries.end());
    if (m_selectedEntryId == entryId) {
        m_selectedEntryId.clear();
        ensureSelection();
    }
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::setItemTag(const QString &itemId, const QString &tag)
{
    if (isReadOnly())
        return;
    auto [entry, item] = findItemAndEntry(itemId);
    if (!item || !entry)
        return;
    const std::string next = ss(tag);
    if (item->tag == next)
        return;
    item->tag = next;
    entry->updatedAt = nowTp();
    schedulePersist();
    emit tagsChanged();
    emit daysChanged();
}

void JournalLibrary::setItemBody(const QString &itemId, const QString &body)
{
    if (isReadOnly())
        return;
    auto [entry, item] = findItemAndEntry(itemId);
    if (!item || !entry)
        return;
    const std::string next = ss(body);
    if (item->body == next)
        return;
    item->body = next;
    entry->updatedAt = nowTp();
    schedulePersist();
}

void JournalLibrary::selectJournalByIndex(int index)
{
    if (index < 0 || index >= static_cast<int>(m_catalog.journals.size()))
        return;
    selectJournal(qs(m_catalog.journals[index].id.toString()));
}

void JournalLibrary::setItemReview(const QString &itemId, const QString &verdict, const QString &note)
{
    if (isReadOnly())
        return;
    auto [entry, item] = findItemAndEntry(itemId);
    if (!item || !entry)
        return;
    if (verdict.isEmpty()) {
        item->review.reset();
    } else {
        JournalReview review = item->review.value_or(JournalReview{});
        if (verdict == QLatin1String("correct"))
            review.verdict = JournalReviewVerdict::correct;
        else if (verdict == QLatin1String("wrong"))
            review.verdict = JournalReviewVerdict::wrong;
        else
            return;
        if (!note.isNull())
            review.note = ss(note);
        const TimePoint t = nowTp();
        if (!item->review)
            review.createdAt = t;
        review.updatedAt = t;
        item->review = review;
    }
    entry->updatedAt = nowTp();
    persistActive();
    emit itemsChanged();
    emit daysChanged();
    emit calendarChanged();
}

void JournalLibrary::setItemReviewNote(const QString &itemId, const QString &note)
{
    if (isReadOnly())
        return;
    auto [entry, item] = findItemAndEntry(itemId);
    if (!item || !entry || !item->review)
        return;
    const std::string next = ss(note);
    if (item->review->note == next)
        return;
    item->review->note = next;
    item->review->updatedAt = nowTp();
    entry->updatedAt = nowTp();
    schedulePersist();
    emit itemsChanged();
}

void JournalLibrary::selectCalendarDay(const QString &dayKey)
{
    if (!m_store)
        return;
    const std::string key = ss(dayKey);
    for (const auto &e : m_store->entries) {
        if (dayKeyOf(e) == key) {
            selectDay(qs(e.id.toString()));
            return;
        }
    }
}

void JournalLibrary::shiftCalendarMonth(int delta)
{
    QDate next = m_calendarMonth.addMonths(delta);
    next = QDate(next.year(), next.month(), 1);
    const QDate thisMonth(QDate::currentDate().year(), QDate::currentDate().month(), 1);
    if (next > thisMonth)
        next = thisMonth;
    if (next == m_calendarMonth)
        return;
    m_calendarMonth = next;
    emit calendarChanged();
}


using wick::JournalSyncMutation;

std::optional<Uuid> JournalLibrary::syncJournalID() const
{
    if (m_catalog.journals.empty())
        return std::nullopt;
    return m_catalog.activeJournalID;
}

std::string JournalLibrary::syncJournalName() const
{
    return journalNameFor(m_catalog.activeJournalID);
}

std::string JournalLibrary::journalNameFor(const Uuid &id) const
{
    for (const auto &j : m_catalog.journals) {
        if (j.id == id)
            return j.name;
    }
    return {};
}

bool JournalLibrary::syncIsWritable() const
{
    return journalWritable(m_catalog.activeJournalID);
}

bool JournalLibrary::journalWritable(const Uuid &id) const
{
    if (m_catalogReadOnly)
        return false;
    if (m_store && id == m_catalog.activeJournalID)
        return !isReadOnly();
    return true;
}

std::map<Uuid, JournalEntry> JournalLibrary::syncEntrySnapshots()
{
    std::map<Uuid, JournalEntry> out;
    if (!m_store)
        return out;
    for (const auto &e : m_store->entries)
        out[e.id] = e;
    return out;
}

std::map<Uuid, JournalEntry> JournalLibrary::entrySnapshotsFor(const Uuid &journalID)
{
    if (m_store && journalID == m_catalog.activeJournalID)
        return syncEntrySnapshots();
    JournalFileStore store(m_paths.journalDirectory(journalID));
    store.load();
    std::map<Uuid, JournalEntry> out;
    for (const auto &e : store.entries)
        out[e.id] = e;
    return out;
}

std::optional<JournalEntry> JournalLibrary::syncEntrySnapshot(const Uuid &entryID)
{
    if (!m_store)
        return std::nullopt;
    for (const auto &e : m_store->entries) {
        if (e.id == entryID)
            return e;
    }
    return std::nullopt;
}

std::optional<JournalEntry> JournalLibrary::entrySnapshotFor(const Uuid &journalID, const Uuid &entryID)
{
    if (m_store && journalID == m_catalog.activeJournalID)
        return syncEntrySnapshot(entryID);
    JournalFileStore store(m_paths.journalDirectory(journalID));
    store.load();
    for (const auto &e : store.entries) {
        if (e.id == entryID)
            return e;
    }
    return std::nullopt;
}

void JournalLibrary::prepareForRemoteApply(const Uuid &)
{
    flushNow();
}

namespace {
bool localHashMatches(const std::vector<JournalEntry> &entries, const Uuid &entryID,
                      const std::optional<std::string> &expected)
{
    const JournalEntry *current = nullptr;
    for (const auto &e : entries) {
        if (e.id == entryID) {
            current = &e;
            break;
        }
    }
    if (!expected)
        return current == nullptr;
    if (!current)
        return false;
    return wick::JournalSyncEncoding::contentHash(*current) == *expected;
}
} // namespace

std::set<Uuid> JournalLibrary::applySyncedChanges(const std::vector<JournalSyncMutation> &changes,
                                                 const Uuid &journalID)
{
    if (m_catalogReadOnly)
        return {};
    const bool active = m_store && journalID == m_catalog.activeJournalID;
    std::unique_ptr<JournalFileStore> owned;
    JournalFileStore *store = nullptr;
    if (active) {
        if (isReadOnly())
            return {};
        flushNow();
        store = m_store.get();
    } else {
        owned = std::make_unique<JournalFileStore>(m_paths.journalDirectory(journalID));
        owned->load();
        if (owned->isReadOnlyDueToLoadFailure)
            return {};
        store = owned.get();
    }
    std::set<Uuid> applied;
    for (const auto &change : changes) {
        if (!localHashMatches(store->entries, change.entryID, change.expectedLocalHash))
            continue;
        if (change.kind == JournalSyncMutation::Kind::upsert) {
            JournalEntry appliedEntry = change.entry;
            if (appliedEntry.items.empty())
                appliedEntry.items.push_back(JournalItem{Uuid::generate(), "", "", {}, std::nullopt});
            bool found = false;
            for (auto &e : store->entries) {
                if (e.id == appliedEntry.id) {
                    e = appliedEntry;
                    found = true;
                    break;
                }
            }
            if (!found)
                store->entries.push_back(appliedEntry);
            applied.insert(change.entryID);
        } else {
            for (auto it = store->entries.begin(); it != store->entries.end(); ++it) {
                if (it->id == change.entryID) {
                    store->entries.erase(it);
                    applied.insert(change.entryID);
                    break;
                }
            }
        }
    }
    if (applied.empty())
        return {};
    store->persist();
    if (active) {
        m_dirty = false;
        if (!m_store->isReadOnlyDueToLoadFailure)
            m_savedState = QStringLiteral("已自动保存");
        rebuildAfterStructuralChange();
    } else {
        emit journalsChanged();
    }
    return applied;
}

void JournalLibrary::applySyncedEntry(const JournalEntry &entry, const Uuid &journalID)
{
    if (m_catalogReadOnly)
        return;
    const bool active = m_store && journalID == m_catalog.activeJournalID;
    std::unique_ptr<JournalFileStore> owned;
    JournalFileStore *store = nullptr;
    if (active) {
        if (isReadOnly())
            return;
        flushNow();
        store = m_store.get();
    } else {
        owned = std::make_unique<JournalFileStore>(m_paths.journalDirectory(journalID));
        owned->load();
        if (owned->isReadOnlyDueToLoadFailure)
            return;
        store = owned.get();
    }
    JournalEntry applied = entry;
    if (applied.items.empty())
        applied.items.push_back(JournalItem{Uuid::generate(), "", "", {}, std::nullopt});
    bool found = false;
    for (auto &e : store->entries) {
        if (e.id == applied.id) {
            e = applied;
            found = true;
            break;
        }
    }
    if (!found)
        store->entries.push_back(applied);
    store->persist();
    if (active) {
        m_dirty = false;
        rebuildAfterStructuralChange();
    } else {
        emit journalsChanged();
    }
}

void JournalLibrary::removeSyncedEntry(const Uuid &entryID, const Uuid &journalID)
{
    if (m_catalogReadOnly)
        return;
    const bool active = m_store && journalID == m_catalog.activeJournalID;
    std::unique_ptr<JournalFileStore> owned;
    JournalFileStore *store = nullptr;
    if (active) {
        if (isReadOnly())
            return;
        store = m_store.get();
    } else {
        owned = std::make_unique<JournalFileStore>(m_paths.journalDirectory(journalID));
        owned->load();
        if (owned->isReadOnlyDueToLoadFailure)
            return;
        store = owned.get();
    }
    for (auto it = store->entries.begin(); it != store->entries.end(); ++it) {
        if (it->id == entryID) {
            store->entries.erase(it);
            store->persist();
            if (active)
                rebuildAfterStructuralChange();
            else
                emit journalsChanged();
            return;
        }
    }
}

std::string JournalLibrary::applySyncedJournalName(const std::string &name, const Uuid &journalID)
{
    const QString trimmed = QString::fromStdString(name).trimmed();
    std::string current;
    int index = -1;
    for (int i = 0; i < static_cast<int>(m_catalog.journals.size()); ++i) {
        if (m_catalog.journals[static_cast<size_t>(i)].id == journalID) {
            index = i;
            current = m_catalog.journals[static_cast<size_t>(i)].name;
            break;
        }
    }
    if (index < 0)
        return current.empty() ? syncJournalName() : current;
    const QString resolved = trimmed.isEmpty()
        ? QString::fromStdString(current)
        : uniquifyName(trimmed, journalID);
    auto &info = m_catalog.journals[static_cast<size_t>(index)];
    if (resolved.toStdString() == info.name)
        return info.name;
    info.name = resolved.toStdString();
    info.updatedAt = nowTp();
    writeCatalog();
    emit journalsChanged();
    emit journalContentChanged();
    return info.name;
}

std::set<std::string> JournalLibrary::syncedImageFilenames()
{
    const auto id = syncJournalID();
    if (!id)
        return {};
    return imageFilenamesFor(*id);
}

std::set<std::string> JournalLibrary::imageFilenamesFor(const Uuid &journalID)
{
    std::set<std::string> out;
    const auto snaps = entrySnapshotsFor(journalID);
    for (const auto &[_, e] : snaps) {
        for (const auto &item : e.items) {
            for (const auto &f : item.imageFilenames)
                out.insert(f);
        }
    }
    return out;
}

std::optional<std::string> JournalLibrary::syncedImageData(const std::string &filename)
{
    const auto id = syncJournalID();
    if (!id)
        return std::nullopt;
    return imageDataFor(*id, filename);
}

std::optional<std::string> JournalLibrary::imageDataFor(const Uuid &journalID, const std::string &filename)
{
    if (!JournalImageFilename::isValid(filename))
        return std::nullopt;
    return wick::readFileBytes(m_paths.imagesDirectory(journalID) / filename);
}

bool JournalLibrary::hasSyncedImage(const std::string &filename)
{
    const auto id = syncJournalID();
    if (!id)
        return false;
    return hasImageFor(*id, filename);
}

bool JournalLibrary::hasImageFor(const Uuid &journalID, const std::string &filename)
{
    if (!JournalImageFilename::isValid(filename))
        return false;
    std::error_code ec;
    return std::filesystem::exists(m_paths.imagesDirectory(journalID) / filename, ec);
}

void JournalLibrary::storeSyncedImage(const std::string &filename, std::string_view data,
                                      const Uuid &journalID)
{
    if (!JournalImageFilename::isValid(filename))
        return;
    wick::atomicWriteFile(m_paths.imagesDirectory(journalID) / filename, data);
}

std::optional<wick::JournalTradingSnapshotDocument> JournalLibrary::syncedTradingSnapshot(const Uuid &journalID)
{
    const auto path = m_paths.tradingJSON(journalID);
    std::error_code ec;
    if (!std::filesystem::exists(path, ec))
        return std::nullopt;
    const auto bytes = wick::readFileBytes(path);
    if (!bytes)
        return std::nullopt;
    const auto snap = wick::TradingPositionSnapshot::decode(*bytes);
    if (!snap)
        return std::nullopt;

    wick::JournalTradingSnapshotDocument doc;
    doc.journalID = journalID;
    doc.venue = snap->sourceVenue.value_or("unknown");
    doc.accountLabel = snap->sourceAccountLabel.value_or("");
    doc.fetchedAtMilliseconds = snap->fetchedAt;
    doc.payload = *bytes;
    return doc;
}

void JournalLibrary::applySyncedTradingSnapshot(const wick::JournalTradingSnapshotDocument &document, const Uuid &journalID)
{
    if (m_catalogReadOnly || document.payload.empty())
        return;
    const auto path = m_paths.tradingJSON(journalID);
    m_paths.ensureJournalDirectories(journalID);
    wick::atomicWriteFile(path, document.payload);
    if (journalID == m_catalog.activeJournalID) {
        refreshTradingPositions();
    }
}

void JournalLibrary::removeSyncedTradingSnapshot(const Uuid &journalID)
{
    if (m_catalogReadOnly)
        return;
    const auto path = m_paths.tradingJSON(journalID);
    std::error_code ec;
    std::filesystem::remove(path, ec);
    if (journalID == m_catalog.activeJournalID) {
        refreshTradingPositions();
    }
}
