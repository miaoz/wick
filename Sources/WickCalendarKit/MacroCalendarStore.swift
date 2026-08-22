import Foundation
import WickSync

/// Per-day display + value formatting for the trading calendar page.
enum MacroCalendarFormat {
    /// Event release time in China time (matches akshare's `Asia/Shanghai` conversion).
    static func eventTime(_ date: Date) -> String {
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static let formatter = DateFormatter()
}

/// `@MainActor` store for the global-macro trading calendar.
///
/// Fetches events per local day from `MacroCalendarClient` (akshare `macro_info_ws`),
/// keeps them in memory, and persists a JSON cache under
/// `~/Library/Application Support/Wick/MacroCalendarCache/` so past days stay readable offline.
/// Cached data is shown immediately while a background refresh updates it.
///
/// Freshness (CA-01): each feed tracks its own `fetchedAt`; today uses a short
/// TTL, historical dates a long one. Expired feeds refresh in the background
/// (never permanently returning stale data), and the same date+feed is
/// single-flight so page turns and multiple windows share one request.
@MainActor
public final class MacroCalendarStore: ObservableObject {
    public static let shared = MacroCalendarStore()

    /// Short TTL for today's feeds; historical days can stay cached far longer.
    static var todayTTL: TimeInterval = 30 * 60
    static var historicalTTL: TimeInterval = 7 * 24 * 3600

    private struct DayState {
        var events: [MacroCalendarEvent] = []
        var earnings: [EarningsReport] = []
        var error: String?
        var earningsError: String?
        var macroFetchedAt: Date?
        var earningsFetchedAt: Date?
    }

    private enum Feed: String {
        case macro
        case earnings
    }

    private var days: [String: DayState] = [:]
    /// Single-flight keys: `"<dayKey>|<feed>"` for in-flight fetches.
    private var inFlight: Set<String> = []
    private let cacheDirectory: URL

    #if DEBUG
    /// Test seams substituting the network fetches.
    static var eventsFetcher: (@Sendable (Date) async throws -> [MacroCalendarEvent])?
    static var earningsFetcher: (@Sendable (Date) async throws -> [EarningsReport])?

    /// Test-only: build a store with an isolated cache directory.
    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    #endif

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let wickRoot = support.appendingPathComponent("Wick", isDirectory: true)
        cacheDirectory = wickRoot.appendingPathComponent("MacroCalendarCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func events(for date: Date) -> [MacroCalendarEvent] {
        days[dayKey(for: date)]?.events ?? []
    }

    public func earnings(for date: Date) -> [EarningsReport] {
        days[dayKey(for: date)]?.earnings ?? []
    }

    public func isLoading(for date: Date) -> Bool {
        let key = dayKey(for: date)
        return inFlight.contains("\(key)|\(Feed.macro.rawValue)")
            || inFlight.contains("\(key)|\(Feed.earnings.rawValue)")
    }

    public func errorText(for date: Date) -> String? {
        days[dayKey(for: date)]?.error
    }

    public func earningsErrorText(for date: Date) -> String? {
        days[dayKey(for: date)]?.earningsError
    }

    /// Loads a day's events and earnings: seeds from disk cache, then refreshes
    /// whichever feed is stale in the background. Not-expired feeds are left
    /// untouched (no network).
    public func loadIfNeeded(for date: Date) {
        let key = dayKey(for: date)
        if days[key] == nil {
            var state = DayState()
            if let cached = readCache(key: key), !cached.isEmpty {
                state.events = cached
            }
            if let cachedEarnings = readEarningsCache(key: key), !cachedEarnings.isEmpty {
                state.earnings = cachedEarnings
            }
            days[key] = state
        }
        if feedIsStale(.macro, key: key, date: date) {
            startFetch(.macro, key: key, date: date)
        }
        if feedIsStale(.earnings, key: key, date: date) {
            startFetch(.earnings, key: key, date: date)
        }
        objectWillChange.send()
    }

    /// Explicit refresh of both feeds for a day, bypassing the TTL.
    public func reload(for date: Date) {
        let key = dayKey(for: date)
        if days[key] == nil {
            days[key] = DayState()
        }
        startFetch(.macro, key: key, date: date)
        startFetch(.earnings, key: key, date: date)
        objectWillChange.send()
    }

