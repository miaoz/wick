import Combine
import Foundation

/// Sync failure translated for display; views map it to localized text.
enum ExchangeSyncError: Error, Equatable {
    case invalidKey
    case rateLimited
    case network
    case other

    init(_ error: BinanceError) {
        switch error {
        case .invalidCredentials:
            self = .invalidKey
        case .rateLimited:
            self = .rateLimited
        case .network:
            self = .network
        case .timestampOutsideRecvWindow, .http, .malformedResponse:
            self = .other
        }
    }

    func text(language: AppLanguage) -> String {
        let key: L10n.Key
        switch self {
        case .invalidKey: key = .exchangeErrorInvalidKey
        case .rateLimited: key = .exchangeErrorRateLimited
        case .network: key = .exchangeErrorNetwork
        case .other: key = .exchangeErrorOther
        }
        return L10n.string(key, language: language)
    }
}

/// Owns the Binance credentials (Keychain), the incremental position cache
/// (`Application Support/Wick/TradingPositions.json`), and the periodic
/// refresh.
///
/// The sync window starts at the earliest journal day (fallback: the client's
/// 180-day default when the journal is empty); positions opened earlier are
/// never fetched. Refreshes are incremental - raw fills are cached and only
/// the tail since the last successful fetch is re-requested (past fills are
/// immutable), plus a one-time backward extension when the journal's earliest
/// day moves earlier. Position days without a journal entry get one created
/// automatically (one item per symbol, so tag matching renders the positions
/// inside it); a position is considered for creation exactly once, so deleting
/// an auto-created entry is respected. Journal views query
/// `positions(entryDayKey:tag:)` which keeps matching at display time - no
/// journal content is ever rewritten by the exchange integration.
@MainActor
final class ExchangePositionCoordinator: ObservableObject {
    static let shared = ExchangePositionCoordinator()

    /// Auto-refresh cadence while enabled; also the staleness threshold for
    /// refresh-on-journal-open.
    static let refreshInterval: TimeInterval = 30 * 60

    /// Re-fetch overlap ahead of the last coverage point; dedupe makes it exact.
    private static let fetchOverlap: TimeInterval = 5 * 60

    /// Journal-auto-creation decisions survive `disconnect()` (which wipes the
    /// data cache): without this, reconnecting would resurrect entries the
    /// user deleted. Capped to bound growth.
    private static let handledIDsKey = "wick.binance.handledPositionIDs"
    private static let handledIDsCap = 5000

    @Published private(set) var snapshot: TradingPositionSnapshot? {
        didSet { rebuildDerivedStats() }
    }
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: ExchangeSyncError?
    @Published private(set) var hasCredentials = false
    /// Realized PnL per local day; rebuilt when `snapshot` changes (P5).
    private(set) var pnlByDay: [Date: Double] = [:]
    /// Closed position count keyed by open-day `yyyy-MM-dd`.
    private(set) var closedCountByDayKey: [String: Int] = [:]

    private let apiKeyStore: KeychainTokenStore
    private let secretStore: KeychainTokenStore
    private var refreshTimer: Timer?

    #if DEBUG
    /// UI-check/screenshot mode: skip Keychain reads so a headless launch
    /// never blocks on an access prompt. Credentials look absent, so all
    /// network sync paths stay inert as well.
    static var skipKeychainAccess = false
    #endif

    init(
        keychainService: String = "com.miaoz.wick.binance"
    ) {
        apiKeyStore = KeychainTokenStore(service: keychainService, account: "apiKey")
        secretStore = KeychainTokenStore(service: keychainService, account: "apiSecret")
        #if DEBUG
        if Self.skipKeychainAccess {
            hasCredentials = false
        } else {
            hasCredentials = apiKeyStore.load() != nil && secretStore.load() != nil
        }
        #else
        hasCredentials = apiKeyStore.load() != nil && secretStore.load() != nil
        #endif
    }

    var isEnabled: Bool {
        AppSettings.shared.binancePositionsEnabled && hasCredentials
    }

    // MARK: - Lifecycle

    /// Loads the disk cache and kicks off the first refresh when enabled.
    func start() {
        loadCache()
        guard isEnabled else { return }
        scheduleTimer()
        refreshIfStale()
    }

