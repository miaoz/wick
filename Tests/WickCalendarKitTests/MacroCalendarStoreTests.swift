import XCTest
import WickSync
@testable import WickCalendarKit

/// Thread-safe counter for the fetch test seams (the fetchers are `@Sendable`).
final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func bump() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}

/// CA-01: per-feed TTL freshness and single-flight for the trading calendar.
@MainActor
final class MacroCalendarStoreTests: XCTestCase {
    private var cacheRoot: URL!
    private var store: MacroCalendarStore!

    override func setUp() async throws {
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WickCalendarStore-\(UUID().uuidString)", isDirectory: true)
        store = MacroCalendarStore(cacheDirectory: cacheRoot)
        MacroCalendarStore.eventsFetcher = nil
        MacroCalendarStore.earningsFetcher = nil
        MacroCalendarStore.todayTTL = 30 * 60
        MacroCalendarStore.historicalTTL = 7 * 24 * 3600
    }

    override func tearDown() async throws {
        MacroCalendarStore.eventsFetcher = nil
        MacroCalendarStore.earningsFetcher = nil
        try? FileManager.default.removeItem(at: cacheRoot)
        store = nil
        cacheRoot = nil
    }

    private func sampleEvent() -> MacroCalendarEvent {
        MacroCalendarEvent(
            id: "1",
            time: Date(),
            country: "US",
            title: "CPI",
            importance: 3,
            actual: 2.1,
            forecast: 2.0,
            previous: 2.2,
            link: nil
        )
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for condition", file: file, line: line)
    }

    func testNotExpiredFeedDoesNotRefetch() async {
        let calls = AtomicCounter()
        MacroCalendarStore.eventsFetcher = { _ in
            calls.bump()
            return [MacroCalendarEvent(id: "1", time: Date(), country: "US", title: "CPI", importance: 3, actual: 2.1, forecast: 2.0, previous: 2.2, link: nil)]
        }
        MacroCalendarStore.earningsFetcher = { _ in [] }
        MacroCalendarStore.todayTTL = 3600 // not expired within the test

        store.loadIfNeeded(for: Date())
        await waitUntil { calls.count == 1 }

        store.loadIfNeeded(for: Date())
        await waitUntil { !store.isLoading(for: Date()) }
        XCTAssertEqual(calls.count, 1, "a not-expired feed must not refetch")
    }

    func testExpiredFeedRefetchesInBackground() async {
        let calls = AtomicCounter()
        MacroCalendarStore.eventsFetcher = { _ in
            calls.bump()
            return [MacroCalendarEvent(id: "1", time: Date(), country: "US", title: "CPI", importance: 3, actual: 2.1, forecast: 2.0, previous: 2.2, link: nil)]
        }
        MacroCalendarStore.earningsFetcher = { _ in [] }
        MacroCalendarStore.todayTTL = -1 // always expired

        store.loadIfNeeded(for: Date())
        await waitUntil { calls.count == 1 }

        store.loadIfNeeded(for: Date())
        await waitUntil { calls.count == 2 }
        XCTAssertEqual(calls.count, 2)
    }

    func testConcurrentLoadsAreSingleFlight() async {
        let calls = AtomicCounter()
        MacroCalendarStore.eventsFetcher = { _ in
            calls.bump()
            return [MacroCalendarEvent(id: "1", time: Date(), country: "US", title: "CPI", importance: 3, actual: 2.1, forecast: 2.0, previous: 2.2, link: nil)]
        }
        MacroCalendarStore.earningsFetcher = { _ in [] }
        MacroCalendarStore.todayTTL = -1

        for _ in 0..<5 {
            store.loadIfNeeded(for: Date())
        }
        await waitUntil { calls.count == 1 }
        XCTAssertEqual(calls.count, 1, "concurrent loadIfNeeded must single-flight the fetch")
    }

    func testReloadBypassesTTL() async {
        let calls = AtomicCounter()
        MacroCalendarStore.eventsFetcher = { _ in
            calls.bump()
            return [MacroCalendarEvent(id: "1", time: Date(), country: "US", title: "CPI", importance: 3, actual: 2.1, forecast: 2.0, previous: 2.2, link: nil)]
        }
        MacroCalendarStore.earningsFetcher = { _ in [] }
        MacroCalendarStore.todayTTL = 3600

        store.loadIfNeeded(for: Date())
        await waitUntil { calls.count == 1 }

        store.reload(for: Date())
        await waitUntil { calls.count == 2 }
        XCTAssertEqual(calls.count, 2, "explicit reload must bypass the TTL")
    }

    func testMacroSuccessEarningsFailureUpdatesOnlySuccess() async {
        enum TestError: Error { case fail }
        MacroCalendarStore.eventsFetcher = { _ in return [MacroCalendarEvent(id: "1", time: Date(), country: "US", title: "CPI", importance: 3, actual: 2.1, forecast: 2.0, previous: 2.2, link: nil)] }
        MacroCalendarStore.earningsFetcher = { _ in throw TestError.fail }

        store.loadIfNeeded(for: Date())
        await waitUntil { !store.isLoading(for: Date()) }

        XCTAssertEqual(store.events(for: Date()).count, 1)
        XCTAssertNil(store.errorText(for: Date()))
        XCTAssertTrue(store.earnings(for: Date()).isEmpty)
        XCTAssertNotNil(store.earningsErrorText(for: Date()))
    }

    func testFailureDoesNotOverwriteExistingDiskCache() async throws {
        enum TestError: Error { case fail }
        // First load succeeds and writes the disk cache.
        MacroCalendarStore.eventsFetcher = { _ in return [MacroCalendarEvent(id: "1", time: Date(), country: "US", title: "CPI", importance: 3, actual: 2.1, forecast: 2.0, previous: 2.2, link: nil)] }
        MacroCalendarStore.earningsFetcher = { _ in [] }
        store.loadIfNeeded(for: Date())
        await waitUntil { store.events(for: Date()).count == 1 }

        // Now the macro feed fails; the cached events must survive.
        MacroCalendarStore.eventsFetcher = { _ in throw TestError.fail }
        store.reload(for: Date())
        await waitUntil { !store.isLoading(for: Date()) }

        XCTAssertEqual(store.events(for: Date()).count, 1, "failed refresh must keep the cached data")
        XCTAssertNil(store.errorText(for: Date()), "no error when cached data is shown")
    }
}
