#include "AppSettings.h"

#include "JournalPaths.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QStandardPaths>
#include <QStyleHints>
#include <QUrl>
#include <QVariant>
#include <QtGlobal>

#include <algorithm>

namespace {

constexpr auto kLanguage = "wick.language";
constexpr auto kAppearance = "wick.appearance";
constexpr auto kPhase = "wick.phase";
constexpr auto kPnl = "wick.pnlColorConvention";
constexpr auto kFont = "wick.journal.fontName";
constexpr auto kReminderEnabled = "wick.journal.reminderEnabled";
constexpr auto kReminderHour = "wick.journal.reminderHour";
constexpr auto kReminderMinute = "wick.journal.reminderMinute";
constexpr auto kShowPct = "wick.menubar.showPercentage";
constexpr auto kLaunch = "wick.launchAtLogin";
constexpr auto kUpdates = "wick.updates.checkAutomatically";
constexpr auto kWeekMon = "wick.calendar.weekStartsOnMonday";
constexpr auto kSync = "wick.sync.enabled";
constexpr auto kSnapshots = "wick.sync.tradingSnapshots";
constexpr auto kExJournal = "wick.exchange.journalId";
constexpr auto kExVenue = "wick.exchange.venue";

QString normalizeLanguage(const QString &raw)
{
    if (raw == QLatin1String("en") || raw.startsWith(QLatin1String("en")))
        return QStringLiteral("en");
    return QStringLiteral("zh-Hans");
}

QString normalizeAppearance(const QString &raw)
{
    if (raw == QLatin1String("light") || raw == QLatin1String("system"))
        return raw;
    return QStringLiteral("dark");
}

QString normalizePhase(const QString &raw)
{
    if (raw == QLatin1String("dawn") || raw == QLatin1String("day")
        || raw == QLatin1String("dusk") || raw == QLatin1String("night"))
        return raw;
    return QStringLiteral("night");
}

QString normalizeConvention(const QString &raw)
{
    if (raw == QLatin1String("redUp"))
        return raw;
    return QStringLiteral("greenUp");
}

int versionParts(const QString &raw, int *out, int n)
{
    QString v = raw.trimmed();
    if (v.startsWith(QLatin1Char('v')) || v.startsWith(QLatin1Char('V')))
        v = v.mid(1);
    const int dash = v.indexOf(QLatin1Char('-'));
    if (dash >= 0)
        v = v.left(dash);
    const QStringList bits = v.split(QLatin1Char('.'));
    int count = 0;
    for (int i = 0; i < n; ++i)
        out[i] = 0;
    for (int i = 0; i < bits.size() && i < n; ++i) {
        bool ok = false;
        out[i] = bits[i].toInt(&ok);
        if (!ok)
            out[i] = 0;
        ++count;
    }
    return count;
}

bool isNewerVersion(const QString &candidate, const QString &current)
{
    int a[4]{};
    int b[4]{};
    versionParts(candidate, a, 4);
    versionParts(current, b, 4);
    for (int i = 0; i < 4; ++i) {
        if (a[i] != b[i])
            return a[i] > b[i];
    }
    return false;
}

} // namespace

AppSettings *AppSettings::instance()
{
    static AppSettings *s = nullptr;
    if (!s)
        s = new AppSettings(qApp);
    return s;
}

AppSettings::AppSettings(QObject *parent)
    : QObject(parent)
    , m_store(QStringLiteral("wick"), QStringLiteral("秉烛"))
{
    load();
    m_fontFamilies = QFontDatabase::families();
    std::sort(m_fontFamilies.begin(), m_fontFamilies.end(),
              [](const QString &a, const QString &b) { return a.localeAwareCompare(b) < 0; });

#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    if (auto *hints = QGuiApplication::styleHints()) {
        connect(hints, &QStyleHints::colorSchemeChanged, this, [this](Qt::ColorScheme) {
            if (m_appearance == QLatin1String("system"))
                emit appearanceChanged();
        });
    }
#endif
}

