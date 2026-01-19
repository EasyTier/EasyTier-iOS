import EasyTierShared
import SwiftUI

@main
struct EasyTierApp: App {
    #if targetEnvironment(simulator)
        @StateObject var manager = MockNEManager()
    #else
        @StateObject var manager = NEManager()
    #endif

    init() {
        let values: [String: Any] = [
            "logLevel": LogLevel.info.rawValue,
            "statusRefreshInterval": 1.0,
            "useRealDeviceNameAsDefault": true,
            "includeAllNetworks": false,
            "excludeLocalNetworks": false,
            "excludeCellularServices": true,
            "excludeAPNs": true,
            "excludeDeviceCommunication": true,
            "enforceRoutes": false,
        ]
        UserDefaults(suiteName: APP_GROUP_ID)?.register(defaults: values)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
    }
}
