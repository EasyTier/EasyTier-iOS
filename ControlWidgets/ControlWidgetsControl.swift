//
//  ControlWidgetsControl.swift
//  ControlWidgets
//
//  Created by YinMo19 on 2026/1/13.
//

import AppIntents
import SwiftUI
import WidgetKit
import NetworkExtension

struct ControlWidgetsControl: ControlWidget {
    static let kind: String = "site.yinmo.easytier.ControlWidgets"

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
                Label(isOn ? LocalizedStringResource("vpn_connected") : LocalizedStringResource("vpn_disconnected"), systemImage: "network")
                    .controlWidgetActionHint(isOn ? LocalizedStringResource("vpn_disconnect") : LocalizedStringResource("vpn_connect"))
            }
        }
        .displayName("EasyTier")
        .description(LocalizedStringResource("toggle_vpn_connection"))
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
            return manager.connection.status == .connected
        }
    }
}

struct ToggleVPNIntent: SetValueIntent {
    static let title: LocalizedStringResource = "toggle_vpn"

    @Parameter(title: LocalizedStringResource("vpn_connected"))
    var value: Bool

    func perform() async throws -> some IntentResult {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            return .result()
        }

        if value {
            // Connect - need to load config from App Group
            let defaults = UserDefaults(suiteName: "group.site.yinmo.easytier")
            guard let configData = defaults?.data(forKey: "LastVPNConfig"),
                  let config = try? JSONDecoder().decode([String: String].self, from: configData) else {
                // Try to start with empty options as fallback
                try manager.connection.startVPNTunnel()
                return .result()
            }
            
            // Convert to NSDictionary for VPN options
            var options: [String: NSObject] = [:]
            for (key, val) in config {
                options[key] = val as NSString
            }
            try manager.connection.startVPNTunnel(options: options)
        } else {
            manager.connection.stopVPNTunnel()
        }

        return .result()
    }
}