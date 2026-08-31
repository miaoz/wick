#pragma once

#include "JournalCatalog.h"
#include "JournalPaths.h"
#include "JournalLocalSource.h"
#include "JournalStore.h"
#include "TradingModels.h"

#include <QDate>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

/// QObject surface for the journal window. Owns catalog + active JournalFileStore.
class JournalLibrary : public QObject, public wick::JournalLocalSource
{
    Q_OBJECT

    Q_PROPERTY(QVariantList journals READ journals NOTIFY journalsChanged)
    Q_PROPERTY(QVariantList tags READ tags NOTIFY tagsChanged)
    Q_PROPERTY(QVariantList days READ days NOTIFY daysChanged)
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QVariantList calendarDays READ calendarDays NOTIFY calendarChanged)

    Q_PROPERTY(QString activeJournalId READ activeJournalId NOTIFY journalsChanged)
    Q_PROPERTY(QString activeJournalName READ activeJournalName NOTIFY journalsChanged)
    Q_PROPERTY(QString selectedEntryId READ selectedEntryId NOTIFY selectionChanged)
    Q_PROPERTY(QString selectedDayKey READ selectedDayKey NOTIFY selectionChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)

    Q_PROPERTY(bool isReadOnly READ isReadOnly NOTIFY readOnlyChanged)
    Q_PROPERTY(bool isCatalogReadOnly READ isCatalogReadOnly NOTIFY readOnlyChanged)
    Q_PROPERTY(QString errorBanner READ errorBanner NOTIFY bannersChanged)
    Q_PROPERTY(QString restoreBanner READ restoreBanner NOTIFY bannersChanged)

    Q_PROPERTY(QString pageDateLabel READ pageDateLabel NOTIFY selectionChanged)
    Q_PROPERTY(QString pageWeekday READ pageWeekday NOTIFY selectionChanged)
    Q_PROPERTY(QString pageLunar READ pageLunar NOTIFY selectionChanged)
    Q_PROPERTY(bool pageHasPnl READ pageHasPnl NOTIFY selectionChanged)
    Q_PROPERTY(QString pagePnlText READ pagePnlText NOTIFY selectionChanged)
    Q_PROPERTY(double pagePnl READ pagePnl NOTIFY selectionChanged)
    Q_PROPERTY(QString selectedDayStamp READ selectedDayStamp NOTIFY selectionChanged)
    Q_PROPERTY(QString pageSavedState READ pageSavedState NOTIFY savedStateChanged)
    Q_PROPERTY(double pageBurnElapsed READ pageBurnElapsed NOTIFY selectionChanged)
    Q_PROPERTY(bool pageIsToday READ pageIsToday NOTIFY selectionChanged)
    Q_PROPERTY(bool pageReviewEligible READ pageReviewEligible NOTIFY selectionChanged)
    Q_PROPERTY(bool hasSelectedDay READ hasSelectedDay NOTIFY selectionChanged)

    Q_PROPERTY(QString todayDateLabel READ todayDateLabel NOTIFY calendarChanged)
    Q_PROPERTY(QString todayWeekday READ todayWeekday NOTIFY calendarChanged)
    Q_PROPERTY(QString todayLunar READ todayLunar NOTIFY calendarChanged)
    Q_PROPERTY(bool todayIsWeekend READ todayIsWeekend NOTIFY calendarChanged)
    Q_PROPERTY(QString calendarMonthLabel READ calendarMonthLabel NOTIFY calendarChanged)
    Q_PROPERTY(bool hasCalendarMonthPnl READ hasCalendarMonthPnl NOTIFY calendarChanged)
    Q_PROPERTY(QString calendarMonthPnlText READ calendarMonthPnlText NOTIFY calendarChanged)
    Q_PROPERTY(double calendarMonthPnl READ calendarMonthPnl NOTIFY calendarChanged)

    Q_PROPERTY(int columnMode READ columnMode WRITE setColumnMode NOTIFY layoutChanged)
    Q_PROPERTY(bool inspectorVisible READ inspectorVisible WRITE setInspectorVisible NOTIFY layoutChanged)

