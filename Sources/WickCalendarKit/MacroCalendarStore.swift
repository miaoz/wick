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
@MainActor
public final class MacroCalendarStore: ObservableObject {
    public static let shared = MacroCalendarStore()

    private struct DayState {
        var events: [MacroCalendarEvent] = []
        var earnings: [EarningsReport] = []
        var isLoading = false
        var error: String?
        var earningsError: String?
    }

    private var days: [String: DayState] = [:]
    private let cacheDirectory: URL

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
        days[dayKey(for: date)]?.isLoading ?? false
    }

    public func errorText(for date: Date) -> String? {
        days[dayKey(for: date)]?.error
    }

    public func earningsErrorText(for date: Date) -> String? {
        days[dayKey(for: date)]?.earningsError
    }

    /// Loads a day's events and earnings if they are not already cached in
    /// memory. Cached disk data is shown immediately and a background network
    /// refresh tops it up.
    public func loadIfNeeded(for date: Date) {
        let key = dayKey(for: date)
        guard days[key] == nil else { return }

        var state = DayState(isLoading: true)
        if let cached = readCache(key: key), !cached.isEmpty {
            state.events = cached
        }
        if let cachedEarnings = readEarningsCache(key: key), !cachedEarnings.isEmpty {
            state.earnings = cachedEarnings
        }
        days[key] = state

        Task { [weak self] in
            await self?.fetch(key: key, for: date)
        }
        objectWillChange.send()
    }

    /// The two feeds are independent: one may fail (or be empty) without
    /// affecting the other, and `isLoading` clears only when both settle.
    private func fetch(key: String, for date: Date) async {
        async let macroFetch = MacroCalendarClient.events(for: date, calendar: .current)
        async let earningsFetch = EarningsCalendarClient.reports(for: date, calendar: .current)

        do {
            let result = try await macroFetch
            if var state = days[key] {
                state.events = result
                state.error = nil
                days[key] = state
                writeCache(result, key: key)
            }
        } catch {
            if var state = days[key] {
                // Keep already-cached data; only surface the error when there's nothing to show.
                state.error = state.events.isEmpty ? error.localizedDescription : nil
                days[key] = state
            }
        }

        do {
            let result = try await earningsFetch
            if var state = days[key] {
                state.earnings = result
                state.earningsError = nil
                days[key] = state
                writeEarningsCache(result, key: key)
            }
        } catch {
            if var state = days[key] {
                state.earningsError = state.earnings.isEmpty ? error.localizedDescription : nil
                days[key] = state
            }
        }

        if var state = days[key] {
            state.isLoading = false
            days[key] = state
        }
        objectWillChange.send()
    }

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
