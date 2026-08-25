import SwiftUI
import UIKit
import WickCalendarKit
import WickSync

/// Full trading calendar view on iOS with Dual-Mode Architecture:
/// 1. Default (Flat Paper List): High-density, scrollable, clean paper layout with date nav & tabs.
/// 2. Easter Egg (Physical Tearable): Full-screen verlet physics tearable page with vermilion binding rail.
struct CalendarView: View {
    @AppStorage("wick.calendar.physicalEasterEgg") private var physicalEasterEgg = false
    @ObservedObject private var calendarStore = MacroCalendarStore.shared
    @Environment(\.appLanguage) private var language: AppLanguage
    @State private var selectedDate = Date()
    @State private var activeTab: CalendarTab = .macro

    enum CalendarTab {
        case macro
        case earnings
    }

    var body: some View {
        NavigationStack {
            Group {
                if physicalEasterEgg {
                    PhysicalCalendarView(language: language)
                } else {
                    FlatCalendarView(
                        selectedDate: $selectedDate,
                        activeTab: $activeTab,
                        calendarStore: calendarStore,
                        language: language
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - 1. Default Flat Paper Calendar

private struct FlatCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var activeTab: CalendarView.CalendarTab
    @ObservedObject var calendarStore: MacroCalendarStore
    let language: AppLanguage

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Tall, Breathing Almanac Hero Card
                FlatCalendarHeroCard(
                    date: selectedDate,
                    events: calendarStore.events(for: selectedDate),
                    language: language,
                    onPreviousDay: { shiftDate(by: -1) },
                    onNextDay: { shiftDate(by: 1) },
                    onToday: {
                        selectedDate = Date()
                        calendarStore.loadIfNeeded(for: selectedDate)
                    }
                )

                // Macro / Earnings Dual Tabs
                HStack(spacing: 8) {
                    TabButton(
                        title: "\(L10n.string(.macroEventsSection, language: language)) (\(calendarStore.events(for: selectedDate).count))",
                        isActive: activeTab == .macro
                    ) {
                        activeTab = .macro
                    }

                    TabButton(
                        title: "\(L10n.string(.earningsSection, language: language)) (\(calendarStore.earnings(for: selectedDate).count))",
                        isActive: activeTab == .earnings
                    ) {
                        activeTab = .earnings
                    }
                }
                .padding(.horizontal, 14)

                // Event List
                if activeTab == .macro {
                    let events = calendarStore.events(for: selectedDate)
                    if events.isEmpty {
                        EmptyDayStampView(
                            stamp: language == .chinese ? "本日休市" : "CLOSED",
                            text: language == .chinese ? "本日无重大宏观发布" : "No macro events scheduled"
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(events) { event in
                                MacroEventCard(event: event, language: language)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                } else {
                    let earnings = calendarStore.earnings(for: selectedDate)
                    if earnings.isEmpty {
                        EmptyDayStampView(
                            stamp: language == .chinese ? "本日休市" : "CLOSED",
                            text: language == .chinese ? "本日无重点公司财报" : "No earnings reports scheduled"
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(earnings) { item in
                                EarningsReportCard(report: item, language: language)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(PhoneTheme.paper.ignoresSafeArea())
        .onAppear {
            calendarStore.loadIfNeeded(for: selectedDate)
        }
    }

    private func shiftDate(by delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) {
            selectedDate = newDate
            calendarStore.loadIfNeeded(for: selectedDate)
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
        }
    }
}

// MARK: - Flat Calendar Hero Card

private struct FlatCalendarHeroCard: View {
    let date: Date
    var events: [MacroCalendarEvent] = []
    let language: AppLanguage
    let onPreviousDay: () -> Void
    let onNextDay: () -> Void
    let onToday: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dayNum: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: date)
    }

    private var yearMonthDisplay: String {
        let fmt = DateFormatter()
        fmt.locale = language.locale
        fmt.dateFormat = language == .chinese ? "yyyy年 M月" : "MMMM yyyy"
        return fmt.string(from: date)
    }

    private var weekdayChars: [String] {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        if language == .chinese {
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let name = names[(weekday - 1) % 7]
            return name.map { String($0) }
        } else {
            let names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
            return [names[(weekday - 1) % 7]]
        }
    }

    private var dayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    private var daysLeft: Int {
        let total = Calendar.current.range(of: .day, in: .year, for: date)?.count ?? 365
        return max(0, total - dayOfYear)
    }

    private var lunarGanzhiText: String {
        if let lunar = LunarCalendar.lunar(from: date) {
            let m = (lunar.isLeapMonth ? "闰" : "") + LunarCalendar.monthName(lunar.month)
            let d = LunarCalendar.dayName(lunar.day)
            let gz = LunarCalendar.ganzhiYear(lunar.year)
            let z = LunarCalendar.zodiac(lunar.year)
            if language == .chinese {
                return "\(m)\(d) · \(gz)年 (属\(z))"
            } else {
                return "\(m) \(d) · Year \(gz)"
            }
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Navigation Bar (Year/Month + Prev/Next Controls + Today Tag)
            HStack(alignment: .center) {
                Button(action: onPreviousDay) {
                    Image(systemName: "chevron.left")
                        .font(PhoneFont.ui(12, weight: .semibold))
                        .foregroundColor(PhoneTheme.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(PhoneTheme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Text(yearMonthDisplay)
                        .font(PhoneFont.paper(14, weight: .bold))
                        .foregroundColor(PhoneTheme.inkPrimary)

                    if !isToday {
                        Button(action: onToday) {
                            Text(L10n.string(.journalToday, language: language))
                                .font(PhoneFont.paper(10.5, weight: .bold))
                                .foregroundColor(PhoneTheme.cinnabar)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(PhoneTheme.cinnabarSoft)
                                .cornerRadius(3)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(PhoneTheme.cinnabar.opacity(0.3), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button(action: onNextDay) {
                    Image(systemName: "chevron.right")
                        .font(PhoneFont.ui(12, weight: .semibold))
                        .foregroundColor(PhoneTheme.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(PhoneTheme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // 2. Grand Almanac Center Stage
            HStack(alignment: .center, spacing: 14) {
                // Left Column: Day count & progress
                VStack(alignment: .leading, spacing: 4) {
                    Text(language == .chinese ? "第 \(dayOfYear) 天" : "Day \(dayOfYear)")
                        .font(PhoneFont.paper(12, weight: .medium))
                        .foregroundColor(PhoneTheme.inkSecondary)
                    Text(language == .chinese ? "余 \(daysLeft) 天" : "\(daysLeft) days left")
                        .font(PhoneFont.paper(10.5))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
                .frame(minWidth: 70, alignment: .leading)

                Spacer()

                // Center: Big Bold Day Numeral
                Text(dayNum)
                    .font(PhoneFont.paper(60, weight: .black))
                    .foregroundColor(PhoneTheme.cinnabar)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                // Right Column: Vertical Weekday Cinnabar Slip
                VStack(spacing: 2) {
                    ForEach(Array(weekdayChars.enumerated()), id: \.offset) { _, ch in
                        Text(ch)
                    }
                }
                .font(PhoneFont.paper(language == .chinese ? 12.5 : 10, weight: .bold))
                .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                .padding(.horizontal, language == .chinese ? 7 : 5)
                .padding(.vertical, 7)
                .background(PhoneTheme.cinnabar)
                .cornerRadius(3)
                .shadow(color: PhoneTheme.cinnabar.opacity(0.25), radius: 3, y: 1)
                .frame(minWidth: 70, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            // 3. Hairline Divider
            Rectangle()
                .fill(PhoneTheme.rule)
                .frame(height: 1)
                .padding(.horizontal, 14)

            // 4. Lunar Line
            if !lunarGanzhiText.isEmpty {
                Text(lunarGanzhiText)
                    .font(PhoneFont.paper(11.5))
                    .foregroundColor(PhoneTheme.inkSecondary)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }

            // 5. Integrated Yi / Ji Guidance Bar with Lucky / Taboo & Seal
            let entry = TraderAlmanac.entry(for: date, events: events)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        TraderYiJiChip(
                            mark: language == .chinese ? "宜" : "DO",
                            text: entry.yiText(language: language),
                            markBackground: PhoneTheme.cinnabar,
                            markInk: Color(red: 0.98, green: 0.95, blue: 0.90),
                            textInk: PhoneTheme.inkPrimary,
                            markFont: PhoneFont.paper(9.5, weight: .black),
                            textFont: PhoneFont.paper(11),
                            cornerRadius: 2,
                            paddingH: 4,
                            paddingV: 1.5
                        )
                        TraderYiJiChip(
                            mark: language == .chinese ? "忌" : "AVOID",
                            text: entry.jiText(language: language),
                            markBackground: PhoneTheme.char,
                            markInk: Color(red: 0.98, green: 0.95, blue: 0.90),
                            textInk: PhoneTheme.inkPrimary,
                            markFont: PhoneFont.paper(9.5, weight: .black),
                            textFont: PhoneFont.paper(11),
                            cornerRadius: 2,
                            paddingH: 4,
                            paddingV: 1.5
                        )
                    }

                    Spacer(minLength: 4)

                    if let seal = entry.sealText(language: language) {
                        TraderAlmanacSealBadge(text: seal, accent: PhoneTheme.cinnabar, scale: 1.15, angle: -3)
                    }
                }

                if entry.luckyText(language: language) != nil || entry.shaText(language: language) != nil {
                    TraderAlmanacMetaRow(
                        entry: entry,
                        language: language,
                        accentColor: PhoneTheme.cinnabar,
                        textInk: PhoneTheme.inkTertiary,
                        font: PhoneFont.paper(9.5)
                    )
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PhoneTheme.paper)
            .cornerRadius(4)
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .background(PhoneTheme.paperHi)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(PhoneTheme.rule, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PhoneFont.paper(12.5, weight: .bold))
                .foregroundColor(isActive ? Color(red: 0.98, green: 0.95, blue: 0.90) : PhoneTheme.inkSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? PhoneTheme.cinnabar : PhoneTheme.paperHi)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isActive ? PhoneTheme.cinnabar : PhoneTheme.rule, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MacroEventCard: View {
    let event: MacroCalendarEvent
    let language: AppLanguage
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Time & Importance
            VStack(spacing: 2) {
                Text(MacroCalendarFormat.eventTime(event.time))
                    .font(PhoneFont.ui(11, weight: .bold, monospacedDigit: true))
                    .foregroundColor(PhoneTheme.cinnabar)

                HStack(spacing: 1) {
                    ForEach(0..<max(1, min(3, event.importance)), id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(PhoneFont.ui(7))
                            .foregroundColor(PhoneTheme.ember)
                    }
                }
            }
            .frame(width: 44, alignment: .leading)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !event.country.isEmpty {
                        Text(event.country)
                            .font(PhoneFont.paper(9.5, weight: .bold))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.rule.opacity(0.6))
                            .cornerRadius(2)
                    }
                    Text(event.title)
                        .font(PhoneFont.paper(12.5, weight: .semibold))
                        .foregroundColor(PhoneTheme.inkPrimary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    if let prev = event.previous {
                        Text("\(language == .chinese ? "前" : "Prev") \(formatNumber(prev))")
                            .font(PhoneFont.ui(10, monospacedDigit: true))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                    if let fc = event.forecast {
                        Text("\(language == .chinese ? "预" : "Fcst") \(formatNumber(fc))")
                            .font(PhoneFont.ui(10, monospacedDigit: true))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                    if let act = event.actual {
                        Text("\(language == .chinese ? "今" : "Act") \(formatNumber(act))")
                            .font(PhoneFont.ui(10.5, weight: .bold, monospacedDigit: true))
                            .foregroundColor(PhoneTheme.cinnabar)
                    }
                }
            }

            Spacer(minLength: 4)
        }
        .padding(10)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(event.importance >= 3 ? PhoneTheme.cinnabar.opacity(0.3) : PhoneTheme.rule, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        }
    }

    private func formatNumber(_ val: Double) -> String {
        String(format: "%.1f", val)
    }
}

private struct EarningsReportCard: View {
    let report: EarningsReport
    let language: AppLanguage
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(report.callTime.badge(language: language))
                .font(PhoneFont.paper(9.5, weight: .bold))
                .foregroundColor(PhoneTheme.cinnabar)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(PhoneTheme.cinnabarSoft)
                .cornerRadius(2)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(report.code)
                        .font(PhoneFont.ui(11, weight: .bold, monospacedDigit: true))
                        .foregroundColor(PhoneTheme.cinnabar)
                        .fixedSize()
                    Text(report.companyName)
                        .font(PhoneFont.paper(12.5, weight: .semibold))
                        .foregroundColor(PhoneTheme.inkPrimary)
                        .lineLimit(isExpanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let eps = report.epsEstimate {
                    Text("\(language == .chinese ? "EPS 预期" : "EPS Est"): \(String(format: "%.2f", eps))")
                        .font(PhoneFont.ui(10, monospacedDigit: true))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(10)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        }
    }
}

private struct EmptyDayStampView: View {
    let stamp: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(PhoneTheme.cinnabar.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 88, height: 44)
                Text(stamp)
                    .font(PhoneFont.paper(14, weight: .bold))
                    .foregroundColor(PhoneTheme.cinnabar.opacity(0.8))
            }
            .rotationEffect(.degrees(-3))
            .padding(.top, 36)

            Text(text)
                .font(PhoneFont.paper(12))
                .foregroundColor(PhoneTheme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 2. Easter Egg Physical Tearable Calendar

private struct PhysicalCalendarView: View {
    let language: AppLanguage
    @State private var tornPiece: FallingPage?

    var body: some View {
        GeometryReader { geo in
            let safe = keyWindowSafeInsets
            let layout = PaperLayout.fullScreen(
                size: geo.size,
                safeTop: min(max(safe.top, geo.safeAreaInsets.top), 140),
                safeBottom: min(max(safe.bottom, geo.safeAreaInsets.bottom), 60)
            )
            ZStack {
                TradingCalendarTheme.paper
                if geo.size.width > 1, geo.size.height > 1 {
                    TradingCalendarRootView(
                        language: language,
                        onClose: {},
                        onPageTorn: { tornPiece = $0 },
                        layout: layout
                    )
                    .id(layout)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .overlay {
                if let tornPiece {
                    iOSFallingPageOverlay(piece: tornPiece) {
                        self.tornPiece = nil
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var keyWindowSafeInsets: (top: CGFloat, bottom: CGFloat) {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        if let insets = keyWindow?.safeAreaInsets {
            return (insets.top, insets.bottom)
        }
        return (0, 0)
    }
}

private struct iOSFallingPageOverlay: View {
    let piece: FallingPage
    let onFinished: () -> Void

    var body: some View {
        GeometryReader { geo in
            let fallDistance = geo.size.height
                - piece.layout.blockTopPad
                - piece.layout.pageTopInset
                + 60
            FallingPageView(page: piece, fallDistance: max(fallDistance, 400), headroom: 14)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                onFinished()
            }
        }
    }
}