public:
    explicit JournalLibrary(QObject *parent = nullptr);
    explicit JournalLibrary(wick::JournalPaths paths, QObject *parent = nullptr);

    void bootstrap();

    QVariantList journals() const;
    QVariantList tags() const;
    QVariantList days() const;
    QVariantList items() const;
    QVariantList calendarDays() const;

    QString activeJournalId() const;
    QString activeJournalName() const;
    QString selectedEntryId() const { return m_selectedEntryId; }
    QString selectedDayKey() const;
    QString searchText() const { return m_searchText; }
    void setSearchText(const QString &text);

    bool isReadOnly() const;
    bool isCatalogReadOnly() const { return m_catalogReadOnly; }
    QString errorBanner() const { return m_errorBanner; }
    QString restoreBanner() const { return m_restoreBanner; }

    QString pageDateLabel() const;
    QString pageWeekday() const;
    QString pageLunar() const;
    bool pageHasPnl() const;
    QString pagePnlText() const;
    double pagePnl() const;
    QString selectedDayStamp() const;
    QString pageSavedState() const;
    double pageBurnElapsed() const;
    bool pageIsToday() const;
    bool pageReviewEligible() const;
    bool hasSelectedDay() const;

    QString todayDateLabel() const;
    QString todayWeekday() const;
    QString todayLunar() const;
    bool todayIsWeekend() const;
    QString calendarMonthLabel() const;
    bool hasCalendarMonthPnl() const;
    QString calendarMonthPnlText() const;
    double calendarMonthPnl() const;

    int columnMode() const { return m_columnMode; }
    void setColumnMode(int mode);
    bool inspectorVisible() const { return m_inspectorVisible; }
    void setInspectorVisible(bool visible);

    enum class RemoteDeleteResult {
        deleted,
        notFound,
        refusedReadOnly,
        ioFailure
    };

    Q_INVOKABLE void selectJournal(const QString &id);
    Q_INVOKABLE void addJournal(const QString &name);
    Q_INVOKABLE bool renameJournal(const QString &id, const QString &name);
    Q_INVOKABLE bool deleteJournal(const QString &id);
    RemoteDeleteResult deleteJournalFromRemote(const wick::Uuid &id);
    Q_INVOKABLE bool moveJournal(int fromIndex, int toIndex);
    void setExchangeBinding(const wick::Uuid &id, std::optional<wick::JournalExchangeBinding> binding);
    std::optional<wick::JournalExchangeBinding> exchangeBindingFor(const wick::Uuid &id) const;
    QString defaultJournalName() const;
    int ensurePositionEntries(const wick::Uuid &journalID,
                              const std::vector<std::pair<QDate, std::vector<wick::JournalItem>>> &skeletons);
    bool hasJournal(const wick::Uuid &id) const;
    std::vector<wick::Uuid> journalIds() const;
    std::optional<wick::JournalInfo> registerRemoteJournal(const wick::Uuid &id, const QString &name);
    Q_INVOKABLE void selectJournalByIndex(int index);
    Q_INVOKABLE void selectDay(const QString &entryId);
    Q_INVOKABLE void openOrCreateToday();
    Q_INVOKABLE void addItem();
    Q_INVOKABLE void addItemTo(const QString &entryId = QString());
    Q_INVOKABLE void deleteItem(const QString &itemId);
    Q_INVOKABLE void deleteEmptyItem(const QString &itemId);
    Q_INVOKABLE void deleteSelectedDay();
    Q_INVOKABLE void deleteDay(const QString &entryId);
    Q_INVOKABLE void setItemTag(const QString &itemId, const QString &tag);
    Q_INVOKABLE void setItemBody(const QString &itemId, const QString &body);
    Q_INVOKABLE void setItemReview(const QString &itemId, const QString &verdict, const QString &note = QString());
    Q_INVOKABLE void setItemReviewNote(const QString &itemId, const QString &note);
    Q_INVOKABLE void cycleColumns();
    Q_INVOKABLE void toggleInspector();
    Q_INVOKABLE void flushNow();
    Q_INVOKABLE void selectCalendarDay(const QString &dayKey);
    Q_INVOKABLE void shiftCalendarMonth(int delta);
    Q_INVOKABLE QString lunarLineFor(const QDate &date) const;

    Q_INVOKABLE QUrl imageFileUrl(const QString &filename) const;
    Q_INVOKABLE QString addImageFromUrl(const QString &itemId, const QUrl &fileUrl);
    Q_INVOKABLE bool pasteClipboardImage(const QString &itemId);
    Q_INVOKABLE void removeImage(const QString &itemId, const QString &filename);
    Q_INVOKABLE QString exportArchiveTo(const QUrl &destination);
    Q_INVOKABLE QString importArchiveFrom(const QUrl &source);

    const wick::JournalPaths &paths() const { return m_paths; }
    void refreshTradingPositions();

    // JournalLocalSource (engine; Qt-free tests use FakeLocalSource)
    std::optional<wick::Uuid> syncJournalID() const override;
    std::string syncJournalName() const override;
    std::string journalNameFor(const wick::Uuid &id) const;
    bool syncIsWritable() const override;
    bool journalWritable(const wick::Uuid &id) const;
    std::map<wick::Uuid, wick::JournalEntry> syncEntrySnapshots() override;
    std::map<wick::Uuid, wick::JournalEntry> entrySnapshotsFor(const wick::Uuid &journalID);
    std::optional<wick::JournalEntry> syncEntrySnapshot(const wick::Uuid &entryID) override;
    std::optional<wick::JournalEntry> entrySnapshotFor(const wick::Uuid &journalID, const wick::Uuid &entryID);
    std::set<std::string> imageFilenamesFor(const wick::Uuid &journalID);
    std::optional<std::string> imageDataFor(const wick::Uuid &journalID, const std::string &filename);
    bool hasImageFor(const wick::Uuid &journalID, const std::string &filename);
    void prepareForRemoteApply(const wick::Uuid &entryID) override;
    std::set<wick::Uuid> applySyncedChanges(const std::vector<wick::JournalSyncMutation> &changes,
                                            const wick::Uuid &journalID) override;
    void applySyncedEntry(const wick::JournalEntry &entry, const wick::Uuid &journalID) override;
    void removeSyncedEntry(const wick::Uuid &entryID, const wick::Uuid &journalID) override;
    std::string applySyncedJournalName(const std::string &name, const wick::Uuid &journalID) override;
    std::set<std::string> syncedImageFilenames() override;
    std::optional<std::string> syncedImageData(const std::string &filename) override;
    bool hasSyncedImage(const std::string &filename) override;
    void storeSyncedImage(const std::string &filename, std::string_view data,
                          const wick::Uuid &journalID) override;

    bool syncTradingSnapshotEnabled() const override { return true; }
    std::optional<wick::JournalTradingSnapshotDocument> syncedTradingSnapshot(const wick::Uuid &journalID) override;
    void applySyncedTradingSnapshot(const wick::JournalTradingSnapshotDocument &document, const wick::Uuid &journalID) override;
    void removeSyncedTradingSnapshot(const wick::Uuid &journalID) override;