    /// Positions for journal display: opened on `entryDayKey` and loosely
    /// matching the item's tag (BTC -> BTCUSDT / BTCUSDC, ...).
    func positions(entryDayKey: String, tag: String) -> [TradingPosition] {
        guard let all = snapshot?.positions else { return [] }
        return SymbolTagMatcher
            .filter(all, matchingTag: tag)
            .filter { JournalDayKey.make(from: $0.openTime) == entryDayKey }
            .sorted { $0.openTime < $1.openTime }
    }

    /// Refresh (if enabled) when the cached data is older than the interval.
    func refreshIfStale() {
        guard isEnabled, !isSyncing else { return }
        if let fetchedAt = snapshot?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.refreshInterval
        {
            return
        }
        syncNow()
    }

    // MARK: - Credentials

    /// Stores credentials, enables the integration, and starts a sync.
    /// Auth failures surface via `lastError` and disable auto-sync until the
    /// user saves a working key; other failures keep the schedule running.
    func saveAndSync(apiKey: String, secret: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty else { return }

        apiKeyStore.save(trimmedKey)
        secretStore.save(trimmedSecret)
        hasCredentials = true
        AppSettings.shared.binancePositionsEnabled = true
        lastError = nil
        scheduleTimer()
        syncNow()
    }

