import Foundation
import WickSync

/// A single global-macro calendar event, mirroring what akshare's `macro_info_ws`
/// returns (time, country, title, importance, actual/forecast/previous, link).
public struct MacroCalendarEvent: Identifiable, Codable, Equatable, Sendable {
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

        var seen = Set<String>()
        return items.compactMap { item in
            // Events without a release time are not calendar-addressable.
            guard let publicDate = item.public_date else { return nil }
            let title = (item.title ?? item.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let actual = Self.number(item.actual)
            let forecast = Self.number(item.forecast)
            // akshare: where a revision exists it supersedes the previous value.
            let previous = Self.number(item.revised) ?? Self.number(item.previous)

            // `calendar_key` can be present but empty (common for event-style
            // entries) — an empty id is worse than none, since SwiftUI renders
            // duplicate identities as repeated rows.
            let calendarKey = item.calendar_key?.trimmingCharacters(in: .whitespaces)
            let id = (calendarKey?.isEmpty == false ? calendarKey : nil)
                ?? (item.id.map { String($0) })
                ?? "\(publicDate)-\(title)"

            let event = MacroCalendarEvent(
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

            // The feed occasionally lists the same release twice under
            // different tickers/ids — collapse identical rows.
            let dedupKey = "\(publicDate)|\(event.country)|\(title)"
            guard seen.insert(dedupKey).inserted else { return nil }
            return event
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

// MARK: - Earnings calendar (DDC service)

/// When in the (local) trading day the report drops.
public enum EarningsCallTime: String, Codable, Sendable {
    case beforeOpen = "BMO"   // 盘前
    case afterClose = "AMC"   // 盘后
    /// TNS / TAS / unknown — the feed has more codes than it documents.
    case unspecified

    /// Localized compact badge text across macOS and iOS:
    /// Chinese: "盘前" / "盘后" / "未定"
    /// English: "BMO" / "AMC" / "TBD"
    public func badge(language: AppLanguage) -> String {
        switch self {
        case .beforeOpen: return L10n.string(.earningsBeforeOpen, language: language)
        case .afterClose: return L10n.string(.earningsAfterClose, language: language)
        case .unspecified: return L10n.string(.earningsTimeTbd, language: language)
        }
    }
}

/// A single earnings-calendar entry from the WallStreetCN DDC service.
public struct EarningsReport: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    /// Day-granularity: the feed stamps every report at 00:00.
    public let date: Date
    /// Ticker with market suffix, e.g. `603259.SH` / `PLTR.US`.
    public let code: String
    public let companyName: String
    public let country: String
    /// The feed encodes "no estimate" as 0 — normalized to nil at decode.
    public let epsEstimate: Double?
    /// 0 until the actual is out — normalized to nil at decode.
    public let reportedEps: Double?
    public let callTime: EarningsCallTime

    public init(
        id: String,
        date: Date,
        code: String,
        companyName: String,
        country: String,
        epsEstimate: Double?,
        reportedEps: Double?,
        callTime: EarningsCallTime
    ) {
        self.id = id
        self.date = date
        self.code = code
        self.companyName = companyName
        self.country = country
        self.epsEstimate = epsEstimate
        self.reportedEps = reportedEps
        self.callTime = callTime
    }
}

/// Decodes the DDC earnings payload, which is *columnar*: `data.fields` holds
/// the column names and every entry in `data.items` is a positional row array.
enum EarningsPayloadDecoder {
    static func decode(_ data: Data) throws -> [EarningsReport] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MacroCalendarError.badPayload("malformed_json")
        }
        guard let root = object as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let fields = payload["fields"] as? [String],
              let items = payload["items"] as? [[Any]]
        else {
            throw MacroCalendarError.badPayload("missing_fields")
        }

        return items.compactMap { row in
            guard row.count == fields.count else { return nil }
            var column: [String: Any] = [:]
            column.reserveCapacity(fields.count)
            for (index, field) in fields.enumerated() {
                column[field] = row[index]
            }
            guard let timestamp = (column["public_date"] as? NSNumber)?.doubleValue,
                  let code = column["code"] as? String, !code.isEmpty,
                  let name = column["company_name"] as? String, !name.isEmpty
            else { return nil }

            return EarningsReport(
                id: (column["id"] as? NSNumber)?.stringValue
                    ?? "\(Int(timestamp))-\(code)",
                date: Date(timeIntervalSince1970: timestamp),
                code: code,
                companyName: name,
                country: (column["country"] as? String) ?? "",
                epsEstimate: Self.nonzero(column["eps_estimate"]),
                reportedEps: Self.nonzero(column["reported_eps"]),
                callTime: EarningsCallTime(
                    rawValue: (column["earnings_call_time"] as? String) ?? ""
                ) ?? .unspecified
            )
        }
    }

    /// The feed writes 0 for "no data"; a real EPS of exactly 0 is a fair loss.
    private static func nonzero(_ value: Any?) -> Double? {
        guard let number = (value as? NSNumber)?.doubleValue, number != 0 else { return nil }
        return number
    }
}
