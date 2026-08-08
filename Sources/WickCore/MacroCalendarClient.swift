import Foundation

/// Swift re-implementation of akshare's `macro_info_ws`.
///
/// Despite the `_ws` suffix this is *not* a WebSocket — it is a keyless `GET` to the
/// WallStreetCN macro-calendar REST endpoint (`api-one-wscn.awtmt.com/apiv1/finance/macrodatas`),
/// which returns every macro event in a 24-hour window. `start`/`end` are the chosen day's
/// local midnight and the following midnight as Unix timestamps.
enum MacroCalendarClient {
    static let endpoint = URL(string: "https://api-one-wscn.awtmt.com/apiv1/finance/macrodatas")!

    /// Unix (second) range covering one local day: `[midnight, midnight+1day)`.
    static func dayUnixRange(for date: Date, calendar: Calendar = .current) -> (start: Int, end: Int) {
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        return (
            Int(startDate.timeIntervalSince1970),
            Int(endDate.timeIntervalSince1970)
        )
    }

    static func events(for date: Date, calendar: Calendar = .current) async throws -> [MacroCalendarEvent] {
        let range = dayUnixRange(for: date, calendar: calendar)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start", value: String(range.start)),
            URLQueryItem(name: "end", value: String(range.end))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Wick/MacroCalendar (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MacroCalendarError.http(http.statusCode)
        }
        return try MacroCalendarPayloadDecoder.decode(data)
    }
}
