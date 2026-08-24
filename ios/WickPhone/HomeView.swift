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

    @Environment(\.appLanguage) private var language: AppLanguage

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // 1. Main Time & Candle Burn Card
                    TimeArcPaperCard(language: language)

                    // 2. 即将发布事件
                    UpcomingEventsCard(
                        calendarStore: calendarStore,
                        language: language
                    )

                    // 3. 今日交易
                    TodayTradingCard(
                        store: store,
                        exchangeCoordinator: exchangeCoordinator,
                        language: language
                    ) {
                        showEditor = true
                    }

                    // 4. 今日记录
                    TodayJournalCard(
                        store: store,
                        language: language,
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

        let defaultTag = language == .chinese ? "速记" : "Quick"
        let newItem = JournalItem(
            id: UUID(),
            tag: defaultTag,
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

            ZStack(alignment: .topTrailing) {
                // Top-Right Ambient Candle Glow from macOS
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                PhoneTheme.emberHi.opacity(0.28),
                                PhoneTheme.ember.opacity(0.10),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 140
                        )
                    )
                    .frame(width: 180, height: 180)
                    .offset(x: 45, y: -45)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 14) {
                    // Header row: big date + lunar + vertical cinnabar slip
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.dateDisplay(for: date, language: language))
                                .font(.system(size: 30, weight: .black, design: .serif))
                                .foregroundColor(PhoneTheme.inkPrimary)

                            if let lunar = LunarLine.string(for: date) {
                                Text("\(Self.weekdayDisplay(for: date, language: language)) · \(lunar)")
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundColor(PhoneTheme.inkSecondary)
                            }
                        }

                        Spacer()

                        // 朱砂引首 · 竖排签条
                        VStack(spacing: 2) {
                            if language == .chinese {
                                Text("秉")
                                Text("烛")
                            } else {
                                Text("W")
                                Text("I")
                                Text("C")
                                Text("K")
                            }
                        }
                        .font(.system(size: language == .chinese ? 11.5 : 8.5, weight: .bold, design: language == .chinese ? .serif : .monospaced))
                        .foregroundColor(PhoneTheme.cinnabar)
                        .padding(.horizontal, language == .chinese ? 6 : 5)
                        .padding(.vertical, 5)
                        .background(PhoneTheme.cinnabarSoft)
                        .cornerRadius(2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(PhoneTheme.cinnabar.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: PhoneTheme.ember.opacity(0.18), radius: 6, x: 0, y: 1)
                    }

                    // Day Burn Strip with metric headline
                    if let dayProgress {
                        VStack(spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(L10n.string(.panelHeroToday, language: language))
                                    .font(.system(size: 11, weight: .bold, design: .serif))
                                    .foregroundColor(PhoneTheme.inkSecondary)
                                    .tracking(0.5)

                                Spacer()

                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(dayProgress.percentageText)
                                        .font(.system(size: 24, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkPrimary)

                                    Text(dayProgress.remainingText)
                                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(PhoneTheme.cinnabar)
                                }
                            }

                            BurnStripView(
                                elapsed: 1.0 - dayProgress.fractionRemaining,
                                ticks: 24,
                                showsFlame: true
                            )
                            .frame(height: 18)
                        }
                    }

                    // Sub chips: Week / Month / Year
                    HStack(spacing: 8) {
                        ForEach(Array(all.dropFirst())) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.subtitle)
                                        .font(.system(size: 10, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkSecondary)
                                    Spacer()
                                    Text(item.percentageText)
                                        .font(.system(size: 10.5, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.inkPrimary)
                                }

                                BurnStripView(
                                    elapsed: 1.0 - item.fractionRemaining,
                                    ticks: item.id == "weekOfYear" ? 7 : (item.id == "month" ? 31 : 12),
                                    showsFlame: false
                                )
                                .frame(height: 4)

                                Text(item.remainingText)
                                    .font(.system(size: 9, design: .serif))
                                    .foregroundColor(PhoneTheme.inkTertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PhoneTheme.paper)
                            .cornerRadius(3)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(PhoneTheme.rule, lineWidth: 1))
                        }
                    }
                }
                .padding(18)
            }
            .background(PhoneTheme.paperHi)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
            .clipped()
        }
    }

    private static func dateDisplay(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = language == .chinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    private static func weekdayDisplay(for date: Date, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - 2. Upcoming Events Card (即将发布事件)

private struct UpcomingEventsCard: View {
    @ObservedObject var calendarStore: MacroCalendarStore
    let language: AppLanguage

    var body: some View {
        let todayEvents = calendarStore.events(for: Date())
        let upcoming = todayEvents.filter { $0.time >= Date() }
        let displayEvents = upcoming.isEmpty ? Array(todayEvents.suffix(3)) : Array(upcoming.prefix(3))
        let nextEvent = upcoming.first

        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(PhoneTheme.cinnabar)
                        .frame(width: 6, height: 6)
                        .shadow(color: PhoneTheme.cinnabar, radius: 3)
                    Text(L10n.string(.upcomingEventsTitle, language: language))
                        .font(.system(size: 12.5, weight: .bold, design: .serif))
                        .foregroundColor(PhoneTheme.inkPrimary)
                }

                Spacer()

                if let nextEvent {
                    Text(Self.countdownText(to: nextEvent.time, language: language))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(PhoneTheme.cinnabar)
                } else if !todayEvents.isEmpty {
                    Text(L10n.string(.allEventsPublished, language: language))
                        .font(.system(size: 10.5, design: .serif))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
            }

            if displayEvents.isEmpty {
                Text(L10n.string(.noUpcomingEvents, language: language))
                    .font(.system(size: 11.5, design: .serif))
                    .foregroundColor(PhoneTheme.inkTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(displayEvents.enumerated()), id: \.element.id) { index, event in
                        if index > 0 {
                            Rectangle()
                                .fill(PhoneTheme.rule)
                                .frame(height: 0.5)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(MacroCalendarFormat.eventTime(event.time))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(PhoneTheme.cinnabar)

                                Text("\(event.country) · \(event.title)")
                                    .font(.system(size: 12, weight: .medium, design: .serif))
                                    .foregroundColor(PhoneTheme.inkPrimary)
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                if event.importance > 0 {
                                    HStack(spacing: 1) {
                                        ForEach(0..<min(event.importance, 3), id: \.self) { _ in
                                            Text("★")
                                                .font(.system(size: 8))
                                                .foregroundColor(PhoneTheme.cinnabar)
                                        }
                                    }
                                }
                            }

                            if event.previous != nil || event.forecast != nil {
                                HStack(spacing: 10) {
                                    if let prev = event.previous {
                                        Text("\(L10n.string(.macroPrevious, language: language)): \(String(format: "%.1f", prev))")
                                    }
                                    if let fc = event.forecast {
                                        Text("\(L10n.string(.macroForecast, language: language)): \(String(format: "%.1f", fc))")
                                            .foregroundColor(PhoneTheme.inkSecondary)
                                    }
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(PhoneTheme.inkTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(PhoneTheme.paperHi)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
    }

    private static func countdownText(to date: Date, language: AppLanguage) -> String {
        let diff = Int(date.timeIntervalSinceNow)
        if diff <= 0 {
            return language == .chinese ? "刚刚已发布" : "Just published"
        }
        let mins = diff / 60
        let hours = mins / 60
        if hours > 0 {
            return language == .chinese ? "倒计时 \(hours)小时\(mins % 60)分" : "in \(hours)h \(mins % 60)m"
        } else {
            return language == .chinese ? "倒计时 \(mins)分钟" : "in \(mins)m"
        }
    }
}

// MARK: - 3. Today's Trading Card (今日交易)

private struct TodayTradingCard: View {
    @ObservedObject var store: PhoneJournalStore
    @ObservedObject var exchangeCoordinator: PhoneExchangeCoordinator
    let language: AppLanguage
    let onOpenEditor: () -> Void

    var body: some View {
        Button(action: onOpenEditor) {
            VStack(alignment: .leading, spacing: 10) {
                // Header: "今日交易" + Realized PnL
                HStack {
                    Text(L10n.string(.todayTradingTitle, language: language))
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

                let closedCount = exchangeCoordinator.closedCount(for: JournalDayKey.make(from: Date()))
                let journalID = PhoneJournalStore.shared.activeJournalID
                let venueName = journalID.flatMap { exchangeCoordinator.binding(for: $0)?.venue }.map { Self.venueTitle($0) }

                HStack(spacing: 10) {
                    if closedCount > 0 {
                        Text(String(format: language == .chinese ? "%d 笔平仓" : "%d closed", closedCount))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(PhoneTheme.inkPrimary)
                    } else {
                        Text(L10n.string(.noClosedTrades, language: language))
                            .font(.system(size: 11, design: .serif))
                            .foregroundColor(PhoneTheme.inkTertiary)
                    }

                    if let venueName {
                        Text(venueName)
                            .font(.system(size: 9.5, weight: .medium, design: .serif))
                            .foregroundColor(PhoneTheme.inkSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.paper)
                            .cornerRadius(2)
                    }

                    Spacer()

                    Text(L10n.string(.viewTradingDetails, language: language))
                        .font(.system(size: 11, design: .serif))
                        .foregroundColor(PhoneTheme.inkTertiary)
                }
            }
            .padding(14)
            .background(PhoneTheme.paperHi)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(PhoneTheme.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private static func venueTitle(_ venue: ExchangeVenue) -> String {
        switch venue {
        case .hyperliquid: return "Hyperliquid"
        case .binance: return "Binance USDⓈ-M"
        case .okx: return "OKX SWAP"
        }
    }
}

// MARK: - 4. Today's Journal Card (今日记录)

private struct TodayJournalCard: View {
    @ObservedObject var store: PhoneJournalStore
    let language: AppLanguage
    @Binding var quickText: String
    let onAddNote: () -> Void
    let onReviewTap: (JournalItem) -> Void

    var body: some View {
        let todayEntry = store.entries.first { Calendar.current.isDateInToday($0.date) }
        let items = todayEntry?.items ?? []
        let unreviewedCount = items.filter { $0.review == nil }.count

        VStack(alignment: .leading, spacing: 10) {
            // Header: "今日记录" + counts
            HStack {
                Text(L10n.string(.todayRecordsTitle, language: language))
                    .font(.system(size: 12.5, weight: .bold, design: .serif))
                    .foregroundColor(PhoneTheme.inkPrimary)

                Spacer()

                HStack(spacing: 6) {
                    Text(String(format: L10n.string(.recordsCountFormat, language: language), items.count))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(PhoneTheme.inkSecondary)

                    if unreviewedCount > 0 {
                        Text(String(format: L10n.string(.unreviewedCountBadgeFormat, language: language), unreviewedCount))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(PhoneTheme.cinnabar)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(PhoneTheme.cinnabarSoft)
                            .cornerRadius(3)
                    }
                }
            }

            if items.isEmpty {
                Text(L10n.string(.emptyTodayJournalHint, language: language))
                    .font(.system(size: 11.5, design: .serif))
                    .foregroundColor(PhoneTheme.inkTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(items.prefix(3))) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(item.tag.isEmpty ? (language == .chinese ? "笔记" : "Note") : item.tag)
                                .font(.system(size: 9.5, weight: .bold, design: .serif))
                                .foregroundColor(PhoneTheme.cinnabar)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(PhoneTheme.cinnabarSoft)
                                .cornerRadius(2)

                            Text(item.body.isEmpty ? (language == .chinese ? "（空）" : "(Empty)") : item.body)
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
                                    Text(L10n.string(.journalReview, language: language))
                                        .font(.system(size: 10, weight: .bold, design: .serif))
                                        .foregroundColor(PhoneTheme.cinnabar.opacity(0.85))
                                        .rotationEffect(.degrees(-3))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Quick capture input bar
            HStack(spacing: 8) {
                TextField(L10n.string(.quickNotePlaceholder, language: language), text: $quickText)
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