void AppSettings::load()
{
    m_language = normalizeLanguage(
        m_store.value(QLatin1String(kLanguage), QStringLiteral("zh-Hans")).toString());
    m_appearance = normalizeAppearance(
        m_store.value(QLatin1String(kAppearance), QStringLiteral("dark")).toString());
    m_phase = normalizePhase(
        m_store.value(QLatin1String(kPhase), QStringLiteral("night")).toString());
    m_pnlColorConvention = normalizeConvention(
        m_store.value(QLatin1String(kPnl), QStringLiteral("greenUp")).toString());
    m_journalFontName = m_store.value(QLatin1String(kFont), QString()).toString();

    if (!hasKey(QLatin1String(kReminderEnabled)))
        m_reminderEnabled = true;
    else
        m_reminderEnabled = m_store.value(QLatin1String(kReminderEnabled)).toBool();

    if (!hasKey(QLatin1String(kReminderHour)))
        m_reminderHour = 21;
    else
        m_reminderHour = std::clamp(m_store.value(QLatin1String(kReminderHour)).toInt(), 0, 23);

    if (!hasKey(QLatin1String(kReminderMinute)))
        m_reminderMinute = 0;
    else
        m_reminderMinute = std::clamp(m_store.value(QLatin1String(kReminderMinute)).toInt(), 0, 59);

    if (!hasKey(QLatin1String(kShowPct)))
        m_showMenuBarPercentage = true;
    else
        m_showMenuBarPercentage = m_store.value(QLatin1String(kShowPct)).toBool();

    if (!hasKey(QLatin1String(kWeekMon)))
        m_weekStartsOnMonday = false;
    else
        m_weekStartsOnMonday = m_store.value(QLatin1String(kWeekMon)).toBool();

    if (!hasKey(QLatin1String(kLaunch)))
        m_launchAtLogin = false;
    else
        m_launchAtLogin = m_store.value(QLatin1String(kLaunch)).toBool();

    if (!hasKey(QLatin1String(kUpdates)))
        m_checkForUpdatesAutomatically = true;
    else
        m_checkForUpdatesAutomatically = m_store.value(QLatin1String(kUpdates)).toBool();

    m_syncEnabled = m_store.value(QLatin1String(kSync), false).toBool();
    m_syncTradingSnapshots = m_store.value(QLatin1String(kSnapshots), false).toBool();
    m_exchangeJournalId = m_store.value(QLatin1String(kExJournal), QString()).toString();
    m_exchangeVenue = m_store.value(QLatin1String(kExVenue), QStringLiteral("binance")).toString();
}

bool AppSettings::hasKey(const QString &key) const
{
    return m_store.contains(key);
}

void AppSettings::write(const QString &key, const QVariant &value)
{
    m_store.setValue(key, value);
}

void AppSettings::setLanguage(const QString &value)
{
    const QString next = normalizeLanguage(value);
    if (next == m_language)
        return;
    m_language = next;
    write(QLatin1String(kLanguage), m_language);
    emit languageChanged();
}

void AppSettings::setAppearance(const QString &value)
{
    const QString next = normalizeAppearance(value);
    if (next == m_appearance)
        return;
    m_appearance = next;
    write(QLatin1String(kAppearance), m_appearance);
    emit appearanceChanged();
}

void AppSettings::setPhase(const QString &value)
{
    const QString next = normalizePhase(value);
    if (next == m_phase)
        return;
    m_phase = next;
    write(QLatin1String(kPhase), m_phase);
    emit phaseChanged();
}

void AppSettings::setPnlColorConvention(const QString &value)
{
    const QString next = normalizeConvention(value);
    if (next == m_pnlColorConvention)
        return;
    m_pnlColorConvention = next;
    write(QLatin1String(kPnl), m_pnlColorConvention);
    emit pnlColorConventionChanged();
}

void AppSettings::setJournalFontName(const QString &value)
{
    if (value == m_journalFontName)
        return;
    m_journalFontName = value;
    write(QLatin1String(kFont), m_journalFontName);
    emit journalFontNameChanged();
}

void AppSettings::setReminderEnabled(bool value)
{
    if (value == m_reminderEnabled)
        return;
    m_reminderEnabled = value;
    write(QLatin1String(kReminderEnabled), m_reminderEnabled);
    emit reminderChanged();
}

void AppSettings::setReminderHour(int value)
{
    value = std::clamp(value, 0, 23);
    if (value == m_reminderHour)
        return;
    m_reminderHour = value;
    write(QLatin1String(kReminderHour), m_reminderHour);
    emit reminderChanged();
}

void AppSettings::setReminderMinute(int value)
{
    value = std::clamp(value, 0, 59);
    if (value == m_reminderMinute)
        return;
    m_reminderMinute = value;
    write(QLatin1String(kReminderMinute), m_reminderMinute);
    emit reminderChanged();
}

