import Combine
import Foundation
import os

/// The slice of `JournalStore` the exchange coordinator reads/writes. Kept as
/// a protocol so lifecycle tests can substitute a temp-root store instead of
/// touching Application Support / the real singleton.
@MainActor
protocol ExchangeJournalStore: AnyObject {
    var activeJournalID: UUID? { get }
    var activeJournal: JournalInfo? { get }
    var journals: [JournalInfo] { get }
    func setExchangeBinding(_ binding: JournalExchangeBinding?, for id: UUID)
    func entries(for journalID: UUID) -> JournalEntriesLoadResult
    func ensurePositionEntries(
        _ skeletons: [(day: Date, items: [JournalItem])],
        in journalID: UUID
    ) -> [Date]
}

extension JournalStore: ExchangeJournalStore {}

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
    private static let exchangeService = "com.miaoz.wick.exchange"
    private static let log = Logger(subsystem: "com.miaoz.wick", category: "exchange")

    @Published private(set) var snapshot: TradingPositionSnapshot? {
        didSet { rebuildDerivedStats() }
    }
    /// Busy state derived from the CURRENT active journal's in-flight run.
    @Published private(set) var isSyncing = false
    /// Error derived from the CURRENT active journal's last run.
    @Published private(set) var lastError: ExchangeSyncError?
    @Published private(set) var hasCredentials = false

    private(set) var pnlByDay: [Date: Double] = [:]
    private(set) var closedCountByDayKey: [String: Int] = [:]

    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var observedJournalID: UUID?

    // MARK: - Per-journal run identity (EX-01)

    /// Identity frozen at request time; a result is committed only while its
    /// token is still the latest for the journal AND the binding is unchanged.
    private struct JobToken: Equatable {
        let runID: UUID
        let journalID: UUID
        let bindingFingerprint: String
        let generation: Int
    }

    /// journalID → runID of the single in-flight run (one run per journal).
    private var runningJobs: [UUID: UUID] = [:]
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    /// runID → frozen token for the still-current run.
    private var jobTokens: [UUID: JobToken] = [:]
    /// Bumped on disconnect / binding change / journal deletion so an in-flight
    /// result for the old binding is discarded.
    private var generationByJournal: [UUID: Int] = [:]
    /// Last run outcome per journal (the published `lastError` mirrors the
    /// active journal's value so other journals' errors never leak in).
    private var errorsByJournal: [UUID: ExchangeSyncError?] = [:]

    #if DEBUG
    static var skipKeychainAccess = false
    /// Test seam: substitutes client construction so lifecycle tests run
    /// without Keychain or network. `nil` binding means "no binding".
    static var clientFactoryOverride: ((JournalExchangeBinding?, UUID) -> (any ExchangeTradeClient)?)?
    /// Test seam: substitutes the configured check (secrets availability).
    static var configuredOverride: ((UUID) -> Bool)?
    /// Test seam: substitutes the journal store so lifecycle tests use a
    /// temp-root store instead of the Application Support singleton.
    static var storeOverride: (any ExchangeJournalStore)?
    /// Test seam: redirects the trading cache directory away from
    /// Application Support.
    static var cacheDirectoryOverride: URL?
    #endif

    private var store: any ExchangeJournalStore {
        #if DEBUG
        if let override = Self.storeOverride { return override }
        #endif
        return JournalStore.shared
    }

    init() {}

    var activeBinding: JournalExchangeBinding? {
        store.activeJournal?.exchangeBinding
    }

    var isEnabled: Bool {
        #if DEBUG
        if Self.skipKeychainAccess { return false }
        #endif
        guard let binding = activeBinding else { return false }
        if binding.venue == .hyperliquid {
            return HyperliquidInfoClient.normalizedAddress(binding.accountLabel) != nil
        }
        return loadSecrets(for: store.activeJournalID) != nil
    }

    // MARK: - Lifecycle

    func start() {
        observeJournalChanges()
        loadCacheForActiveJournal()
        updateHasCredentials()
        guard isEnabled else { return }
        scheduleTimer()
        refreshIfStale()
    }

    func positions(entryID: UUID, entryDate: Date, itemID: UUID, tag: String) -> [TradingPosition] {
        guard let all = snapshot?.positions else { return [] }
        let tradingDayKey = JournalDayKey.make(from: entryDate)
        let matched = SymbolTagMatcher
            .filter(all, matchingTag: tag)
            .filter { JournalDayKey.make(from: $0.openTime) == tradingDayKey }
            .sorted { $0.openTime < $1.openTime }
        guard !matched.isEmpty,
              let journalID = store.activeJournalID,
              let entry = loadableEntries(for: journalID).entries.first(where: { $0.id == entryID })
        else {
            return matched
        }
        return Self.positions(
            matched,
            ownedBy: itemID,
            currentTag: tag,
            items: entry.items
        )
    }

    /// A position is a day-level entity and appears under only one matching item.
    static func positions(
        _ positions: [TradingPosition],
        ownedBy itemID: UUID,
        currentTag: String,
        items: [JournalItem]
    ) -> [TradingPosition] {
        positions.filter { position in
            items.first(where: { item in
                let candidateTag = item.id == itemID ? currentTag : item.tag
                return SymbolTagMatcher.matches(tag: candidateTag, symbol: position.symbol)
            })?.id == itemID
        }
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
        // A binding change invalidates any in-flight run for the old binding.
        cancelTasks(for: journalID)
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .hyperliquid, accountLabel: normalized),
            for: journalID
        )
        lastError = nil
        errorsByJournal[journalID] = nil
        updateHasCredentials()
        scheduleTimer()
        syncNow(journalID: journalID)
    }

    func disconnect(journalID: UUID) {
        cancelTasks(for: journalID)
        secretStore(for: journalID).clear()
        store.setExchangeBinding(nil, for: journalID)
        try? FileManager.default.removeItem(at: Self.cacheURL(for: journalID))
        if journalID == store.activeJournalID {
            snapshot = nil
        }
        lastError = nil
        errorsByJournal[journalID] = nil
        updateHasCredentials()
        refreshPublishedState()
        if !isEnabled { stopTimer() }
    }

    func binding(for journalID: UUID) -> JournalExchangeBinding? {
        store.journals.first(where: { $0.id == journalID })?.exchangeBinding
    }

    func isConfigured(for journalID: UUID) -> Bool {
        #if DEBUG
        if Self.skipKeychainAccess { return false }
        if let override = Self.configuredOverride {
            return override(journalID)
        }
        #endif
        guard let binding = binding(for: journalID) else { return false }
        if binding.venue == .hyperliquid {
            return HyperliquidInfoClient.normalizedAddress(binding.accountLabel) != nil
        }
        return loadSecrets(for: journalID) != nil
    }

    func lastFetchedAt(for journalID: UUID) -> Date? {
        if journalID == store.activeJournalID {
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
        guard let journalID = store.activeJournalID else { return }
        syncNow(journalID: journalID)
    }

    func syncNow(journalID: UUID) {
        guard runningJobs[journalID] == nil else { return }
        guard isConfigured(for: journalID),
              let binding = binding(for: journalID),
              let client = makeClient(binding: binding, journalID: journalID)
        else {
            if journalID == store.activeJournalID {
                hasCredentials = false
            }
            return
        }

        let token = JobToken(
            runID: UUID(),
            journalID: journalID,
            bindingFingerprint: Self.bindingFingerprint(for: binding, journalID: journalID),
            generation: generationByJournal[journalID, default: 0]
        )
        runningJobs[journalID] = token.runID
        jobTokens[token.runID] = token
        errorsByJournal[journalID] = nil
        refreshPublishedState()

        let cached = journalID == store.activeJournalID
            ? snapshot
            : loadSnapshot(at: Self.cacheURL(for: journalID))
        let desiredStart = Self.desiredWindowStart(
            entries: loadableEntries(for: journalID).entries
        )
        let task = Task { [weak self] in
            _ = await self?.runSync(
                client: client,
                cached: cached,
                desiredStart: desiredStart,
                token: token
            )
        }
        runningTasks[token.runID] = task
    }

    /// Cancels the in-flight run for a journal and bumps its generation, so a
    /// stale result can never be committed after a disconnect, a binding
    /// change, or a journal deletion.
    func cancelTasks(for journalID: UUID) {
        guard let runID = runningJobs[journalID] else { return }
        runningTasks[runID]?.cancel()
        runningTasks.removeValue(forKey: runID)
        jobTokens.removeValue(forKey: runID)
        runningJobs.removeValue(forKey: journalID)
        generationByJournal[journalID, default: 0] += 1
        refreshPublishedState()
    }

    /// Recomputes the published busy/error state from the ACTIVE journal so a
    /// background run for another journal never leaks its status into the UI.
    func refreshPublishedState() {
        guard let activeID = store.activeJournalID else {
            isSyncing = false
            lastError = nil
            return
        }
        isSyncing = runningJobs[activeID] != nil
        lastError = errorsByJournal[activeID] ?? nil
    }

    private static func bindingFingerprint(
        for binding: JournalExchangeBinding,
        journalID: UUID
    ) -> String {
        "\(journalID.uuidString)|\(binding.venue.rawValue)|\(binding.accountLabel)"
    }

    private func bindingFingerprint(for journalID: UUID) -> String {
        guard let binding = binding(for: journalID) else {
            return "none|\(journalID.uuidString)"
        }
        return Self.bindingFingerprint(for: binding, journalID: journalID)
    }

    private func runSync(
        client: any ExchangeTradeClient,
        cached: TradingPositionSnapshot?,
        desiredStart: Date,
        token: JobToken
    ) async {
        do {
            let now = Date()
            var fills = cached?.fills ?? []
            var funding = cached?.funding ?? []
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

            // Funding is supplementary: a failure must never block positions,
            // so it is fetched best-effort and the last known good set is kept.
            // A cache written before funding support has fills but no funding
            // history — backfill the whole covered window once so funding isn't
            // stuck at the incremental tail forever.
            var fetchedFunding: [FundingEvent] = []
            var fundingBackfilled = cached?.fundingBackfilled == true
            let fundingRanges = fundingBackfilled ? ranges : [(windowStart, now)]
            if !fundingRanges.isEmpty {
                do {
                    for range in fundingRanges {
                        fetchedFunding += try await client.fetchFunding(from: range.0, to: range.1)
                    }
                    fundingBackfilled = true
                } catch {
                    fetchedFunding = []
                    Self.log.error("funding fetch failed: \(String(describing: error), privacy: .public)")
                }
            }

            if !ranges.isEmpty {
                var seen = Set(fills.map { "\($0.symbol)#\($0.id)" })
                for fill in fetched where seen.insert("\(fill.symbol)#\(fill.id)").inserted {
                    fills.append(fill)
                }
                fills.sort { ($0.time, $0.id) < ($1.time, $1.id) }

                var fundingSeen = Set(funding.map { "\($0.symbol)#\($0.time)" })
                for event in fetchedFunding where fundingSeen.insert("\(event.symbol)#\(event.time)").inserted {
                    funding.append(event)
                }
                funding.sort { ($0.time, $0.symbol) < ($1.time, $1.symbol) }
            }
            fills = TradingFill.clipped(fills, from: windowStart, to: now)
            let startMs = Int64((windowStart.timeIntervalSince1970 * 1000).rounded())
            let endMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
            funding = funding.filter { $0.time >= startMs && $0.time < endMs }

            // CPU-heavy aggregation runs off the main actor (snapshot the
            // fills into an immutable value so the detached task never races
            // the mutable local).
            let fillsSnapshot = fills
            let fundingSnapshot = funding
            let positions = await Task.detached(priority: .utility) {
                FundingAttributor.attach(
                    positions: PositionAggregator.aggregate(fills: fillsSnapshot),
                    funding: fundingSnapshot
                )
            }.value
            let emptyWindow = fills.isEmpty
            finishSync(
                fills: fills,
                positions: positions,
                windowStart: windowStart,
                token: token,
                error: emptyWindow ? .emptyWindow : nil,
                funding: funding,
                fundingBackfilled: fundingBackfilled
            )
        } catch let error as ExchangeClientError {
            finishSync(
                fills: nil, positions: nil, windowStart: nil, token: token,
                error: ExchangeSyncError(error)
            )
        } catch let error as BinanceError {
            finishSync(
                fills: nil, positions: nil, windowStart: nil, token: token,
                error: ExchangeSyncError(error)
            )
        } catch {
            finishSync(
                fills: nil, positions: nil, windowStart: nil, token: token,
                error: .other
            )
        }
    }

    private func finishSync(
        fills: [TradingFill]?,
        positions: [TradingPosition]?,
        windowStart: Date?,
        token: JobToken,
        error: ExchangeSyncError?,
        funding: [FundingEvent]? = nil,
        fundingBackfilled: Bool = false
    ) {
        defer {
            // Only clear the per-journal mapping when this run is STILL the
            // latest — an old cancelled task finishing after a newer run started
            // must never wipe the newer run's identity (AC-P1-06).
            if runningJobs[token.journalID] == token.runID {
                runningJobs.removeValue(forKey: token.journalID)
            }
            runningTasks.removeValue(forKey: token.runID)
            jobTokens.removeValue(forKey: token.runID)
            refreshPublishedState()
        }

        // Verify the result is still the one the caller asked for: same run is
        // still the latest for the journal, the journal is still in the
        // catalog, the binding fingerprint is unchanged, and the generation
        // was not bumped by a cancel. A stale result is discarded entirely —
        // no cache write, no auto-creation, no error state.
        guard jobTokens[token.runID] == token,
              runningJobs[token.journalID] == token.runID,
              store.journals.contains(where: { $0.id == token.journalID }),
              bindingFingerprint(for: token.journalID) == token.bindingFingerprint,
              generationByJournal[token.journalID, default: 0] == token.generation,
              !Task.isCancelled
        else {
            return
        }

        errorsByJournal[token.journalID] = error
        let accepted = (error == nil || error == .emptyWindow)
        guard accepted, let fills, let positions, let windowStart else {
            if error == .invalidKey, token.journalID == store.activeJournalID {
                stopTimer()
            }
            return
        }

        let journalID = token.journalID
        ensurePositionEntriesIfNeeded(
            positions: positions,
            journalID: journalID
        )

        let next = TradingPositionSnapshot(
            fetchedAt: Date(),
            windowStart: windowStart,
            positions: positions,
            fills: fills,
            funding: funding ?? [],
            fundingBackfilled: fundingBackfilled
        )
        saveCache(next, for: journalID)
        if journalID == store.activeJournalID {
            snapshot = next
        }
    }

    private func rebuildDerivedStats() {
        pnlByDay = DailyRealizedPnl.netSumsByOpenDay(
            positions: snapshot?.positions ?? [],
            calendar: .current
        )
        var counts: [String: Int] = [:]
        for position in snapshot?.positions ?? [] where position.isClosed {
            counts[JournalDayKey.make(from: position.openTime), default: 0] += 1
        }
        closedCountByDayKey = counts
    }

    /// Loads a journal's entries for windowing / auto-creation. Corrupt or
    /// newer-format journals yield no entries and must NOT be auto-created
    /// (their file stays byte-for-byte untouched).
    private func loadableEntries(for journalID: UUID) -> (entries: [JournalEntry], canAutoCreate: Bool) {
        switch store.entries(for: journalID) {
        case .active(let entries), .loaded(let entries):
            return (entries, true)
        case .missing:
            return ([], true)
        case .corrupt, .unsupportedVersion:
            return ([], false)
        }
    }

    private func ensurePositionEntriesIfNeeded(
        positions: [TradingPosition],
        journalID: UUID
    ) {
        if journalID == store.activeJournalID {
            NotificationCenter.default.post(name: .wickWillFlushJournalDrafts, object: nil)
        }
        let loaded = loadableEntries(for: journalID)
        guard loaded.canAutoCreate else { return }
        let journalEntries = loaded.entries
        var existingTagsByDay: [String: [String]] = [:]
        for entry in journalEntries {
            let tradingDayKey = JournalDayKey.make(from: entry.date)
            existingTagsByDay[tradingDayKey, default: []].append(
                contentsOf: entry.items.map(\.tag)
            )
        }
        let plan = PositionEntryPlanner.plan(
            positions: positions,
            existingTagsByDay: existingTagsByDay,
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

        var reservedItemIDs = Set(journalEntries.flatMap { $0.items.map(\.id) })
        func itemID(dayKey: String, symbol: String) -> UUID {
            let stable = PositionEntryPlanner.stableItemID(
                journalID: journalID,
                dayKey: dayKey,
                symbol: symbol
            )
            if reservedItemIDs.insert(stable).inserted {
                return stable
            }
            let fallback = UUID()
            reservedItemIDs.insert(fallback)
            return fallback
        }

        let skeletons: [(day: Date, items: [JournalItem])] = plan.compactMap { planned in
            var coveredTags = existingTagsByDay[planned.dayKey] ?? []
            var items: [JournalItem] = []
            for symbol in planned.symbols {
                guard !coveredTags.contains(where: {
                    SymbolTagMatcher.matches(tag: $0, symbol: symbol)
                }) else { continue }
                let tag = tagForSymbol(symbol)
                items.append(
                    JournalItem(
                        id: itemID(dayKey: planned.dayKey, symbol: symbol),
                        tag: tag
                    )
                )
                coveredTags.append(tag)
            }
            guard !items.isEmpty else { return nil }
            return (
                day: planned.day,
                items: items
            )
        }
        let changedDays = store.ensurePositionEntries(skeletons, in: journalID)
        if !changedDays.isEmpty {
            NSLog("Wick exchange: ensured position items on %ld journal day(s)", changedDays.count)
        }
    }

    // MARK: - Journal switching

    private func observeJournalChanges() {
        observedJournalID = store.activeJournalID
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

    func activeJournalDidChange() {
        let newID = store.activeJournalID
        guard newID != observedJournalID else {
            updateHasCredentials()
            refreshPublishedState()
            return
        }
        observedJournalID = newID
        loadCacheForActiveJournal()
        updateHasCredentials()
        // Re-derive busy/error for the CURRENT journal immediately: switching
        // away from a syncing journal must not leave stale `isSyncing`/error,
        // and `refreshIfStale()` must see the fresh state (AC-P1-06).
        refreshPublishedState()
        if isEnabled {
            scheduleTimer()
            refreshIfStale()
        } else {
            stopTimer()
        }
    }

    func pruneDeletedJournals(_ journals: [JournalInfo]) {
        let live = Set(journals.map(\.id))
        // Cancel every in-flight run whose journal left the catalog, even if it
        // never produced a cache file (first sync deleted mid-request).
        for id in runningJobs.keys where !live.contains(id) {
            cancelTasks(for: id)
        }
        let dir = Self.tradingDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "json" {
            let name = file.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name), !live.contains(id) else { continue }
            // A deleted journal must never be resurrected by a stale run.
            cancelTasks(for: id)
            secretStore(for: id).clear()
            try? FileManager.default.removeItem(at: file)
            errorsByJournal.removeValue(forKey: id)
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
        // Saving new credentials invalidates any in-flight run using the old
        // secret, so its result can never be committed after the change.
        cancelTasks(for: journalID)
        saveSecrets(blob, for: journalID)
        store.setExchangeBinding(
            JournalExchangeBinding(venue: venue, accountLabel: label),
            for: journalID
        )
        lastError = nil
        errorsByJournal[journalID] = nil
        updateHasCredentials()
        scheduleTimer()
        syncNow(journalID: journalID)
    }

    private func makeClient(
        binding: JournalExchangeBinding,
        journalID: UUID
    ) -> (any ExchangeTradeClient)? {
        #if DEBUG
        if let override = Self.clientFactoryOverride {
            return override(binding, journalID)
        }
        #endif
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
        #if DEBUG
        if let override = Self.cacheDirectoryOverride { return override }
        #endif
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Wick/Trading", isDirectory: true)
    }

    private static func cacheURL(for journalID: UUID) -> URL {
        tradingDirectory().appendingPathComponent("\(journalID.uuidString).json")
    }

    private func loadCacheForActiveJournal() {
        guard let journalID = store.activeJournalID else {
            snapshot = nil
            return
        }
        snapshot = loadSnapshot(at: Self.cacheURL(for: journalID))
        if let positions = snapshot?.positions, !positions.isEmpty {
            ensurePositionEntriesIfNeeded(positions: positions, journalID: journalID)
        }
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
