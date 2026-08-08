import SwiftUI
import WickSync

/// Event-pane pagination for busy days. A day with up to `singlePageLimit`
/// events prints whole; beyond that the pane flips between uniform
/// `rowsPerPage`-row pages so every page keeps the same geometry (one row is
/// always reserved for the overflow / return line).
enum MacroEventPaging {
    static let singlePageLimit = 5
    static let rowsPerPage = 4

    static func pageCount(for eventCount: Int) -> Int {
        guard eventCount > singlePageLimit else { return 1 }
        return Int(ceil(Double(eventCount) / Double(rowsPerPage)))
    }
}

/// The "printed page" for a single trading-calendar day, drawn in himekuri's「黄历」
/// style (green ink on cream paper, double rule, big day numeral, filled weekday column).
/// This view is snapshotted to a texture and warped by the paper physics in `PaperScene`.
struct MacroDayPageView: View {
    let date: Date
    let events: [MacroCalendarEvent]
    let isLoading: Bool
    let errorText: String?
    let language: AppLanguage
    /// Which events page a busy day is flipped to (0-based; taps cycle pages).
    let eventsPage: Int

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
    }

    // MARK: - Events

    /// Row density adapts to the day's event count, mirroring how a real 黄历
    /// packs its lower half: few items get large print, many get dense print.
    private struct EventDensity {
        let metaFont: CGFloat      // time / country / stars
        let titleFont: CGFloat
        let titleLines: Int
        let valueFont: CGFloat?    // nil hides the values row entirely
        let rowGap: CGFloat

        static func forCount(_ count: Int) -> EventDensity {
            switch count {
            case ...2:
                return EventDensity(metaFont: 9.5, titleFont: 12, titleLines: 2, valueFont: 8.5, rowGap: 10)
            case 3:
                return EventDensity(metaFont: 8, titleFont: 9, titleLines: 2, valueFont: 7.5, rowGap: 4)
            default:
                return EventDensity(metaFont: 7.5, titleFont: 8.5, titleLines: 1, valueFont: nil, rowGap: 4)
            }
        }
    }

    /// Most newsworthy first; ties keep chronological order.
    private var rankedEvents: [MacroCalendarEvent] {
        events.sorted { a, b in
            if a.importance != b.importance { return a.importance > b.importance }
            return a.time < b.time
        }
    }

    /// The events pane is a fixed compartment: everything between the lunar
    /// line and the footer. Content is top-aligned, so sparse days leave paper
    /// whitespace *inside* the pane and the page never reshuffles between days.
    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compartment divider — a double rule echoing the page border.
            VStack(spacing: 2) {
                Rectangle().fill(TradingCalendarTheme.ink.opacity(0.5)).frame(height: 1)
                Rectangle().fill(TradingCalendarTheme.ink.opacity(0.28)).frame(height: 0.5)
            }
            .padding(.top, 2)

            eventsHeader
                .padding(.top, 5)

            if isLoading, events.isEmpty {
                panePlaceholder { loadingMark }
            } else if let errorText, events.isEmpty {
                panePlaceholder {
                    Text(errorText)
                        .font(TradingCalendarTheme.mincho(8.5))
                        .foregroundStyle(TradingCalendarTheme.red)
                }
            } else if events.isEmpty {
                panePlaceholder { quietSeal }
            } else {
                eventList
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var eventsHeader: some View {
        HStack(spacing: 6) {
            Text(L10n.string(.macroEventsSection, language: language))
                .font(TradingCalendarTheme.kanji(9))
                .foregroundStyle(TradingCalendarTheme.paper)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Rectangle().fill(TradingCalendarTheme.ink))
            if !events.isEmpty {
                // Kept as a separate mincho text: HiraginoSans-W7 mis-renders
                // a middle dot inside the chip's CJK run.
                Text("· \(events.count)")
                    .font(TradingCalendarTheme.mincho(8.5))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
            }
            Spacer()
            if isLoading, !events.isEmpty {
                Text(L10n.string(.macroLoading, language: language))
                    .font(TradingCalendarTheme.mincho(7))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
            }
        }
    }

    /// Centers an empty/loading/error state within the pane's remaining space.
    private func panePlaceholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingMark: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(TradingCalendarTheme.red.opacity(0.85))
                .frame(width: 4, height: 4)
            Text(L10n.string(.macroLoading, language: language))
                .font(TradingCalendarTheme.mincho(8.5))
                .foregroundStyle(TradingCalendarTheme.dimInk)
        }
    }

    /// A fixed-size printed page has no scrolling — busy days are split into
    /// uniform pages (taps on the pane flip them) instead of clipping mid-row.
    private var eventList: some View {
        let ranked = rankedEvents
        let density = EventDensity.forCount(ranked.count)
        let pageCount = MacroEventPaging.pageCount(for: ranked.count)
        let page = min(max(eventsPage, 0), pageCount - 1)
        let rows: [MacroCalendarEvent]
        if pageCount > 1 {
            let start = page * MacroEventPaging.rowsPerPage
            rows = Array(ranked[start..<min(start + MacroEventPaging.rowsPerPage, ranked.count)])
        } else {
            rows = ranked
        }
        let remaining = ranked.count - page * MacroEventPaging.rowsPerPage - rows.count
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { event in
                eventRow(event, density: density)
            }
            if pageCount > 1 {
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        hairline
                        Text(overflowText(remaining: remaining))
                            .font(TradingCalendarTheme.mincho(7.5))
                            .foregroundStyle(TradingCalendarTheme.faintInk)
                            .fixedSize()
                        hairline
                    }
                    // The flip affordance is invisible otherwise — annotate it
                    // on the first page (where the overflow first appears).
                    if page == 0 {
                        Text(L10n.string(.macroEventsFlipHint, language: language))
                            .font(TradingCalendarTheme.mincho(6.5))
                            .tracking(0.5)
                            .foregroundStyle(TradingCalendarTheme.faintInk.opacity(0.75))
                    }
                }
                .padding(.top, 5)
            }
        }
        .padding(.top, 4)
    }

    /// The pane's footer line: overflow count with a "next page" chevron, or
    /// the return affordance once the last page is reached.
    private func overflowText(remaining: Int) -> String {
        if remaining > 0 {
            return String(format: L10n.string(.macroMoreEventsFormat, language: language), remaining) + " ›"
        }
        return "‹ " + L10n.string(.macroEventsFirstPage, language: language)
    }

    private var hairline: some View {
        Rectangle().fill(TradingCalendarTheme.ink.opacity(0.18)).frame(height: 0.5)
    }

    private func eventRow(_ event: MacroCalendarEvent, density: EventDensity) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            HStack(spacing: 5) {
                Text(MacroCalendarFormat.eventTime(event.time))
                    .font(TradingCalendarTheme.mincho(density.metaFont))
                    .foregroundStyle(TradingCalendarTheme.red)
                    .monospacedDigit()
                Text(event.country)
                    .font(TradingCalendarTheme.kanji(density.metaFont))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                importanceStars(event.importance, size: density.metaFont - 0.5)
            }
            Text(event.title)
                .font(TradingCalendarTheme.mincho(density.titleFont))
                .foregroundStyle(TradingCalendarTheme.ink)
                .lineLimit(density.titleLines)
                .lineSpacing(0.5)
            if let valueFont = density.valueFont {
                valuesRow(event, fontSize: valueFont)
            }
        }
        .padding(.bottom, 2.5)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TradingCalendarTheme.ink.opacity(0.12))
                .frame(height: 0.4)
        }
        .padding(.bottom, density.rowGap)
    }

    @ViewBuilder
    private func valuesRow(_ event: MacroCalendarEvent, fontSize: CGFloat) -> some View {
        let hasValue = event.actual != nil || event.forecast != nil || event.previous != nil
        if hasValue {
            HStack(spacing: 8) {
                valueChip(L10n.string(.macroActual, language: language), event.actual)
                valueChip(L10n.string(.macroForecast, language: language), event.forecast)
                valueChip(L10n.string(.macroPrevious, language: language), event.previous)
            }
            .font(TradingCalendarTheme.mincho(fontSize))
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

    private func importanceStars(_ importance: Int, size: CGFloat) -> some View {
        let stars = min(max(importance, 0), 2)
        return HStack(spacing: 1) {
            ForEach(0..<2, id: \.self) { i in
                Text("★")
                    .font(TradingCalendarTheme.kanji(size))
                    .foregroundStyle(i < stars ? TradingCalendarTheme.red : TradingCalendarTheme.ink.opacity(0.15))
            }
        }
    }

    // MARK: - Quiet-day seal

    /// Sparse days get a red「印章」instead of a dead text hole — on a 黄历 the
    /// lower half is always printed, so "nothing today" is print, not absence.
    private var quietSeal: some View {
        let weekend = weekday == 1 || weekday == 7
        return VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(TradingCalendarTheme.red.opacity(0.8), lineWidth: 2.2)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(TradingCalendarTheme.red.opacity(0.4), lineWidth: 0.8)
                    .padding(4.5)
                sealCharacters(weekend: weekend)
            }
            .frame(width: 62, height: 62)
            .rotationEffect(.degrees(-3))
            Text(weekend ? "MARKET CLOSED" : "A QUIET DAY")
                .font(TradingCalendarTheme.mincho(6.5))
                .tracking(2)
                .foregroundStyle(TradingCalendarTheme.faintInk)
        }
    }

    /// 休市 reads top-to-bottom; 本日无事 is set as a 2×2 seal read in the
    /// traditional order — right column (本日) first, then left (无事).
    private func sealCharacters(weekend: Bool) -> some View {
        let columns: [[String]] = weekend ? [["休", "市"]] : [["无", "事"], ["本", "日"]]
        return HStack(spacing: 4) {
            ForEach(columns, id: \.self) { column in
                VStack(spacing: 1) {
                    ForEach(column, id: \.self) { ch in
                        Text(ch)
                            .font(TradingCalendarTheme.kanji(weekend ? 20 : 16))
                            .foregroundStyle(TradingCalendarTheme.red.opacity(0.85))
                    }
                }
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

    /// Prints values the way a newspaper does: integers plain, one decimal
    /// when it's exact, two only when the precision is real.
    private func formatValue(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        if (value * 10).rounded() == value * 10 {
            return String(format: "%.1f", value)
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
