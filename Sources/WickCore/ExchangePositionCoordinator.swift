import Combine
import Foundation

/// Sync failure translated for display; views map these to localized UI text.
enum ExchangeSyncError: Error, Equatable {
    case invalidKey
    case rateLimited
    case network
    case other
    /// Window contained no fills (typical for a mistyped Hyperliquid address).
    case emptyWindow

    init(_ error: BinanceError) {
        self.init(error.asExchangeClientError)
    }

    init(_ error: ExchangeClientError) {
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
        case .emptyWindow: key = .exchangeErrorEmptyWindow
        }
        return L10n.string(key, language: language)
    }
}

/// Per-journal exchange credentials stored as **one** Keychain (or dev-file)
/// item so a packaged build prompts once per journal, not once per field.
struct ExchangeSecretBlob: Codable, Equatable {
    var venue: ExchangeVenue
    var apiKey: String
    var secret: String
    var passphrase: String?
}

/// Owns per-journal exchange bindings, secrets, and the incremental fill cache.
///
/// One journal ≤ one venue. Switching journals loads that journal's snapshot.
/// Unpackaged `swift run` builds persist secrets to a 0600 file (no Keychain
/// password prompts on every rebuild); packaged `.app` builds use Keychain.
@MainActor
final class ExchangePositionCoordinator: ObservableObject {
    static let shared = ExchangePositionCoordinator()

    static let refreshInterval: TimeInterval = 30 * 60
    private static let fetchOverlap: TimeInterval = 5 * 60
    private static let handledIDsCap = 5000
    private static let exchangeService = "com.miaoz.wick.exchange"
    private static let legacyBinanceService = "com.miaoz.wick.binance"
    private static let legacyHandledIDsKey = "wick.binance.handledPositionIDs"

    @Published private(set) var snapshot: TradingPositionSnapshot? {
        didSet { rebuildDerivedStats() }
    }
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: ExchangeSyncError?
    @Published private(set) var hasCredentials = false

    private(set) var pnlByDay: [Date: Double] = [:]
    private(set) var closedCountByDayKey: [String: Int] = [:]

    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var observedJournalID: UUID?

    #if DEBUG
    static var skipKeychainAccess = false
    #endif

    init() {}

    var activeBinding: JournalExchangeBinding? {
        JournalStore.shared.activeJournal?.exchangeBinding
    }

    var isEnabled: Bool {
        #if DEBUG
        if Self.skipKeychainAccess { return false }
        #endif
        guard let binding = activeBinding else { return false }
        if binding.venue == .hyperliquid {
            return HyperliquidInfoClient.normalizedAddress(binding.accountLabel) != nil
        }
        return loadSecrets(for: JournalStore.shared.activeJournalID) != nil
    }

    // MARK: - Lifecycle

    func start() {
        migrateLegacyBinanceIfNeeded()
        observeJournalChanges()
        loadCacheForActiveJournal()
        updateHasCredentials()
        guard isEnabled else { return }
        scheduleTimer()
        refreshIfStale()
    }

    func positions(entryDayKey: String, tag: String) -> [TradingPosition] {
        guard let all = snapshot?.positions else { return [] }
        return SymbolTagMatcher
            .filter(all, matchingTag: tag)
            .filter { JournalDayKey.make(from: $0.openTime) == entryDayKey }
            .sorted { $0.openTime < $1.openTime }
    }

    func refreshIfStale() {
        guard isEnabled, !isSyncing else { return }
        if let fetchedAt = snapshot?.fetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.refreshInterval
        {
            return
        }
        syncNow()
    }

    // MARK: - Bind / disconnect

    func saveAndSyncBinance(apiKey: String, secret: String, journalID: UUID) {
        saveCentralized(
            venue: .binance,
            apiKey: apiKey,
            secret: secret,
            passphrase: nil,
            label: "Binance",
            journalID: journalID
        )
    }

    func saveAndSyncOKX(apiKey: String, secret: String, passphrase: String, journalID: UUID) {
        saveCentralized(
            venue: .okx,
            apiKey: apiKey,
            secret: secret,
            passphrase: passphrase,
            label: "OKX",
            journalID: journalID
        )
    }