    // MARK: - Freshness / single-flight

    private func feedIsStale(_ feed: Feed, key: String, date: Date) -> Bool {
        guard let state = days[key] else { return true }
        let fetchedAt: Date?
        switch feed {
        case .macro: fetchedAt = state.macroFetchedAt
        case .earnings: fetchedAt = state.earningsFetchedAt
        }
        guard let fetchedAt else { return true }
        let ttl = Calendar.current.isDateInToday(date) ? Self.todayTTL : Self.historicalTTL
        return Date().timeIntervalSince(fetchedAt) >= ttl
    }

    private func startFetch(_ feed: Feed, key: String, date: Date) {
        let flightKey = "\(key)|\(feed.rawValue)"
        guard !inFlight.contains(flightKey) else { return }
        inFlight.insert(flightKey)
        Task { [weak self] in
            defer { self?.inFlight.remove(flightKey) }
            await self?.fetch(feed: feed, key: key, for: date)
        }
    }

    /// Fetches ONE feed. Success updates that feed's cache and `fetchedAt`;
    /// failure keeps any existing disk cache and only surfaces an error when
    /// there is nothing to show.
    private func fetch(feed: Feed, key: String, for date: Date) async {
        do {
            switch feed {
            case .macro:
                let result = try await fetchMacroEvents(for: date)
                if var state = days[key] {
                    state.events = result
                    state.error = nil
                    state.macroFetchedAt = Date()
                    days[key] = state
                    writeCache(result, key: key)
                }
            case .earnings:
                let result = try await fetchEarningsReports(for: date)
                if var state = days[key] {
                    state.earnings = result
                    state.earningsError = nil
                    state.earningsFetchedAt = Date()
                    days[key] = state
                    writeEarningsCache(result, key: key)
                }
            }
        } catch {
            if var state = days[key] {
                switch feed {
                case .macro:
                    state.error = state.events.isEmpty ? error.localizedDescription : nil
                case .earnings:
                    state.earningsError = state.earnings.isEmpty ? error.localizedDescription : nil
                }
                days[key] = state
            }
        }
        objectWillChange.send()
    }

    private func fetchMacroEvents(for date: Date) async throws -> [MacroCalendarEvent] {
        #if DEBUG
        if let fetcher = Self.eventsFetcher {
            return try await fetcher(date)
        }
        #endif
        return try await MacroCalendarClient.events(for: date, calendar: .current)
    }

    private func fetchEarningsReports(for date: Date) async throws -> [EarningsReport] {
        #if DEBUG
        if let fetcher = Self.earningsFetcher {
            return try await fetcher(date)
        }
        #endif
        return try await EarningsCalendarClient.reports(for: date, calendar: .current)
    }

    // MARK: - Disk cache

    private func dayKey(for date: Date) -> String {
        JournalDayKey.make(from: date)
    }

    private func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private func earningsCacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).earnings.json", isDirectory: false)
    }

    private func readCache(key: String) -> [MacroCalendarEvent]? {
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([MacroCalendarEvent].self, from: data)
        else { return nil }
        // Caches written before the empty-calendar_key fix can carry empty ids
        // (duplicate SwiftUI identities render as repeated rows) — rebuild them.
        return events.map { event in
            guard event.id.isEmpty else { return event }
            return MacroCalendarEvent(
                id: "\(Int(event.time.timeIntervalSince1970))-\(event.title)",
                time: event.time,
                country: event.country,
                title: event.title,
                importance: event.importance,
                actual: event.actual,
                forecast: event.forecast,
                previous: event.previous,
                link: event.link
            )
        }
    }

    private func writeCache(_ events: [MacroCalendarEvent], key: String) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: cacheURL(for: key), options: .atomic)
    }

    private func readEarningsCache(key: String) -> [EarningsReport]? {
        let url = earningsCacheURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([EarningsReport].self, from: data)
    }

    private func writeEarningsCache(_ reports: [EarningsReport], key: String) {
        guard let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: earningsCacheURL(for: key), options: .atomic)
    }
}
