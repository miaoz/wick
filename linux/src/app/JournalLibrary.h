#pragma once

#include "JournalCatalog.h"
#include "JournalPaths.h"
#include "JournalStore.h"

#include <QDate>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariant>
#include <QVariantList>
#include <QVariantMap>

#include <memory>
#include <optional>
#include <string>

/// QObject surface for the journal window. Owns catalog + active JournalFileStore.
class JournalLibrary : public QObject
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

    int columnMode() const { return m_columnMode; }
    void setColumnMode(int mode);
    bool inspectorVisible() const { return m_inspectorVisible; }
    void setInspectorVisible(bool visible);

    Q_INVOKABLE void selectJournal(const QString &id);
    Q_INVOKABLE void addJournal(const QString &name);
    Q_INVOKABLE void selectDay(const QString &entryId);
    Q_INVOKABLE void openOrCreateToday();
    Q_INVOKABLE void addItem();
    Q_INVOKABLE void deleteEmptyItem(const QString &itemId);
    Q_INVOKABLE void setItemTag(const QString &itemId, const QString &tag);
    Q_INVOKABLE void setItemBody(const QString &itemId, const QString &body);
    Q_INVOKABLE void setItemReview(const QString &itemId, const QString &verdict);
    Q_INVOKABLE void cycleColumns();
    Q_INVOKABLE void toggleInspector();
    Q_INVOKABLE void flushNow();
    Q_INVOKABLE void selectCalendarDay(const QString &dayKey);
    Q_INVOKABLE void shiftCalendarMonth(int delta);
    Q_INVOKABLE QString lunarLineFor(const QDate &date) const;

    Q_INVOKABLE QUrl imageFileUrl(const QString &filename) const;
    Q_INVOKABLE QStringList itemImageFilenames(const QString &itemId) const;
    Q_INVOKABLE QString addImageFromUrl(const QString &itemId, const QUrl &fileUrl);
    Q_INVOKABLE void removeImage(const QString &itemId, const QString &filename);
    // Empty string = success; otherwise an error message.
    Q_INVOKABLE QString exportArchiveTo(const QUrl &destination);
    Q_INVOKABLE QString importArchiveFrom(const QUrl &source);

public slots:
    void persistSoon();

signals:
    void journalsChanged();
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
    wick::JournalItem *findItem(const QString &itemId);
    const wick::JournalItem *findItem(const QString &itemId) const;
    bool itemMatchesSearch(const wick::JournalEntry &entry, const wick::JournalItem &item) const;
    bool entryMatchesSearch(const wick::JournalEntry &entry) const;
    bool itemIsEmpty(const wick::JournalItem &item) const;
    QString uniquifyName(const QString &base) const;

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

    wick::JournalPaths m_paths;
    wick::JournalCatalogSnapshot m_catalog;
    std::unique_ptr<wick::JournalFileStore> m_store;

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
};
