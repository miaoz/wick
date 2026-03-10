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
    static func allProgress(at date: Date, calendar: Calendar = .current) -> [TimeProgress] {
        [
            makeProgress(for: .day, title: "日", subtitle: "今天", at: date, calendar: calendar),
            makeProgress(for: .weekOfYear, title: "周", subtitle: "本周", at: date, calendar: calendar),
            makeProgress(for: .month, title: "月", subtitle: "本月", at: date, calendar: calendar),
            makeProgress(for: .year, title: "年", subtitle: "今年", at: date, calendar: calendar)
        ]
    }

    private static func makeProgress(
        for component: Calendar.Component,
        title: String,
        subtitle: String,
        at date: Date,
        calendar: Calendar
    ) -> TimeProgress {
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return TimeProgress(
                id: String(describing: component),
                title: title,
                subtitle: subtitle,
                fractionRemaining: 0,
                percentageText: "0%",
                remainingText: "还剩 0 分钟",
                endText: "时间边界不可用"
            )
        }

        let fractionRemaining = remainingFraction(for: interval, at: date)

        return TimeProgress(
            id: String(describing: component),
            title: title,
            subtitle: subtitle,
            fractionRemaining: fractionRemaining,
            percentageText: fractionRemaining.formatted(.percent.precision(.fractionLength(1))),
            remainingText: remainingText(for: component, from: date, to: interval.end, calendar: calendar),
            endText: endText(for: component, end: interval.end)
        )
    }

    private static func remainingFraction(for interval: DateInterval, at date: Date) -> Double {
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
        calendar: Calendar
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
            valueText(for: unit, in: components)
        }

        if parts.isEmpty {
            return "还剩不到 1 分钟"
        }

        return "还剩 " + parts.prefix(2).joined(separator: " ")
    }

    private static func valueText(for component: Calendar.Component, in dateComponents: DateComponents) -> String? {
        let value: Int?
        let unit: String

        switch component {
        case .month:
            value = dateComponents.month
            unit = "个月"
        case .day:
            value = dateComponents.day
            unit = "天"
        case .hour:
            value = dateComponents.hour
            unit = "小时"
        case .minute:
            value = dateComponents.minute
            unit = "分钟"
        default:
            value = nil
            unit = ""
        }

        guard let value, value > 0 else {
            return nil
        }

        return "\(value)\(unit)"
    }

    private static func endText(for component: Calendar.Component, end: Date) -> String {
        switch component {
        case .day:
            return "到 " + end.formatted(.dateTime.hour().minute())
        case .weekOfYear, .month:
            return "到 " + end.formatted(.dateTime.month().day().hour().minute())
        case .year:
            return "到 " + end.formatted(.dateTime.year().month().day())
        default:
            return end.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
