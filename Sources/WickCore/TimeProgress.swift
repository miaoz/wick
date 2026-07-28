import Foundation

struct TimeProgress: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let fractionRemaining: Double
    let percentageText: String
    let remainingText: String
    let endText: String
}

enum TimeProgressCalculator {
    /// Fraction of the current local day still remaining in `[0, 1]`.
    static func dayFractionRemaining(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            return 0
        }
        return remainingFraction(for: interval, at: date)
    }

    static func allProgress(
        at date: Date,
        language: AppLanguage,
        calendar: Calendar = .current
    ) -> [TimeProgress] {
        let locale = language.locale

        return [
            makeProgress(
                for: .day,
                title: L10n.string(.dayTitle, language: language),
                subtitle: L10n.string(.daySubtitle, language: language),
                at: date,
                calendar: calendar,
                language: language,
                locale: locale
            ),
            makeProgress(
                for: .weekOfYear,
                title: L10n.string(.weekTitle, language: language),
                subtitle: L10n.string(.weekSubtitle, language: language),
                at: date,
                calendar: calendar,
                language: language,
                locale: locale
            ),
            makeProgress(
                for: .month,
                title: L10n.string(.monthTitle, language: language),
                subtitle: L10n.string(.monthSubtitle, language: language),
                at: date,
                calendar: calendar,
                language: language,
                locale: locale
            ),
            makeProgress(
                for: .year,
                title: L10n.string(.yearTitle, language: language),
                subtitle: L10n.string(.yearSubtitle, language: language),
                at: date,
                calendar: calendar,
                language: language,
                locale: locale
            )
        ]
    }

    private static func makeProgress(
        for component: Calendar.Component,
        title: String,
        subtitle: String,
        at date: Date,
        calendar: Calendar,
        language: AppLanguage,
        locale: Locale
    ) -> TimeProgress {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return TimeProgress(
                id: String(describing: component),
                title: title,
                subtitle: subtitle,
                fractionRemaining: 0,
                percentageText: "0%",
                remainingText: remainingZeroText(language: language),
                endText: L10n.string(.endUnavailable, language: language)
            )
        }

        let fractionRemaining = remainingFraction(for: interval, at: date)

        return TimeProgress(
            id: String(describing: component),
            title: title,
            subtitle: subtitle,
            fractionRemaining: fractionRemaining,
            percentageText: fractionRemaining.formatted(
                .percent
                .precision(.fractionLength(1))
                .locale(locale)
            ),
            remainingText: remainingText(
                for: component,
                from: date,
                to: interval.end,
                calendar: calendar,
                language: language
            ),
            endText: endText(for: component, end: interval.end, language: language, locale: locale)
        )
    }

    private static func remainingZeroText(language: AppLanguage) -> String {
        switch language {
        case .chinese:
            return "还剩 0 分钟"
        case .english:
            return "0m left"
        }
    }

    static func remainingFraction(for interval: DateInterval, at date: Date) -> Double {
        let remaining = interval.end.timeIntervalSince(date)
        guard interval.duration > 0 else {
            return 0
        }

        return max(0, min(1, remaining / interval.duration))
    }

    private static func remainingText(
        for component: Calendar.Component,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> String {
        let units: [Calendar.Component]

        switch component {
        case .day:
            units = [.hour, .minute]
        case .weekOfYear, .month:
            units = [.day, .hour]
        case .year:
            units = [.month, .day]
        default:
            units = [.hour, .minute]
        }

        let components = calendar.dateComponents(Set(units), from: start, to: end)
        let parts = units.compactMap { unit in
            valueText(for: unit, in: components, language: language)
        }

        if parts.isEmpty {
            return L10n.string(.remainingLessThanOneMinute, language: language)
        }

        let joined = parts.prefix(2).joined(separator: " ")
        let prefix = L10n.string(.remainingPrefix, language: language)
        let suffix = L10n.string(.remainingSuffix, language: language)
        return prefix + joined + suffix
    }

    private static func valueText(
        for component: Calendar.Component,
        in dateComponents: DateComponents,
        language: AppLanguage
    ) -> String? {
        let value: Int?
        let unit: String

        switch component {
        case .month:
            value = dateComponents.month
            unit = L10n.string(.unitMonth, language: language)
        case .day:
            value = dateComponents.day
            unit = L10n.string(.unitDay, language: language)
        case .hour:
            value = dateComponents.hour
            unit = L10n.string(.unitHour, language: language)
        case .minute:
            value = dateComponents.minute
            unit = L10n.string(.unitMinute, language: language)
        default:
            value = nil
            unit = ""
        }

        guard let value, value > 0 else {
            return nil
        }

        switch language {
        case .chinese:
            return "\(value)\(unit)"
        case .english:
            return "\(value)\(unit)"
        }
    }

    private static func endText(
        for component: Calendar.Component,
        end: Date,
        language: AppLanguage,
        locale: Locale
    ) -> String {
        let prefix = L10n.string(.endPrefix, language: language)
        let formatted: String

        switch component {
        case .day:
            formatted = end.formatted(
                .dateTime
                .hour()
                .minute()
                .locale(locale)
            )
        case .weekOfYear, .month:
            formatted = end.formatted(
                .dateTime
                .month()
                .day()
                .hour()
                .minute()
                .locale(locale)
            )
        case .year:
            formatted = end.formatted(
                .dateTime
                .year()
                .month()
                .day()
                .locale(locale)
            )
        default:
            formatted = end.formatted(
                .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .locale(locale)
            )
        }

        return prefix + formatted
    }
}
