import SwiftUI

@main
struct BabyBuddyApp: App {
    @StateObject private var store = TrackerStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store).tint(.teal) }
    }
}
