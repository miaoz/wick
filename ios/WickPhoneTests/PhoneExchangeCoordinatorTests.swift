import Foundation
import XCTest
import WickSync
import WickTrading
@testable import WickPhone

/// Exchange client that suspends inside `fetchFills` until the test resumes it,
/// simulating a fetch in flight while the binding is torn down (IO-04).
private final class SuspendingClient: ExchangeTradeClient, @unchecked Sendable {
    private var fillContinuation: CheckedContinuation<[TradingFill], Error>?
    nonisolated(unsafe) private var hasStartedFlag = false

    func fetchFills(from start: Date, to end: Date) async throws -> [TradingFill] {
        hasStartedFlag = true
        return try await withCheckedThrowingContinuation { continuation in
            fillContinuation = continuation
        }
    }

    func fetchFunding(from start: Date, to end: Date) async throws -> [FundingEvent] { [] }

    var hasStarted: Bool { hasStartedFlag }

    func resumeFills() {
        fillContinuation?.resume(returning: [])
        fillContinuation = nil
    }
}

/// IO-04: an in-flight fetch that outlives an unbind must be discarded entirely
/// — never write an orphan snapshot for a journal that lost its binding.
@MainActor
final class PhoneExchangeCoordinatorTests: XCTestCase {
    private var root: URL!
    private var cacheRoot: URL!
    private var store: PhoneJournalStore!
    private var coordinator: PhoneExchangeCoordinator!

    private func bindHyperliquid(_ journalID: UUID) {
        store.setExchangeBinding(
            JournalExchangeBinding(venue: .hyperliquid, accountLabel: "0xabcdef0123456789abcdef0123456789abcdef01"),
            for: journalID
        )
    }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickPhoneExchange-\(UUID().uuidString)", isDirectory: true)
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickPhoneExchangeCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        store = PhoneJournalStore(rootDirectory: root)
        coordinator = PhoneExchangeCoordinator(store: store, cacheDirectory: cacheRoot)
        PhoneExchangeCoordinator.clientFactoryOverride = nil
    }

    override func tearDown() async throws {
        PhoneExchangeCoordinator.clientFactoryOverride = nil
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: cacheRoot)
        store = nil
        coordinator = nil
        root = nil
        cacheRoot = nil
    }

    /// Polls (asynchronously, letting the MainActor sync task run) until the
    /// fake client's fetch actually starts.
    private func waitForFetchStart(_ client: SuspendingClient, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if client.hasStarted { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("the fetch must have started")
    }

    func testUnbindMidFetchDiscardsStaleSnapshot() async throws {
        let journalID = store.activeJournalID!
        bindHyperliquid(journalID)

        let client = SuspendingClient()
        PhoneExchangeCoordinator.clientFactoryOverride = { _ in client }

        coordinator.syncNow(journalID: journalID)
        try await waitForFetchStart(client)

        // Unbind while the fetch is in flight — the run is cancelled + generation bumped.
        coordinator.removeBinding(for: journalID)

        // Let the stale fetch finish; its result must be discarded.
        client.resumeFills()
        try await Task.sleep(nanoseconds: 150_000_000)

        let snapshotURL = cacheRoot.appendingPathComponent("\(journalID.uuidString).json")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "a fetch in flight at unbind must not write an orphan snapshot"
        )
        XCTAssertNil(coordinator.snapshot)
    }

    func testBindingReplacementDiscardsOldInFlightResult() async throws {
        let journalID = store.activeJournalID!
        bindHyperliquid(journalID)

        let client = SuspendingClient()
        PhoneExchangeCoordinator.clientFactoryOverride = { _ in client }

        coordinator.syncNow(journalID: journalID)
        try await waitForFetchStart(client)

        // Re-bind the same journal to a different account while the old fetch
        // is in flight; the old run's fingerprint no longer matches.
        coordinator.setBinding(
            JournalExchangeBinding(venue: .hyperliquid, accountLabel: "0x0000000000000000000000000000000000000000"),
            secrets: nil,
            for: journalID
        )

        client.resumeFills()
        try await Task.sleep(nanoseconds: 150_000_000)

        let snapshotURL = cacheRoot.appendingPathComponent("\(journalID.uuidString).json")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "a result from the pre-rebind fetch must not be committed"
        )
    }
}
