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
    @AppStorage("wick.language") private var languageRaw = AppLanguage.chinese.rawValue
    @AppStorage("wick.appearance") private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage("wick.pnlColorConvention") private var pnlConventionRaw = PnlColorConvention.redUp.rawValue
    @AppStorage("wick.journal.fontName") private var journalFontName = ""

    @State private var selectedTab = 0

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .chinese
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    private var pnlConvention: PnlColorConvention {
        PnlColorConvention(rawValue: pnlConventionRaw) ?? .redUp
    }

    init() {
        PhoneFontManager.registerCustomFonts()
    }

    var body: some Scene {
        WindowGroup {
            PhoneThemeRoot(appearance: appearance, pnlConvention: pnlConvention, language: language) {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Image(systemName: "flame.fill")
                        }
                        .tag(0)

                    DayListView()
                        .tabItem {
                            Image(systemName: "book.closed.fill")
                        }
                        .tag(1)

                    CalendarView()
                        .tabItem {
                            Image(systemName: "calendar")
                        }
                        .tag(2)

                    SettingsView()
                        .tabItem {
                            Image(systemName: "gearshape.fill")
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
    let pnlConvention: PnlColorConvention
    let language: AppLanguage
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("wick.journal.fontName") private var journalFontName = ""
    let content: Content

    init(appearance: AppAppearance, pnlConvention: PnlColorConvention, language: AppLanguage, @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.pnlConvention = pnlConvention
        self.language = language
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
                .environment(\.pnlColorConvention, pnlConvention)
                .environment(\.appLanguage, language)
                .id(journalFontName)
        }
    }
}
