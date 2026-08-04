import EasyTierShared
import SwiftUI

#if os(macOS)
import AppKit

@MainActor
private final class EasyTierAppDelegate: NSObject, NSApplicationDelegate {
    var terminationHandler: (() async -> Void)?

    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        sender.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationHandler else {
            return .terminateNow
        }
        guard terminationTask == nil else {
            return .terminateLater
        }

        terminationTask = Task { @MainActor in
            await terminationHandler()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif

@main
struct EasyTierApp: App {
    #if targetEnvironment(simulator)
        @StateObject private var manager = MockNEManager()
    #else
        @StateObject private var manager = NetworkExtensionManager()
    #endif

    #if os(macOS)
        @NSApplicationDelegateAdaptor private var appDelegate: EasyTierAppDelegate
        @State private var isMenuBarInserted = true
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
#if os(macOS)
        Window("EasyTier", id: "main") {
            ContentView(manager: manager)
                .onAppear {
                    configureTerminationHandler()
                }
        }

        MenuBarExtra(
            "EasyTier",
            image: "MenuBarIcon",
            isInserted: $isMenuBarInserted
        ) {
            MenuBarView(manager: manager)
                .onAppear {
                    configureTerminationHandler()
                }
        }
        .menuBarExtraStyle(.window)
#else
        WindowGroup {
            ContentView(manager: manager)
        }
#endif
    }

    #if os(macOS)
        private func configureTerminationHandler() {
            appDelegate.terminationHandler = {
                await manager.disconnect()
            }
        }
    #endif
}
