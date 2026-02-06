import SwiftUI

let columnWidth: CGFloat = 450

struct ContentView<Manager: NetworkExtensionManagerProtocol>: View {
    @ObservedObject var manager: Manager
    @StateObject private var selectedSession = SelectedProfileSession()
    
    var body: some View {
        TabView {
            DashboardView(manager: manager, selectedSession: selectedSession)
                .tabItem {
                    Image(systemName: "list.bullet.below.rectangle")
                    Text("main.dashboard")
                }
            LogView()
                .tabItem {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                    Text("logging")
                }
            SettingsView(manager: manager)
                .tabItem {
                    Image(systemName: "gearshape")
                        .environment(\.symbolVariants, .none)
                    Text("settings")
                }
        }
    }
}

#if DEBUG
#Preview("Content") {
    let manager = MockNEManager()
    return ContentView(manager: manager)
}

@available(iOS 17.0, *)
#Preview("Content Landscape", traits: .landscapeLeft) {
    let manager = MockNEManager()
    ContentView(manager: manager)
}
#endif
