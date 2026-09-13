import Foundation
import WickSync

/// Keyless English earnings calendar (`api.nasdaq.com/api/calendar/earnings`).
///
/// US listings (and ADRs) only — the English feed does not cover HK/CN the way
/// WallStreetCN's DDC list does. `time-pre-market` / `time-after-hours` map
/// onto the existing BMO/AMC badges; EPS strings like `$0.27` / `($0.61)` are
/// coerced to `Double?`.
enum NasdaqEarningsCalendarClient {
    static let endpoint = URL(string: "https://api.nasdaq.com/api/calendar/earnings")!

    static func reports(for date: Date, calendar: Calendar = MacroCalendarClient.chinaCalendar) async throws -> [EarningsReport] {
        let day = calendar.startOfDay(for: date)
        let ymd = JournalDayKey.make(from: day, timeZone: calendar.timeZone)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "date", value: ymd)]

        var request = URLRequest(url: components.url!)
        request.setValue("Wick/MacroCalendar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MacroCalendarError.http(http.statusCode)
        }
        return try NasdaqEarningsPayloadDecoder.decode(data, date: day)
    }
}

/// Decodes Nasdaq's `{ data: { rows: [...] } }` envelope. Weekend / empty
/// days arrive with `rows: null` — that is a quiet day, not a bad payload.
enum NasdaqEarningsPayloadDecoder {
    static func decode(_ data: Data, date: Date) throws -> [EarningsReport] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MacroCalendarError.badPayload("malformed_json")
        }
        guard let root = object as? [String: Any],
              let payload = root["data"] as? [String: Any]
        else {
            throw MacroCalendarError.badPayload("missing_fields")
        }
        let rows = payload["rows"] as? [[String: Any]] ?? []

        return rows.compactMap { row in
            guard let symbol = (row["symbol"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !symbol.isEmpty,
                  let name = (row["name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return nil }

            return EarningsReport(
                id: "\(Int(date.timeIntervalSince1970))-\(symbol)",
                date: date,
                code: symbol.hasSuffix(".US") ? symbol : "\(symbol).US",
                companyName: name,
                country: "US",
                epsEstimate: money(row["epsForecast"] as? String),
                reportedEps: money(row["eps"] as? String),
                callTime: callTime(row["time"] as? String)
            )
        }
    }

    /// `$3.67` / `($0.27)` / `N/A` / empty → `Double?`. Accounting parentheses
    /// are treated as a leading minus.
    static func money(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if s.caseInsensitiveCompare("N/A") == .orderedSame { return nil }
        s = s.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        let negative = s.hasPrefix("(") && s.hasSuffix(")")
        if negative {
            s = String(s.dropFirst().dropLast())
        }
        s = s.trimmingCharacters(in: .whitespaces)
        guard let value = Double(s) else { return nil }
        return negative ? -value : value
    }

    static func callTime(_ raw: String?) -> EarningsCallTime {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
        case "time-pre-market": return .beforeOpen
        case "time-after-hours": return .afterClose
        default: return .unspecified
        }
    }
}
