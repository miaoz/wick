import SwiftUI
import WickSync

/// Home: the phone counterpart of the macOS menu-bar panel — day/week/month/
/// year remaining progress, refreshing every second. The per-second tick is
/// isolated into the two small `TimelineView` subviews so it never rebuilds the
/// navigation stack, toolbar, sheets, or calendar cover (PF-03).
struct HomeView: View {
    @EnvironmentObject private var store: PhoneJournalStore
    @EnvironmentObject private var sync: PhoneSyncCoordinator

    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showCalendar = false

    private let language = AppLanguage.system

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    TimeHeaderView(language: language)
                }

                Section {
                    ProgressSection(language: language)
                }

                Section {
                    NavigationLink {
                        DayListView(path: $path)
                    } label: {
                        Label("日记", systemImage: "book.closed")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }

                    Button {
                        showCalendar = true
                    } label: {
                        Label("交易日历", systemImage: "calendar")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Wick")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: String.self) { dayKey in
                if let entry = store.entries.first(where: { $0.dayKey == dayKey }) {
                    EditorView(entry: entry)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showCalendar) {
                CalendarView()
            }
            #if DEBUG
            .onAppear {
                // Simulator/UI verification hook: launch with
                // `-wick-open-calendar` to land straight in the calendar.
                if ProcessInfo.processInfo.arguments.contains("-wick-open-calendar") {
                    showCalendar = true
                }
            }
            #endif
        }
    }
}

/// Time-dependent header (phase text, date, clock) — the only part that needs
/// a per-second tick besides the progress bars.
private struct TimeHeaderView: View {
    let language: AppLanguage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 14) {
                Image("CandleIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.phaseText(at: context.date, language: language))
                        .font(.headline)
                    Text(Self.dateText(context.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.date, style: .time)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private static func phaseText(at date: Date, language: AppLanguage) -> String {
        let hour = Double(Calendar.current.component(.hour, from: date))
            + Double(Calendar.current.component(.minute, from: date)) / 60
        switch hour {
        case 6.5..<12:
            return "🌅 " + L10n.string(.phaseDawn, language: language)
        case 12..<18:
            return "☀️ " + L10n.string(.phaseDay, language: language)
        case 18..<22.5:
            return "🌇 " + L10n.string(.phaseDusk, language: language)
        default:
            return "🌙 " + L10n.string(.phaseNight, language: language)
        }
    }

    /// Cached formatter — a fresh DateFormatter per tick is wasteful (PF-03).
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

/// The four remaining-progress bars, ticked every second in isolation.
private struct ProgressSection: View {
    let language: AppLanguage

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ForEach(
                TimeProgressCalculator.allProgress(at: context.date, language: language)
            ) { progress in
                ProgressRow(progress: progress)
            }
        }
    }
}

private struct ProgressRow: View {
    let progress: TimeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.title)
                    .font(.headline)
                Text(progress.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progress.percentageText)
                    .font(.headline.monospacedDigit())
            }
            ProgressView(value: progress.fractionRemaining)
                .tint(.orange)
            HStack {
                Text(progress.remainingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progress.endText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
