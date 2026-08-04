#if os(macOS)
import AppKit
import EasyTierShared
import NetworkExtension
import SwiftUI

struct MenuBarView<Manager: NetworkExtensionManagerProtocol>: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var manager: Manager
    @AppStorage(
        "selectedProfileName",
        store: UserDefaults(suiteName: APP_GROUP_ID)
    ) private var selectedProfileName: String?

    @State private var isPerformingAction = false
    @State private var errorMessage: String?
    @State private var status: NetworkStatus?

    private var isConnected: Bool {
        [.connected, .disconnecting, .reasserting].contains(manager.status)
    }

    private var isPending: Bool {
        isPerformingAction || [.connecting, .disconnecting, .reasserting].contains(manager.status)
    }

    private var statusColor: Color {
        switch manager.status {
        case .connected:
            return .green
        case .connecting, .reasserting, .disconnecting:
            return .orange
        case .invalid, .disconnected:
            return .secondary
        @unknown default:
            return .secondary
        }
    }

    private var statusText: String {
        if manager.isLoading {
            return String(localized: "menubar.status.loading")
        }

        switch manager.status {
        case .invalid:
            return String(localized: "menubar.status.not_configured")
        case .disconnected:
            return String(localized: "menubar.status.disconnected")
        case .connecting:
            return String(localized: "menubar.status.connecting")
        case .connected:
            return String(localized: "menubar.status.connected")
        case .reasserting:
            return String(localized: "menubar.status.reconnecting")
        case .disconnecting:
            return String(localized: "menubar.status.disconnecting")
        @unknown default:
            return String(localized: "menubar.status.unknown")
        }
    }

    private var networkName: String {
        selectedProfileName ?? "EasyTier"
    }

    private var virtualIPv4: String {
        status?.myNodeInfo?.virtualIPv4?.description ?? String(localized: "not_available")
    }

    private var peerCount: String {
        String(status?.peerRoutePairs.count ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusPanel

            if let message = errorMessage ?? status?.errorMsg {
                Divider()
                errorPanel(message)
            }

            Divider()
            actionPanel
        }
        .frame(width: 340)
        .task {
            if manager.isLoading {
                try? await manager.load()
            }
            await refreshStatusLoop()
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(networkName)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if isConnected {
                HStack(spacing: 24) {
                    TrafficItem(
                        trafficType: .Rx,
                        value: status?.sum(of: \.rxBytes)
                    )
                    TrafficItem(
                        trafficType: .Tx,
                        value: status?.sum(of: \.txBytes)
                    )
                }

                HStack(spacing: 12) {
                    compactStat(
                        title: String(localized: "virtual_ipv4"),
                        value: virtualIPv4,
                        systemImage: "network"
                    )
                    compactStat(
                        title: String(localized: "peer_info"),
                        value: peerCount,
                        systemImage: "person.2"
                    )
                }
            }
        }
        .padding(16)
    }

    private var actionPanel: some View {
        HStack(spacing: 8) {
            Button {
                toggleConnection()
            } label: {
                Label(
                    isConnected ? "vpn_disconnect" : "vpn_connect",
                    systemImage: isConnected ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isConnected ? .red : .accentColor)
            .disabled(manager.isLoading || isPending)

            Button {
                openMainWindow()
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.bordered)
            .help(String(localized: "menubar.open"))
            .keyboardShortcut("o")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.bordered)
            .help(String(localized: "menubar.quit"))
            .keyboardShortcut("q")
        }
        .padding(12)
    }

    private func compactStat(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorPanel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }

    private func toggleConnection() {
        guard !isPending else { return }
        isPerformingAction = true
        errorMessage = nil

        Task { @MainActor in
            if isConnected {
                await manager.disconnect()
            } else {
                do {
                    try await manager.connect()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            isPerformingAction = false
        }
    }

    private func openMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func refreshStatus() {
        guard isConnected else {
            status = nil
            return
        }

        manager.fetchRunningInfo { info in
            DispatchQueue.main.async {
                status = info
            }
        }
    }

    private func refreshStatusLoop() async {
        while !Task.isCancelled {
            refreshStatus()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
#endif
