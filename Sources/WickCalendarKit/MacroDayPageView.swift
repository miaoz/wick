import SwiftUI
import WickSync

/// Event-pane pagination for busy days. A day with up to `singlePageLimit`
/// events prints whole; beyond that the pane flips between uniform
/// `rowsPerPage`-row pages so every page keeps the same geometry (one row is
/// always reserved for the overflow / return line). Full-bleed layouts print
/// more rows per page since their pane is taller.
enum MacroEventPaging {
    static let singlePageLimit = 5
    static let rowsPerPage = 4

    static func pageCount(for eventCount: Int, layout: PaperLayout? = nil) -> Int {
        let rows = layout?.rowsPerPage ?? rowsPerPage
        guard eventCount > max(singlePageLimit, rows) else { return 1 }
        return Int(ceil(Double(eventCount) / Double(rows)))
    }
}

/// The events pane's two compartments: macro data releases and the earnings
/// calendar. Tabs are printed into the page texture, so switching them is a
/// pad-level input (tap on the strip / arrow keys), never a direct hit.
public enum MacroCalendarTab {
    case macro
    case earnings
}

/// The "printed page" for a single trading-calendar day, drawn in himekuri's「黄历」
/// style (green ink on cream paper, double rule, big day numeral, filled weekday column).
/// This view is snapshotted to a texture and warped by the paper physics in `PaperScene`.
///
/// The desktop layout prints the fixed 300×400 design; a full-bleed layout sizes
/// the page to its container, scales the typography with the width, keeps the
/// printed matter clear of the notch/home indicator, and spreads the event rows
/// evenly across the taller pane so the sheet always reads as one complete page.
struct MacroDayPageView: View {
    let date: Date
    let events: [MacroCalendarEvent]
    /// The earnings tab's entries for the same day.
    let earnings: [EarningsReport]
    let isLoading: Bool
    /// The active tab's error text (the root view picks per tab).
    let errorText: String?
    let language: AppLanguage
    /// Which events page a busy day is flipped to (0-based; taps cycle pages).
    let eventsPage: Int
    /// Which compartment the pane shows.
    let tab: MacroCalendarTab
    let layout: PaperLayout
    var convention: PnlColorConvention = .redUp

    private let calendar = Calendar.current

    /// Typographic scale relative to the 300pt-wide desktop design.
    private var s: CGFloat { layout.contentScale }

    private var accent: Color {
        TradingCalendarTheme.accentColor(for: convention)
    }

    var body: some View {
        ZStack {
            TradingCalendarTheme.paper
            FibreGrain()
            pageContent
        }
        .frame(width: layout.pageW, height: layout.pageH)
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
        // so the masthead starts below it - matching himekuri's top inset. On a
        // full-bleed page these insets also clear the notch row under the binding
        // and the home indicator, keeping the printed matter inside the frame.
        .padding(.horizontal, layout.isFullBleed ? layout.frameSideInset + 11 * s : 18 * s)
        .padding(.top, layout.contentTopInset)
        .padding(.bottom, layout.contentBottomInset)
        .overlay(borderRules)
    }

    // MARK: - Borders

