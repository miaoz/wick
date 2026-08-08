import SwiftUI

/// The "printed page" for a single trading-calendar day, drawn in himekuri's「黄历」
/// style (green ink on cream paper, double rule, big day numeral, filled weekday column).
/// This view is snapshotted to a texture and warped by the paper physics in `PaperScene`.
struct MacroDayPageView: View {
    let date: Date
    let events: [MacroCalendarEvent]
    let isLoading: Bool
    let errorText: String?
    let language: AppLanguage

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            TradingCalendarTheme.paper
            FibreGrain()
            pageContent
        }
        .frame(width: TradingCalendarGeometry.pageW, height: TradingCalendarGeometry.pageH)
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            masthead
            hero
            lunarLine
            Spacer(minLength: 8)
            eventsSection
            footer
        }
        // The top of the page (above the tear line at `tearY`) sits under the binding,
        // so the masthead starts below it — matching himekuri's top inset.
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .overlay(borderRules)
    }

    // MARK: - Borders

    private var borderRules: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(TradingCalendarTheme.ink.opacity(0.9), lineWidth: 2.2)
            .padding(7)
            .overlay {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(TradingCalendarTheme.ink.opacity(0.7), lineWidth: 0.7)
                    .padding(11.5)
            }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(spacing: 2) {
            Text("公历 \(year)年\(month)月\(day)日 · \(weekdayName)")
                .font(TradingCalendarTheme.mincho(9))
                .tracking(0.6)
                .foregroundStyle(TradingCalendarTheme.ink.opacity(0.85))
            Text(englishMonth)
                .font(TradingCalendarTheme.mincho(7.5))
                .tracking(0.5)
                .foregroundStyle(TradingCalendarTheme.faintInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TradingCalendarTheme.ink.opacity(0.5))
                .frame(height: 0.7)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 10) {
            // Left: vertical Chinese month column.
            VStack(spacing: 0) {
                ForEach(Array(chineseMonth.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(TradingCalendarTheme.mincho(9))
                        .foregroundStyle(TradingCalendarTheme.ink.opacity(0.8))
                }
            }
            .frame(width: 26)

            Spacer(minLength: 0)

            // Center: the big day numeral.
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(TradingCalendarTheme.numeral(day >= 10 ? 66 : 78))
                    .foregroundStyle(TradingCalendarTheme.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("第\(dayOfYear)天 · 剩\(daysLeft)天")
                    .font(TradingCalendarTheme.mincho(6.5))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
            }

            Spacer(minLength: 0)

            // Right: filled weekday column.
            VStack(spacing: 3) {
                ForEach(Array(weekdayName.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(TradingCalendarTheme.kanji(11))
                        .foregroundStyle(TradingCalendarTheme.paper)
                }
                Text(englishWeekday)
                    .font(TradingCalendarTheme.kanji(7, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(TradingCalendarTheme.paper.opacity(0.85))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(TradingCalendarTheme.ink)
            )
            .frame(width: 34)
        }
        .frame(height: 82)
    }

    // MARK: - Lunar info (middle)

    private var lunarLine: some View {
        HStack(spacing: 6) {
            Text(L10n.string(.macroLunar, language: language))
                .font(TradingCalendarTheme.kanji(7))
                .foregroundStyle(TradingCalendarTheme.paper)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Rectangle().fill(TradingCalendarTheme.ink))

            Text(lunarMonthDayText)
                .font(TradingCalendarTheme.mincho(10))
                .foregroundStyle(TradingCalendarTheme.ink)

            Spacer(minLength: 6)

            Text("\(lunarGanzhi)年 · 属\(lunarZodiac)")
                .font(TradingCalendarTheme.mincho(7.5))
                .foregroundStyle(TradingCalendarTheme.dimInk)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TradingCalendarTheme.ink.opacity(0.12))
                .frame(height: 0.6)
        }
    }

    // MARK: - Events

    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.string(.macroEventsSection, language: language))
                    .font(TradingCalendarTheme.kanji(9))
                    .foregroundStyle(TradingCalendarTheme.paper)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Rectangle().fill(TradingCalendarTheme.ink))
                Spacer()
                if isLoading {
                    Text(L10n.string(.macroLoading, language: language))
                        .font(TradingCalendarTheme.mincho(7))
                        .foregroundStyle(TradingCalendarTheme.dimInk)
                }
            }

            if let errorText, events.isEmpty {
                Text(errorText)
                    .font(TradingCalendarTheme.mincho(8))
                    .foregroundStyle(TradingCalendarTheme.red)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else if events.isEmpty {
                Text(L10n.string(.macroNoEvents, language: language))
                    .font(TradingCalendarTheme.mincho(9))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                eventList
            }
        }
        .clipped()
    }

    /// A fixed-size printed page has no scrolling — render the events that fit.
    private var eventList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(events.prefix(maxEventRows)) { event in
                eventRow(event)
            }
        }
        .padding(.top, 2)
    }

    private var maxEventRows: Int { 4 }

    private func eventRow(_ event: MacroCalendarEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(MacroCalendarFormat.eventTime(event.time))
                    .font(TradingCalendarTheme.mincho(8))
                    .foregroundStyle(TradingCalendarTheme.red)
                    .monospacedDigit()
                Text(event.country)
                    .font(TradingCalendarTheme.kanji(8, weight: .semibold))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
                Spacer(minLength: 4)
                importanceStars(event.importance)
            }
            Text(event.title)
                .font(TradingCalendarTheme.mincho(9.5))
                .foregroundStyle(TradingCalendarTheme.ink)
                .lineLimit(2)
                .lineSpacing(0.5)
            valuesRow(event)
        }
        .padding(.bottom, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TradingCalendarTheme.ink.opacity(0.12))
                .frame(height: 0.4)
        }
    }

    @ViewBuilder
    private func valuesRow(_ event: MacroCalendarEvent) -> some View {
        let hasValue = event.actual != nil || event.forecast != nil || event.previous != nil
        if hasValue {
            HStack(spacing: 8) {
                valueChip(L10n.string(.macroActual, language: language), event.actual)
                valueChip(L10n.string(.macroForecast, language: language), event.forecast)
                valueChip(L10n.string(.macroPrevious, language: language), event.previous)
            }
            .font(TradingCalendarTheme.mincho(7.5))
            .foregroundStyle(TradingCalendarTheme.dimInk)
        }
    }

    @ViewBuilder
    private func valueChip(_ label: String, _ value: Double?) -> some View {
        if let value {
            Text("\(label) \(formatValue(value))")
                .foregroundStyle(TradingCalendarTheme.faintInk)
        }
    }

    private func importanceStars(_ importance: Int) -> some View {
        let stars = min(max(importance, 0), 2)
        return HStack(spacing: 1) {
            ForEach(0..<2, id: \.self) { i in
                Text("★")
                    .font(TradingCalendarTheme.kanji(7))
                    .foregroundStyle(i < stars ? TradingCalendarTheme.red : TradingCalendarTheme.ink.opacity(0.15))
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("宏观数据源 · WallStreetCN")
                .font(TradingCalendarTheme.mincho(6.5))
                .foregroundStyle(TradingCalendarTheme.faintInk)
            Spacer()
            Text(L10n.string(.tradingCalendar, language: language))
                .font(TradingCalendarTheme.kanji(9, weight: .semibold))
                .foregroundStyle(TradingCalendarTheme.paper)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Rectangle().fill(TradingCalendarTheme.ink))
                .rotationEffect(.degrees(-2))
        }
        .padding(.top, 5)
    }

    // MARK: - Date / lunar helpers

    private var comps: DateComponents {
        calendar.dateComponents([.year, .month, .day, .weekday], from: date)
    }
    private var year: Int { comps.year ?? 0 }
    private var month: Int { comps.month ?? 0 }
    private var day: Int { comps.day ?? 0 }
    private var weekday: Int { comps.weekday ?? 0 }
    private var dayOfYear: Int {
        calendar.ordinality(of: .day, in: .year, for: date) ?? 0
    }
    private var daysLeft: Int {
        guard let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count else { return 0 }
        return max(0, daysInYear - dayOfYear)
    }

    private var lunar: LunarDate? {
        LunarCalendar.lunar(from: date)
    }
    private var lunarMonthDayText: String {
        guard let lunar else { return "" }
        let leap = lunar.isLeapMonth ? "闰" : ""
        return "\(leap)\(LunarCalendar.monthName(lunar.month))\(LunarCalendar.dayName(lunar.day))"
    }
    private var lunarGanzhi: String {
        LunarCalendar.ganzhiYear(lunar?.year ?? year)
    }
    private var lunarZodiac: String {
        LunarCalendar.zodiac(lunar?.year ?? year)
    }

    private var weekdayName: String {
        ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, weekday - 1))]
    }
    private var englishWeekday: String {
        ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][max(0, min(6, weekday - 1))]
    }
    private var chineseMonth: String {
        ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二"][max(0, min(11, month - 1))] + "月"
    }
    private var englishMonth: String {
        calendar.monthSymbols[max(0, min(11, month - 1))]
    }

    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}

/// A light paper-fibre noise overlay so the sheet doesn't read as flat digital white.
private struct FibreGrain: View {
    var body: some View {
        Canvas { context, size in
            let count = 380
            for _ in 0..<count {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let len = CGFloat.random(in: 1...3)
                let alpha = Double.random(in: 0.03...0.08)
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + len, y: y + 0.6))
                context.stroke(path, with: .color(TradingCalendarTheme.grain.opacity(alpha)), lineWidth: 0.6)
            }
        }
        .allowsHitTesting(false)
    }
}
