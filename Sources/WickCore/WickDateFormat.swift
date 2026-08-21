import Foundation

/// Cached `DateFormatter`s keyed by locale + template (P5).
/// Creating a `DateFormatter` per row per SwiftUI body is expensive on macOS 13.
@MainActor
enum WickDateFormat {
    private static var cache: [String: DateFormatter] = [:]

    static func string(from date: Date, template: String, locale: Locale) -> String {
        let key = locale.identifier + "/" + template
        let formatter: DateFormatter
        if let cached = cache[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            cache[key] = formatter
        }
        return formatter.string(from: date)
    }
}
