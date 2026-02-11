import EasyTierShared
import SwiftUI

@main
struct EasyTierApp: App {
    #if targetEnvironment(simulator)
        @StateObject var manager = MockNEManager()
    #else
        @StateObject var manager = NetworkExtensionManager()
    #endif

    init() {
        let values: [String: Any] = [
            "logLevel": LogLevel.info.rawValue,
            "statusRefreshInterval": 1.0,
            "logPreservedLines": 1000,
            "useRealDeviceNameAsDefault": true,
            "plainTextIPInput": false,
            "profilesUseICloud": false,
        ]
        let sharedValues: [String: Any] = [
            "includeAllNetworks": false,
            "excludeLocalNetworks": true,
            "excludeCellularServices": true,
            "excludeAPNs": true,
            "excludeDeviceCommunication": true,
            "enforceRoutes": false,
        ]
        UserDefaults.standard.register(defaults: values)
        UserDefaults(suiteName: APP_GROUP_ID)?.register(defaults: sharedValues)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
        }
    }
}
