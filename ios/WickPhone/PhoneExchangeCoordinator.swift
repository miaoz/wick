import Combine
import Foundation
import WickSync
import WickTrading

/// Per-journal exchange credentials stored as one Keychain item.
struct ExchangeSecretBlob: Codable, Equatable {
    var venue: ExchangeVenue
    var apiKey: String
    var secret: String
    var passphrase: String?
}

/// Exchange integration coordinator on iOS:
/// 1. Owns per-journal exchange bindings (Binance USD-M, OKX SWAP, Hyperliquid).
/// 2. Fetches trade fills, aggregates sessions into `TradingPosition`, calculates realized PnL.
/// 3. Manages local snapshot cache (`Wick/Trading/<journalID>.json`).
/// 4. Bridges cloud snapshot sync via Dropbox (`trading/snapshot.json`).
@MainActor
final class PhoneExchangeCoordinator: ObservableObject {
    static let shared = PhoneExchangeCoordinator()

    static let refreshInterval: TimeInterval = 30 * 60
    private static let serviceName = "com.miaoz.wick.exchange.phone"
    private static let cloudSyncEnabledKey = "wick.sync.tradingSnapshotEnabled"

    @Published private(set) var snapshot: TradingPositionSnapshot? {
        didSet { rebuildDerivedStats() }
    }
    @Published private(set) var isSyncing = false
    @Published private(set) var syncingJournalIDs: Set<UUID> = []
    @Published private(set) var lastError: String?
    @Published private(set) var errorsByJournal: [UUID: String] = [:]

