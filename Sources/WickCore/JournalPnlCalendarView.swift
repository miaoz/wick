import SwiftUI
import WickSync
import WickTrading

/// Month calendar at the top of the journal sidebar. Each day cell is tinted
/// by its state, in priority order:
/// - realized PnL attributed to positions opened that day: green / red;
/// - has a journal entry but no realized-PnL activity: accent tint;
/// - otherwise: gray.
/// Tapping a day selects its journal entry when one exists.
struct JournalPnlCalendarView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: JournalStore
    @ObservedObject private var coordinator = ExchangePositionCoordinator.shared
    @Environment(\.wickPalette) private var palette

    @State private var displayedMonth: Date = monthStart(of: Date(), calendar: .current)

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    var body: some View {
        VStack(spacing: 8) {
            header
            monthTotalRow
            weekdayRow
            dayGrid
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(displayedMonth.formatted(.dateTime.year().month().locale(settings.locale)))
                .font(.custom("Songti SC", size: 12).weight(.bold))
                .foregroundStyle(palette.textPrimary.color)

            Spacer(minLength: 8)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
        }
        .font(.system(size: 11, weight: .semibold))
    }

    /// 「已实现合计 +1,204.6」(单据等宽数字,红盈黛亏;全零不占版)。
    @ViewBuilder
    private var monthTotalRow: some View {
        if let total = monthTotal {
            HStack {
                Text(L10n.string(.inspectorMonthTotal, language: settings.language))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary.color)
                Spacer()
                Text(Self.format(pnl: total))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(total >= 0 ? palette.pnlUp.color : palette.pnlDown.color)
            }
        }
    }

    private var monthTotal: Double? {
        let days = pnlByDay
        let values = days.filter { calendar.isDate($0.key, equalTo: displayedMonth, toGranularity: .month) }
            .map(\.value)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var canGoForward: Bool {
        displayedMonth < Self.monthStart(of: Date(), calendar: calendar)
    }

    private func shiftMonth(by delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = shifted
    }

    // MARK: - Weekday row

    /// 星期头:周一开头(账册惯例),符号跟随 App 语言(一/二/… 或 M/T/…)。
    private var weekdayRow: some View {
        var symbolCalendar = Calendar.current
        symbolCalendar.locale = settings.locale
        let symbols = symbolCalendar.veryShortWeekdaySymbols
        // veryShortWeekdaySymbols 恒为周日开头;平移成周一开头。
        let ordered = (0..<7).map { symbols[($0 + 1) % 7] }
        return LazyVGrid(columns: Self.columns, spacing: 4) {
            ForEach(ordered, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary.color)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day grid

    /// Days of the displayed month, padded with leading nils so day 1 lands
    /// under its weekday column. Grid starts on Monday (账册惯例,同上).
    private var gridDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let first = displayedMonth
        // Calendar.component(.weekday):周日 = 1 … 周六 = 7 → 周一开头的偏移。
        let leading = (calendar.component(.weekday, from: first) + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: first) {
                days.append(date)
            }
        }
        return days
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 4) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 24)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let state = cellState(for: day)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date()
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 10, weight: isToday ? .heavy : .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(textColor(for: state, isToday: isToday))
            .opacity(isFuture ? 0.4 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fillColor(for: state))
            )
            .overlay {
                if isToday {
                    // 今日格:烛火描边(唯一允许发光的颜料)。
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(palette.accent.color, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                select(day: day)
            }
    }

    // MARK: - State resolution

    private enum CellState {
        case profit
        case loss
        case journaled
        case empty
    }

    private var calendar: Calendar { Calendar.current }

    private var pnlByDay: [Date: Double] {
        coordinator.pnlByDay
    }

    /// dayKey -> entry id, for the journaled state and tap-to-select.
    private var entryByDayKey: [String: UUID] {
        Dictionary(store.entries.map { ($0.dayKey, $0.id) }, uniquingKeysWith: { first, _ in first })
    }

    private func cellState(for day: Date) -> CellState {
        if let pnl = pnlByDay[calendar.startOfDay(for: day)] {
            return pnl >= 0 ? .profit : .loss
        }
        if entryByDayKey[JournalDayKey.make(from: day)] != nil {
            return .journaled
        }
        return .empty
    }

    /// 红盈 / 黛亏 / 有日记无仓位 = 烛痕渍(秉烛 §06);
    /// 软填充对应 tokens 的 cinnabar-soft / dai-soft(约 14%)。
    private func fillColor(for state: CellState) -> Color {
        switch state {
        case .profit: return palette.pnlUp.color.opacity(0.14)
        case .loss: return palette.pnlDown.color.opacity(0.14)
        case .journaled: return palette.stain1.color
        case .empty: return .clear
        }
    }

    private func textColor(for state: CellState, isToday: Bool) -> Color {
        if isToday { return palette.textPrimary.color }
        switch state {
        case .profit: return palette.pnlUp.color
        case .loss: return palette.pnlDown.color
        case .journaled: return palette.textSecondary.color
        case .empty: return palette.textTertiary.color
        }
    }

    private func select(day: Date) {
        guard let entryID = entryByDayKey[JournalDayKey.make(from: day)] else { return }
        store.selectDay(entryID)
    }

    private static func monthStart(of date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static let pnlFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static func format(pnl: Double) -> String {
        let sign = pnl >= 0 ? "+" : "−"
        let digits = pnlFormatter.string(from: NSNumber(value: pnl.magnitude)) ?? "0"
        return sign + digits
    }
}
