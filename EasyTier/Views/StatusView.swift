import Combine
import Foundation
import SwiftUI

import EasyTierShared

struct StatusView<Manager: NetworkExtensionManagerProtocol>: View {
    @ObservedObject var manager: Manager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) var sizeClass
    @AppStorage("statusRefreshInterval") private var statusRefreshInterval: Double = 1.0
    @State var timerSubscription: AnyCancellable?
    @State var status: NetworkStatus?
    
    @State var selectedInfoKind: InfoKind = .peerInfo
    @State var selectedPeerRoute: SelectedPeerRoute?
    @State var showNodeInfo = false
    @State var showStunInfo = false
    @State var showNetworkSettings = false
    @State var lastNetworkSettings: TunnelNetworkSettingsSnapshot?
    
    let networkName: String
    
    init(_ name: String, manager: Manager) {
        networkName = name
        _manager = ObservedObject(wrappedValue: manager)
    }
    
    enum InfoKind: Identifiable, CaseIterable {
        var id: Self { self }
        case peerInfo
        case eventLog
        
        var description: LocalizedStringKey {
            switch self {
            case .peerInfo: "peer_info"
            case .eventLog: "event_log"
            }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                doubleComlum
            } else {
                singleColumn
            }
        }
        .onAppear {
            refreshStatus()
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                refreshStatus()
                startTimer()
            case .inactive, .background:
                stopTimer()
            @unknown default:
                break
            }
        }
        .onChange(of: statusRefreshInterval) { _ in
            guard scenePhase == .active else { return }
            stopTimer()
            startTimer()
        }
        .sheet(item: $selectedPeerRoute) { selection in
            PeerConnDetailSheet(status: $status, peerRouteID: selection.id)
        }
        .sheet(isPresented: $showNodeInfo) {
            NodeInfoSheet(status: $status)
        }
        .sheet(isPresented: $showStunInfo) {
            StunInfoSheet(status: $status)
        }
        .sheet(isPresented: $showNetworkSettings) {
            NetworkSettingsSheet(settings: $lastNetworkSettings)
        }
    }
    
    var singleColumn: some View {
        Form {
            Section("device.status") {
                localStatus
            }

            if let error = status?.errorMsg {
                Section("common.error") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("common.info") {
                Picker(
                    "common.info",
                    selection: $selectedInfoKind
                ) {
                    ForEach(InfoKind.allCases) {
                        kind in
                        Text(kind.description).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                switch (selectedInfoKind) {
                case .peerInfo:
                    peerInfo
                case .eventLog:
                    TimelineLogPanel(events: status?.events ?? [])
                }
            }
        }
    }
    
    var doubleComlum: some View {
        HStack(spacing: 0) {
            Form {
                Section("device.status") {
                    localStatus
                }

                if let error = status?.errorMsg {
                    Section("common.error") {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .foregroundStyle(.red)
                    }
                }
                
                Section("peer_info") {
                    peerInfo
                }
            }
            .frame(maxWidth: columnWidth)
            Form {
                Section("event_log") {
                    TimelineLogPanel(events: status?.events ?? [])
                }
            }
        }
    }
    
    var localStatus: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(networkName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(status?.myNodeInfo?.version ?? String(localized: "not_available"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: .init(status?.running))
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                manager.fetchLastNetworkSettings { settings in
                    DispatchQueue.main.async {
                        lastNetworkSettings = settings
                        showNetworkSettings = true
                    }
                }
            }
            
            HStack(spacing: 42) {
                TrafficItem(
                    trafficType: .Rx,
                    value: (status?.sum(of: \.rxBytes)),
                )
                TrafficItem(
                    trafficType: .Tx,
                    value: (status?.sum(of: \.txBytes)),
                )
            }

            HStack(spacing: 42) {
                Button {
                    showNodeInfo = true
                } label: {
                    StatItem(
                        label: "virtual_ipv4",
                        value: LocalizedStringKey(stringLiteral: status?.myNodeInfo?.virtualIPv4?.description ?? "not_available"),
                        icon: "network"
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    showStunInfo = true
                } label: {
                    StatItem(
                        label: "nat_type",
                        value: status?.myNodeInfo?.stunInfo?.udpNATType.description ?? LocalizedStringKey(stringLiteral: "not_available"),
                        icon: "shield"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    var peerInfo: some View {
        ForEach(status?.peerRoutePairs ?? []) { pair in
            Button {
                selectedPeerRoute = SelectedPeerRoute(id: pair.id)
            } label: {
                PeerRowView(pair: pair)
            }
            .buttonStyle(.plain)
        }
    }

    func refreshStatus() {
        manager.fetchRunningInfo { info in
            status = info
        }
    }

    func startTimer() {
        guard timerSubscription == nil else { return }
        let interval = max(0.2, statusRefreshInterval)
        timerSubscription = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
            refreshStatus()
        }
    }

    private func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
    }
}

struct PeerRowView: View {
    let pair: NetworkStatus.PeerRoutePair
    
    var isPublicServer: Bool {
        pair.route.featureFlag?.isPublicServer ?? false
    }

    var latency: Double? {
        let latencies = pair.peer?.conns.compactMap {
            $0.stats?.latencyUs
        }
        guard let latencies else { return nil }
        return Double(latencies.reduce(0, +)) / Double(latencies.count)
    }

    var lossRate: Double? {
        let lossRates = pair.peer?.conns.compactMap {
            $0.lossRate
        }
        guard let lossRates else { return nil }
        return lossRates.reduce(0, +) / Double(lossRates.count)
    }

    var body: some View {
        HStack(alignment: .center) {
            // Icon
            ZStack {
                Circle()
                    .fill((isPublicServer ? Color.pink : Color.blue).opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: isPublicServer ? "server.rack" : "rectangle.connected.to.line.below")
                    .foregroundStyle(isPublicServer ? .pink : .blue)
            }.padding(.trailing, 8)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(pair.route.hostname)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let text = ({
                        var infoLine: [String] = []
                        infoLine.append("ID: \(String(pair.route.peerId))")
                        if let conns = pair.peer?.conns, !conns.isEmpty {
                            let types = conns.compactMap(\.tunnel?.tunnelType);
                            if !types.isEmpty {
                                infoLine.append(Array(Set(types)).sorted().joined(separator: "&").uppercased())
                            }
                        }
                        return infoLine.joined(separator: " ")
                    })(), !text.isEmpty {
                        Text(text)
                    }
                    
                    if let text = ({
                        var infoLine: [String] = []
                        if let ip = pair.route.ipv4Addr {
                            infoLine.append("IP: \(ip.description)")
                            if let _ = pair.route.ipv6Addr {
                                infoLine.append("(+IPv6)")
                            }
                        } else if let ip = pair.route.ipv6Addr {
                            infoLine.append("IP: \(ip.description)")
                        }
                        return infoLine.joined(separator: " ")
                    })(), !text.isEmpty {
                        Text(text)
                    }
                }
                .compatibleLabelSpacing(0)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Metrics
            VStack(alignment: .trailing, spacing: 4) {
                if let latency {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("\(String(format: "%.1f", latency / 1000.0)) ms")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(latencyColor(latency))
                }
                
                HStack {
                    Text(pair.route.cost == 1 ? "p2p" : "relay_\(pair.route.cost)")
                        .font(.caption2)
                        .foregroundStyle(pair.route.cost == 1 ? .blue : .purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((pair.route.cost == 1 ? Color.blue : Color.purple).opacity(0.1))
                        .clipShape(Capsule())
                    if let lossRate {
                        let lossPercent = String(format: "%.0f", lossRate * 100)
                        Text("loss_rate_format_\(lossPercent)")
                            .font(.caption2)
                            .foregroundStyle(lossRateColor(lossRate))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(lossRateColor(lossRate).opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    func latencyColor(_ us: Double) -> Color {
        switch us {
        case 0..<100_000: return .green
        case 100_000..<200_000: return .orange
        default: return .red
        }
    }
    
    func lossRateColor(_ rate: Double) -> Color {
        switch rate {
        case 0..<0.02: return .secondary
        case 0.02..<0.1: return .orange
        default: return .red
        }
    }
}

struct SelectedPeerRoute: Identifiable {
    let id: Int
}

struct TrafficItem: View {
    let trafficType: TrafficType
    let value: Int?
    
    @State var diff: Double?
    @State var lastTime: Date?
    @State var previousValue: Int?

    enum TrafficType {
        case Tx
        case Rx
    }
    
    var unifiedValue: Double {
        guard let diff else { return Double.nan }
        let v = Double(diff)
        return switch abs(v) {
        case ..<1024:
            v
        case ..<1048576:
            v / 1024
        case ..<1073741824:
            v / 1048576
        case ..<1099511627776:
            v / 1073741824
        default:
            v / 1099511627776
        }
    }
    var unit: String {
        switch abs(diff ?? 0) {
        case ..<1024:
            "B/s"
        case ..<1048576:
            "KB/s"
        case ..<1073741824:
            "MB/s"
        case ..<1099511627776:
            "GB/s"
        default:
            "TB/s"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch trafficType {
            case .Tx:
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.orange, .orange.opacity(0.3))
                    Text("upload")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            case .Rx:
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.blue.opacity(0.3), .blue)
                    Text("download")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%4.f", unifiedValue))
                    .font(.title3)
                    .fontWeight(.medium)
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: value) { newValue in
            guard let newValue else { return }
            guard let lastTime else {
                lastTime = Date()
                return
            }
            guard let previousValue else {
                self.lastTime = Date()
                previousValue = newValue
                return
            }
            let currentTime = Date()
            let interval = currentTime.timeIntervalSince(lastTime)
            self.lastTime = currentTime
            diff = max(Double(newValue - previousValue) / interval, 0)
            $previousValue.wrappedValue = newValue
        }
    }
}

struct StatItem: View {
    let label: LocalizedStringKey
    let value: LocalizedStringKey
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .compatibleLabelSpacing(2)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusBadge: View {
    let status: ActiveStatus

    var badgeColor: Color {
        switch status {
        case .Stopped:
            .red
        case .Running:
            .green
        case .Loading:
            .orange
        }
    }

    enum ActiveStatus: LocalizedStringKey {
        case Stopped = "stopped"
        case Running = "running"
        case Loading = "loading"

        init(_ active: Bool?) {
            if let active {
                self = active ? .Running : .Stopped
            } else {
                self = .Loading
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            Text(status.rawValue)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badgeColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        StatusView("Example", manager: manager)
            .environmentObject(manager)
        
        StatusView("Example", manager: manager)
            .environmentObject(manager)
            .previewInterfaceOrientation(.landscapeLeft)
    }
}

extension View {
    func compatibleLabelSpacing(_ spacing: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            return self.labelIconToTitleSpacing(spacing)
        } else {
            return self
        }
    }
}
