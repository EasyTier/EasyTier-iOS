import NetworkExtension
import AppIntents
import SwiftUI
import WidgetKit

import EasyTierShared

struct VPNStatusEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let profileName: String
    let ipAddress: String?
    
    init(date: Date, isConnected: Bool, profileName: String, ipAddress: String? = nil) {
        self.date = date
        self.isConnected = isConnected
        self.profileName = profileName
        self.ipAddress = ipAddress
    }
}

struct VPNStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> VPNStatusEntry {
        VPNStatusEntry(date: Date(), isConnected: false, profileName: "")
    }

    func getSnapshot(in context: Context, completion: @Sendable @escaping (VPNStatusEntry) -> Void) {
        Task {
            let isConnected = await fetchConnectionStatus()
            let profileName = fetchProfileName()
            completion(VPNStatusEntry(date: Date(), isConnected: isConnected, profileName: profileName, ipAddress: getIPv4Address()))
        }
    }

    func getTimeline(in context: Context, completion: @Sendable @escaping (Timeline<VPNStatusEntry>) -> Void) {
        Task {
            let isConnected = await fetchConnectionStatus()
            let profileName = fetchProfileName()
            let entry = VPNStatusEntry(date: Date(), isConnected: isConnected, profileName: profileName, ipAddress: getIPv4Address())
            let nextRefresh = Date().addingTimeInterval(300)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
    
    func getOptions() -> EasyTierOptions? {
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        guard let configData = defaults?.data(forKey: "VPNConfig"),
              let options = try? JSONDecoder().decode(EasyTierOptions.self, from: configData) else {
            return nil
        }
        return options
    }
    
    func getIPv4Address() -> String? {
        return getOptions()?.ipv4?.description
    }

    private func fetchConnectionStatus() async -> Bool {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let manager = managers.first else {
                return false
            }
            return [.connecting, .connected, .reasserting].contains(manager.connection.status)
        } catch {
            return false
        }
    }

    private func fetchProfileName() -> String {
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        return defaults?.string(forKey: "selectedProfileName") ?? ""
    }
}

struct VPNStatusWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: VPNStatusProvider.Entry
    
    var badgeColor: Color {
        if entry.isConnected {
            .green
        } else {
            .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(badgeColor)
                        .frame(width: 8, height: 8)
                    Text(entry.isConnected ? "vpn_connected" : "vpn_disconnected")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(badgeColor)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(badgeColor.opacity(0.1))
                .clipShape(Capsule())
                .fixedSize()
                Spacer()
                Text("EasyTier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(entry.profileName.isEmpty ? "select_network" : LocalizedStringKey(entry.profileName))
                .font(family == .systemSmall ? .title2.bold() : .title.bold())

            if entry.isConnected {
                Text(entry.ipAddress ?? "DHCP")
                    .font(family == .systemSmall ? .subheadline : .callout)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .overlay(alignment: .bottomTrailing) {
            Group {
                let text: LocalizedStringKey = entry.isConnected ? "vpn_disconnect" : "vpn_connect"
                if #available(iOS 17.0, macOS 14.0, *) {
                    Button(text, intent: ToggleVPNConnectionIntent())
                } else {
                    Button(text) {
                        Task {
                            _ = try? await ToggleVPNConnectionIntent().perform()
                        }
                    }
                }
            }
            .padding(0)
            .tint(entry.isConnected ? Color.red : Color.accentColor)
            .buttonStyle(.borderedProminent)
            .widgetAccentable()
        }
        .widgetBackgroundStyle()
    }
}

struct EasyTierStatusWidget: Widget {
    static let kind: String = "\(APP_BUNDLE_ID).widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VPNStatusProvider()) { entry in
            VPNStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("EasyTier")
        .description("widget_desc")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ToggleVPNConnectionIntent: AppIntent {
    static let title: LocalizedStringResource = "toggle_vpn"

    func perform() async throws -> some IntentResult {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            return .result()
        }

        let isConnected = [.connecting, .connected, .reasserting].contains(manager.connection.status)
        if isConnected {
            manager.connection.stopVPNTunnel()
        } else {
            connectWithManager(manager)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "\(APP_BUNDLE_ID).widget")
        return .result()
    }
}

extension View {
    @ViewBuilder
    func widgetBackgroundStyle() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.containerBackground(.fill.tertiary, for: .widget)
        } else {
            self
        }
    }
}

#if DEBUG
@available(iOS 17.0, macOS 14.0, *)
#Preview(
    "Connected",
    as: .systemSmall,
    widget: {
        EasyTierStatusWidget()
    },
    timeline: {
        VPNStatusEntry(date: Date(), isConnected: true, profileName: "Example")
    }
)

@available(iOS 17.0, macOS 14.0, *)
#Preview(
    "Connected Medium",
    as: .systemMedium,
    widget: {
        EasyTierStatusWidget()
    },
    timeline: {
        VPNStatusEntry(date: Date(), isConnected: true, profileName: "Example")
    }
)

@available(iOS 17.0, macOS 14.0, *)
#Preview(
    "Disconnected",
    as: .systemSmall,
    widget: {
        EasyTierStatusWidget()
    },
    timeline: {
        VPNStatusEntry(date: Date(), isConnected: false, profileName: "Test")
    }
)
#endif
