import SwiftUI
import WickSync

/// 秉烛视觉语言的日期选择器(替代原生带蓝框的 DatePicker)。
/// - 宣纸/烟墨/烛火朱砂色板
/// - 农历与宋体月份报头
/// - 星期一开头(账册惯例)
/// - 选中格烛火实底 + 起光,今日格烛火描边
struct JournalDatePickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.wickPalette) private var palette

    @Binding var selectedDate: Date
    var onSelectDate: ((Date) -> Void)?

    @State private var displayedMonth: Date
    @State private var hoveredDay: Date?

    init(
        selectedDate: Binding<Date>,
        onSelectDate: ((Date) -> Void)? = nil
    ) {
        self._selectedDate = selectedDate
        self.onSelectDate = onSelectDate
        let cal = Calendar.current
        let start = cal.dateInterval(of: .month, for: selectedDate.wrappedValue)?.start ?? selectedDate.wrappedValue
        self._displayedMonth = State(initialValue: start)
    }

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayRow
            dayGrid
            footer
        }
        .padding(12)
        .frame(width: 236)
        .background(palette.columnPaper.color)
    }

    // MARK: - Header (月份切换)

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppFont.ui(10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary.color)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Text(displayedMonth.formatted(.dateTime.year().month().locale(settings.locale)))
                .font(AppFont.paper(13, weight: .bold))
                .foregroundStyle(palette.textPrimary.color)

            Spacer(minLength: 4)

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(AppFont.ui(10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary.color)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
    }

    private func shiftMonth(by delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: displayedMonth) else { return }
        displayedMonth = shifted
    }

    // MARK: - Weekday Row (周一开头)

    private var weekdayRow: some View {
        var symbolCalendar = Calendar.current
        symbolCalendar.locale = settings.locale
        let symbols = symbolCalendar.veryShortWeekdaySymbols
        let ordered = (0..<7).map { symbols[($0 + 1) % 7] }
        return LazyVGrid(columns: Self.columns, spacing: 4) {
            ForEach(ordered, id: \.self) { symbol in
                Text(symbol)
                    .font(AppFont.ui(9.5, weight: .medium))
                    .foregroundStyle(palette.textTertiary.color)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day Grid

    private var gridDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let first = displayedMonth
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
                    Color.clear.frame(height: 25)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let isHovered = hoveredDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false

        return Text("\(calendar.component(.day, from: day))")
            .font(AppFont.ui(11, weight: (isSelected || isToday) ? .bold : .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(
                isSelected ? Color(red: 1, green: 0.95, blue: 0.88)
                    : (isToday ? palette.accent.color : palette.textPrimary.color)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 25)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isSelected ? palette.accent.color
                            : (isHovered ? palette.accentSoft.color : Color.clear)
                    )
            )
            .overlay {
                if isSelected {
                    // 选中状态光晕
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.accent.color, lineWidth: 1)
                } else if isToday {
                    // 今日格:烛火描边
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.accent.color, lineWidth: 1.5)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.accent.color.opacity(0.4), lineWidth: 0.8)
                }
            }
            .shadow(color: isSelected ? palette.glow.color.opacity(0.8) : .clear, radius: 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoveredDay = hovering ? day : (hoveredDay == day ? nil : hoveredDay)
            }
            .onTapGesture {
                selectedDate = day
                onSelectDate?(day)
            }
    }

    // MARK: - Footer (今日快捷跳转)

    private var footer: some View {
        HStack {
            Button {
                let today = Date()
                let start = calendar.dateInterval(of: .month, for: today)?.start ?? today
                displayedMonth = start
                selectedDate = today
                onSelectDate?(today)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(AppFont.ui(9.5))
                    Text(L10n.string(.journalToday, language: settings.language))
                        .font(AppFont.paper(11))
                }
                .foregroundStyle(palette.accent.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.accentSoft.color)
                )
            }
            .buttonStyle(.plain)
            .help(L10n.string(.journalToday, language: settings.language))

            Spacer()
        }
        .padding(.top, 2)
    }
}
