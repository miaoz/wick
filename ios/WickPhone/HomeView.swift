import SwiftUI
import WickCalendarKit
import WickSync
import WickTrading

/// Tab 1: "今日" (Today Command & Action Center).
/// Displays daily time arc, burn progress, next macro alert radar, trading brief, and journal quick-capture.
struct HomeView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var sync: PhoneSyncCoordinator
    @StateObject private var calendarStore = MacroCalendarStore.shared
    @StateObject private var exchangeCoordinator = PhoneExchangeCoordinator.shared

    @State private var quickText = ""
    @State private var reviewingItem: JournalItem?
    @State private var showEditor = false

    private let language = AppLanguage.system

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Main Time & Candle Burn Card
                    TimeArcPaperCard(language: language)

                    // 2. Upcoming Macro Event Radar Card
                    MacroRadarAlertCard(calendarStore: calendarStore)

                    // 3. Today's Trading & Ledger Brief
                    TodayTradingBriefCard(
                        store: store,
                        exchangeCoordinator: exchangeCoordinator
                    ) {
                        showEditor = true
                    }

                    // 4. Today's Journal Feed & Quick Capture
                    TodayJournalFeedCard(
                        store: store,
                        quickText: $quickText,
                        onAddNote: addQuickNote,
                        onReviewTap: { item in
                            reviewingItem = item
                        }
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .background(PhoneTheme.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showEditor) {
                let entry = store.openOrCreateToday()
                EditorView(entry: entry)
            }
            .sheet(item: $reviewingItem) { item in
                ReviewSheet(item: item) { review in
                    applyReview(review, for: item)
                }
            }
            .onAppear {
                calendarStore.loadIfNeeded(for: Date())
            }
        }
    }

    private func addQuickNote() {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var today = store.openOrCreateToday()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timePrefix = formatter.string(from: Date())

        let newItem = JournalItem(
            id: UUID(),
            tag: "速记",
            body: "\(timePrefix) \(trimmed)"
        )
        today.items.insert(newItem, at: 0)
        store.updateEntry(today)
        quickText = ""

        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    private func applyReview(_ review: JournalReview?, for item: JournalItem) {
        var today = store.openOrCreateToday()
        if let idx = today.items.firstIndex(where: { $0.id == item.id }) {
            today.items[idx].review = review
            store.updateEntry(today)
        }
    }
}

// MARK: - 1. Time Arc Paper Card

private struct TimeArcPaperCard: View {
    let language: AppLanguage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = context.date
            let all = TimeProgressCalculator.allProgress(at: date, language: language)
            let dayProgress = all.first

            VStack(alignment: .leading, spacing: 14) {
                // Header row: big date + lunar + candle badge
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.dateDisplay(for: date))
                            .font(.system(size: 32, weight: .black, design: .serif))
                            .foregroundColor(PhoneTheme.inkPrimary)

                        if let lunar = LunarLine.string(for: date) {
                            Text("\(Self.weekdayDisplay(for: date)) · \(lunar)")
                                .font(.system(size: 11.5, design: .serif))
                                .foregroundColor(PhoneTheme.inkSecondary)
                        }
                    }

                    Spacer()

                    // Candle flame icon badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(PhoneTheme.char)
                            .shadow(color: PhoneTheme.ember.opacity(0.3), radius: 6, x: 0, y: 2)

                        Image(systemName: "flame.fill")
                            .font(.system(size: 18))
                            .foregroundColor(PhoneTheme.emberHi)
                    }
                    .frame(width: 38, height: 38)
                }

                // Day Burn Strip with big percentage
                if let dayProgress {
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("今日剩余")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(PhoneTheme.inkSecondary)
                            Spacer()
                            Text(dayProgress.percentageText)
                                .font(.system(size: 28, weight: .black, design: .serif))
                                .foregroundColor(PhoneTheme.inkPrimary)
                        }

                        BurnStripView(
                            elapsed: 1.0 - dayProgress.fractionRemaining,
                            ticks: 24,
                            showsFlame: true
                        )
                        .frame(height: 22)
                    }
                }

                // Sub strips: Week / Month / Year
                VStack(spacing: 8) {
                    ForEach(Array(all.dropFirst())) { item in
                        HStack(spacing: 10) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(PhoneTheme.inkSecondary)
                                .frame(width: 32, alignment: .leading)

                            BurnStripView(
                                elapsed: 1.0 - item.fractionRemaining,
                                ticks: item.title.contains("周") ? 7 : (item.title.contains("月") ? 31 : 12),
                                showsFlame: false
                            )
                            .frame(height: 8)

                            Text(item.remainingText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(PhoneTheme.inkTertiary)
                                .frame(width: 72, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(18)
            .background(PhoneTheme.paperHi)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        }
    }

    private static func dateDisplay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private static func weekdayDisplay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

// MARK: - 2. Macro Radar Alert Card

private struct MacroRadarAlertCard: View {
    @ObservedObject var calendarStore: MacroCalendarStore

    var body: some View {
        let todayEvents = calendarStore.events(for: Date())
        let nextEvent = todayEvents.first { $0.time >= Date() } ?? todayEvents.first

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(PhoneTheme.cinnabar)
                        .frame(width: 6, height: 6)
                        .shadow(color: PhoneTheme.cinnabar, radius: 3)
                    Text("下个关键宏观发布")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(PhoneTheme.cinnabar)
                }

                Spacer()

                if let nextEvent {
                    Text(Self.countdownText(to: nextEvent.time))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoneTheme.inkSecondary)
                }
            }

            if let nextEvent {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(MacroCalendarFormat.eventTime(nextEvent.time)) \(nextEvent.country) · \(nextEvent.title)")
                        .font(.system(size: 12.5, weight: .bold, design: .serif))
                        .foregroundColor(PhoneTheme.inkPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let prev = nextEvent.previous {
                        Text("前值: \(String(format: "%.1f", prev))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                    if let fc = nextEvent.forecast {
                        Text("预期: \(String(format: "%.1f", fc))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkSecondary)
                    }
                }
            } else {
                Text("今日暂无待公布的高星宏观数据")
                    .font(.system(size: 12, design: .serif))
                    .foregroundColor(PhoneTheme.inkTertiary)
            }
        }
        .padding(12)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
    }

    private static func countdownText(to date: Date) -> String {
        let diff = Int(date.timeIntervalSinceNow)
        if diff <= 0 { return "刚刚已发布" }
        let mins = diff / 60
        let hours = mins / 60
        if hours > 0 {
            return "倒计时 \(hours)小时\(mins % 60)分"
        } else {
            return "倒计时 \(mins)分钟"
        }
    }
}

