#include "ExchangeCoordinator.h"

#include "JournalLibrary.h"
#include "ExchangeClients.h"
#include "FundingAttributor.h"
#include "JournalModels.h"
#include "PositionAggregator.h"
#include "PositionEntryPlanner.h"
#include "SecretTokenStore.h"
#include "SymbolTagMatcher.h"

#include <QDate>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <nlohmann/json.hpp>
#include <fstream>
#include <set>

using wick::BinanceFuturesClient;
using wick::ExchangeHttpError;
using wick::ExchangeVenue;
using wick::FundingAttributor;
using wick::FundingEvent;
using wick::HyperliquidInfoClient;
using wick::JournalDayKey;
using wick::JournalExchangeBinding;
using wick::JournalItem;
using wick::OKXSwapClient;
using wick::PlannedPositionDay;
using wick::PositionAggregator;
using wick::PositionEntryPlanner;
using wick::SecretTokenStore;
using wick::SymbolTagMatcher;
using wick::TradingFill;
using wick::TradingPosition;
using wick::TradingPositionSnapshot;
using wick::Uuid;
using wick::parseExchangeVenue;
using wick::timeFromUnix;
using wick::unixFromTime;

namespace {

constexpr const char *kService = "com.miaoz.wick.exchange";

SecretTokenStore storeFor(const QString &journalId)
{
    return SecretTokenStore(kService, journalId.toStdString(), "Wick exchange credentials");
}

std::optional<Uuid> parseId(const QString &id)
{
    return Uuid::parse(id.toStdString());
}

QString venueTitle(ExchangeVenue v)
{
    switch (v) {
    case ExchangeVenue::okx: return QStringLiteral("OKX");
    case ExchangeVenue::hyperliquid: return QStringLiteral("Hyperliquid");
    case ExchangeVenue::binance:
    default: return QStringLiteral("Binance");
    }
}

} // namespace

class ExchangeWorker : public QObject
{
    Q_OBJECT
public slots:
    void run(const QString &journalId, const QString &venue, const QString &blob, qint64 fromMs, qint64 toMs)
    {
        try {
            std::vector<TradingFill> fills;
            std::vector<FundingEvent> funding;
            if (venue == QLatin1String("hyperliquid")) {
                HyperliquidInfoClient c;
                c.user = blob.toStdString();
                fills = c.fetchFills(fromMs, toMs);
                try {
                    funding = c.fetchFunding(fromMs, toMs);
                } catch (...) {
                    funding.clear();
                }
            } else {
                const auto json = nlohmann::json::parse(blob.toStdString());
                if (venue == QLatin1String("okx")) {
                    OKXSwapClient c;
                    c.apiKey = json.value("apiKey", "");
                    c.secret = json.value("secret", "");
                    c.passphrase = json.value("passphrase", "");
                    fills = c.fetchFills(fromMs, toMs);
                    try {
                        funding = c.fetchFunding(fromMs, toMs);
                    } catch (...) {
                        funding.clear();
                    }
                } else {
                    BinanceFuturesClient c;
                    c.apiKey = json.value("apiKey", "");
                    c.secret = json.value("secret", "");
                    fills = c.fetchFills(fromMs, toMs);
                    try {
                        funding = c.fetchFunding(fromMs, toMs);
                    } catch (...) {
                        funding.clear();
                    }
                }
            }
            auto positions = PositionAggregator::aggregate(fills);
            positions = FundingAttributor::attach(positions, funding);
            TradingPositionSnapshot snap;
            snap.fetchedAt = toMs;
            snap.windowStart = fromMs;
            snap.positions = positions;
            snap.fills = fills;
            snap.funding = funding;
            snap.fundingBackfilled = true;
            snap.sourceVenue = venue.toStdString();
            const std::string snapshotJson = snap.encode();
            emit finished(journalId, QString(), QString::fromStdString(snapshotJson),
                          static_cast<int>(positions.size()));
        } catch (const ExchangeHttpError &e) {
            QString msg;
            switch (e.kind) {
            case ExchangeHttpError::invalidCredentials:
                msg = QStringLiteral("凭证无效：%1").arg(QString::fromStdString(e.what()));
                break;
            case ExchangeHttpError::timestamp:
                msg = QStringLiteral("本机时间与交易所相差过大");
                break;
            case ExchangeHttpError::rateLimited:
                msg = QStringLiteral("请求过于频繁，请稍后再试");
                break;
            case ExchangeHttpError::network:
                msg = QStringLiteral("网络错误：%1").arg(QString::fromStdString(e.what()));
                break;
            default:
                msg = QString::fromStdString(e.what());
                if (msg.isEmpty())
                    msg = QStringLiteral("同步失败");
                break;
            }
            emit finished(journalId, msg, QString(), 0);
        } catch (const std::exception &e) {
            emit finished(journalId, QString::fromUtf8(e.what()), QString(), 0);
        }
    }

signals:
    void finished(const QString &journalId, const QString &error, const QString &positionsJson, int count);
};

