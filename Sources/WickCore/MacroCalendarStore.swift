import Foundation

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
final class MacroCalendarStore: ObservableObject {
    static let shared = MacroCalendarStore()

    private struct DayState {
        var events: [MacroCalendarEvent] = []
        var isLoading = false
        var error: String?
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

    func events(for date: Date) -> [MacroCalendarEvent] {
        days[dayKey(for: date)]?.events ?? []
    }

    func isLoading(for date: Date) -> Bool {
        days[dayKey(for: date)]?.isLoading ?? false
    }

    func errorText(for date: Date) -> String? {
        days[dayKey(for: date)]?.error
    }

    /// Loads a day's events if they are not already cached in memory. Cached disk
    /// data is shown immediately and a background network refresh tops it up.
    func loadIfNeeded(for date: Date) {
        let key = dayKey(for: date)
        guard days[key] == nil else { return }

        var state: DayState
        if let cached = readCache(key: key), !cached.isEmpty {
            state = DayState(events: cached, isLoading: true)
        } else {
            state = DayState(isLoading: true)
        }
        days[key] = state

        Task { [weak self] in
            await self?.fetch(key: key, for: date)
        }
        objectWillChange.send()
    }

    private func fetch(key: String, for date: Date) async {
        do {
            let result = try await MacroCalendarClient.events(for: date, calendar: .current)
            if var state = days[key] {
                state.events = result
                state.isLoading = false
                state.error = nil
                days[key] = state
                writeCache(result, key: key)
            }
        } catch {
            if var state = days[key] {
                // Keep already-cached data; only surface the error when there's nothing to show.
                let hadData = !state.events.isEmpty
                state.isLoading = false
                state.error = hadData ? nil : error.localizedDescription
                days[key] = state
            }
        }
        objectWillChange.send()
    }

    private func dayKey(for date: Date) -> String {
        JournalDayKey.make(from: date)
    }

    private func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json", isDirectory: false)
    }

    private func readCache(key: String) -> [MacroCalendarEvent]? {
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([MacroCalendarEvent].self, from: data)
    }

    private func writeCache(_ events: [MacroCalendarEvent], key: String) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: cacheURL(for: key), options: .atomic)
    }
}