// MARK: - 3. Today's Trading Brief Card

private struct TodayTradingBriefCard: View {
    @ObservedObject var store: PhoneJournalStore
    @ObservedObject var exchangeCoordinator: PhoneExchangeCoordinator
    let onOpenEditor: () -> Void

    var body: some View {
        Button(action: onOpenEditor) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("今日日记与实盘记录")
                        .font(.system(size: 12.5, weight: .bold, design: .serif))
                        .foregroundColor(PhoneTheme.inkPrimary)

                    Spacer()

                    if let pnl = exchangeCoordinator.pnl(for: Date()) {
                        let isGain = pnl >= 0
                        Text("\(isGain ? "+" : "")\(String(format: "%.2f", pnl)) USDT")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(PhoneTheme.pnlColor(isGain: isGain))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }
                }

                let todayEntry = store.entries.first { Calendar.current.isDateInToday($0.date) }
                let itemCount = todayEntry?.items.count ?? 0
                let unreviewedCount = todayEntry?.items.filter { $0.review == nil }.count ?? 0
                let closedCount = exchangeCoordinator.closedCount(for: JournalDayKey.make(from: Date()))

                HStack(spacing: 12) {
                    Text("今日记录 \(itemCount) 条")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PhoneTheme.inkSecondary)

                    if closedCount > 0 {
                        Text("\(closedCount) 笔平仓")
                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkPrimary)
                    }

                    if unreviewedCount > 0 {
                        Text("\(unreviewedCount) 条待复盘")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(PhoneTheme.cinnabar)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.cinnabarSoft)
                            .cornerRadius(3)
                    }
                }
            }
            .padding(12)
            .background(PhoneTheme.paperHi)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Today's Journal Feed & Quick Capture

private struct TodayJournalFeedCard: View {
    @ObservedObject var store: PhoneJournalStore
    @Binding var quickText: String
    let onAddNote: () -> Void
    let onReviewTap: (JournalItem) -> Void

    var body: some View {
        let todayEntry = store.entries.first { Calendar.current.isDateInToday($0.date) }
        let items = todayEntry?.items ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日记录流水")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundColor(PhoneTheme.inkPrimary)
                Spacer()
            }

            if items.isEmpty {
                Text("今天还没有记录，在下方快速写下一笔吧…")
                    .font(.system(size: 11.5, design: .serif))
                    .foregroundColor(PhoneTheme.inkTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.prefix(3))) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(item.tag.isEmpty ? "笔记" : item.tag)
                                .font(.system(size: 9.5, weight: .bold, design: .serif))
                                .foregroundColor(PhoneTheme.cinnabar)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PhoneTheme.cinnabarSoft)
                                .cornerRadius(2)

                            Text(item.body.isEmpty ? "（空）" : item.body)
                                .font(.system(size: 12, design: .serif))
                                .foregroundColor(PhoneTheme.inkPrimary)
                                .lineLimit(2)

                            Spacer()

                            if let review = item.review {
                                JournalReviewBadge(verdict: review.verdict, style: .mini, size: 20)
                            } else {
                                Button {
                                    onReviewTap(item)
                                } label: {
                                    Text("复盘")
                                        .font(.system(size: 9.5, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(PhoneTheme.paper)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(PhoneTheme.cinnabar.opacity(0.5), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Quick capture input bar
            HStack(spacing: 8) {
                TextField("写下此刻的交易想法或盘感…", text: $quickText)
                    .font(.system(size: 12, design: .serif))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PhoneTheme.paper)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
                    .onSubmit(onAddNote)

                Button(action: onAddNote) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.95, blue: 0.90))
                        .frame(width: 30, height: 30)
                        .background(PhoneTheme.ember)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .disabled(quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
    }
}