    func saveAndSyncHyperliquid(address: String, journalID: UUID) {
        guard let normalized = HyperliquidInfoClient.normalizedAddress(address) else {
            lastError = .invalidKey
            return
        }
        JournalStore.shared.setExchangeBinding(
            JournalExchangeBinding(venue: .hyperliquid, accountLabel: normalized),
            for: journalID
        )
        lastError = nil
        updateHasCredentials()
        scheduleTimer()
        syncNow(journalID: journalID)
    }

    func disconnect(journalID: UUID) {
        secretStore(for: journalID).clear()
        JournalStore.shared.setExchangeBinding(nil, for: journalID)
        try? FileManager.default.removeItem(at: Self.cacheURL(for: journalID))
        if journalID == JournalStore.shared.activeJournalID {
            snapshot = nil
        }
        lastError = nil
        updateHasCredentials()
        if !isEnabled { stopTimer() }
    }

    func binding(for journalID: UUID) -> JournalExchangeBinding? {
        JournalStore.shared.journals.first(where: { $0.id == journalID })?.exchangeBinding
    }

    func isConfigured(for journalID: UUID) -> Bool {
        #if DEBUG
        if Self.skipKeychainAccess { return false }
        #endif
        guard let binding = binding(for: journalID) else { return false }
        if binding.venue == .hyperliquid {
            return HyperliquidInfoClient.normalizedAddress(binding.accountLabel) != nil
        }
        return loadSecrets(for: journalID) != nil
    }

    func lastFetchedAt(for journalID: UUID) -> Date? {
        if journalID == JournalStore.shared.activeJournalID {
            return snapshot?.fetchedAt
        }
        return loadSnapshot(at: Self.cacheURL(for: journalID))?.fetchedAt
    }

    // MARK: - Sync

    static func desiredWindowStart(entries: [JournalEntry], now: Date = Date()) -> Date {
        if let earliest = entries.map(\.date).min() {
            return Calendar.current.startOfDay(for: earliest)
        }
        return Calendar.current.startOfDay(for: now)
    }

    func syncNow() {
        guard let journalID = JournalStore.shared.activeJournalID else { return }
        syncNow(journalID: journalID)
    }

    func syncNow(journalID: UUID) {
        guard !isSyncing else { return }
        guard isConfigured(for: journalID),
              let binding = binding(for: journalID),
              let client = makeClient(binding: binding, journalID: journalID)
        else {
            if journalID == JournalStore.shared.activeJournalID {
                hasCredentials = false
            }
            return
        }

        isSyncing = true
        lastError = nil
        let cached = journalID == JournalStore.shared.activeJournalID
            ? snapshot
            : loadSnapshot(at: Self.cacheURL(for: journalID))
        let desiredStart = Self.desiredWindowStart(
            entries: JournalStore.shared.entries(for: journalID)
        )
        Task { [weak self] in
            await self?.runSync(
                client: client,
                cached: cached,
                desiredStart: desiredStart,
                journalID: journalID
            )
        }
    }

