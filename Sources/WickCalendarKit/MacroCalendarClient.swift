import Foundation

/// Swift re-implementation of akshare's `macro_info_ws`.
///
/// Despite the `_ws` suffix this is *not* a WebSocket — it is a keyless `GET` to the
/// WallStreetCN macro-calendar REST endpoint (`api-one-wscn.awtmt.com/apiv1/finance/macrodatas`),
/// which returns every macro event in a 24-hour window. `start`/`end` are the chosen day's
/// local midnight and the following midnight as Unix timestamps.
enum MacroCalendarClient {
    static let endpoint = URL(string: "https://api-one-wscn.awtmt.com/apiv1/finance/macrodatas")!

    /// China timezone calendar used by WallStreetCN's daily trading feeds.
    static let chinaCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 3600)!
        return cal
    }()

    /// Unix (second) range covering one local day: `[midnight, midnight+1day)`.
    /// Defaults to `chinaCalendar` so requests align with WallStreetCN's Beijing-time trading day partitions.
    static func dayUnixRange(for date: Date, calendar: Calendar = chinaCalendar) -> (start: Int, end: Int) {
        let startDate = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        return (
            Int(startDate.timeIntervalSince1970),
            Int(endDate.timeIntervalSince1970)
        )
    }

    static func events(for date: Date, calendar: Calendar = chinaCalendar) async throws -> [MacroCalendarEvent] {
        let range = dayUnixRange(for: date, calendar: calendar)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start", value: String(range.start)),
            URLQueryItem(name: "end", value: String(range.end))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Wick/MacroCalendar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MacroCalendarError.http(http.statusCode)
        }
        // The endpoint treats `end` as inclusive, so events at the following
        // midnight leak into today's payload (and reappear on tomorrow's page).
        // Clamp to the requested half-open range [start, end).
        return try MacroCalendarPayloadDecoder.decode(data).filter { event in
            let t = Int(event.time.timeIntervalSince1970)
            return t >= range.start && t < range.end
        }
    }
}

/// The earnings calendar, from WallStreetCN's *other* host: the DDC data
/// service (`api-ddc-wscn.awtmt.com`, note the missing `/apiv1` prefix).
/// Replies are columnar (`fields` + positional `items`) and capped at 20 rows
/// per day — plenty for a printed page, but a hard ceiling to know about.
enum EarningsCalendarClient {
    static let endpoint = URL(string: "https://api-ddc-wscn.awtmt.com/finance/report/list")!

    static func reports(for date: Date, calendar: Calendar = MacroCalendarClient.chinaCalendar) async throws -> [EarningsReport] {
        let range = MacroCalendarClient.dayUnixRange(for: date, calendar: calendar)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start", value: String(range.start)),
            URLQueryItem(name: "end", value: String(range.end)),
            // Same market set the site passes for its earnings tab.
            URLQueryItem(name: "country", value: "US,HK,CN")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Wick/MacroCalendar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MacroCalendarError.http(http.statusCode)
        }
        return try EarningsPayloadDecoder.decode(data).filter { report in
            let t = Int(report.date.timeIntervalSince1970)
            return t >= range.start && t < range.end
        }
    }
}