public slots:
    void persistSoon();

signals:
    void journalContentChanged();
    void journalsChanged();
    void activeJournalChanged();
    void tagsChanged();
    void daysChanged();
    void itemsChanged();
    void calendarChanged();
    void selectionChanged();
    void searchTextChanged();
    void readOnlyChanged();
    void bannersChanged();
    void savedStateChanged();
    void layoutChanged();
    void journalDeletedLocally(const wick::Uuid &id);

private:
    wick::TimePoint nowTp() const;
    int tzOffsetSeconds() const;
    QDate dateOf(const wick::JournalEntry &entry) const;
    QDate dateOf(wick::TimePoint tp) const;
    wick::TimePoint startOfDay(const QDate &date) const;
    std::string dayKeyOf(const wick::JournalEntry &entry) const;
    std::string dayKeyOf(const QDate &date) const;
    QString weekdayName(const QDate &date) const;
    QString bigDateLabel(const QDate &date) const;
    QString monthLabel(int month) const;

    wick::JournalEntry *selectedEntry();
    const wick::JournalEntry *selectedEntry() const;
    std::pair<wick::JournalEntry *, wick::JournalItem *> findItemAndEntry(const QString &itemId);
    wick::JournalItem *findItem(const QString &itemId);
    const wick::JournalItem *findItem(const QString &itemId) const;
    QVariantList itemsForEntry(const wick::JournalEntry &entry) const;
    bool itemMatchesSearch(const wick::JournalEntry &entry, const wick::JournalItem &item) const;
    bool entryMatchesSearch(const wick::JournalEntry &entry) const;
    bool itemIsEmpty(const wick::JournalItem &item) const;
    QString uniquifyName(const QString &base) const;
    QString uniquifyName(const QString &base, const wick::Uuid &excluding) const;

    void bindActive(const wick::Uuid &id);
    void seedDefaultJournal();
    void applyCatalog(const wick::JournalCatalogSnapshot &catalog, bool restoredFromBackup);
    void enterCatalogReadOnly(const QString &message);
    bool writeCatalog();
    void persistActive();
    void schedulePersist();
    void rebuildAfterStructuralChange();
    void ensureSelection();
    void emitPageAndCalendar();
    void touchActiveJournalMetadata();
    QString recoverCatalogFromScratch();
    void invalidateDaysCache();

    struct InactiveCountsCache {
        std::filesystem::file_time_type journalMtime{};
        int entryCount = 0;
        std::filesystem::file_time_type tradingMtime{};
        int positionsCount = 0;
    };

    wick::JournalPaths m_paths;
    wick::JournalCatalogSnapshot m_catalog;
    std::unique_ptr<wick::JournalFileStore> m_store;

    mutable std::optional<QVariantList> m_cachedDays;
    mutable std::map<wick::Uuid, InactiveCountsCache> m_inactiveCountsCache;

    QString m_selectedEntryId;
    QString m_searchText;
    QString m_errorBanner;
    QString m_restoreBanner;
    QString m_savedState;
    bool m_catalogReadOnly = false;
    bool m_dirty = false;
    int m_columnMode = 0;
    bool m_inspectorVisible = true;
    QDate m_calendarMonth;
    QTimer m_saveTimer;
    std::vector<wick::TradingPosition> m_tradingPositions;
};
