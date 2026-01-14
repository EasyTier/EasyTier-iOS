import AppIntents
import SwiftUI
import WidgetKit
import NetworkExtension

@main
struct ControlWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ControlWidgetsControl()
    }
}

struct ControlWidgetsControl: ControlWidget {
    static let kind: String = "site.yinmo.easytier.controlwidgets"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: VPNControlProvider()
        ) { isConnected in
            ControlWidgetToggle(
                "EasyTier",
                isOn: isConnected,
                action: ToggleVPNIntent()
            ) { isOn in
                Label(isOn ? "vpn_connected" : "vpn_disconnected", systemImage: "network")
                    .controlWidgetActionHint(isOn ? "vpn_disconnect" : "vpn_connect")
            }
        }
        .displayName("EasyTier")
        .description("toggle_vpn_connection")
    }
}

extension ControlWidgetsControl {
    struct VPNControlProvider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let manager = managers.first else {
                return false
            }
            return [.connecting, .connected, .reasserting].contains(manager.connection.status)
        }
    }
}

struct ToggleVPNIntent: SetValueIntent {
    static let title: LocalizedStringResource = "toggle_vpn"

    @Parameter(title: "vpn_connected")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            return .result()
        }

        if value {
            try manager.connection.startVPNTunnel()
        } else {
            manager.connection.stopVPNTunnel()
        }

        return .result()
    }
}