ExchangeCoordinator::ExchangeCoordinator(JournalLibrary *library, QObject *parent)
    : QObject(parent)
    , m_library(library)
{
    m_worker = new ExchangeWorker;
    m_worker->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(m_worker, &ExchangeWorker::finished, this, &ExchangeCoordinator::onWorkerFinished);
    m_thread.start();
    if (m_library) {
        connect(m_library, &JournalLibrary::journalsChanged, this, &ExchangeCoordinator::refreshStatus);
        connect(m_library, &JournalLibrary::activeJournalChanged, this, [this]() {
            if (m_targetId.isEmpty())
                setTargetJournalId(m_library->activeJournalId());
            refreshStatus();
        });
        if (m_targetId.isEmpty())
            m_targetId = m_library->activeJournalId();
    }
    refreshStatus();
}

ExchangeCoordinator::~ExchangeCoordinator()
{
    m_thread.quit();
    m_thread.wait(4000);
}

void ExchangeCoordinator::setTargetJournalId(const QString &id)
{
    if (id == m_targetId)
        return;
    m_targetId = id;
    emit targetChanged();
    refreshStatus();
}

bool ExchangeCoordinator::configured() const
{
    return isConfigured(m_targetId);
}

QString ExchangeCoordinator::venue() const
{
    if (!m_library)
        return {};
    for (const auto &row : m_library->journals()) {
        const auto map = row.toMap();
        if (map.value(QStringLiteral("id")).toString() == m_targetId)
            return map.value(QStringLiteral("venue")).toString();
    }
    return {};
}

QString ExchangeCoordinator::accountLabel() const
{
    if (!m_library)
        return {};
    for (const auto &row : m_library->journals()) {
        const auto map = row.toMap();
        if (map.value(QStringLiteral("id")).toString() == m_targetId)
            return map.value(QStringLiteral("accountLabel")).toString();
    }
    return {};
}

bool ExchangeCoordinator::isConfigured(const QString &journalId) const
{
    if (!m_library || journalId.isEmpty())
        return false;
    QString venue;
    QString label;
    for (const auto &row : m_library->journals()) {
        const auto map = row.toMap();
        if (map.value(QStringLiteral("id")).toString() == journalId) {
            if (!map.value(QStringLiteral("exchangeBound")).toBool())
                return false;
            venue = map.value(QStringLiteral("venue")).toString();
            label = map.value(QStringLiteral("accountLabel")).toString();
            break;
        }
    }
    if (venue.isEmpty())
        return false;
    if (venue == QLatin1String("hyperliquid"))
        return HyperliquidInfoClient::normalizedAddress(label.toStdString()).has_value();
    return storeFor(journalId).load().has_value();
}

void ExchangeCoordinator::saveBinance(const QString &journalId, const QString &apiKey, const QString &secret)
{
    if (apiKey.trimmed().isEmpty() || secret.trimmed().isEmpty())
        return;
    nlohmann::json blob;
    blob["venue"] = "binance";
    blob["apiKey"] = apiKey.trimmed().toStdString();
    blob["secret"] = secret.trimmed().toStdString();
    bindAndSync(journalId, QStringLiteral("binance"), QStringLiteral("Binance"),
                QString::fromStdString(blob.dump()));
}

void ExchangeCoordinator::saveOKX(const QString &journalId, const QString &apiKey, const QString &secret,
                                  const QString &passphrase)
{
    if (apiKey.trimmed().isEmpty() || secret.trimmed().isEmpty() || passphrase.trimmed().isEmpty())
        return;
    nlohmann::json blob;
    blob["venue"] = "okx";
    blob["apiKey"] = apiKey.trimmed().toStdString();
    blob["secret"] = secret.trimmed().toStdString();
    blob["passphrase"] = passphrase.trimmed().toStdString();
    bindAndSync(journalId, QStringLiteral("okx"), QStringLiteral("OKX"),
                QString::fromStdString(blob.dump()));
}

