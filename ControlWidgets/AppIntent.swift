//
//  AppIntent.swift
//  ControlWidgets
//
//  Created by YinMo19 on 2026/1/13.
//

import AppIntents

// Toggle VPN connection via App Group notification
struct ToggleVPNIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle VPN"
    
    @Parameter(title: "Connected")
    var value: Bool
    
    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.site.yinmo.easytier")
        
        // Set the desired state
        defaults?.set(value, forKey: "VPNDesiredState")
        defaults?.synchronize()
        
        // Notify main app to perform the action
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("site.yinmo.easytier.toggleVPN" as CFString),
            nil,
            nil,
            true
        )
        
        return .result()
    }
}