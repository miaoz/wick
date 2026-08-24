import SwiftUI
import UIKit
import WickCalendarKit
import WickSync

/// Full trading calendar view on iOS with Dual-Mode Architecture:
/// 1. Default (Flat Paper List): High-density, scrollable, clean paper layout with date nav & tabs.
/// 2. Easter Egg (Physical Tearable): Full-screen verlet physics tearable page with vermilion binding rail.
struct CalendarView: View {
    @AppStorage("wick.calendar.physicalEasterEgg") private var physicalEasterEgg = false
    @StateObject private var calendarStore = MacroCalendarStore.shared
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
                    PhysicalCalendarView()
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    FlatCalendarView(
                        selectedDate: $selectedDate,
                        activeTab: $activeTab,
                        calendarStore: calendarStore
                    )
                    .navigationTitle("交易黄历")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}

// MARK: - 1. Default Flat Paper Calendar

private struct FlatCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var activeTab: CalendarView.CalendarTab
    @ObservedObject var calendarStore: MacroCalendarStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Top Date Navigation Bar
                HStack {
                    Button {
                        shiftDate(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(PhoneTheme.paperHi)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text(Self.dateDisplay(for: selectedDate))
                            .font(.system(size: 18, weight: .bold, design: .serif))
                            .foregroundColor(PhoneTheme.inkPrimary)

                        if let lunar = LunarLine.string(for: selectedDate) {
                            Text(lunar)
                                .font(.system(size: 10.5, design: .serif))
                                .foregroundColor(PhoneTheme.inkTertiary)
                        }
                    }

                    Spacer()

                    Button {
                        shiftDate(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(PhoneTheme.paperHi)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                    }

                    if !Calendar.current.isDateInToday(selectedDate) {
                        Button("今天") {
                            selectedDate = Date()
                            calendarStore.loadIfNeeded(for: selectedDate)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundColor(PhoneTheme.cinnabar)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(PhoneTheme.cinnabarSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                // Yi / Ji Paper Banner
                HStack {
                    HStack(spacing: 4) {
                        Text("宜")
                            .font(.system(size: 10, weight: .black, design: .serif))
                            .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.cinnabar)
                            .cornerRadius(2)
                        Text("止盈 · 依纪复盘")
                            .font(.system(size: 11.5, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("忌")
                            .font(.system(size: 10, weight: .black, design: .serif))
                            .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.char)
                            .cornerRadius(2)
                        Text("追涨 · 扛单违规")
                            .font(.system(size: 11.5, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(PhoneTheme.paperHi)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                .padding(.horizontal, 14)

                // Macro / Earnings Dual Tabs
                HStack(spacing: 8) {
                    TabButton(
                        title: "宏观事件 (\(calendarStore.events(for: selectedDate).count))",
                        isActive: activeTab == .macro
                    ) {
                        activeTab = .macro
                    }

                    TabButton(
                        title: "公司财报 (\(calendarStore.earnings(for: selectedDate).count))",
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
                        EmptyDayStampView(text: "本日无重大宏观发布")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(events) { event in
                                MacroEventCard(event: event)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                } else {
                    let earnings = calendarStore.earnings(for: selectedDate)
                    if earnings.isEmpty {
                        EmptyDayStampView(text: "本日无重点公司财报")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(earnings) { item in
                                EarningsReportCard(report: item)
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

    private static func dateDisplay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .serif))
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

    var body: some View {
        HStack(spacing: 12) {
            // Time & Importance
            VStack(spacing: 2) {
                Text(MacroCalendarFormat.eventTime(event.time))
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(PhoneTheme.cinnabar)

                HStack(spacing: 1) {
                    ForEach(0..<max(1, min(3, event.importance)), id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundColor(PhoneTheme.ember)
                    }
                }
            }
            .frame(width: 44)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !event.country.isEmpty {
                        Text(event.country)
                            .font(.system(size: 9.5, weight: .bold, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.rule.opacity(0.6))
                            .cornerRadius(2)
                    }
                    Text(event.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .serif))
                        .foregroundColor(PhoneTheme.inkPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let prev = event.previous {
                        Text("前 \(formatNumber(prev))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                    if let fc = event.forecast {
                        Text("预 \(formatNumber(fc))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                    if let act = event.actual {
                        Text("今 \(formatNumber(act))")
                            .font(.system(size: 10.5, design: .monospaced).weight(.bold))
                            .foregroundColor(PhoneTheme.cinnabar)
                    }
                }
            }

            Spacer()
        }
        .padding(10)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(event.importance >= 3 ? PhoneTheme.cinnabar.opacity(0.3) : PhoneTheme.rule, lineWidth: 1)
        )
    }

    private func formatNumber(_ val: Double) -> String {
        String(format: "%.1f", val)
    }
}

private struct EarningsReportCard: View {
    let report: EarningsReport

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Text(report.callTime.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(PhoneTheme.inkSecondary)
                Text(report.callTime == .beforeOpen ? "盘前" : (report.callTime == .afterClose ? "盘后" : "—"))
                    .font(.system(size: 8.5))
                    .foregroundColor(PhoneTheme.inkTertiary)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(report.code)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoneTheme.cinnabar)
                    Text(report.companyName)
                        .font(.system(size: 12.5, weight: .semibold, design: .serif))
                        .foregroundColor(PhoneTheme.inkPrimary)
                        .lineLimit(1)
                }

                if let eps = report.epsEstimate {
                    Text("EPS 预期: \(String(format: "%.2f", eps))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
            }

            Spacer()
        }
        .padding(10)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
    }
}

private struct EmptyDayStampView: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(PhoneTheme.cinnabar.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 88, height: 44)
                Text("本日休市")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundColor(PhoneTheme.cinnabar.opacity(0.8))
            }
            .rotationEffect(.degrees(-3))
            .padding(.top, 36)

            Text(text)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(PhoneTheme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - 2. Easter Egg Physical Tearable Calendar

private struct PhysicalCalendarView: View {
    @State private var tornPiece: FallingPage?
    private let language = AppLanguage.system

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
