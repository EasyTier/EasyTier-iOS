import SwiftUI
import SwiftData

let columnWidth: CGFloat = 450

struct ContentView<Manager: NEManagerProtocol>: View {
    var body: some View {
        TabView {
            DashboardView<Manager>()
                .tabItem {
                    Image(systemName: "list.bullet.below.rectangle")
                    Text("Dashboard")
                }
            LogView()
                .tabItem {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                    Text("Logs")
                }
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                        .environment(\.symbolVariants, .none)
                    Text("Settings")
                }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        ContentView<MockNEManager>()
            .modelContainer(
                try! ModelContainer(
                    for: Schema([ProfileSummary.self, NetworkProfile.self]),
                    configurations: ModelConfiguration(
                        isStoredInMemoryOnly: true
                    )
                )
            )
            .environmentObject(manager)
    }
}