    private func runSync(
        client: any ExchangeTradeClient,
        cached: TradingPositionSnapshot?,
        desiredStart: Date,
        journalID: UUID
    ) async {
        do {
            let now = Date()
            var fills = cached?.fills ?? []
            var windowStart = cached?.windowStart ?? desiredStart
            var ranges: [(Date, Date)] = []

            if fills.isEmpty {
                windowStart = desiredStart
                ranges = [(desiredStart, now)]
            } else if desiredStart > windowStart {
                // First journal day is later than the previous window start.
                // Drop older fills; never fetch further back.
                fills = TradingFill.clipped(fills, from: desiredStart, to: now)
                windowStart = desiredStart
                let resumeAt = max(
                    windowStart,
                    min(cached!.fetchedAt, now).addingTimeInterval(-Self.fetchOverlap)
                )
                if resumeAt < now {
                    ranges.append((resumeAt, now))
                }
            } else {
                if desiredStart < windowStart {
                    ranges.append((desiredStart, windowStart))
                    windowStart = desiredStart
                }
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
            fills = TradingFill.clipped(fills, from: windowStart, to: now)

            let positions = PositionAggregator.aggregate(fills: fills)
            let emptyWindow = fills.isEmpty
            finishSync(
                fills: fills,
                positions: positions,
                windowStart: windowStart,
                journalID: journalID,
                error: emptyWindow ? .emptyWindow : nil
            )
        } catch let error as ExchangeClientError {
            finishSync(
                fills: nil, positions: nil, windowStart: nil, journalID: journalID,
                error: ExchangeSyncError(error)
            )
        } catch let error as BinanceError {
            finishSync(
                fills: nil, positions: nil, windowStart: nil, journalID: journalID,
                error: ExchangeSyncError(error)
            )
        } catch {
            finishSync(
                fills: nil, positions: nil, windowStart: nil, journalID: journalID,
                error: .other
            )
        }
    }

    private func finishSync(
        fills: [TradingFill]?,
        positions: [TradingPosition]?,
        windowStart: Date?,
        journalID: UUID,
        error: ExchangeSyncError?
    ) {
        isSyncing = false
        lastError = error
        let accepted = (error == nil || error == .emptyWindow)
        guard accepted, let fills, let positions, let windowStart else {
            if error == .invalidKey, journalID == JournalStore.shared.activeJournalID {
                stopTimer()
            }
            return
        }

        let prior = journalID == JournalStore.shared.activeJournalID
            ? snapshot
            : loadSnapshot(at: Self.cacheURL(for: journalID))
        var handledOrdered = Array(prior?.handledPositionIDs ?? [])
        autoCreateEntriesIfNeeded(
            positions: positions,
            handled: Set(handledOrdered),
            journalID: journalID
        )

        for position in positions where !handledOrdered.contains(position.id) {
            handledOrdered.append(position.id)
        }
        if handledOrdered.count > Self.handledIDsCap {
            handledOrdered = Array(handledOrdered.suffix(Self.handledIDsCap))
        }

        let next = TradingPositionSnapshot(
            fetchedAt: Date(),
            windowStart: windowStart,
            positions: positions,
            fills: fills,
            handledPositionIDs: Set(handledOrdered)
        )
        saveCache(next, for: journalID)
        if journalID == JournalStore.shared.activeJournalID {
            snapshot = next
        }
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

    private func autoCreateEntriesIfNeeded(
        positions: [TradingPosition],
        handled: Set<String>,
        journalID: UUID
    ) {
        let journalEntries = JournalStore.shared.entries(for: journalID)
        let plan = PositionEntryPlanner.plan(
            positions: positions,
            existingDayKeys: Set(journalEntries.map(\.dayKey)),
            handledPositionIDs: handled,
            dayKey: { JournalDayKey.make(from: $0) },
            startOfDay: { Calendar.current.startOfDay(for: $0) }
        )
        guard !plan.isEmpty else { return }

        var tagCounts: [String: Int] = [:]
        for entry in journalEntries {
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
        let created = JournalStore.shared.autoCreateEntries(skeletons, in: journalID)
        if !created.isEmpty {
            NSLog("Wick exchange: auto-created %ld journal day(s)", created.count)
        }
    }

    // MARK: - Journal switching

    private func observeJournalChanges() {
        observedJournalID = JournalStore.shared.activeJournalID
        NotificationCenter.default.publisher(for: .wickActiveJournalDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.activeJournalDidChange()
            }
            .store(in: &cancellables)

        JournalStore.shared.$journals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] journals in
                self?.pruneDeletedJournals(journals)
            }
            .store(in: &cancellables)
    }

    private func activeJournalDidChange() {
        let newID = JournalStore.shared.activeJournalID
        guard newID != observedJournalID else {
            updateHasCredentials()
            return
        }
        observedJournalID = newID
        loadCacheForActiveJournal()
        updateHasCredentials()
        if isEnabled {
            scheduleTimer()
            refreshIfStale()
        } else {
            stopTimer()
        }
    }

    private func pruneDeletedJournals(_ journals: [JournalInfo]) {
        let live = Set(journals.map(\.id))
        let dir = Self.tradingDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name), !live.contains(id) else { continue }
            secretStore(for: id).clear()
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Client / secrets

    private func saveCentralized(
        venue: ExchangeVenue,
        apiKey: String,
        secret: String,
        passphrase: String?,
        label: String,
        journalID: UUID
    ) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPass = passphrase?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedKey.isEmpty, !trimmedSecret.isEmpty else { return }
        if venue == .okx, trimmedPass.isEmpty { return }

        let blob = ExchangeSecretBlob(
            venue: venue,
            apiKey: trimmedKey,
            secret: trimmedSecret,
            passphrase: venue == .okx ? trimmedPass : nil
        )
        saveSecrets(blob, for: journalID)
        JournalStore.shared.setExchangeBinding(
            JournalExchangeBinding(venue: venue, accountLabel: label),
            for: journalID
        )
        lastError = nil
        updateHasCredentials()
        scheduleTimer()
        syncNow(journalID: journalID)
    }