void AppSettings::setShowMenuBarPercentage(bool value)
{
    if (value == m_showMenuBarPercentage)
        return;
    m_showMenuBarPercentage = value;
    write(QLatin1String(kShowPct), m_showMenuBarPercentage);
    emit showMenuBarPercentageChanged();
}

void AppSettings::setWeekStartsOnMonday(bool value)
{
    if (value == m_weekStartsOnMonday)
        return;
    m_weekStartsOnMonday = value;
    write(QLatin1String(kWeekMon), m_weekStartsOnMonday);
    emit weekStartsOnMondayChanged();
}

void AppSettings::setLaunchAtLogin(bool value)
{
    if (value == m_launchAtLogin) {
        applyLaunchAtLogin();
        return;
    }
    m_launchAtLogin = value;
    write(QLatin1String(kLaunch), m_launchAtLogin);
    applyLaunchAtLogin();
    emit launchAtLoginChanged();
}

void AppSettings::applyLaunchAtLogin()
{
    const auto result = LaunchAtLogin::setEnabled(m_launchAtLogin);
    m_launchAtLoginNote = result.note;
    emit launchAtLoginChanged();
}

void AppSettings::setCheckForUpdatesAutomatically(bool value)
{
    if (value == m_checkForUpdatesAutomatically)
        return;
    m_checkForUpdatesAutomatically = value;
    write(QLatin1String(kUpdates), m_checkForUpdatesAutomatically);
    emit checkForUpdatesAutomaticallyChanged();
}

void AppSettings::setSyncEnabled(bool value)
{
    if (value == m_syncEnabled)
        return;
    m_syncEnabled = value;
    write(QLatin1String(kSync), m_syncEnabled);
    emit syncChanged();
}

void AppSettings::setSyncTradingSnapshots(bool value)
{
    if (value == m_syncTradingSnapshots)
        return;
    m_syncTradingSnapshots = value;
    write(QLatin1String(kSnapshots), m_syncTradingSnapshots);
    emit syncChanged();
}

void AppSettings::setExchangeJournalId(const QString &value)
{
    if (value == m_exchangeJournalId)
        return;
    m_exchangeJournalId = value;
    write(QLatin1String(kExJournal), m_exchangeJournalId);
    emit exchangeChanged();
}

void AppSettings::setExchangeVenue(const QString &value)
{
    if (value == m_exchangeVenue)
        return;
    m_exchangeVenue = value;
    write(QLatin1String(kExVenue), m_exchangeVenue);
    emit exchangeChanged();
}

QString AppSettings::resolvedScheme() const
{
    if (m_appearance == QLatin1String("light"))
        return QStringLiteral("light");
    if (m_appearance == QLatin1String("dark"))
        return QStringLiteral("dark");
    const auto hint = QGuiApplication::styleHints()
        ? QGuiApplication::styleHints()->colorScheme()
        : Qt::ColorScheme::Unknown;
    if (hint == Qt::ColorScheme::Light)
        return QStringLiteral("light");
    return QStringLiteral("dark");
}

QString AppSettings::appVersion() const
{
    const QString v = QCoreApplication::applicationVersion();
    return v.isEmpty() ? QStringLiteral("0.1.0") : v;
}

QString AppSettings::t(const QString &zh, const QString &en) const
{
    return isChinese() ? zh : en;
}

void AppSettings::revealDataDirectory()
{
    const auto root = wick::JournalPaths::defaultPaths().librariesRoot;
    QDir().mkpath(QString::fromStdString(root.string()));
    const QUrl url = QUrl::fromLocalFile(QString::fromStdString(root.string()));
    if (!QDesktopServices::openUrl(url)) {
        m_dataStatusText = t(QStringLiteral("无法打开文件管理器"),
                             QStringLiteral("Could not open file manager"));
        emit dataStatusChanged();
    }
}

void AppSettings::stubExport()
{
    m_dataStatusText = t(QStringLiteral("即将支持"), QStringLiteral("Coming soon"));
    emit dataStatusChanged();
}

void AppSettings::stubImport()
{
    m_dataStatusText = t(QStringLiteral("即将支持"), QStringLiteral("Coming soon"));
    emit dataStatusChanged();
}

void AppSettings::setDataStatus(const QString &text)
{
    if (text == m_dataStatusText)
        return;
    m_dataStatusText = text;
    emit dataStatusChanged();
}

void AppSettings::openReleasesPage()
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("https://github.com/miaoz/wick/releases")));
}

