import Foundation

/// A single global-macro calendar event, mirroring what akshare's `macro_info_ws`
/// returns (time, country, title, importance, actual/forecast/previous, link).
public struct MacroCalendarEvent: Identifiable, Codable, Equatable {
    public let id: String
    public let time: Date
    public let country: String
    public let title: String
    public let importance: Int
    public let actual: Double?
    public let forecast: Double?
    public let previous: Double?
    public let link: URL?

    public init(
        id: String,
        time: Date,
        country: String,
        title: String,
        importance: Int,
        actual: Double?,
        forecast: Double?,
        previous: Double?,
        link: URL?
    ) {
        self.id = id
        self.time = time
        self.country = country
        self.title = title
        self.importance = importance
        self.actual = actual
        self.forecast = forecast
        self.previous = previous
        self.link = link
    }
}

enum MacroCalendarError: Error, Equatable {
    case http(Int)
    case badPayload(String)
}

/// Decodes the WallStreetCN `macro_info_ws` payload (`{ code, data: { items: [...] } }`)
/// into `MacroCalendarEvent`s, applying akshare's data-shaping rules:
/// - `public_date` (unix seconds) → `time`
/// - numeric strings → `Double?` (empty / non-numeric become `nil`)
/// - `revised` fills `previous` when present (the `revised` column is then dropped)
/// - `uri` → `link`
enum MacroCalendarPayloadDecoder {
    private struct RawResponse: Decodable {
        let code: Int?
        let data: RawData?
    }

    private struct RawData: Decodable {
        let items: [RawItem]
    }

    private struct RawItem: Decodable {
        let id: Int?
        let public_date: Int?
        let country: String?
        let title: String?
        let importance: Int?
        let actual: String?
        let forecast: String?
        let previous: String?
        let revised: String?
        let uri: String?
        let calendar_key: String?
    }

    static func decode(_ data: Data) throws -> [MacroCalendarEvent] {
        let response: RawResponse
        do {
            response = try JSONDecoder().decode(RawResponse.self, from: data)
        } catch {
            throw MacroCalendarError.badPayload("malformed_json")
        }

        guard let items = response.data?.items else {
            throw MacroCalendarError.badPayload("missing_items")
        }

        return items.compactMap { item in
            // Events without a release time are not calendar-addressable.
            guard let publicDate = item.public_date else { return nil }
            let title = (item.title ?? item.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let actual = Self.number(item.actual)
            let forecast = Self.number(item.forecast)
            // akshare: where a revision exists it supersedes the previous value.
            let previous = Self.number(item.revised) ?? Self.number(item.previous)

            let id = item.calendar_key
                ?? (item.id.map { String($0) })
                ?? "\(publicDate)-\(title)"

            return MacroCalendarEvent(
                id: id,
                time: Date(timeIntervalSince1970: Double(publicDate)),
                country: (item.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                title: title,
                importance: item.importance ?? 0,
                actual: actual,
                forecast: forecast,
                previous: previous,
                link: item.uri.flatMap(URL.init(string:))
            )
        }
    }

    /// Mirrors `pd.to_numeric(errors="coerce")`: numeric strings become values,
    /// everything else (empty, "%", units, text) becomes `nil`.
    static func number(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        // Tolerate a leading/trailing percent sign (e.g. "0.2%") by stripping it.
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
        return Double(cleaned)
    }
}