    @Published var cloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudSyncEnabled, forKey: Self.cloudSyncEnabledKey)
        }
    }

    private(set) var pnlByDay: [Date: Double] = [:]
    private(set) var closedCountByDayKey: [String: Int] = [:]
    private(set) var openCountByDayKey: [String: Int] = [:]

    private let fileManager = FileManager.default
    private let store: PhoneJournalStore
    private let cacheDirectory: URL
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Per-journal run identity (EX-01 port)

    /// Identity frozen at request time; a result is committed only while its
    /// token is still the latest for the journal AND the binding is unchanged.
    /// Without this, an in-flight fetch that outlives an unbind/delete would
    /// write an orphan snapshot (and, with cloud sync on, upload it).
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

    #if DEBUG
    /// Test seam: substitute client construction so lifecycle tests run without
    /// Keychain or network. Returning nil means "no usable client".
    static var clientFactoryOverride: ((JournalExchangeBinding) -> (any ExchangeTradeClient)?)?
    #endif

    private static func realCacheDirectory() -> URL {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("Wick/Trading", isDirectory: true)
    }

    init(store: PhoneJournalStore = .shared, cacheDirectory: URL = PhoneExchangeCoordinator.realCacheDirectory()) {
        self.cloudSyncEnabled = UserDefaults.standard.bool(forKey: Self.cloudSyncEnabledKey)
        self.store = store
        self.cacheDirectory = cacheDirectory
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Listen for active journal changes
        store.$activeJournalID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] journalID in
                self?.loadSnapshot(for: journalID)
            }
            .store(in: &cancellables)

        // A deleted journal must never be resurrected by a stale run.
        store.$journals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] journals in
                self?.pruneDeletedJournals(journals)
            }
            .store(in: &cancellables)

        loadSnapshot(for: store.activeJournalID)
    }

    // MARK: - Snapshot Loading & Caching

    func loadSnapshot(for journalID: UUID?) {
        guard let journalID else {
            snapshot = nil
            return
        }
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        else {
            snapshot = nil
            return
        }
        snapshot = rebuildingDerivedPositions(in: loaded)
    }

    func snapshot(for journalID: UUID) -> TradingPositionSnapshot? {
        if journalID == store.activeJournalID {
            return snapshot
        }
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        else { return nil }
        return rebuildingDerivedPositions(in: loaded)
    }

    private func rebuildingDerivedPositions(
        in snapshot: TradingPositionSnapshot
    ) -> TradingPositionSnapshot {
        guard !snapshot.fills.isEmpty else { return snapshot }
        var rebuilt = snapshot
        rebuilt.positions = FundingAttributor.attach(
            positions: PositionAggregator.aggregate(fills: snapshot.fills),
            funding: snapshot.funding
        )
        return rebuilt
    }

    /// Number of aggregated trading positions for a journal.
    func positionsCount(for journalID: UUID) -> Int {
        snapshot(for: journalID)?.positions.count ?? 0
    }

    private func saveSnapshot(_ newSnapshot: TradingPositionSnapshot, for journalID: UUID) {
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        if let data = try? JSONEncoder().encode(newSnapshot) {
            try? data.write(to: url, options: .atomic)
        }
        if journalID == store.activeJournalID {
            snapshot = newSnapshot
        }
    }

    private func rebuildDerivedStats() {
        pnlByDay = DailyRealizedPnl.netSumsByOpenDay(
            positions: snapshot?.positions ?? [],
            calendar: .current
        )
        var closedCounts: [String: Int] = [:]
        var openCounts: [String: Int] = [:]
        for position in snapshot?.positions ?? [] {
            let dayKey = JournalDayKey.make(from: position.openTime)
            if position.isClosed {
                closedCounts[dayKey, default: 0] += 1
            } else {
                openCounts[dayKey, default: 0] += 1
            }
        }
        closedCountByDayKey = closedCounts
        openCountByDayKey = openCounts
    }

    // MARK: - Query Positions

    func positions(entryDate: Date, tag: String) -> [TradingPosition] {
        guard let all = snapshot?.positions else { return [] }
        let tradingDayKey = JournalDayKey.make(from: entryDate)
        return SymbolTagMatcher
            .filter(all, matchingTag: tag)
            .filter { JournalDayKey.make(from: $0.openTime) == tradingDayKey }
            .sorted { $0.openTime < $1.openTime }
    }

    func pnl(for date: Date) -> Double? {
        let start = Calendar.current.startOfDay(for: date)
        return pnlByDay[start]
    }

    func closedCount(for dayKey: String) -> Int {
        closedCountByDayKey[dayKey] ?? 0
    }

    func openCount(for dayKey: String) -> Int {
        openCountByDayKey[dayKey] ?? 0
    }

    func isConfigured(for journalID: UUID) -> Bool {
        binding(for: journalID) != nil
    }

    func binding(for journalID: UUID) -> JournalExchangeBinding? {
        store.journals.first(where: { $0.id == journalID })?.exchangeBinding
    }

    func isSyncing(for journalID: UUID) -> Bool {
        syncingJournalIDs.contains(journalID)
    }

    func error(for journalID: UUID) -> String? {
        errorsByJournal[journalID]
    }

    // MARK: - Fetch & Sync

    func syncNow(journalID: UUID? = nil) {
        let targetID = journalID ?? store.activeJournalID
        guard let targetID,
              let journal = store.journals.first(where: { $0.id == targetID }),
              let binding = journal.exchangeBinding
        else { return }

        guard runningJobs[targetID] == nil else { return }
        let token = JobToken(
            runID: UUID(),
            journalID: targetID,
            bindingFingerprint: Self.bindingFingerprint(for: binding, journalID: targetID),
            generation: generationByJournal[targetID, default: 0]
        )
        runningJobs[targetID] = token.runID
        jobTokens[token.runID] = token
        syncingJournalIDs.insert(targetID)
        isSyncing = !syncingJournalIDs.isEmpty
        lastError = nil
        errorsByJournal.removeValue(forKey: targetID)

        let task = Task { [weak self] in
            _ = await self?.fetchAndCommit(token: token, binding: binding)
        }
        runningTasks[token.runID] = task
    }

    /// Fetches fills/funding for a frozen run identity and commits the result
    /// only while the token is still current (EX-01). A stale result — an
    /// in-flight fetch after unbind/delete/rebind — is discarded entirely.
    private func fetchAndCommit(token: JobToken, binding: JournalExchangeBinding) async {
        let targetID = token.journalID
        do {
            let client = try makeClient(for: binding, journalID: targetID)
            let entries = (targetID == store.activeJournalID)
                ? store.entries
                : []
            let earliestDay = entries.map(\.date).min() ?? Date()
            let windowStart = Calendar.current.startOfDay(for: earliestDay)
            let windowEnd = Date()

            let fills = try await client.fetchFills(from: windowStart, to: windowEnd)
            let funding = (try? await client.fetchFunding(from: windowStart, to: windowEnd)) ?? []
            let positions = PositionAggregator.aggregate(fills: fills)

            let newSnapshot = TradingPositionSnapshot(
                fetchedAt: Date(),
                windowStart: windowStart,
                positions: positions,
                fills: fills,
                funding: funding,
                fundingBackfilled: false,
                sourceVenue: binding.venue.rawValue,
                sourceAccountLabel: binding.accountLabel
            )

            guard jobTokens[token.runID] == token,
                  runningJobs[targetID] == token.runID,
                  store.journals.contains(where: { $0.id == targetID }),
                  bindingFingerprint(for: targetID) == token.bindingFingerprint,
                  generationByJournal[targetID, default: 0] == token.generation,
                  !Task.isCancelled
            else {
                finishSync(token: token, error: nil)
                return
            }
            saveSnapshot(newSnapshot, for: targetID)
            finishSync(token: token, error: nil)
        } catch {
            finishSync(token: token, error: error.localizedDescription)
        }
    }

    private func finishSync(token: JobToken, error: String?) {
        defer {
            // Only clear the per-journal mapping when this run is STILL the
            // latest — an old cancelled task finishing after a newer run started
            // must never wipe the newer run's identity.
            if runningJobs[token.journalID] == token.runID {
                runningJobs.removeValue(forKey: token.journalID)
            }
            runningTasks.removeValue(forKey: token.runID)
            jobTokens.removeValue(forKey: token.runID)
            syncingJournalIDs.remove(token.journalID)
            isSyncing = !syncingJournalIDs.isEmpty
        }
        guard jobTokens[token.runID] == token,
              runningJobs[token.journalID] == token.runID,
              store.journals.contains(where: { $0.id == token.journalID }),
              bindingFingerprint(for: token.journalID) == token.bindingFingerprint,
              generationByJournal[token.journalID, default: 0] == token.generation
        else {
            return
        }
        if let error {
            errorsByJournal[token.journalID] = error
            lastError = error
        }
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
        syncingJournalIDs.remove(journalID)
        isSyncing = !syncingJournalIDs.isEmpty
    }

    private func makeClient(for binding: JournalExchangeBinding, journalID: UUID) throws -> any ExchangeTradeClient {
        #if DEBUG
        if let override = Self.clientFactoryOverride {
            guard let client = override(binding) else {
                throw ExchangeClientError.invalidCredentials("No client factory override")
            }
            return client
        }
        #endif
        switch binding.venue {
        case .hyperliquid:
            return HyperliquidInfoClient(user: binding.accountLabel)
        case .binance:
            guard let secret = loadSecret(for: journalID) else {
                throw ExchangeClientError.invalidCredentials("Missing credentials for Binance")
            }
            return BinanceFuturesClient(apiKey: secret.apiKey, secret: secret.secret)
        case .okx:
            guard let secret = loadSecret(for: journalID) else {
                throw ExchangeClientError.invalidCredentials("Missing credentials for OKX")
            }
            return OKXSwapClient(
                apiKey: secret.apiKey,
                secret: secret.secret,
                passphrase: secret.passphrase ?? ""
            )
        }
    }

    // MARK: - Bindings & Secrets

    func setBinding(_ binding: JournalExchangeBinding, secrets: ExchangeSecretBlob?, for journalID: UUID) {
        // Saving a new binding invalidates any in-flight run using the old one,
        // so its result can never be committed after the change.
        cancelTasks(for: journalID)
        if let secrets {
            saveSecret(secrets, for: journalID)
        }
        store.setExchangeBinding(binding, for: journalID)
        syncNow(journalID: journalID)
    }

    func removeBinding(for journalID: UUID) {
        cancelTasks(for: journalID)
        deleteSecret(for: journalID)
        store.setExchangeBinding(nil, for: journalID)
        removeCloudSnapshot(for: journalID)
        if journalID == store.activeJournalID {
            snapshot = nil
        }
    }

    /// Cancels every in-flight run whose journal left the catalog, even if it
    /// never produced a cache file (first sync deleted mid-request).
    func pruneDeletedJournals(_ journals: [JournalInfo]) {
        let live = Set(journals.map(\.id))
        for id in runningJobs.keys where !live.contains(id) {
            cancelTasks(for: id)
        }
    }

    private func tokenStore(for journalID: UUID) -> KeychainTokenStore {
        KeychainTokenStore(service: Self.serviceName, account: journalID.uuidString)
    }

    private func loadSecret(for journalID: UUID) -> ExchangeSecretBlob? {
        guard let json = tokenStore(for: journalID).load(),
              let data = json.data(using: .utf8),
              let blob = try? JSONDecoder().decode(ExchangeSecretBlob.self, from: data)
        else { return nil }
        return blob
    }

    private func saveSecret(_ secret: ExchangeSecretBlob, for journalID: UUID) {
        guard let data = try? JSONEncoder().encode(secret),
              let json = String(data: data, encoding: .utf8)
        else { return }
        tokenStore(for: journalID).save(json)
    }

    private func deleteSecret(for journalID: UUID) {
        tokenStore(for: journalID).clear()
    }

    // MARK: - Cloud Snapshot Sync (Dropbox Bridge)

    func cloudSnapshotDocument(for journalID: UUID) -> JournalTradingSnapshotDocument? {
        guard cloudSyncEnabled else { return nil }
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        else { return nil }

        let venue = snap.sourceVenue ?? "unknown"
        let accountLabel = snap.sourceAccountLabel ?? "Cloud"
        return JournalTradingSnapshotDocument(
            journalID: journalID,
            venue: venue,
            accountLabel: accountLabel,
            fetchedAt: snap.fetchedAt,
            payload: data
        )
    }

    func applyCloudSnapshotDocument(_ document: JournalTradingSnapshotDocument, journalID: UUID) {
        guard cloudSyncEnabled else { return }
        guard var downloaded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: document.payload) else {
            return
        }

        let currentFetched = snapshot(for: journalID)?.fetchedAt ?? .distantPast
        if downloaded.fetchedAt >= currentFetched {
            downloaded = rebuildingDerivedPositions(in: downloaded)
            downloaded.sourceVenue = document.venue
            downloaded.sourceAccountLabel = document.accountLabel
            saveSnapshot(downloaded, for: journalID)
        }
    }

    func removeCloudSnapshot(for journalID: UUID) {
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        try? fileManager.removeItem(at: url)
        if journalID == store.activeJournalID {
            snapshot = nil
        }
    }
}
