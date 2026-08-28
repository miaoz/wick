import Combine
import XCTest
import WickSync
import WickTrading
@testable import WickCore

/// A client that blocks each fetch until the test releases it, so a run can be
/// observed mid-flight and then cancelled/invalidated.
actor BlockingTradeClient: ExchangeTradeClient {
    private let errorToThrow: ExchangeClientError?
    private var fetchCount = 0
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var cancelledWhileBlocked = false

    init(error: ExchangeClientError? = nil) {
        errorToThrow = error
    }

    func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill] {
        fetchCount += 1
        await withCheckedContinuation { cont in
            releaseContinuation = cont
        }
        if Task.isCancelled {
            cancelledWhileBlocked = true
            throw CancellationError()
        }
        if let errorToThrow {
            throw errorToThrow
        }
        return []
    }

    func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent] {
        []
    }

    func waitUntilFetchStarted() async {
        while fetchCount == 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// A client that returns fixed fills/funding immediately (or throws on funding),
/// for exercising the coordinator's funding cache and net-PnL path.
actor StubTradeClient: ExchangeTradeClient {
    private let fills: [TradingFill]
    private let funding: [FundingEvent]
    private let throwOnFunding: Bool
    private(set) var recordedFundingRanges: [(Date, Date)] = []

    init(fills: [TradingFill] = [], funding: [FundingEvent] = [], throwOnFunding: Bool = false) {
        self.fills = fills
        self.funding = funding
        self.throwOnFunding = throwOnFunding
    }

    func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill] {
        fills
    }

    func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent] {
        recordedFundingRanges.append((start, end))
        if throwOnFunding {
            throw ExchangeClientError.network("funding unavailable")
        }
        return funding
    }
}

