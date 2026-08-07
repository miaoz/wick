import SwiftUI
import WickSync

@main
struct WickPhoneApp: App {
    @StateObject private var store = PhoneJournalStore.shared
    @StateObject private var sync = PhoneSyncCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .environmentObject(sync)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                store.flushPendingWrites()
            case .active:
                sync.engine.syncNow()
            default:
                break
            }
        }
    }
}
