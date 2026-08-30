#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QStringList>
#include <QUrl>

class QNetworkAccessManager;
class QNetworkReply;

/// UserDefaults-compatible prefs (org wick / app 秉烛). Keys match Mac AppSettings.
class AppSettings : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString appearance READ appearance WRITE setAppearance NOTIFY appearanceChanged)
    Q_PROPERTY(QString phase READ phase WRITE setPhase NOTIFY phaseChanged)
    Q_PROPERTY(QString pnlColorConvention READ pnlColorConvention WRITE setPnlColorConvention
               NOTIFY pnlColorConventionChanged)
    Q_PROPERTY(QString journalFontName READ journalFontName WRITE setJournalFontName
               NOTIFY journalFontNameChanged)

    Q_PROPERTY(bool reminderEnabled READ reminderEnabled WRITE setReminderEnabled
               NOTIFY reminderChanged)
    Q_PROPERTY(int reminderHour READ reminderHour WRITE setReminderHour NOTIFY reminderChanged)
    Q_PROPERTY(int reminderMinute READ reminderMinute WRITE setReminderMinute NOTIFY reminderChanged)

    Q_PROPERTY(bool showMenuBarPercentage READ showMenuBarPercentage WRITE setShowMenuBarPercentage
               NOTIFY showMenuBarPercentageChanged)
    Q_PROPERTY(bool weekStartsOnMonday READ weekStartsOnMonday WRITE setWeekStartsOnMonday
               NOTIFY weekStartsOnMondayChanged)
    Q_PROPERTY(bool launchAtLogin READ launchAtLogin WRITE setLaunchAtLogin
               NOTIFY launchAtLoginChanged)
    Q_PROPERTY(QString launchAtLoginNote READ launchAtLoginNote NOTIFY launchAtLoginChanged)

    Q_PROPERTY(bool checkForUpdatesAutomatically READ checkForUpdatesAutomatically
               WRITE setCheckForUpdatesAutomatically NOTIFY checkForUpdatesAutomaticallyChanged)

    Q_PROPERTY(bool syncEnabled READ syncEnabled WRITE setSyncEnabled NOTIFY syncChanged)
    Q_PROPERTY(bool syncTradingSnapshots READ syncTradingSnapshots WRITE setSyncTradingSnapshots
               NOTIFY syncChanged)
    Q_PROPERTY(QString exchangeJournalId READ exchangeJournalId WRITE setExchangeJournalId
               NOTIFY exchangeChanged)
    Q_PROPERTY(QString exchangeVenue READ exchangeVenue WRITE setExchangeVenue NOTIFY exchangeChanged)

    Q_PROPERTY(QString resolvedScheme READ resolvedScheme NOTIFY appearanceChanged)
    Q_PROPERTY(bool isChinese READ isChinese NOTIFY languageChanged)
    Q_PROPERTY(QString appVersion READ appVersion CONSTANT)
    Q_PROPERTY(QString dataStatusText READ dataStatusText NOTIFY dataStatusChanged)
    Q_PROPERTY(QString updateStatusText READ updateStatusText NOTIFY updateStatusChanged)
    Q_PROPERTY(bool isCheckingUpdates READ isCheckingUpdates NOTIFY updateStatusChanged)
    Q_PROPERTY(QStringList fontFamilies READ fontFamilies NOTIFY fontFamiliesChanged)
    Q_PROPERTY(bool omarchyAvailable READ omarchyAvailable NOTIFY omarchyChanged)
    Q_PROPERTY(QString omarchyThemeName READ omarchyThemeName NOTIFY omarchyChanged)
    Q_PROPERTY(QVariantMap omarchyColors READ omarchyColors NOTIFY omarchyChanged)

