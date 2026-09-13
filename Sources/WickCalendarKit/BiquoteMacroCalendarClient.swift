import Foundation

/// Keyless English macro calendar (`biquote.io/api/calendar`).
///
/// Same shape as `MacroCalendarEvent`: ISO timestamps, ISO country codes,
/// actual/forecast/previous as numbers, `revisedPrevious` superseding
/// `previous` (mirrors WallStreetCN's `revised` rule), and
/// low/medium/high → 1/2/3 stars. `from`/`to` are exclusive-end UTC dates;
/// the client asks for every UTC day that overlaps the requested local day
/// and then clamps to the half-open unix window.
enum BiquoteMacroCalendarClient {
    static let endpoint = URL(string: "https://biquote.io/api/calendar")!

    /// UTC `yyyy-MM-dd` pair covering every instant in the local day
    /// `[midnight, midnight+1day)`. `to` is exclusive (the API 400s when
    /// `from == to`).
    static func dateQueryRange(for date: Date, calendar: Calendar = MacroCalendarClient.chinaCalendar) -> (from: String, to: String) {
        let range = MacroCalendarClient.dayUnixRange(for: date, calendar: calendar)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let fromDay = utc.startOfDay(for: Date(timeIntervalSince1970: Double(range.start)))
        let lastInstant = Date(timeIntervalSince1970: Double(range.end - 1))
        let toDay = utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: lastInstant)) ?? lastInstant
        return (ymd(fromDay, calendar: utc), ymd(toDay, calendar: utc))
    }

    static func events(for date: Date, calendar: Calendar = MacroCalendarClient.chinaCalendar) async throws -> [MacroCalendarEvent] {
        let range = MacroCalendarClient.dayUnixRange(for: date, calendar: calendar)
        let query = dateQueryRange(for: date, calendar: calendar)

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "from", value: query.from),
            URLQueryItem(name: "to", value: query.to)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Wick/MacroCalendar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw MacroCalendarError.http(http.statusCode)
        }
        return try BiquoteMacroPayloadDecoder.decode(data).filter { event in
            let t = Int(event.time.timeIntervalSince1970)
            return t >= range.start && t < range.end
        }
    }

    private static func ymd(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Decodes biquote's top-level event array into `MacroCalendarEvent`s.
enum BiquoteMacroPayloadDecoder {
    static func decode(_ data: Data) throws -> [MacroCalendarEvent] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MacroCalendarError.badPayload("malformed_json")
        }
        guard let items = object as? [[String: Any]] else {
            throw MacroCalendarError.badPayload("missing_items")
        }

        var seen = Set<String>()
        return items.compactMap { item in
            guard let timeRaw = item["time"] as? String,
                  let time = parseTime(timeRaw)
            else { return nil }
            let title = ((item["name"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let country = ((item["countryCode"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let id = ((item["id"] as? String)?.trimmingCharacters(in: .whitespaces))
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? ((item["eventId"] as? String)?.trimmingCharacters(in: .whitespaces))
                    .flatMap { $0.isEmpty ? nil : $0 }
                ?? "\(Int(time.timeIntervalSince1970))-\(title)"

            let event = MacroCalendarEvent(
                id: id,
                time: time,
                country: country,
                title: title,
                importance: importance(item["importance"]),
                actual: number(item["actual"]),
                forecast: number(item["forecast"]),
                previous: number(item["revisedPrevious"]) ?? number(item["previous"]),
                link: (item["sourceUrl"] as? String).flatMap(URL.init(string:))
            )
            let dedupKey = "\(Int(time.timeIntervalSince1970))|\(country)|\(title)"
            guard seen.insert(dedupKey).inserted else { return nil }
            return event
        }
    }

    /// `"low"`/`"medium"`/`"high"` → 1/2/3 so the existing star UI keeps working.
    static func importance(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber {
            return min(max(number.intValue, 0), 3)
        }
        guard let raw = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else { return 0 }
        switch raw {
        case "high": return 3
        case "medium": return 2
        case "low": return 1
        default: return min(max(Int(raw) ?? 0, 0), 3)
        }
    }

    static func number(_ raw: Any?) -> Double? {
        if raw == nil || raw is NSNull { return nil }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String { return MacroCalendarPayloadDecoder.number(string) }
        return nil
    }

    static func parseTime(_ raw: String) -> Date? {
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
