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

    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            PhoneThemeRoot {
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
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let palette = DayArcEngine.palette(at: context.date, scheme: colorScheme)
            content
                .environment(\.wickPalette, palette)
        }
    }
}
