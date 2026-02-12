import SwiftUI

#if os(iOS)
let columnMaxWidth: CGFloat = 450
let columnMinWidth: CGFloat = 300
#else
let columnMaxWidth: CGFloat = 360
let columnMinWidth: CGFloat = 300
#endif

struct ContentView<Manager: NetworkExtensionManagerProtocol>: View {
    @ObservedObject var manager: Manager
    @StateObject private var selectedSession = SelectedProfileSession()
    
#if os(macOS)
    enum TabItem: Hashable {
        case dashboard, log, settings
    }
    @State private var selectedTab: TabItem? = .dashboard
#endif
    
    var body: some View {
#if os(macOS)
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: TabItem.dashboard) {
                    Label("main.dashboard", systemImage: "list.bullet.below.rectangle")
                }
                NavigationLink(value: TabItem.log) {
                    Label("logging", systemImage: "rectangle.and.text.magnifyingglass")
                }
                NavigationLink(value: TabItem.settings) {
                    Label("settings", systemImage: "gearshape")
                }
            }
        } detail: {
            switch selectedTab {
            case .dashboard:
                DashboardView(manager: manager, selectedSession: selectedSession)
            case .log:
                LogView()
            case .settings:
                SettingsView(manager: manager)
            case .none:
                ZStack {
#if os(iOS)
                    Color(.systemGroupedBackground)
#endif
                    Image(systemName: "network")
                        .resizable()
                        .frame(width: 128, height: 128)
                        .foregroundStyle(Color.accentColor.opacity(0.2))
                }
                .ignoresSafeArea()
            }
        }
        .navigationTitle("EasyTier")
        .frame(minWidth: 500, minHeight: 300)
#else
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
#endif
    }
}

#if DEBUG
#Preview("Content") {
    let manager = MockNEManager()
    return ContentView(manager: manager)
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Content Landscape", traits: .landscapeLeft) {
    let manager = MockNEManager()
    ContentView(manager: manager)
}
#endif
