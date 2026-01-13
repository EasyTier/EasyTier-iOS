//
//  ControlWidgetsControl.swift
//  ControlWidgets
//
//  Created by YinMo19 on 2026/1/13.
//

import AppIntents
import SwiftUI
import WidgetKit

struct ControlWidgetsControl: ControlWidget {
    static let kind: String = "site.yinmo.easytier.ControlWidgets"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: Self.kind,
            provider: VPNControlProvider()
        ) { isConnected in
            ControlWidgetToggle(
                isOn: isConnected,
                action: ToggleVPNIntent()
            ) {
                Label("EasyTier", systemImage: "network")
            }
        }
        .displayName("EasyTier")
        .description("Toggle VPN connection")
    }
}

struct VPNControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: VPNControlConfiguration) -> Bool {
        false
    }
    
    func currentValue(configuration: VPNControlConfiguration) async throws -> Bool {
        let defaults = UserDefaults(suiteName: "group.site.yinmo.easytier")
        return defaults?.bool(forKey: "VPNIsConnected") ?? false
    }
}

struct VPNControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "VPN Control"
}