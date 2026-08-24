import SwiftUI
import WickCalendarKit

// MARK: - Inspector · 右栏检查器(今日事件 + 盈亏月历)

/// The main window's fourth column (⌥⌘0). Top half: today's macro events /
/// earnings printed in the almanac's ink-and-cinnabar language (no dark room,
/// no tear — the physical pad is the easter egg). Bottom half: the month's
/// realized-PnL calendar. Only exists when the physical-calendar easter egg
/// is off; when it's on, the PnL calendar moves to the sidebar top instead.
struct JournalInspectorView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.wickPalette) private var palette
    @ObservedObject private var calendarStore = MacroCalendarStore.shared

    @State private var eventsCollapsed = false
    @State private var pnlCollapsed = false
    @State private var tab: InspectorTab = .macro
    @State private var expandedMacroEventIDs: Set<String> = []
    @State private var expandedEarningsIDs: Set<String> = []

    private enum InspectorTab {
        case macro
        case earnings
    }

    var body: some View {
        VStack(spacing: 0) {
            eventsSection
            Divider().overlay(palette.divider.color)
            pnlSection
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(palette.columnPaper.color)
        .onAppear {
            calendarStore.loadIfNeeded(for: Date())
        }
    }

    // MARK: 今日事件

    private var eventsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: L10n.string(.tradingCalendar, language: settings.language),
                detail: weekdayStamp,
                collapsed: $eventsCollapsed
            )

            if !eventsCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    // 报头:大日期 + 农历,与黄历同字态(语言跟随 App 设置;
                    // Text(date, format:) 不吃注入 locale,走 DateFormatter)。
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(inspectorBigDate)
                            .font(AppFont.ui(24, weight: .black, design: .serif))
                            .foregroundStyle(palette.textPrimary.color)
                        if let lunar = LunarLine.string(for: Date()) {
                            Text(lunar)
                                .font(AppFont.paper(10))
                                .foregroundStyle(palette.textSecondary.color)
                                .lineLimit(1)
                        }
                    }

                    // 宜忌行:朱砂「宜」/ 烟墨「忌」小方印 + 宋体小字(秉烛 §03)。
                    HStack(spacing: 9) {
                        yijiChip(
                            mark: L10n.string(.inspectorYiLabel, language: settings.language),
                            text: L10n.string(.inspectorYiText, language: settings.language),
                            markBackground: palette.pnlUp.color,
                            markInk: Color(red: 0.98, green: 0.92, blue: 0.85)
                        )
                        yijiChip(
                            mark: L10n.string(.inspectorJiLabel, language: settings.language),
                            text: L10n.string(.inspectorJiText, language: settings.language),
                            markBackground: palette.textPrimary.color,
                            // 「忌」章底随烟墨反相,章字吃纸面色才读得出。
                            markInk: palette.columnPaper.color
                        )
                    }

                    // 栏目签条:宏观 / 财报
                    HStack(spacing: 6) {
                        inspectorTab(title: L10n.string(.macroEventsSection, language: settings.language), tab: .macro)
                        inspectorTab(title: L10n.string(.earningsSection, language: settings.language), tab: .earnings)
                    }

                    if pnlCollapsed {
                        // 盈亏月历收合 → 行区独撑余下高度,全量滚动(事件常有数十项);
                        // 反向(事件收合、盈亏上提)本来就是定高堆叠的天然行为。
                        ScrollView { rowsContent }
                            .scrollIndicators(.never)
                            .hidesAppKitScrollers()
                    } else {
                        rowsContent
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }

    private var weekdayStamp: String {
        Date().formatted(.dateTime.weekday(.wide).locale(settings.locale))
    }

    /// 检查器大日期:「8月21日」/ "Aug 21",跟随 App 语言。
    private var inspectorBigDate: String {
        WickDateFormat.string(from: Date(), template: "MMMd", locale: settings.language.locale)
    }

    /// 宜忌小印:白文小方章(朱砂/烟墨)+ 宋体短语。
    private func yijiChip(mark: String, text: String, markBackground: Color, markInk: Color) -> some View {
        HStack(spacing: 4) {
            Text(mark)
                .font(AppFont.paper(8.5, weight: .bold))
                .foregroundStyle(markInk)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(markBackground)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            Text(text)
                .font(AppFont.paper(9.5))
                .foregroundStyle(palette.textSecondary.color)
        }
    }

    private func inspectorTab(title: String, tab: InspectorTab) -> some View {
        Button {
            self.tab = tab
        } label: {
            Text(title)
                .font(AppFont.paper(10, weight: self.tab == tab ? .bold : .medium))
                .foregroundStyle(self.tab == tab ? Color(red: 0.98, green: 0.92, blue: 0.85) : palette.pnlUp.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(self.tab == tab ? palette.pnlUp.color : .clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(palette.pnlUp.color, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rowsContent: some View {
        if calendarStore.isLoading(for: Date()) {
            Text(L10n.string(.macroLoading, language: settings.language))
                .font(AppFont.preset(.caption))
                .foregroundStyle(palette.textTertiary.color)
                .padding(.vertical, 6)
        } else if tab == .macro {
            macroRows(limit: rowLimit)
        } else {
            earningsRows(limit: rowLimit)
        }
    }

    /// 盈亏月历收合时事件栏独撑整栏,行数不再截断(事件常有数十项)。
    private var rowLimit: Int? {
        pnlCollapsed ? nil : 8
    }

    private func macroRows(limit: Int?) -> some View {
        let events = calendarStore.events(for: Date())
        return Group {
            if events.isEmpty {
                idleChop
            } else {
                let shown = limit.map { Array(events.prefix($0)) } ?? events
                ForEach(shown) { event in
                    let isExpanded = expandedMacroEventIDs.contains(event.id)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(Self.eventTimeFormatter.string(from: event.time))
                            .font(AppFont.ui(9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.pnlUp.color)
                            .frame(width: 34, alignment: .leading)
                        Text(event.country)
                            .font(AppFont.paper(10))
                            .foregroundStyle(palette.textSecondary.color)
                            .lineLimit(1)
                            .frame(width: 32, alignment: .leading)
                        Text(event.title)
                            .font(AppFont.paper(10.5))
                            .foregroundStyle(palette.textPrimary.color)
                            // 检查器行短,长标题默认折两行,点击可展开全部/收起。
                            .lineLimit(isExpanded ? nil : 2)
                        Spacer(minLength: 4)
                        Text(macroValues(event))
                            .font(AppFont.ui(8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textTertiary.color)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3.5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedMacroEventIDs.contains(event.id) {
                                expandedMacroEventIDs.remove(event.id)
                            } else {
                                expandedMacroEventIDs.insert(event.id)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.divider.color.opacity(0.7)).frame(height: 1)
                    }
                }
                if events.count > shown.count {
                    Text(String(format: L10n.string(.macroMoreEventsFormat, language: settings.language), events.count - shown.count) + " ›")
                        .font(AppFont.paper(10))
                        .foregroundStyle(palette.pnlUp.color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func earningsRows(limit: Int?) -> some View {
        let reports = calendarStore.earnings(for: Date())
        return Group {
            if reports.isEmpty {
                idleChop
            } else {
                let shown = limit.map { Array(reports.prefix($0)) } ?? reports
                ForEach(shown) { report in
                    let isExpanded = expandedEarningsIDs.contains(report.id)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(earningsCallMark(report))
                            .font(AppFont.paper(9, weight: .bold))
                            .foregroundStyle(palette.pnlUp.color)
                            .frame(width: 30, alignment: .leading)
                        Text(report.code)
                            .font(AppFont.ui(9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textPrimary.color)
                            // 代码永不折行(溢出两行比参差不齐更难看),公司名让位。
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 52, alignment: .leading)
                        Text(report.companyName)
                            .font(AppFont.paper(10.5))
                            .foregroundStyle(palette.textPrimary.color)
                            .lineLimit(isExpanded ? nil : 1)
                        Spacer(minLength: 4)
                        if let eps = report.epsEstimate {
                            Text("EPS \(Self.epsFormatter.string(from: NSNumber(value: eps)) ?? "")")
                                .font(AppFont.ui(8.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(palette.textTertiary.color)
                        }
                    }
                    .padding(.vertical, 3.5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedEarningsIDs.contains(report.id) {
                                expandedEarningsIDs.remove(report.id)
                            } else {
                                expandedEarningsIDs.insert(report.id)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.divider.color.opacity(0.7)).frame(height: 1)
                    }
                }
                if reports.count > shown.count {
                    Text(String(format: L10n.string(.macroMoreEventsFormat, language: settings.language), reports.count - shown.count) + " ›")
                        .font(AppFont.paper(10))
                        .foregroundStyle(palette.pnlUp.color)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// 闲日章:周末「休市」/ 工作日「本日无事」(秉烛 §06)。
    private var idleChop: some View {
        let isWeekend = Calendar.current.isDateInWeekend(Date())
        let text = L10n.string(isWeekend ? .calendarIdleWeekend : .calendarIdleWeekday, language: settings.language)
        return Text(text)
            .font(AppFont.paper(11, weight: .bold))
            .tracking(2)
            .foregroundStyle(palette.pnlUp.color.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(palette.pnlUp.color.opacity(0.75), lineWidth: 1.2)
            }
            .rotationEffect(.degrees(-3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    // MARK: 盈亏月历(下半栏)

    private var pnlSection: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: L10n.string(.inspectorMonthlyOverview, language: settings.language),
                detail: nil,
                collapsed: $pnlCollapsed
            )
            if !pnlCollapsed {
                JournalPnlCalendarView()
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: Shared chrome

    private func sectionHeader(title: String, detail: String?, collapsed: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                collapsed.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(AppFont.paper(12, weight: .bold))
                    .foregroundStyle(palette.textPrimary.color)
                if let detail {
                    Text(detail)
                        .font(AppFont.ui(9, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.textTertiary.color)
                }
                Spacer()
                Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                    .font(AppFont.ui(9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary.color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 事件数值:一栏只印一个数(设计 §03:今值优先,否则前值,最后预期)。
    private func macroValues(_ event: MacroCalendarEvent) -> String {
        if let actual = event.actual {
            return L10n.string(.macroActual, language: settings.language) + " " + Self.numberFormatter.string(from: NSNumber(value: actual))!
        }
        if let previous = event.previous {
            return L10n.string(.macroPrevious, language: settings.language) + " " + Self.numberFormatter.string(from: NSNumber(value: previous))!
        }
        if let forecast = event.forecast {
            return L10n.string(.macroForecast, language: settings.language) + " " + Self.numberFormatter.string(from: NSNumber(value: forecast))!
        }
        return ""
    }

    private func earningsCallMark(_ report: EarningsReport) -> String {
        report.callTime.badge(language: settings.language)
    }

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let epsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