public:
    static AppSettings *instance();

    explicit AppSettings(QObject *parent = nullptr);

    QString language() const { return m_language; }
    void setLanguage(const QString &value);

    QString appearance() const { return m_appearance; }
    void setAppearance(const QString &value);

    QString phase() const { return m_phase; }
    void setPhase(const QString &value);

    QString pnlColorConvention() const { return m_pnlColorConvention; }
    void setPnlColorConvention(const QString &value);

    QString journalFontName() const { return m_journalFontName; }
    void setJournalFontName(const QString &value);

    bool reminderEnabled() const { return m_reminderEnabled; }
    void setReminderEnabled(bool value);
    int reminderHour() const { return m_reminderHour; }
    void setReminderHour(int value);
    int reminderMinute() const { return m_reminderMinute; }
    void setReminderMinute(int value);

    bool showMenuBarPercentage() const { return m_showMenuBarPercentage; }
    void setShowMenuBarPercentage(bool value);

    bool weekStartsOnMonday() const { return m_weekStartsOnMonday; }
    void setWeekStartsOnMonday(bool value);

    bool launchAtLogin() const { return m_launchAtLogin; }
    void setLaunchAtLogin(bool value);
    QString launchAtLoginNote() const { return m_launchAtLoginNote; }

    bool checkForUpdatesAutomatically() const { return m_checkForUpdatesAutomatically; }
    void setCheckForUpdatesAutomatically(bool value);

    bool syncEnabled() const { return m_syncEnabled; }
    void setSyncEnabled(bool value);
    bool syncTradingSnapshots() const { return m_syncTradingSnapshots; }
    void setSyncTradingSnapshots(bool value);

    QString exchangeJournalId() const { return m_exchangeJournalId; }
    void setExchangeJournalId(const QString &value);
    QString exchangeVenue() const { return m_exchangeVenue; }
    void setExchangeVenue(const QString &value);

    QString resolvedScheme() const;
    bool isChinese() const { return m_language != QLatin1String("en"); }
    QString appVersion() const;
    QString dataStatusText() const { return m_dataStatusText; }
    QString updateStatusText() const { return m_updateStatusText; }
    bool isCheckingUpdates() const { return m_checkingUpdates; }
    QStringList fontFamilies() const { return m_fontFamilies; }
    bool omarchyAvailable() const { return m_omarchyAvailable; }
    QString omarchyThemeName() const { return m_omarchyThemeName; }
    QVariantMap omarchyColors() const { return m_omarchyColors; }

    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void openReleasesPage();
    Q_INVOKABLE void revealDataDirectory();
    Q_INVOKABLE void stubExport();
    Q_INVOKABLE void stubImport();
    Q_INVOKABLE void setDataStatus(const QString &text);
    Q_INVOKABLE QString t(const QString &zh, const QString &en) const;
    Q_INVOKABLE QString importFontFile(const QUrl &fileUrl);

signals:
    void languageChanged();
    void appearanceChanged();
    void phaseChanged();
    void pnlColorConventionChanged();
    void journalFontNameChanged();
    void reminderChanged();
    void showMenuBarPercentageChanged();
    void weekStartsOnMondayChanged();
    void launchAtLoginChanged();
    void checkForUpdatesAutomaticallyChanged();
    void syncChanged();
    void exchangeChanged();
    void dataStatusChanged();
    void updateStatusChanged();
    void fontFamiliesChanged();
    void omarchyChanged();

private:
    void load();
    void loadApplicationFonts();
    void refreshFontFamilies();
    void initOmarchyWatcher();
    void reloadOmarchyTheme();
    void write(const QString &key, const QVariant &value);
    bool hasKey(const QString &key) const;
    void applyLaunchAtLogin();
    void finishUpdateCheck(QNetworkReply *reply);

    QSettings m_store;
    QString m_language;
    QString m_appearance;
    QString m_phase;
    QString m_pnlColorConvention;
    QString m_journalFontName;
    bool m_reminderEnabled = true;
    int m_reminderHour = 21;
    int m_reminderMinute = 0;
    bool m_showMenuBarPercentage = true;
    bool m_weekStartsOnMonday = false;
    bool m_launchAtLogin = false;
    QString m_launchAtLoginNote;
    bool m_checkForUpdatesAutomatically = true;
    bool m_syncEnabled = false;
    bool m_syncTradingSnapshots = false;
    QString m_exchangeJournalId;
    QString m_exchangeVenue;
    QString m_dataStatusText;
    QString m_updateStatusText;
    bool m_checkingUpdates = false;
    QStringList m_fontFamilies;
    bool m_omarchyAvailable = false;
    QString m_omarchyThemeName;
    QVariantMap m_omarchyColors;
    class QFileSystemWatcher *m_omarchyWatcher = nullptr;
    class QTimer *m_omarchyDebounceTimer = nullptr;
    QNetworkAccessManager *m_nam = nullptr;
};

class LaunchAtLogin
{
public:
    struct Result {
        bool ok = false;
        QString note;
    };

    static Result setEnabled(bool enabled);
    static QString unitPath();
    static QString unitContents(const QString &execPath);
};