    /// The double rule around the printed matter. On a full-bleed page the frame
    /// is inset from the screen edges (below the binding/notch, above the rounded
    /// corners and home indicator) - a printed margin, not a screen border.
    private var borderRules: some View {
        let outer = EdgeInsets(
            top: layout.frameTopInset,
            leading: layout.frameSideInset,
            bottom: layout.frameBottomInset,
            trailing: layout.frameSideInset
        )
        let inner = EdgeInsets(
            top: layout.frameTopInset + 4.5 * s,
            leading: layout.frameSideInset + 4.5 * s,
            bottom: layout.frameBottomInset + 4.5 * s,
            trailing: layout.frameSideInset + 4.5 * s
        )
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(accent.opacity(0.85), lineWidth: 2.2 * s)
            .padding(outer)
            .overlay {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(accent.opacity(0.55), lineWidth: 0.7 * s)
                    .padding(inner)
            }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(spacing: 2 * s) {
            Text("公历 \(year)年\(month)月\(day)日 · 周\(weekdayName)")
                .font(TradingCalendarTheme.mincho(9 * s))
                .tracking(0.6 * s)
                .foregroundStyle(TradingCalendarTheme.ink.opacity(0.85))
            Text(englishMonth)
                .font(TradingCalendarTheme.mincho(7.5 * s))
                .tracking(0.5 * s)
                .foregroundStyle(TradingCalendarTheme.faintInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6 * s)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.4))
                .frame(height: 0.7 * s)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 10 * s) {
            // Left: vertical Chinese month column.
            VStack(spacing: 0) {
                ForEach(Array(chineseMonth.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(TradingCalendarTheme.mincho(9 * s))
                        .foregroundStyle(TradingCalendarTheme.ink.opacity(0.8))
                }
            }
            .frame(width: 26 * s)

            Spacer(minLength: 0)

            // Center: the big day numeral.
            VStack(spacing: 2 * s) {
                Text("\(day)")
                    .font(TradingCalendarTheme.numeral(day >= 10 ? 66 * s : 78 * s))
                    .foregroundStyle(accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("第\(dayOfYear)天 · 剩\(daysLeft)天")
                    .font(TradingCalendarTheme.mincho(6.5 * s))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
            }

            Spacer(minLength: 0)

            // Right: filled weekday column - on a full-bleed page it runs the
            // full height of the hero like the spine label of a real pad.
            VStack(spacing: 3 * s) {
                ForEach(Array(weekdayName.enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(TradingCalendarTheme.kanji(11 * s))
                        .foregroundStyle(TradingCalendarTheme.paper)
                }
                Text(englishWeekday)
                    .font(TradingCalendarTheme.kanji(7 * s, weight: .semibold))
                    .tracking(0.5 * s)
                    .foregroundStyle(TradingCalendarTheme.paper.opacity(0.85))
            }
            .padding(.vertical, 8 * s)
            .padding(.horizontal, 6 * s)
            .frame(maxHeight: layout.isFullBleed ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent)
            )
            .frame(width: 34 * s)
        }
        .frame(height: 82 * s)
    }

    // MARK: - Lunar info (middle)

    private var lunarLine: some View {
        HStack(spacing: 6 * s) {
            Text(L10n.string(.macroLunar, language: language))
                .font(TradingCalendarTheme.kanji(7 * s))
                .foregroundStyle(TradingCalendarTheme.paper)
                .padding(.horizontal, 5 * s)
                .padding(.vertical, 1.5 * s)
                .background(Rectangle().fill(accent))

            Text(lunarMonthDayText)
                .font(TradingCalendarTheme.mincho(10 * s))
                .foregroundStyle(TradingCalendarTheme.ink)

            Spacer(minLength: 6 * s)

            Text("\(lunarGanzhi)年 · 属\(lunarZodiac)")
                .font(TradingCalendarTheme.mincho(7.5 * s))
                .foregroundStyle(TradingCalendarTheme.dimInk)
        }
        .padding(.vertical, 7 * s)
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

        static func forCount(_ count: Int, scale: CGFloat = 1) -> EventDensity {
            switch count {
            case ...2:
                return EventDensity(metaFont: 9.5 * scale, titleFont: 12 * scale, titleLines: 2, valueFont: 8.5 * scale, rowGap: 10 * scale)
            case 3:
                return EventDensity(metaFont: 8 * scale, titleFont: 9 * scale, titleLines: 2, valueFont: 7.5 * scale, rowGap: 4 * scale)
            default:
                return EventDensity(metaFont: 7.5 * scale, titleFont: 8.5 * scale, titleLines: 1, valueFont: nil, rowGap: 4 * scale)
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
    /// line and the footer. On the fixed desktop page content is top-aligned,
    /// so sparse days leave paper whitespace *inside* the pane and the page
    /// never reshuffles between days; a full-bleed page instead spreads its
    /// rows into equal bands so the pane is always used evenly.
    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compartment divider - a double rule echoing the page border.
            VStack(spacing: 2 * s) {
                Rectangle().fill(accent.opacity(0.55)).frame(height: 1 * s)
                Rectangle().fill(accent.opacity(0.3)).frame(height: 0.5 * s)
            }
            .padding(.top, 2 * s)

            eventsHeader
                .padding(.top, 5 * s)

            if isLoading, activeCount == 0 {
                panePlaceholder { loadingMark }
            } else if let errorText, activeCount == 0 {
                panePlaceholder {
                    Text(errorText)
                        .font(TradingCalendarTheme.mincho(8.5 * s))
                        .foregroundStyle(accent)
                }
            } else if activeCount == 0 {
                panePlaceholder { quietSeal }
            } else if tab == .macro {
                eventList
            } else {
                earningsList
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private var activeCount: Int {
        tab == .macro ? events.count : earnings.count
    }

    private var eventsHeader: some View {
        HStack(spacing: 6 * s) {
            tabChip(.macro, title: L10n.string(.macroEventsSection, language: language))
            tabChip(.earnings, title: L10n.string(.earningsSection, language: language))
            if activeCount > 0 {
                // Kept as a separate mincho text: HiraginoSans-W7 mis-renders
                // a middle dot inside the chip's CJK run.
                Text("· \(activeCount)")
                    .font(TradingCalendarTheme.mincho(8.5 * s))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
            }
            Spacer()
            if isLoading, activeCount > 0 {
                Text(L10n.string(.macroLoading, language: language))
                    .font(TradingCalendarTheme.mincho(7 * s))
                    .foregroundStyle(TradingCalendarTheme.dimInk)
            }
        }
    }

    /// A pane tab chip: solid accent when active, an outlined ghost when not.
    private func tabChip(_ chip: MacroCalendarTab, title: String) -> some View {
        let active = tab == chip
        return Text(title)
            .font(TradingCalendarTheme.kanji(9 * s))
            .foregroundStyle(active ? TradingCalendarTheme.paper : TradingCalendarTheme.dimInk)
            .padding(.horizontal, 5 * s)
            .padding(.vertical, 2 * s)
            .background(Rectangle().fill(active ? accent : .clear))
            .overlay {
                if !active {
                    Rectangle()
                        .strokeBorder(accent.opacity(0.45), lineWidth: 0.7 * s)
                }
            }
    }

    /// Centers an empty/loading/error state within the pane's remaining space.
    private func panePlaceholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingMark: some View {
        HStack(spacing: 5 * s) {
            Rectangle()
                .fill(accent.opacity(0.85))
                .frame(width: 4 * s, height: 4 * s)
            Text(L10n.string(.macroLoading, language: language))
                .font(TradingCalendarTheme.mincho(8.5 * s))
                .foregroundStyle(TradingCalendarTheme.dimInk)
        }
    }

    /// Slice one page out of a pane list, keeping every page's geometry
    /// identical (one row is always reserved for the overflow / return line).
    private func pageSlice<Item>(
        _ items: [Item]
    ) -> (rows: ArraySlice<Item>, remaining: Int, page: Int, pageCount: Int) {
        let pageCount = MacroEventPaging.pageCount(for: items.count, layout: layout)
        let page = min(max(eventsPage, 0), pageCount - 1)
        guard pageCount > 1 else { return (items[...], 0, page, pageCount) }
        let start = page * layout.rowsPerPage
        let rows = items[start..<min(start + layout.rowsPerPage, items.count)]
        return (rows, items.count - start - rows.count, page, pageCount)
    }

    /// Print metrics for the pane's rows. Full-bleed pages set the type from
    /// the nominal band (the pane split into its rows-per-page, capped so quiet
    /// days don't blow up to poster type) with a uniform leading - the pane
    /// reads as one ruled table; the desktop page adapts the type to the day's
    /// item count (few items get large print, many get dense print).
    private func paneMetrics(
        totalCount: Int
    ) -> (density: EventDensity, leadingGap: CGFloat?, topPadding: CGFloat) {
        if layout.isFullBleed {
            let band = min(
                layout.eventPaneHeight / CGFloat(max(layout.rowsPerPage, 1)),
                50 * layout.contentScale
            )
            return (
                EventDensity(
                    metaFont: 0.175 * band,
                    titleFont: 0.215 * band,
                    titleLines: 1,
                    valueFont: 0.155 * band,
                    rowGap: 0
                ),
                0.33 * band,
                0.25 * band
            )
        }
        return (EventDensity.forCount(totalCount, scale: s), nil, 4 * s)
    }

    /// A printed page has no scrolling - busy days are split into uniform
    /// pages (taps on the pane flip them) instead of clipping mid-row.
    private var eventList: some View {
        let ranked = rankedEvents
        let slice = pageSlice(ranked)
        let metrics = paneMetrics(totalCount: ranked.count)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(slice.rows) { event in
                eventRow(event, density: metrics.density, leadingGap: metrics.leadingGap)
            }
            if slice.pageCount > 1 {
                overflowFooter(remaining: slice.remaining, page: slice.page)
            }
        }
        .padding(.top, metrics.topPadding)
        // Top-aligned under the section header - leftover space stays at the
        // pane's bottom (like the desktop page), never between the header and
        // the first row.
        .frame(maxHeight: layout.isFullBleed ? .infinity : nil, alignment: .top)
    }

    /// The earnings tab's list - same paging and print rhythm as macro events.
    private var earningsList: some View {
        let slice = pageSlice(earnings)
        let metrics = paneMetrics(totalCount: earnings.count)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(slice.rows) { report in
                earningsRow(report, density: metrics.density, leadingGap: metrics.leadingGap)
            }
            if slice.pageCount > 1 {
                overflowFooter(remaining: slice.remaining, page: slice.page)
            }
        }
        .padding(.top, metrics.topPadding)
        .frame(maxHeight: layout.isFullBleed ? .infinity : nil, alignment: .top)
    }

    /// The pane's footer line: overflow count with a "next page" chevron, or
    /// the return affordance once the last page is reached. The flip hint
    /// prints on the first page only (the full-bleed pad is touch-driven).
    private func overflowFooter(remaining: Int, page: Int) -> some View {
        VStack(spacing: 3 * s) {
            HStack(spacing: 6 * s) {
                hairline
                Text(overflowText(remaining: remaining))
                    .font(TradingCalendarTheme.mincho(7.5 * s))
                    .foregroundStyle(TradingCalendarTheme.faintInk)
                    .fixedSize()
                hairline
            }
            if page == 0 {
                Text(L10n.string(
                    layout.isFullBleed ? .macroEventsFlipHintTouch : .macroEventsFlipHint,
                    language: language
                ))
                    .font(TradingCalendarTheme.mincho(6.5 * s))
                    .tracking(0.5 * s)
                    .foregroundStyle(TradingCalendarTheme.faintInk.opacity(0.75))
            }
        }
        .padding(.top, layout.isFullBleed ? 10 * s : 5 * s)
    }

    /// The pane's footer text: overflow count with a "next page" chevron, or
    /// the return affordance once the last page is reached.
    private func overflowText(remaining: Int) -> String {
        if remaining > 0 {
            return String(format: L10n.string(.macroMoreEventsFormat, language: language), remaining) + " ›"
        }
        return "‹ " + L10n.string(.macroEventsFirstPage, language: language)
    }

    private var hairline: some View {
        Rectangle().fill(TradingCalendarTheme.ink.opacity(0.18)).frame(height: 0.5 * s)
    }

    private func eventRow(
        _ event: MacroCalendarEvent,
        density: EventDensity,
        leadingGap: CGFloat?
    ) -> some View {
        rowChrome(
            VStack(alignment: .leading, spacing: 1.5 * s) {
                HStack(spacing: 5 * s) {
                    Text(MacroCalendarFormat.eventTime(event.time))
                        .font(TradingCalendarTheme.mincho(density.metaFont))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    Text(event.country)
                        .font(TradingCalendarTheme.kanji(density.metaFont))
                        .foregroundStyle(TradingCalendarTheme.dimInk)
                        .lineLimit(1)
                    Spacer(minLength: 4 * s)
                    importanceStars(event.importance, size: density.metaFont - 0.5)
                }
                Text(event.title)
                    .font(TradingCalendarTheme.mincho(density.titleFont))
                    .foregroundStyle(TradingCalendarTheme.ink)
                    .lineLimit(density.titleLines)
                    .lineSpacing(0.5 * s)
                if let valueFont = density.valueFont {
                    valuesRow(event, fontSize: valueFont)
                }
            },
            density: density,
            leadingGap: leadingGap
        )
    }

    /// An earnings row mirrors an event row: the call-time label sits where the
    /// clock would (red when known, dim when not), the company name is the
    /// title, EPS estimate/actual are the values line. No importance stars.
    private func earningsRow(
        _ report: EarningsReport,
        density: EventDensity,
        leadingGap: CGFloat?
    ) -> some View {
        rowChrome(
            VStack(alignment: .leading, spacing: 1.5 * s) {
                HStack(spacing: 5 * s) {
                    Text(callTimeText(report.callTime))
                        .font(TradingCalendarTheme.mincho(density.metaFont))
                        .foregroundStyle(
                            report.callTime == .unspecified
                                ? TradingCalendarTheme.dimInk
                                : accent
                        )
                    Text(report.country)
                        .font(TradingCalendarTheme.kanji(density.metaFont))
                        .foregroundStyle(TradingCalendarTheme.dimInk)
                        .lineLimit(1)
                    Text(report.code)
                        .font(TradingCalendarTheme.mincho(density.metaFont - 0.5))
                        .foregroundStyle(TradingCalendarTheme.faintInk)
                        .lineLimit(1)
                    Spacer(minLength: 4 * s)
                }
                Text(report.companyName)
                    .font(TradingCalendarTheme.mincho(density.titleFont))
                    .foregroundStyle(TradingCalendarTheme.ink)
                    .lineLimit(density.titleLines)
                    .lineSpacing(0.5 * s)
                if let valueFont = density.valueFont {
                    earningsValuesRow(report, fontSize: valueFont)
                }
            },
            density: density,
            leadingGap: leadingGap
        )
    }

    /// Row chrome shared by event and earnings rows: the hairline under each
    /// row, plus the uniform leading that rules a full-bleed pane like a table.
    @ViewBuilder
    private func rowChrome<Content: View>(
        _ content: Content,
        density: EventDensity,
        leadingGap: CGFloat?
    ) -> some View {
        if let leadingGap {
            // A full-bleed row is set at its natural height; the uniform
            // leading and the hairline under the text make the pane read as
            // one ruled table no matter how tall each row is.
            content
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TradingCalendarTheme.ink.opacity(0.12))
                        .frame(height: 0.4 * s)
                }
                .padding(.bottom, leadingGap)
        } else {
            content
                .padding(.bottom, 2.5 * s)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(TradingCalendarTheme.ink.opacity(0.12))
                        .frame(height: 0.4 * s)
                }
                .padding(.bottom, density.rowGap)
        }
    }

    @ViewBuilder
    private func valuesRow(_ event: MacroCalendarEvent, fontSize: CGFloat) -> some View {
        let hasValue = event.actual != nil || event.forecast != nil || event.previous != nil
        if hasValue {
            HStack(spacing: 8 * s) {
                valueChip(L10n.string(.macroActual, language: language), event.actual)
                valueChip(L10n.string(.macroForecast, language: language), event.forecast)
                valueChip(L10n.string(.macroPrevious, language: language), event.previous)
            }
            .font(TradingCalendarTheme.mincho(fontSize))
            .foregroundStyle(TradingCalendarTheme.dimInk)
        }
    }

    @ViewBuilder
    private func earningsValuesRow(_ report: EarningsReport, fontSize: CGFloat) -> some View {
        if report.epsEstimate != nil || report.reportedEps != nil {
            HStack(spacing: 8 * s) {
                valueChip(L10n.string(.macroForecast, language: language), report.epsEstimate)
                valueChip(L10n.string(.macroActual, language: language), report.reportedEps)
            }
            .font(TradingCalendarTheme.mincho(fontSize))
            .foregroundStyle(TradingCalendarTheme.dimInk)
        }
    }

    private func callTimeText(_ callTime: EarningsCallTime) -> String {
        callTime.badge(language: language)
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
        return HStack(spacing: 1 * s) {
            ForEach(0..<2, id: \.self) { i in
                Text("★")
                    .font(TradingCalendarTheme.kanji(size))
                    .foregroundStyle(i < stars ? accent : TradingCalendarTheme.ink.opacity(0.15))
            }
        }
    }

    // MARK: - Quiet-day seal

    /// Sparse days get a dynamic accent「印章」instead of a dead text hole - on a 黄历 the
    /// lower half is always printed, so "nothing today" is print, not absence.
    private var quietSeal: some View {
        let weekend = weekday == 1 || weekday == 7
        return VStack(spacing: 9 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                    .strokeBorder(accent.opacity(0.8), lineWidth: 2.2 * s)
                RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                    .strokeBorder(accent.opacity(0.4), lineWidth: 0.8 * s)
                    .padding(4.5 * s)
                sealCharacters(weekend: weekend)
            }
            .frame(width: 62 * s, height: 62 * s)
            .rotationEffect(.degrees(-3))
            Text(weekend ? "MARKET CLOSED" : "A QUIET DAY")
                .font(TradingCalendarTheme.mincho(6.5 * s))
                .tracking(2 * s)
                .foregroundStyle(TradingCalendarTheme.faintInk)
        }
    }

    /// 休市 reads top-to-bottom; 本日无事 is set as a 2×2 seal read in the
    /// traditional order - right column (本日) first, then left (无事).
    private func sealCharacters(weekend: Bool) -> some View {
        let columns: [[String]] = weekend ? [["休", "市"]] : [["无", "事"], ["本", "日"]]
        return HStack(spacing: 4 * s) {
            ForEach(columns, id: \.self) { column in
                VStack(spacing: 1 * s) {
                    ForEach(column, id: \.self) { ch in
                        Text(ch)
                            .font(TradingCalendarTheme.kanji((weekend ? 20 : 16) * s))
                            .foregroundStyle(accent.opacity(0.85))
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("宏观数据源 · WallStreetCN")
                .font(TradingCalendarTheme.mincho(6.5 * s))
                .foregroundStyle(TradingCalendarTheme.faintInk)
            Spacer()
            Text(L10n.string(.tradingCalendar, language: language))
                .font(TradingCalendarTheme.kanji(9 * s, weight: .semibold))
                .foregroundStyle(TradingCalendarTheme.paper)
                .padding(.horizontal, 7 * s)
                .padding(.vertical, 3 * s)
                .background(Rectangle().fill(accent))
                .rotationEffect(.degrees(-2))
        }
        .padding(.top, 5 * s)
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
            // Constant density per unit area (380 specks on the 300×400 design).
            let count = min(1600, max(380, Int(380 * size.width * size.height / 120_000)))
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
