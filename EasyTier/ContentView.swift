import SwiftUI

let columnWidth: CGFloat = 450

struct ContentView<Manager: NEManagerProtocol>: View {
    @ObservedObject var manager: Manager
    
    var body: some View {
        TabView {
            DashboardView(manager: manager)
                .tabItem {
                    Image(systemName: "list.bullet.below.rectangle")
                    Text("main.dashboard")
                }
            LogView()
                .tabItem {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                    Text("logging")
                }
            SettingsView<Manager>()
                .tabItem {
                    Image(systemName: "gearshape")
                        .environment(\.symbolVariants, .none)
                    Text("settings")
                }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        ContentView(manager: manager)
        ContentView(manager: manager)
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