    private func makeClient(
        binding: JournalExchangeBinding,
        journalID: UUID
    ) -> (any ExchangeTradeClient)? {
        switch binding.venue {
        case .hyperliquid:
            guard let address = HyperliquidInfoClient.normalizedAddress(binding.accountLabel) else {
                return nil
            }
            return HyperliquidInfoClient(user: address)
        case .binance:
            guard let secrets = loadSecrets(for: journalID) else { return nil }
            return BinanceFuturesClient(apiKey: secrets.apiKey, secret: secrets.secret)
        case .okx:
            guard let secrets = loadSecrets(for: journalID),
                  let passphrase = secrets.passphrase, !passphrase.isEmpty
            else { return nil }
            return OKXSwapClient(
                apiKey: secrets.apiKey,
                secret: secrets.secret,
                passphrase: passphrase
            )
        }
    }

    private func secretStore(for journalID: UUID) -> KeychainTokenStore {
        KeychainTokenStore(service: Self.exchangeService, account: journalID.uuidString)
    }

    private func loadSecrets(for journalID: UUID?) -> ExchangeSecretBlob? {
        #if DEBUG
        if Self.skipKeychainAccess { return nil }
        #endif
        guard let journalID,
              let raw = secretStore(for: journalID).load(),
              let data = raw.data(using: .utf8),
              let blob = try? JSONDecoder().decode(ExchangeSecretBlob.self, from: data)
        else {
            return nil
        }
        return blob
    }

    private func saveSecrets(_ blob: ExchangeSecretBlob, for journalID: UUID) {
        guard let data = try? JSONEncoder().encode(blob),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        secretStore(for: journalID).save(raw)
    }

    private func updateHasCredentials() {
        hasCredentials = isEnabled
    }

    // MARK: - Legacy migration (global Binance → active journal)

    private func migrateLegacyBinanceIfNeeded() {
        guard let journalID = JournalStore.shared.activeJournalID else { return }
        if JournalStore.shared.activeJournal?.exchangeBinding != nil { return }
        if loadSecrets(for: journalID) != nil { return }

        let legacyKey = KeychainTokenStore(service: Self.legacyBinanceService, account: "apiKey")
        let legacySecret = KeychainTokenStore(service: Self.legacyBinanceService, account: "apiSecret")
        guard let apiKey = legacyKey.load(), let secret = legacySecret.load() else { return }

        saveSecrets(
            ExchangeSecretBlob(venue: .binance, apiKey: apiKey, secret: secret, passphrase: nil),
            for: journalID
        )
        JournalStore.shared.setExchangeBinding(
            JournalExchangeBinding(venue: .binance, accountLabel: "Binance"),
            for: journalID
        )
        legacyKey.clear()
        legacySecret.clear()

        let legacyCache = Self.legacyCacheURL
        let newCache = Self.cacheURL(for: journalID)
        if FileManager.default.fileExists(atPath: legacyCache.path),
           !FileManager.default.fileExists(atPath: newCache.path)
        {
            try? FileManager.default.createDirectory(
                at: newCache.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.moveItem(at: legacyCache, to: newCache)
        }

        if let handled = UserDefaults.standard.stringArray(forKey: Self.legacyHandledIDsKey),
           var snapshot = loadSnapshot(at: newCache)
        {
            snapshot.handledPositionIDs.formUnion(handled)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: newCache, options: .atomic)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyHandledIDsKey)
        AppSettings.shared.binancePositionsEnabled = false
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

    private static func tradingDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Wick/Trading", isDirectory: true)
    }

    private static func cacheURL(for journalID: UUID) -> URL {
        tradingDirectory().appendingPathComponent("\(journalID.uuidString).json")
    }

    private static var legacyCacheURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Wick/TradingPositions.json")
    }

    private func loadCacheForActiveJournal() {
        guard let journalID = JournalStore.shared.activeJournalID else {
            snapshot = nil
            return
        }
        snapshot = loadSnapshot(at: Self.cacheURL(for: journalID))
    }

    private func loadSnapshot(at url: URL) -> TradingPositionSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        else { return nil }
        return decoded
    }

    private func saveCache(_ snapshot: TradingPositionSnapshot, for journalID: UUID) {
        let url = Self.cacheURL(for: journalID)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
