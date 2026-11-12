import SwiftUI

@main
struct BabyBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TrackerStore.shared
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).tint(.teal)
                .onChange(of: scenePhase) { _, phase in if phase == .active { store.reload() } }
        }
    }
}