/// Lifecycle tests for the exchange coordinator's per-journal run identity:
/// stale results (after disconnect / journal deletion / binding change) must be
/// discarded without touching cache, journal, or error state.
@MainActor
final class ExchangePositionCoordinatorTests: XCTestCase {
    private var tempRoot: URL!
    private var cacheRoot: URL!
    private var store: JournalStore!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickExchangeTests-\(UUID().uuidString)", isDirectory: true)
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickExchangeCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        store = JournalStore(rootDirectory: tempRoot)
        ExchangePositionCoordinator.skipKeychainAccess = false
        ExchangePositionCoordinator.clientFactoryOverride = nil
        ExchangePositionCoordinator.configuredOverride = nil
        ExchangePositionCoordinator.storeOverride = store
        ExchangePositionCoordinator.cacheDirectoryOverride = cacheRoot
    }

    override func tearDown() async throws {
        ExchangePositionCoordinator.clientFactoryOverride = nil
        ExchangePositionCoordinator.configuredOverride = nil
        ExchangePositionCoordinator.storeOverride = nil
        ExchangePositionCoordinator.cacheDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
        try? FileManager.default.removeItem(at: cacheRoot)
        store = nil
        tempRoot = nil
        cacheRoot = nil
    }

    private func bindActiveJournal() -> UUID {
        let id = store.activeJournalID!
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .binance, accountLabel: "Binance"),
            for: id
        )
        ExchangePositionCoordinator.configuredOverride = { _ in true }
        return id
    }

    private func cacheFile(for journalID: UUID) -> URL {
        cacheRoot.appendingPathComponent("\(journalID.uuidString).json", isDirectory: false)
    }

    private func awaitRunCompletion(_ coordinator: ExchangePositionCoordinator) async {
        // Poll until the coordinator has no in-flight run for the active journal.
        for _ in 0..<200 {
            if !coordinator.isSyncing { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func emptySnapshot(fetchedAt: Date = Date()) -> TradingPositionSnapshot {
        TradingPositionSnapshot(
            fetchedAt: fetchedAt,
            windowStart: fetchedAt.addingTimeInterval(-3_600),
            positions: []
        )
    }

    func testEquivalentTagsRenderEachPositionOnlyOnce() {
        let first = JournalItem(tag: "BTC")
        let duplicate = JournalItem(tag: "BTC")
        let position = TradingPosition(
            id: "btc-1",
            symbol: "BTC",
            side: .long,
            openTime: Date(),
            closeTime: nil,
            entryPrice: 100,
            exitPrice: nil,
            peakSize: 1,
            realizedPnl: 0
        )

        XCTAssertEqual(
            ExchangePositionCoordinator.positions(
                [position],
                ownedBy: first.id,
                currentTag: first.tag,
                items: [first, duplicate]
            ).map(\.id),
            [position.id]
        )
        XCTAssertTrue(
            ExchangePositionCoordinator.positions(
                [position],
                ownedBy: duplicate.id,
                currentTag: duplicate.tag,
                items: [first, duplicate]
            ).isEmpty
        )
    }

    func testCloudSnapshotMasksHyperliquidAddressAndContainsNoCredentials() throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = store.activeJournalID!
        let address = "0x1234567890abcdef1234567890abcdef12345678"
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .hyperliquid, accountLabel: address),
            for: journalID
        )
        try JSONEncoder().encode(emptySnapshot()).write(to: cacheFile(for: journalID))

        let document = try XCTUnwrap(coordinator.cloudSnapshotDocument(for: journalID))
        XCTAssertEqual(document.venue, ExchangeVenue.hyperliquid.rawValue)
        XCTAssertEqual(document.accountLabel, "0x1234...5678")
        XCTAssertFalse(String(decoding: document.payload, as: UTF8.self).contains(address))
    }

    func testCloudSnapshotAppliesAtMillisecondPrecisionAndRefreshesActiveJournal() throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = store.activeJournalID!
        let fetchedAt = Date(timeIntervalSince1970: 1_777_777_777.1234)
        let cached = emptySnapshot(fetchedAt: fetchedAt)
        let document = JournalTradingSnapshotDocument(
            journalID: journalID,
            venue: ExchangeVenue.binance.rawValue,
            accountLabel: "Binance",
            fetchedAt: fetchedAt,
            payload: try JSONEncoder().encode(cached)
        )

        coordinator.applyCloudSnapshotDocument(document, journalID: journalID)

        XCTAssertEqual(coordinator.snapshot?.fetchedAt, fetchedAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile(for: journalID).path))
    }

    func testCloudSnapshotRebuildsDerivedPositionsBeforeCreatingEntries() throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = store.activeJournalID!
        let fetchedAt = Date()
        let closeOnlyFill = TradingFill(
            id: 7,
            symbol: "BTCUSDT",
            side: "SELL",
            price: 110,
            qty: 1,
            realizedPnl: 10,
            time: Self.ms(fetchedAt.addingTimeInterval(-60))
        )
        let stalePhantom = TradingPosition(
            id: "stale-phantom",
            symbol: "BTCUSDT",
            side: .short,
            openTime: fetchedAt.addingTimeInterval(-60),
            closeTime: nil,
            entryPrice: 110,
            exitPrice: nil,
            peakSize: 1,
            realizedPnl: 10
        )
        let cached = TradingPositionSnapshot(
            fetchedAt: fetchedAt,
            windowStart: Calendar.current.startOfDay(for: fetchedAt),
            positions: [stalePhantom],
            fills: [closeOnlyFill]
        )
        let document = JournalTradingSnapshotDocument(
            journalID: journalID,
            venue: ExchangeVenue.binance.rawValue,
            accountLabel: "Binance",
            fetchedAt: fetchedAt,
            payload: try JSONEncoder().encode(cached)
        )

        coordinator.applyCloudSnapshotDocument(document, journalID: journalID)

        XCTAssertTrue(coordinator.snapshot?.positions.isEmpty == true)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testLocalOnlyDisconnectPreservesReadOnlySnapshot() throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let cached = emptySnapshot()
        try JSONEncoder().encode(cached).write(to: cacheFile(for: journalID))
        coordinator.activeJournalDidChange()

        coordinator.disconnect(journalID: journalID, preserveSnapshot: true)

        XCTAssertNil(store.activeJournal?.exchangeBinding)
        XCTAssertEqual(coordinator.snapshot, cached)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile(for: journalID).path))
    }

    func testSyncAddsOnlyMissingSymbolItemToExistingDay() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        var entry = store.createEntry(on: now)
        entry.items = [JournalItem(tag: "BTC", body: "keep this note")]
        store.updateEntry(entry)
        let fills = [
            TradingFill(
                id: 1,
                symbol: "BTCUSDT",
                side: "BUY",
                price: 100,
                qty: 1,
                time: Self.ms(now.addingTimeInterval(-120))
            ),
            TradingFill(
                id: 2,
                symbol: "SKHYNIXUSDT",
                side: "BUY",
                price: 200,
                qty: 1,
                time: Self.ms(now.addingTimeInterval(-60))
            ),
        ]
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in
            StubTradeClient(fills: fills)
        }

        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        let updated = store.entries.first { $0.id == entry.id }
        XCTAssertEqual(updated?.items.map(\.tag), ["BTC", "SKHYNIX"])
        XCTAssertEqual(updated?.items.first?.body, "keep this note")
    }

    func testCloseOnlySyncDoesNotCreateJournalEntry() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let closeOnlyFill = TradingFill(
            id: 1,
            symbol: "BTCUSDT",
            side: "SELL",
            price: 110,
            qty: 1,
            realizedPnl: 10,
            time: Self.ms(now.addingTimeInterval(-60))
        )
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in
            StubTradeClient(fills: [closeOnlyFill])
        }

        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(coordinator.snapshot?.positions.isEmpty == true)
    }

    func testSyncCollapsesPairsCoveredBySamePreferredBaseTag() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let fills = [
            TradingFill(
                id: 1,
                symbol: "BTCUSDT",
                side: "BUY",
                price: 100,
                qty: 1,
                time: Self.ms(now.addingTimeInterval(-120))
            ),
            TradingFill(
                id: 2,
                symbol: "BTCUSDC",
                side: "BUY",
                price: 100,
                qty: 1,
                time: Self.ms(now.addingTimeInterval(-60))
            ),
        ]
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in
            StubTradeClient(fills: fills)
        }

        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.items.map(\.tag), ["BTC"])
    }

    func testCacheLoadCreatesMissingPositionDay() async throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let fills = [TradingFill(
            id: 7,
            symbol: "XAUUSDT",
            side: "BUY",
            price: 100,
            qty: 1,
            time: Self.ms(now.addingTimeInterval(-60))
        )]
        let position = try XCTUnwrap(PositionAggregator.aggregate(fills: fills).first)
        let cached = TradingPositionSnapshot(
            fetchedAt: now,
            windowStart: Calendar.current.startOfDay(for: now),
            positions: [position],
            fills: fills,
            fundingBackfilled: true
        )
        try JSONEncoder().encode(cached).write(to: cacheFile(for: journalID))
        coordinator.activeJournalDidChange()
        XCTAssertEqual(store.entries.first?.items.map(\.tag), ["XAU"])
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in
            StubTradeClient(fills: fills)
        }

        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.items.map(\.tag), ["XAU"])
    }

    func testCacheLoadRebuildsDerivedPositionsAndIgnoresOrphanClose() throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let closeOnlyFill = TradingFill(
            id: 7,
            symbol: "BTCUSDT",
            side: "SELL",
            price: 110,
            qty: 1,
            realizedPnl: 10,
            time: Self.ms(now.addingTimeInterval(-60))
        )
        let stalePhantom = TradingPosition(
            id: "BTCUSDT|BOTH|\(closeOnlyFill.time)|7",
            symbol: "BTCUSDT",
            side: .short,
            openTime: now.addingTimeInterval(-60),
            closeTime: nil,
            entryPrice: 110,
            exitPrice: nil,
            peakSize: 1,
            realizedPnl: 10
        )
        let cached = TradingPositionSnapshot(
            fetchedAt: now,
            windowStart: Calendar.current.startOfDay(for: now),
            positions: [stalePhantom],
            fills: [closeOnlyFill],
            fundingBackfilled: true
        )
        try JSONEncoder().encode(cached).write(to: cacheFile(for: journalID))

        coordinator.activeJournalDidChange()

        XCTAssertTrue(coordinator.snapshot?.positions.isEmpty == true)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCacheLoadMatchesDisplayedDateWhenStableDayKeyDiffers() throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let calendar = Calendar.current
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 7,
            hour: 10
        )))
        var entry = store.createEntry(on: day)
        let xau = JournalItem(tag: "XAU", body: "keep the original note")
        entry.items = [xau]
        store.updateEntry(entry)

        let fills = [TradingFill(
            id: 7,
            symbol: "XAUUSDT",
            side: "BUY",
            price: 100,
            qty: 1,
            time: Self.ms(day)
        )]
        let position = try XCTUnwrap(PositionAggregator.aggregate(fills: fills).first)
        let cached = TradingPositionSnapshot(
            fetchedAt: day.addingTimeInterval(60),
            windowStart: calendar.startOfDay(for: day),
            positions: [position],
            fills: fills,
            fundingBackfilled: true
        )
        try JSONEncoder().encode(cached).write(to: cacheFile(for: journalID))

        coordinator.activeJournalDidChange()
        coordinator.activeJournalDidChange()

        let updated = try XCTUnwrap(store.entries.first(where: { $0.id == entry.id }))
        XCTAssertEqual(updated.items, [xau])
        XCTAssertEqual(
            coordinator.positions(
                entryID: updated.id,
                entryDate: updated.date,
                itemID: xau.id,
                tag: xau.tag
            ).map(\.id),
            [position.id]
        )
    }

    func testDisconnectMidFlightDiscardsStaleResult() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let client = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        coordinator.syncNow(journalID: journalID)
        await client.waitUntilFetchStarted()
        XCTAssertTrue(coordinator.isSyncing)

        coordinator.disconnect(journalID: journalID)
        await client.release()
        await awaitRunCompletion(coordinator)

        XCTAssertNil(coordinator.snapshot, "a stale result after disconnect must not be committed")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: cacheFile(for: journalID).path),
            "a stale result must not write the trading cache"
        )
    }

    func testJournalDeletionMidFlightDoesNotRecreateAnything() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let second = store.createJournal(name: "Second")!
        let client = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        coordinator.syncNow(journalID: journalID)
        await client.waitUntilFetchStarted()

        // Delete the syncing journal while its request is in flight.
        store.deleteJournal(id: journalID)
        await client.release()
        await awaitRunCompletion(coordinator)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: cacheFile(for: journalID).path),
            "a stale result for a deleted journal must not write the cache"
        )
        let journalDir = tempRoot.appendingPathComponent(journalID.uuidString, isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: journalDir.path),
            "a stale result must not recreate the deleted journal folder"
        )
        XCTAssertEqual(store.journals.map(\.id), [second.id])
    }

    func testBindingChangeMidFlightDiscardsStaleResult() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let client = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        coordinator.syncNow(journalID: journalID)
        await client.waitUntilFetchStarted()

        // Change the binding (simulate re-saving different credentials).
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .okx, accountLabel: "OKX"),
            for: journalID
        )
        await client.release()
        await awaitRunCompletion(coordinator)

        XCTAssertNil(coordinator.snapshot, "a stale result for the old binding must not be committed")
    }

    func testParallelRunsOnDifferentJournalsAreIndependent() async {
        let coordinator = ExchangePositionCoordinator()
        let firstID = store.activeJournalID!
        let second = store.createJournal(name: "Second")!
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .binance, accountLabel: "Binance"),
            for: firstID
        )
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .okx, accountLabel: "OKX"),
            for: second.id
        )
        ExchangePositionCoordinator.configuredOverride = { _ in true }
        let failingClient = BlockingTradeClient(error: .invalidCredentials("bad key"))
        let okClient = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { binding, _ in
            binding?.venue == .okx ? okClient : failingClient
        }

        // A (active) fails; B succeeds concurrently.
        coordinator.syncNow(journalID: firstID)
        await failingClient.waitUntilFetchStarted()
        coordinator.syncNow(journalID: second.id)
        await okClient.waitUntilFetchStarted()

        await failingClient.release()
        await okClient.release()

        // A's failure surfaces while A is active (drive the PRODUCTION change
        // handler — no manual refreshPublishedState call).
        store.switchToJournal(id: firstID)
        coordinator.activeJournalDidChange()
        for _ in 0..<200 {
            if coordinator.lastError == .invalidKey { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(coordinator.lastError, .invalidKey)
        XCTAssertFalse(coordinator.isSyncing)

        // B's settings must not show A's failure — only B's own outcome.
        store.switchToJournal(id: second.id)
        coordinator.activeJournalDidChange()
        for _ in 0..<200 {
            if coordinator.lastError == .emptyWindow { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(coordinator.lastError, .emptyWindow, "B shares no error with A in an independent run")
        XCTAssertFalse(coordinator.isSyncing)
    }

    // MARK: - AC-P1-06 interleaving

    func testSwitchToIdleJournalShowsIdleWithoutManualRefresh() async {
        let coordinator = ExchangePositionCoordinator()
        let firstID = store.activeJournalID!
        let second = store.createJournal(name: "Second")!
        store.switchToJournal(id: firstID) // A active again for the test
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .binance, accountLabel: "Binance"),
            for: firstID
        )
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .okx, accountLabel: "OKX"),
            for: second.id
        )
        ExchangePositionCoordinator.configuredOverride = { _ in true }
        let client = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        // First journal (active) is syncing.
        coordinator.syncNow(journalID: firstID)
        await client.waitUntilFetchStarted()
        XCTAssertTrue(coordinator.isSyncing)

        // Switch straight to B; the production change handler must derive B's
        // idle state WITHOUT any manual refresh call.
        store.switchToJournal(id: second.id)
        coordinator.activeJournalDidChange()
        XCTAssertFalse(coordinator.isSyncing, "B must show idle right after the switch")
        XCTAssertNil(coordinator.lastError)

        // B is idle and can start a refresh (no stale isSyncing gate).
        let bClient = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in bClient }
        coordinator.syncNow(journalID: second.id)
        await bClient.waitUntilFetchStarted()
        XCTAssertTrue(coordinator.isSyncing, "B must be able to start its own refresh")
        await bClient.release()
        await client.release()
        await awaitRunCompletion(coordinator)
    }

    func testOldRunFinishDoesNotClearNewRun() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let client1 = BlockingTradeClient()
        let client2 = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client1 }

        // Run 1 starts and blocks.
        coordinator.syncNow(journalID: journalID)
        await client1.waitUntilFetchStarted()

        // Cancel run 1, immediately start run 2 (new credentials path).
        coordinator.cancelTasks(for: journalID)
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client2 }
        coordinator.syncNow(journalID: journalID)
        await client2.waitUntilFetchStarted()

        // Release run 1: its finish must NOT wipe run 2's identity.
        await client1.release()
        for _ in 0..<100 {
            if coordinator.isSyncing { break }  // still syncing = run 2 alive
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(coordinator.isSyncing, "run 2 must survive run 1's late finish")

        // Run 2 commits its result.
        await client2.release()
        await awaitRunCompletion(coordinator)
        XCTAssertFalse(coordinator.isSyncing)
    }

    func testDeleteNoCacheJournalMidRequestCancelsClient() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = store.activeJournalID!
        _ = store.createJournal(name: "Second") // second becomes active
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .binance, accountLabel: "Binance"),
            for: journalID
        )
        ExchangePositionCoordinator.configuredOverride = { _ in true }
        let client = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        // First sync of a journal with NO cache file, blocked mid-request.
        coordinator.syncNow(journalID: journalID)
        await client.waitUntilFetchStarted()

        // Delete the journal; pruneDeletedJournals must cancel via runningJobs
        // even though no cache file exists.
        store.deleteJournal(id: journalID)
        coordinator.pruneDeletedJournals(store.journals)
        await client.release()

        for _ in 0..<200 {
            let cancelled = await client.cancelledWhileBlocked
            if cancelled { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let cancelled = await client.cancelledWhileBlocked
        XCTAssertTrue(cancelled, "a deleted journal with no cache must still cancel its in-flight client")
    }

    func testCancelledClientReceivesCancellationAndStateIsUntouched() async {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let client = BlockingTradeClient()
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        coordinator.syncNow(journalID: journalID)
        await client.waitUntilFetchStarted()

        // Cancel the run (same path disconnect uses); the blocked fetch sees
        // the cancellation when released.
        coordinator.disconnect(journalID: journalID)
        await client.release()

        for _ in 0..<200 {
            let cancelled = await client.cancelledWhileBlocked
            if cancelled { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let cancelled = await client.cancelledWhileBlocked
        XCTAssertTrue(cancelled, "the in-flight client must observe task cancellation")
        XCTAssertNil(coordinator.snapshot)
    }

    // MARK: - Funding fees

    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    func testFundingFlowsIntoSnapshotAndNetsDayPnl() async throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let fills = [
            TradingFill(
                id: 1, symbol: "BTCUSDT", side: "BUY", price: 100, qty: 1,
                time: Self.ms(now.addingTimeInterval(-60))
            ),
            TradingFill(
                id: 2, symbol: "BTCUSDT", side: "SELL", price: 110, qty: 1,
                commission: -1, commissionAsset: "USDT", realizedPnl: 10,
                time: Self.ms(now.addingTimeInterval(-30))
            ),
        ]
        let funding = [FundingEvent(
            symbol: "BTCUSDT", amount: -0.5,
            time: Self.ms(now.addingTimeInterval(-45))
        )]
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in
            StubTradeClient(fills: fills, funding: funding)
        }

        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        let snapshot = try XCTUnwrap(coordinator.snapshot)
        XCTAssertEqual(snapshot.funding.count, 1)
        let position = try XCTUnwrap(snapshot.positions.first)
        XCTAssertEqual(position.fundingPnl, -0.5, accuracy: 1e-12)
        // 10 realized − 1 commission − 0.5 funding = 8.5 net on the open day.
        XCTAssertEqual(position.netPnl, 8.5, accuracy: 1e-12)
        let openDay = Calendar.current.startOfDay(for: position.openTime)
        XCTAssertEqual(coordinator.pnlByDay[openDay] ?? 0, 8.5, accuracy: 1e-12)
        XCTAssertTrue(snapshot.fundingBackfilled)
    }

    func testFundingFailureDoesNotBlockPositionSync() async throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let fills = [
            TradingFill(
                id: 1, symbol: "BTCUSDT", side: "BUY", price: 100, qty: 1,
                time: Self.ms(now.addingTimeInterval(-60))
            ),
            TradingFill(
                id: 2, symbol: "BTCUSDT", side: "SELL", price: 110, qty: 1,
                realizedPnl: 10, time: Self.ms(now.addingTimeInterval(-30))
            ),
        ]
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in
            StubTradeClient(fills: fills, throwOnFunding: true)
        }

        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        let snapshot = try XCTUnwrap(coordinator.snapshot)
        XCTAssertEqual(snapshot.positions.count, 1, "positions must sync even when funding fails")
        XCTAssertTrue(snapshot.funding.isEmpty)
        XCTAssertNil(coordinator.lastError, "a funding failure must not surface as a sync error")
    }

    func testFirstFundingSyncBackfillsFullWindow() async throws {
        let coordinator = ExchangePositionCoordinator()
        let journalID = bindActiveJournal()
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let fills = [
            TradingFill(
                id: 1, symbol: "BTCUSDT", side: "BUY", price: 100, qty: 1,
                time: Self.ms(now.addingTimeInterval(-120))
            ),
            TradingFill(
                id: 2, symbol: "BTCUSDT", side: "SELL", price: 110, qty: 1,
                commission: -1, commissionAsset: "USDT", realizedPnl: 10,
                time: Self.ms(now.addingTimeInterval(-60))
            ),
        ]
        // A cache written before funding support: fills present, funding empty.
        let cached = TradingPositionSnapshot(
            fetchedAt: now.addingTimeInterval(-300),
            windowStart: todayStart,
            positions: [],
            fills: fills,
            funding: [],
            fundingBackfilled: false
        )
        try JSONEncoder().encode(cached).write(to: cacheFile(for: journalID))

        let client = StubTradeClient(
            fills: fills,
            funding: [FundingEvent(
                symbol: "BTCUSDT", amount: -0.5,
                time: Self.ms(now.addingTimeInterval(-90))
            )]
        )
        ExchangePositionCoordinator.clientFactoryOverride = { _, _ in client }

        // Load the seeded cache into the coordinator, then sync.
        coordinator.activeJournalDidChange()
        coordinator.syncNow(journalID: journalID)
        await awaitRunCompletion(coordinator)

        // The first funding sync must backfill the WHOLE window, not just the
        // incremental tail ([fetchedAt - overlap, now]), or funding stays empty.
        let ranges = await client.recordedFundingRanges
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(
            ranges[0].0.timeIntervalSince1970,
            todayStart.timeIntervalSince1970,
            accuracy: 1.0,
            "funding backfill must reach back to windowStart"
        )

        let snapshot = try XCTUnwrap(coordinator.snapshot)
        XCTAssertTrue(snapshot.fundingBackfilled, "a successful backfill must be remembered")
        XCTAssertEqual(snapshot.funding.count, 1)
        let position = try XCTUnwrap(snapshot.positions.first)
        XCTAssertEqual(position.fundingPnl, -0.5, accuracy: 1e-12)
        XCTAssertEqual(position.netPnl, 8.5, accuracy: 1e-12)
    }

    func testOpenAndClosedPositionCountsPerDay() async throws {
        let coordinator = ExchangePositionCoordinator.shared
        let journalID = bindActiveJournal()

        let now = Date()
        let dayKey = JournalDayKey.make(from: now)

        // One closed position and one open position on the same day.
        let closedPos = TradingPosition(
            id: "btc-closed",
            symbol: "BTCUSDT",
            side: .long,
            openTime: now.addingTimeInterval(-3600),
            closeTime: now.addingTimeInterval(-1800),
            entryPrice: 50_000,
            exitPrice: 51_000,
            peakSize: 1.0,
            realizedPnl: 1000
        )
        let openPos = TradingPosition(
            id: "eth-open",
            symbol: "ETHUSDT",
            side: .long,
            openTime: now.addingTimeInterval(-1200),
            closeTime: nil,
            entryPrice: 3_000,
            exitPrice: nil,
            peakSize: 2.0,
            realizedPnl: 0
        )

        let cached = TradingPositionSnapshot(
            fetchedAt: now,
            windowStart: Calendar.current.startOfDay(for: now),
            positions: [closedPos, openPos],
            fills: [],
            funding: []
        )
        try JSONEncoder().encode(cached).write(to: cacheFile(for: journalID))

        coordinator.activeJournalDidChange()

        XCTAssertEqual(coordinator.closedCount(for: dayKey), 1)
        XCTAssertEqual(coordinator.openCount(for: dayKey), 1)
        XCTAssertEqual(coordinator.closedCountByDayKey[dayKey], 1)
        XCTAssertEqual(coordinator.openCountByDayKey[dayKey], 1)
    }
}