void ExchangeCoordinator::saveHyperliquid(const QString &journalId, const QString &address)
{
    const auto normalized = HyperliquidInfoClient::normalizedAddress(address.toStdString());
    if (!normalized) {
        m_lastError = QStringLiteral("请输入有效的 0x 钱包地址");
        m_statusText = m_lastError;
        emit statusChanged();
        return;
    }
    const auto parsed = parseId(journalId);
    if (!parsed || !m_library)
        return;
    JournalExchangeBinding binding;
    binding.venue = ExchangeVenue::hyperliquid;
    binding.accountLabel = *normalized;
    m_library->setExchangeBinding(*parsed, binding);
    setTargetJournalId(journalId);
    syncNow(journalId);
}

void ExchangeCoordinator::disconnectJournal(const QString &journalId)
{
    const auto parsed = parseId(journalId);
    if (!parsed || !m_library)
        return;
    try {
        storeFor(journalId).clear();
    } catch (...) {
    }
    m_library->setExchangeBinding(*parsed, std::nullopt);
    m_lastError.clear();
    m_statusText = QStringLiteral("已断开");
    emit statusChanged();
    emit targetChanged();
}

void ExchangeCoordinator::bindAndSync(const QString &journalId, const QString &venue, const QString &label,
                                      const QString &blobJson)
{
    const auto parsed = parseId(journalId);
    if (!parsed || !m_library)
        return;
    try {
        storeFor(journalId).save(blobJson.toStdString());
    } catch (const std::exception &e) {
        m_lastError = QString::fromUtf8(e.what());
        m_statusText = m_lastError;
        emit statusChanged();
        return;
    }
    JournalExchangeBinding binding;
    if (const auto v = parseExchangeVenue(venue.toStdString()))
        binding.venue = *v;
    binding.accountLabel = label.toStdString();
    m_library->setExchangeBinding(*parsed, binding);
    setTargetJournalId(journalId);
    syncNow(journalId);
}

void ExchangeCoordinator::syncNow(const QString &journalId)
{
    if (!m_library || journalId.isEmpty() || m_syncing)
        return;
    if (!isConfigured(journalId)) {
        m_lastError.clear();
        m_statusText = QStringLiteral("尚未绑定交易所");
        emit statusChanged();
        return;
    }

    qint64 fromMs = QDate::currentDate().startOfDay().toMSecsSinceEpoch();
    const auto parsed = parseId(journalId);
    if (parsed) {
        const auto snaps = m_library->entrySnapshotsFor(*parsed);
        for (const auto &[_, e] : snaps) {
            const qint64 ms = wick::unixFromTime(e.date) * 1000;
            if (ms < fromMs)
                fromMs = ms;
        }
    }
    const qint64 toMs = QDateTime::currentMSecsSinceEpoch();

    QString venueStr = venue();
    QString blob;
    if (journalId != m_targetId) {
        for (const auto &row : m_library->journals()) {
            const auto map = row.toMap();
            if (map.value(QStringLiteral("id")).toString() == journalId)
                venueStr = map.value(QStringLiteral("venue")).toString();
        }
    }
    if (venueStr == QLatin1String("hyperliquid")) {
        blob = accountLabel();
        if (journalId != m_targetId) {
            for (const auto &row : m_library->journals()) {
                const auto map = row.toMap();
                if (map.value(QStringLiteral("id")).toString() == journalId)
                    blob = map.value(QStringLiteral("accountLabel")).toString();
            }
        }
    } else {
        auto raw = storeFor(journalId).load();
        if (!raw) {
            m_lastError = QStringLiteral("找不到已保存的凭证");
            m_statusText = m_lastError;
            emit statusChanged();
            return;
        }
        blob = QString::fromStdString(*raw);
    }

    m_syncing = true;
    m_lastError.clear();
    m_statusText = QStringLiteral("正在同步仓位…");
    emit statusChanged();
    QMetaObject::invokeMethod(m_worker, "run", Qt::QueuedConnection,
                              Q_ARG(QString, journalId),
                              Q_ARG(QString, venueStr),
                              Q_ARG(QString, blob),
                              Q_ARG(qint64, fromMs),
                              Q_ARG(qint64, toMs));
}

