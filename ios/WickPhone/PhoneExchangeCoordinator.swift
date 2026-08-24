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

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.cloudSyncEnabled = UserDefaults.standard.bool(forKey: Self.cloudSyncEnabledKey)

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = support.appendingPathComponent("Wick/Trading", isDirectory: true)
        self.cacheDirectory = dir
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        // Listen for active journal changes
        PhoneJournalStore.shared.$activeJournalID
            .sink { [weak self] journalID in
                self?.loadSnapshot(for: journalID)
            }
            .store(in: &cancellables)

        loadSnapshot(for: PhoneJournalStore.shared.activeJournalID)
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
        snapshot = loaded
    }

    func snapshot(for journalID: UUID) -> TradingPositionSnapshot? {
        if journalID == PhoneJournalStore.shared.activeJournalID {
            return snapshot
        }
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: data)
        else { return nil }
        return loaded
    }

    private func saveSnapshot(_ newSnapshot: TradingPositionSnapshot, for journalID: UUID) {
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        if let data = try? JSONEncoder().encode(newSnapshot) {
            try? data.write(to: url, options: .atomic)
        }
        if journalID == PhoneJournalStore.shared.activeJournalID {
            snapshot = newSnapshot
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

    func isConfigured(for journalID: UUID) -> Bool {
        binding(for: journalID) != nil
    }

    func binding(for journalID: UUID) -> JournalExchangeBinding? {
        PhoneJournalStore.shared.journals.first(where: { $0.id == journalID })?.exchangeBinding
    }

    func isSyncing(for journalID: UUID) -> Bool {
        syncingJournalIDs.contains(journalID)
    }

    func error(for journalID: UUID) -> String? {
        errorsByJournal[journalID]
    }

    // MARK: - Fetch & Sync

    func syncNow(journalID: UUID? = nil) {
        let targetID = journalID ?? PhoneJournalStore.shared.activeJournalID
        guard let targetID,
              let journal = PhoneJournalStore.shared.journals.first(where: { $0.id == targetID }),
              let binding = journal.exchangeBinding
        else { return }

        guard !syncingJournalIDs.contains(targetID) else { return }
        syncingJournalIDs.insert(targetID)
        isSyncing = !syncingJournalIDs.isEmpty
        lastError = nil
        errorsByJournal.removeValue(forKey: targetID)

        Task {
            do {
                let client = try makeClient(for: binding, journalID: targetID)
                let entries = (targetID == PhoneJournalStore.shared.activeJournalID)
                    ? PhoneJournalStore.shared.entries
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

                saveSnapshot(newSnapshot, for: targetID)
                syncingJournalIDs.remove(targetID)
                isSyncing = !syncingJournalIDs.isEmpty
            } catch {
                let msg = error.localizedDescription
                errorsByJournal[targetID] = msg
                lastError = msg
                syncingJournalIDs.remove(targetID)
                isSyncing = !syncingJournalIDs.isEmpty
            }
        }
    }

    private func makeClient(for binding: JournalExchangeBinding, journalID: UUID) throws -> any ExchangeTradeClient {
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
        if let secrets {
            saveSecret(secrets, for: journalID)
        }
        PhoneJournalStore.shared.setExchangeBinding(binding, for: journalID)
        syncNow(journalID: journalID)
    }

    func removeBinding(for journalID: UUID) {
        deleteSecret(for: journalID)
        PhoneJournalStore.shared.setExchangeBinding(nil, for: journalID)
        removeCloudSnapshot(for: journalID)
        if journalID == PhoneJournalStore.shared.activeJournalID {
            snapshot = nil
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
        guard let downloaded = try? JSONDecoder().decode(TradingPositionSnapshot.self, from: document.payload) else {
            return
        }

        let currentFetched = snapshot(for: journalID)?.fetchedAt ?? .distantPast
        if downloaded.fetchedAt >= currentFetched {
            saveSnapshot(downloaded, for: journalID)
        }
    }

    func removeCloudSnapshot(for journalID: UUID) {
        let url = cacheDirectory.appendingPathComponent("\(journalID.uuidString).json")
        try? fileManager.removeItem(at: url)
        if journalID == PhoneJournalStore.shared.activeJournalID {
            snapshot = nil
        }
    }
}
