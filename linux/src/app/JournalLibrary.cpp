#include "JournalLibrary.h"
#include "JournalSyncEncoding.h"
#include "LunarCalendar.h"

#include <QDateTime>
#include <QHash>
#include <QTimeZone>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <variant>

using wick::JournalCatalogLoader;
using wick::JournalCatalogSnapshot;
using wick::JournalDayKey;
using wick::JournalEntry;
using wick::JournalFileStore;
using wick::JournalImageFilename;
using wick::JournalInfo;
using wick::JournalItem;
using wick::JournalReview;
using wick::JournalReviewVerdict;
using wick::TimePoint;
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
    ensureSelection();
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
    static const char *kNames[] = {"", "周一", "周二", "周三", "周四", "周五", "周六", "周日"};
    const int d = date.dayOfWeek();
    if (d < 1 || d > 7)
        return {};
    return QString::fromUtf8(kNames[d]);
}

QString JournalLibrary::bigDateLabel(const QDate &date) const
{
    return QStringLiteral("%1月%2日").arg(date.month()).arg(date.day());
}

QString JournalLibrary::monthLabel(int month) const
{
    static const char *kNames[] = {
        "", "一月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "十一月", "十二月"};
    if (month < 1 || month > 12)
        return {};
    return QString::fromUtf8(kNames[month]);
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

JournalItem *JournalLibrary::findItem(const QString &itemId)
{
    auto *entry = selectedEntry();
    if (!entry)
        return nullptr;
    const auto id = parseUuid(itemId);
    if (!id)
        return nullptr;
    for (auto &item : entry->items) {
        if (item.id == *id)
            return &item;
    }
    return nullptr;
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
        row.insert(QStringLiteral("entryCount"), count);
        row.insert(QStringLiteral("isActive"), j.id == m_catalog.activeJournalID);
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

    int lastYear = 0;
    int lastMonth = 0;
    for (const auto *e : rows) {
        const QDate d = dateOf(*e);
        QVariantMap row;
        row.insert(QStringLiteral("entryId"), qs(e->id.toString()));
        row.insert(QStringLiteral("dayKey"), qs(dayKeyOf(*e)));
        row.insert(QStringLiteral("dateLabel"), bigDateLabel(d));
        row.insert(QStringLiteral("weekday"), weekdayName(d));
        row.insert(QStringLiteral("itemCount"), static_cast<int>(e->items.size()));
        row.insert(QStringLiteral("year"), d.year());
        row.insert(QStringLiteral("monthLabel"), monthLabel(d.month()));
        const bool header = (d.year() != lastYear || d.month() != lastMonth);
        row.insert(QStringLiteral("showMonthHeader"), header);
        lastYear = d.year();
        lastMonth = d.month();

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
        row.insert(QStringLiteral("isSelected"), qs(e->id.toString()) == m_selectedEntryId);
        out.push_back(row);
    }
    return out;
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

    QHash<QString, QString> stateByKey; // journaled / up / down
    if (m_store) {
        for (const auto &e : m_store->entries) {
            const QString key = qs(dayKeyOf(e));
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
            QString state = QStringLiteral("journaled");
            // 绿涨红跌: correct → gain (dai), wrong → loss (cinnabar)
            if (hasWrong)
                state = QStringLiteral("down");
            else if (hasCorrect)
                state = QStringLiteral("up");
            stateByKey.insert(key, state);
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
        cell.insert(QStringLiteral("state"), stateByKey.value(key, QStringLiteral("empty")));
        cell.insert(QStringLiteral("isToday"), d == today);
        cell.insert(QStringLiteral("isFuture"), d > today);
        cell.insert(QStringLiteral("hasEntry"), stateByKey.contains(key));
        out.push_back(cell);
    }
    return out;
}

QVariantList JournalLibrary::items() const
{
    QVariantList out;
    const auto *entry = selectedEntry();
    if (!entry)
        return out;
    int index = 0;
    for (const auto &item : entry->items) {
        ++index;
        if (!itemMatchesSearch(*entry, item))
            continue;
        QVariantMap row;
        row.insert(QStringLiteral("itemId"), qs(item.id.toString()));
        row.insert(QStringLiteral("index"), index);
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
        out.push_back(row);
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

QString JournalLibrary::pageSavedState() const
{
    if (isReadOnly())
        return QStringLiteral("只读");
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
    return QStringLiteral("%1年%2月").arg(m_calendarMonth.year()).arg(m_calendarMonth.month());
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
    if (isReadOnly())
        return;
    auto *entry = selectedEntry();
    if (!entry)
        return;
    JournalItem item;
    item.id = Uuid::generate();
    entry->items.push_back(item);
    entry->updatedAt = nowTp();
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::deleteEmptyItem(const QString &itemId)
{
    if (isReadOnly())
        return;
    auto *entry = selectedEntry();
    if (!entry)
        return;
    const auto id = parseUuid(itemId);
    if (!id)
        return;
    auto it = std::find_if(entry->items.begin(), entry->items.end(),
                           [&](const JournalItem &item) { return item.id == *id; });
    if (it == entry->items.end())
        return;
    if (!itemIsEmpty(*it))
        return;
    entry->items.erase(it);
    if (entry->items.empty()) {
        const Uuid entryId = entry->id;
        m_store->entries.erase(
            std::remove_if(m_store->entries.begin(), m_store->entries.end(),
                           [&](const JournalEntry &e) { return e.id == entryId; }),
            m_store->entries.end());
        m_selectedEntryId.clear();
        ensureSelection();
    } else {
        entry->updatedAt = nowTp();
    }
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::setItemTag(const QString &itemId, const QString &tag)
{
    if (isReadOnly())
        return;
    auto *item = findItem(itemId);
    auto *entry = selectedEntry();
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
    auto *item = findItem(itemId);
    auto *entry = selectedEntry();
    if (!item || !entry)
        return;
    const std::string next = ss(body);
    if (item->body == next)
        return;
    item->body = next;
    entry->updatedAt = nowTp();
    schedulePersist();
}

void JournalLibrary::setItemReview(const QString &itemId, const QString &verdict)
{
    if (isReadOnly())
        return;
    auto *item = findItem(itemId);
    auto *entry = selectedEntry();
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
    for (const auto &j : m_catalog.journals) {
        if (j.id == m_catalog.activeJournalID)
            return j.name;
    }
    return {};
}

bool JournalLibrary::syncIsWritable() const
{
    return !isReadOnly() && !m_catalogReadOnly;
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
    if (!(journalID == m_catalog.activeJournalID) || !m_store || isReadOnly())
        return {};
    flushNow();
    std::set<Uuid> applied;
    for (const auto &change : changes) {
        if (!localHashMatches(m_store->entries, change.entryID, change.expectedLocalHash))
            continue;
        if (change.kind == JournalSyncMutation::Kind::upsert) {
            JournalEntry appliedEntry = change.entry;
            if (appliedEntry.items.empty())
                appliedEntry.items.push_back(JournalItem{Uuid::generate(), "", "", {}, std::nullopt});
            bool found = false;
            for (auto &e : m_store->entries) {
                if (e.id == appliedEntry.id) {
                    e = appliedEntry;
                    found = true;
                    break;
                }
            }
            if (!found)
                m_store->entries.push_back(appliedEntry);
            applied.insert(change.entryID);
        } else {
            for (auto it = m_store->entries.begin(); it != m_store->entries.end(); ++it) {
                if (it->id == change.entryID) {
                    m_store->entries.erase(it);
                    applied.insert(change.entryID);
                    break;
                }
            }
        }
    }
    if (applied.empty())
        return {};
    persistActive();
    rebuildAfterStructuralChange();
    return applied;
}

void JournalLibrary::applySyncedEntry(const JournalEntry &entry, const Uuid &journalID)
{
    if (!(journalID == m_catalog.activeJournalID) || !m_store || isReadOnly())
        return;
    flushNow();
    JournalEntry applied = entry;
    if (applied.items.empty())
        applied.items.push_back(JournalItem{Uuid::generate(), "", "", {}, std::nullopt});
    bool found = false;
    for (auto &e : m_store->entries) {
        if (e.id == applied.id) {
            e = applied;
            found = true;
            break;
        }
    }
    if (!found)
        m_store->entries.push_back(applied);
    persistActive();
    rebuildAfterStructuralChange();
}

void JournalLibrary::removeSyncedEntry(const Uuid &entryID, const Uuid &journalID)
{
    if (!(journalID == m_catalog.activeJournalID) || !m_store || isReadOnly())
        return;
    for (auto it = m_store->entries.begin(); it != m_store->entries.end(); ++it) {
        if (it->id == entryID) {
            m_store->entries.erase(it);
            persistActive();
            rebuildAfterStructuralChange();
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
    if (!(journalID == m_catalog.activeJournalID) || index < 0)
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
    std::set<std::string> out;
    if (!m_store)
        return out;
    for (const auto &e : m_store->entries) {
        for (const auto &item : e.items) {
            for (const auto &f : item.imageFilenames)
                out.insert(f);
        }
    }
    return out;
}

std::optional<std::string> JournalLibrary::syncedImageData(const std::string &filename)
{
    if (!JournalImageFilename::isValid(filename))
        return std::nullopt;
    const auto id = syncJournalID();
    if (!id)
        return std::nullopt;
    return wick::readFileBytes(m_paths.imagesDirectory(*id) / filename);
}

bool JournalLibrary::hasSyncedImage(const std::string &filename)
{
    if (!JournalImageFilename::isValid(filename))
        return false;
    const auto id = syncJournalID();
    if (!id)
        return false;
    std::error_code ec;
    return std::filesystem::exists(m_paths.imagesDirectory(*id) / filename, ec);
}

void JournalLibrary::storeSyncedImage(const std::string &filename, std::string_view data,
                                      const Uuid &journalID)
{
    if (!(journalID == m_catalog.activeJournalID))
        return;
    if (!JournalImageFilename::isValid(filename))
        return;
    wick::atomicWriteFile(m_paths.imagesDirectory(journalID) / filename, data);
}