void ExchangeCoordinator::onWorkerFinished(const QString &journalId, const QString &error,
                                           const QString &snapshotJson, int count)
{
    m_syncing = false;
    if (!error.isEmpty()) {
        m_lastError = error;
        m_statusText = error;
        emit statusChanged();
        return;
    }
    if (!m_library) {
        m_statusText = QStringLiteral("已拉取 %1 个仓位").arg(count);
        emit statusChanged();
        return;
    }
    const auto parsed = parseId(journalId);
    if (!parsed) {
        emit statusChanged();
        return;
    }

    if (!snapshotJson.isEmpty()) {
        const auto tradingFile = m_library->paths().tradingJSON(*parsed);
        std::error_code ec;
        std::filesystem::create_directories(tradingFile.parent_path(), ec);
        std::ofstream out(tradingFile, std::ios::binary | std::ios::trunc);
        if (out) {
            out.write(snapshotJson.toUtf8().constData(), snapshotJson.toUtf8().size());
        }
    }

    const auto snapOpt = TradingPositionSnapshot::decode(snapshotJson.toStdString());
    std::vector<TradingPosition> positions;
    if (snapOpt)
        positions = snapOpt->positions;

    const auto snaps = m_library->entrySnapshotsFor(*parsed);
    std::map<std::string, std::vector<std::string>> tagsByDay;
    std::map<std::string, int> tagCounts;
    for (const auto &[_, e] : snaps) {
        const std::string key = JournalDayKey::make(e.date, QDateTime::currentDateTime().offsetFromUtc());
        for (const auto &item : e.items) {
            tagsByDay[key].push_back(item.tag);
            const std::string tag = wick::trimCopy(item.tag);
            if (!tag.empty())
                tagCounts[tag] += 1;
        }
    }

    const int tz = QDateTime::currentDateTime().offsetFromUtc();
    const auto plan = PositionEntryPlanner::plan(
        positions, tagsByDay,
        [tz](wick::TimePoint tp) { return JournalDayKey::make(tp, tz); },
        [this](wick::TimePoint tp) {
            const QDate d = QDateTime::fromSecsSinceEpoch(wick::unixFromTime(tp)).toLocalTime().date();
            return wick::timeFromUnix(d.startOfDay().toSecsSinceEpoch());
        });

    std::set<Uuid> reserved;
    for (const auto &[_, e] : snaps)
        for (const auto &item : e.items)
            reserved.insert(item.id);

    std::vector<std::pair<QDate, std::vector<JournalItem>>> skeletons;
    for (const auto &planned : plan) {
        std::vector<std::string> covered = tagsByDay[planned.dayKey];
        std::vector<JournalItem> items;
        for (const auto &symbol : planned.symbols) {
            bool already = false;
            for (const auto &tag : covered) {
                if (SymbolTagMatcher::matches(tag, symbol)) {
                    already = true;
                    break;
                }
            }
            if (already)
                continue;
            const auto preferred = SymbolTagMatcher::preferredTag(symbol, tagCounts);
            const std::string tag = preferred ? *preferred : SymbolTagMatcher::baseAsset(symbol);
            JournalItem item;
            item.id = PositionEntryPlanner::stableItemID(*parsed, planned.dayKey, symbol);
            if (!reserved.insert(item.id).second)
                item.id = Uuid::generate();
            item.tag = tag;
            items.push_back(item);
            covered.push_back(tag);
        }
        if (items.empty())
            continue;
        const QDate day = QDateTime::fromSecsSinceEpoch(wick::unixFromTime(planned.day)).toLocalTime().date();
        skeletons.push_back({day, std::move(items)});
    }

    const int created = m_library->ensurePositionEntries(*parsed, skeletons);
    if (*parsed == parseId(m_library->activeJournalId()).value_or(Uuid{})) {
        m_library->refreshTradingPositions();
    }

    m_lastError.clear();
    if (count == 0)
        m_statusText = QStringLiteral("窗口内没有成交");
    else if (created > 0)
        m_statusText = QStringLiteral("已同步 %1 个仓位，补了 %2 个日记日").arg(count).arg(created);
    else
        m_statusText = QStringLiteral("已同步 %1 个仓位，日记条目已覆盖").arg(count);
    emit statusChanged();
}

void ExchangeCoordinator::refreshStatus()
{
    if (m_syncing)
        return;
    if (configured()) {
        const QString v = venueTitle(parseExchangeVenue(venue().toStdString()).value_or(ExchangeVenue::binance));
        m_statusText = v + QStringLiteral(" · ") + accountLabel();
        m_lastError.clear();
    } else {
        m_statusText.clear();
    }
    emit statusChanged();
    emit targetChanged();
}

#include "ExchangeCoordinator.moc"
