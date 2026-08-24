import SwiftUI
import WickCalendarKit
import WickSync
import WickTrading

@main
struct WickPhoneApp: App {
    @StateObject private var store = PhoneJournalStore.shared
    @StateObject private var sync = PhoneSyncCoordinator.shared
    @StateObject private var exchangeCoordinator = PhoneExchangeCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("wick.appearance") private var appearanceRaw = AppAppearance.system.rawValue

    @State private var selectedTab = 0

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            PhoneThemeRoot(appearance: appearance) {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label("今日", systemImage: "flame.fill")
                        }
                        .tag(0)

                    DayListView()
                        .tabItem {
                            Label("日记", systemImage: "book.closed.fill")
                        }
                        .tag(1)

                    CalendarView()
                        .tabItem {
                            Label("黄历", systemImage: "calendar")
                        }
                        .tag(2)

                    SettingsView()
                        .tabItem {
                            Label("设置", systemImage: "gearshape.fill")
                        }
                        .tag(3)
                }
                .tint(PhoneTheme.cinnabar)
                .preferredColorScheme(appearance.colorScheme)
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(exchangeCoordinator)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                store.flushPendingWrites()
            case .active:
                sync.engine.syncNow()
                exchangeCoordinator.syncNow()
            default:
                break
            }
        }
    }
}

/// Hosts the dynamic 24h day-arc theme engine for the iOS client.
private struct PhoneThemeRoot<Content: View>: View {
    let appearance: AppAppearance
    @Environment(\.colorScheme) private var systemColorScheme
    let content: Content

    init(appearance: AppAppearance, @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.content = content()
    }

    private var effectiveScheme: ColorScheme {
        appearance.colorScheme ?? systemColorScheme
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let palette = DayArcEngine.palette(at: context.date, scheme: effectiveScheme)
            content
                .environment(\.wickPalette, palette)
        }
    }
}
