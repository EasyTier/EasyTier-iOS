import SwiftUI
import SwiftData

@main
struct EasyTierApp: App {
    @StateObject var manager = NEManager()

    var body: some Scene {
        WindowGroup {
            ContentView<NEManager>()
        }
        .modelContainer(for: [ProfileSummary.self, NetworkProfile.self])
        .environmentObject(manager)
    }
}