void AppSettings::checkForUpdates()
{
    if (m_checkingUpdates)
        return;
    m_checkingUpdates = true;
    m_updateStatusText = t(QStringLiteral("正在检查…"), QStringLiteral("Checking…"));
    emit updateStatusChanged();

    if (!m_nam)
        m_nam = new QNetworkAccessManager(this);

    QNetworkRequest req(QUrl(QStringLiteral("https://api.github.com/repos/miaoz/wick/releases/latest")));
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("Wick/%1 (Linux)").arg(appVersion()));
    req.setRawHeader("Accept", "application/vnd.github+json");
    req.setTransferTimeout(15000);

    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        finishUpdateCheck(reply);
        reply->deleteLater();
    });
}

void AppSettings::finishUpdateCheck(QNetworkReply *reply)
{
    m_checkingUpdates = false;
    if (!reply || reply->error() != QNetworkReply::NoError) {
        m_updateStatusText = t(QStringLiteral("检查更新失败"), QStringLiteral("Update check failed"));
        emit updateStatusChanged();
        return;
    }

    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status == 404) {
        m_updateStatusText = t(QStringLiteral("暂无发布"), QStringLiteral("No releases yet"));
        emit updateStatusChanged();
        return;
    }
    if (status < 200 || status >= 300) {
        m_updateStatusText = t(QStringLiteral("检查更新失败"), QStringLiteral("Update check failed"));
        emit updateStatusChanged();
        return;
    }

    const auto doc = QJsonDocument::fromJson(reply->readAll());
    if (!doc.isObject()) {
        m_updateStatusText = t(QStringLiteral("检查更新失败"), QStringLiteral("Update check failed"));
        emit updateStatusChanged();
        return;
    }
    QString tag = doc.object().value(QLatin1String("tag_name")).toString();
    if (tag.startsWith(QLatin1Char('v')) || tag.startsWith(QLatin1Char('V')))
        tag = tag.mid(1);

    if (isNewerVersion(tag, appVersion())) {
        m_updateStatusText = t(QStringLiteral("发现新版本 %1").arg(tag),
                               QStringLiteral("Update available: %1").arg(tag));
    } else {
        m_updateStatusText = t(QStringLiteral("已是最新版本"), QStringLiteral("Up to date"));
    }
    emit updateStatusChanged();
}

QString LaunchAtLogin::unitPath()
{
    const QString home = QDir::homePath();
    return home + QStringLiteral("/.config/systemd/user/wick.service");
}

QString LaunchAtLogin::unitContents(const QString &execPath)
{
    return QStringLiteral(
               "[Unit]\n"
               "Description=秉烛 (Wick)\n"
               "PartOf=graphical-session.target\n"
               "After=graphical-session.target\n"
               "\n"
               "[Service]\n"
               "Type=simple\n"
               "ExecStart=%1\n"
               "Restart=on-failure\n"
               "RestartSec=2\n"
               "\n"
               "[Install]\n"
               "WantedBy=default.target\n")
        .arg(execPath);
}

LaunchAtLogin::Result LaunchAtLogin::setEnabled(bool enabled)
{
    Result result;
    const QString exec = QCoreApplication::applicationFilePath();
    if (exec.isEmpty()) {
        result.note = QStringLiteral("二进制路径未知，未写入 systemd 单元");
        return result;
    }

    const QString path = unitPath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    if (enabled) {
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            result.note = QStringLiteral("无法写入 ") + path;
            return result;
        }
        f.write(unitContents(exec).toUtf8());
        f.close();

        QProcess proc;
        proc.start(QStringLiteral("systemctl"),
                   {QStringLiteral("--user"), QStringLiteral("daemon-reload")});
        proc.waitForFinished(3000);

        proc.start(QStringLiteral("systemctl"),
                   {QStringLiteral("--user"), QStringLiteral("enable"),
                    QStringLiteral("wick.service")});
        if (!proc.waitForFinished(5000)) {
            result.note = QStringLiteral("systemctl 超时（单元已写入）");
            result.ok = true;
            return result;
        }
        if (proc.exitCode() != 0) {
            const QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
            result.note = err.isEmpty()
                ? QStringLiteral("systemctl enable 失败（单元已写入，可稍后手动启用）")
                : err;
            result.ok = true;
            return result;
        }
        result.ok = true;
        return result;
    }

    QProcess proc;
    proc.start(QStringLiteral("systemctl"),
               {QStringLiteral("--user"), QStringLiteral("disable"), QStringLiteral("--now"),
                QStringLiteral("wick.service")});
    proc.waitForFinished(5000);
    QFile::remove(path);
    result.ok = true;
    return result;
}