    /// Removes credentials and all synced data (journal content untouched).
    func disconnect() {
        AppSettings.shared.binancePositionsEnabled = false
        apiKeyStore.clear()
        secretStore.clear()
        hasCredentials = false
        snapshot = nil
        lastError = nil
        stopTimer()
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    // MARK: - Sync

    /// Lower bound of the sync window: the earliest journal day. Positions
    /// opened before it are not synced at all; with an empty journal the
    /// client's fallback window applies.
    static func desiredWindowStart(entries: [JournalEntry], now: Date = Date()) -> Date {
        if let earliest = entries.map(\.date).min() {
            return Calendar.current.startOfDay(for: earliest)
        }
        return Calendar.current.startOfDay(
            for: now.addingTimeInterval(-BinanceFuturesClient.historyWindow)
        )
    }

    func syncNow() {
        guard isEnabled, !isSyncing else { return }
        guard let apiKey = apiKeyStore.load(), let secret = secretStore.load() else {
            hasCredentials = false
            return
        }

        isSyncing = true
        lastError = nil

        let client = BinanceFuturesClient(apiKey: apiKey, secret: secret)
        let cached = snapshot
        let desiredStart = Self.desiredWindowStart(entries: JournalStore.shared.entries)
        Task { [weak self] in
            await self?.runSync(client: client, cached: cached, desiredStart: desiredStart)
        }
    }

    /// The fetch itself runs off the main actor (client is Sendable and
    /// non-isolated); reads of journal state happened on main before it.
    private func runSync(
        client: BinanceFuturesClient,
        cached: TradingPositionSnapshot?,
        desiredStart: Date
    ) async {
        do {
            let now = Date()
            var fills = cached?.fills ?? []
            var windowStart = cached?.windowStart ?? desiredStart
            var ranges: [(Date, Date)] = []

            if fills.isEmpty {
                // First sync (or legacy cache without fills): full window.
                windowStart = desiredStart
                ranges = [(desiredStart, now)]
            } else {
                // Journal grew an earlier day since last sync: extend back.
                // Past fills are immutable, so this is a one-time top-up.
                if desiredStart < windowStart {
                    ranges.append((desiredStart, windowStart))
                    windowStart = desiredStart
                }
                // Incremental: everything from the last coverage point on.
                let resumeAt = max(
                    windowStart,
                    min(cached!.fetchedAt, now).addingTimeInterval(-Self.fetchOverlap)
                )
                if resumeAt < now {
                    ranges.append((resumeAt, now))
                }
            }

            var fetched: [TradingFill] = []
            for range in ranges {
                fetched += try await client.fetchFills(from: range.0, to: range.1)
            }

            if !ranges.isEmpty {
                var seen = Set(fills.map { "\($0.symbol)#\($0.id)" })
                for fill in fetched where seen.insert("\(fill.symbol)#\(fill.id)").inserted {
                    fills.append(fill)
                }
                fills.sort { ($0.time, $0.id) < ($1.time, $1.id) }
            }

            let positions = PositionAggregator.aggregate(fills: fills)
            finishSync(fills: fills, positions: positions, windowStart: windowStart, error: nil)
        } catch let error as BinanceError {
            finishSync(fills: nil, positions: nil, windowStart: nil, error: ExchangeSyncError(error))
        } catch {
            finishSync(fills: nil, positions: nil, windowStart: nil, error: .other)
        }
    }

    private func finishSync(
        fills: [TradingFill]?,
        positions: [TradingPosition]?,
        windowStart: Date?,
        error: ExchangeSyncError?
    ) {
        isSyncing = false
        lastError = error
        guard error == nil, let fills, let positions, let windowStart else {
            if error == .invalidKey {
                // Bad key: keep it in the Keychain for editing, stop retrying.
                AppSettings.shared.binancePositionsEnabled = false
                stopTimer()
            }
            return
        }

        // Position days without a journal entry get one (one item per symbol,
        // so tag matching renders the positions inside it). Positions already
        // decided in an earlier sync never trigger creation again - a deleted
        // auto-entry stays deleted.
        var handledOrdered = Self.loadHandledIDs()
        if let cachedHandled = snapshot?.handledPositionIDs {
            for id in cachedHandled where !handledOrdered.contains(id) {
                handledOrdered.append(id)
            }
        }
        autoCreateEntriesIfNeeded(positions: positions, handled: Set(handledOrdered))

        for position in positions where !handledOrdered.contains(position.id) {
            handledOrdered.append(position.id)
        }
        if handledOrdered.count > Self.handledIDsCap {
            handledOrdered = Array(handledOrdered.suffix(Self.handledIDsCap))
        }
        Self.saveHandledIDs(handledOrdered)

        snapshot = TradingPositionSnapshot(
            fetchedAt: Date(),
            windowStart: windowStart,
            positions: positions,
            fills: fills,
            handledPositionIDs: Set(handledOrdered)
        )
        saveCache()
    }

    private func rebuildDerivedStats() {
        pnlByDay = DailyRealizedPnl.sumsByDay(
            fills: snapshot?.fills ?? [],
            calendar: .current
        )
        var counts: [String: Int] = [:]
        for position in snapshot?.positions ?? [] where position.isClosed {
            counts[JournalDayKey.make(from: position.openTime), default: 0] += 1
        }
        closedCountByDayKey = counts
    }

    private static func loadHandledIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: handledIDsKey) ?? []
    }

    private static func saveHandledIDs(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: handledIDsKey)
    }

    private func autoCreateEntriesIfNeeded(positions: [TradingPosition], handled: Set<String>) {
        let plan = PositionEntryPlanner.plan(
            positions: positions,
            existingDayKeys: Set(JournalStore.shared.entries.map(\.dayKey)),
            handledPositionIDs: handled,
            dayKey: { JournalDayKey.make(from: $0) },
            startOfDay: { Calendar.current.startOfDay(for: $0) }
        )
        guard !plan.isEmpty else { return }

        // New items adopt the user's own spelling when one exists (they write
        // BTC, the symbol is BTCUSDT -> tag the new item BTC); otherwise the
        // derived base asset (BTCUSDT -> BTC, 1000PEPEUSDT -> PEPE). Existing
        // tags are never rewritten.
        var tagCounts: [String: Int] = [:]
        for entry in JournalStore.shared.entries {
            for item in entry.items {
                let tag = item.tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tag.isEmpty else { continue }
                tagCounts[tag, default: 0] += 1
            }
        }
        func tagForSymbol(_ symbol: String) -> String {
            SymbolTagMatcher.preferredTag(matching: symbol, tagCounts: tagCounts)
                ?? SymbolTagMatcher.baseAsset(of: symbol)
        }

        let skeletons = plan.map { planned in
            (
                day: planned.day,
                items: planned.symbols.map { JournalItem(tag: tagForSymbol($0)) }
            )
        }
        let created = JournalStore.shared.autoCreateEntries(skeletons)
        if !created.isEmpty {
            NSLog("Wick exchange: auto-created %ld journal day(s)", created.count)
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfStale()
            }
        }
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Cache

    private static var cacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Wick/TradingPositions.json")
    }

    private func saveCache() {
        guard let snapshot else { return }
        let url = Self.cacheURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        else { return }
        snapshot = decoded
    }
}
