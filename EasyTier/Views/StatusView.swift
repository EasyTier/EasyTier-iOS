import Combine
import Foundation
import SwiftUI

struct StatusView<Manager: NEManagerProtocol>: View {
    @EnvironmentObject var manager: Manager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) var sizeClass
    @AppStorage("statusRefreshInterval") private var statusRefreshInterval: Double = 1.0
    @State var timerSubscription: AnyCancellable?
    @State var status: NetworkStatus?
    
    @State var selectedInfoKind: InfoKind = .peerInfo
    @State var selectedPeerRoutePair: NetworkStatus.PeerRoutePair?
    @State var showNodeInfo = false
    @State var showStunInfo = false
    
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
        .onChange(of: scenePhase) { _, newPhase in
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
        .onChange(of: statusRefreshInterval) { _, _ in
            guard scenePhase == .active else { return }
            stopTimer()
            startTimer()
        }
        .sheet(item: $selectedPeerRoutePair) { pair in
            PeerConnDetailSheet(pair: pair)
        }
        .sheet(isPresented: $showNodeInfo) {
            NodeInfoSheet(nodeInfo: status?.myNodeInfo)
        }
        .sheet(isPresented: $showStunInfo) {
            StunInfoSheet(stunInfo: status?.myNodeInfo?.stunInfo)
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
                .pickerStyle(.palette)
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
                    Text(status?.myNodeInfo?.hostname ?? String(localized: "not_available"))
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
                selectedPeerRoutePair = pair
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
                        infoLine.append(pair.route.cost == 1 ? "P2P" : "Relay \(pair.route.cost)")
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

struct TrafficItem: View {
    let trafficType: TrafficType
    let value: Int?
    
    @State var diff: Double?
    @State var lastTime: Date?

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
        .onChange(of: value) { oldValue, newValue in
            guard let oldValue, let newValue else { return }
            guard let lastTime else {
                lastTime = Date()
                return
            }
            let currentTime = Date()
            let interval = currentTime.timeIntervalSince(lastTime)
            self.lastTime = currentTime
            diff = Double(newValue - oldValue) / interval
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

struct TimelineLogPanel: View {
    let events: [String]
    
    var timelineEntries: [TimelineEntry] {
        TimelineEntry.parse(events)
    }
    
    var body: some View {
        if timelineEntries.isEmpty {
            Text("no_parsed_events")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(timelineEntries.enumerated()), id: \.element.id) { index, entry in
                    TimelineRow(entry: entry, isLast: index == timelineEntries.count - 1)
                }
            }
        }
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry
    let isLast: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time Column
            VStack(alignment: .trailing, spacing: 2) {
                if let date = entry.date {
                    Text(date, style: .time) // e.g., 2:31 PM
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text(date.formatted(.dateTime.month().day())) // e.g., Jan 4
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("not_available")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                }
            }
            .padding(.top, 2)
            
            // Timeline Graphic (Dot + Line)
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            
            // JSON Content Bubble
            VStack(alignment: .leading, spacing: 12) {
                if let name = entry.name {
                    Text(name)
                        .font(.headline)
                }
                Text(entry.payload)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.bottom, 24)
        }
    }
}

struct TimelineEntry: Identifiable {
    var id: String { self.original }
    let date: Date?
    let name: String?
    let payload: String
    let original: String
    
    // Parser
    static func parse(_ rawLines: [String]) -> [TimelineEntry] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return rawLines.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timeStr = json["time"] as? String,
                  let date = isoFormatter.date(from: timeStr),
                  let eventData = json["event"] else {
                return TimelineEntry(date: nil, name: nil, payload: line, original: line)
            }
            
            let name: String?
            let payload: Any
            if let eventData = eventData as? [String: Any], eventData.count == 1, let name_ = eventData.keys.first, let payload_ = eventData[name_] {
                name = name_
                payload = payload_
            } else {
                name = nil
                payload = eventData
            }
            
            if let prettyData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .withoutEscapingSlashes, .fragmentsAllowed]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                return TimelineEntry(date: date, name: name, payload: prettyString, original: line)
            }
            return TimelineEntry(date: date, name: nil, payload: line, original: line)
        }.sorted { $0.date ?? .distantPast > $1.date ?? .distantPast }
    }
}

struct PeerConnDetailSheet: View {
    let pair: NetworkStatus.PeerRoutePair

    var conns: [NetworkStatus.PeerConnInfo] {
        pair.peer?.conns ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("peer") {
                    LabeledContent("hostname", value: pair.route.hostname)
                    LabeledContent("peer_id", value: String(pair.route.peerId))
                }

                if conns.isEmpty {
                    Section("connections") {
                        Text("no_connection_details_available")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(conns, id: \.connId) { conn in
                        Section("connection_\(conn.connId)") {
                            LabeledContent("role", value: conn.isClient ? "Client" : "Server")
                            LabeledContent("loss_rate", value: percentString(conn.lossRate))
                            LabeledContent("network", value: conn.networkName ?? String(localized: "not_available"))
                            LabeledContent("closed", value: triState(conn.isClosed))

                            LabeledContent("features", value: conn.features.isEmpty ? "None" : conn.features.joined(separator: ", "))

                            if let tunnel = conn.tunnel {
                                LabeledContent("tunnel_type", value: tunnel.tunnelType.uppercased())
                                LabeledContent("local_addr", value: tunnel.localAddr.url)
                                LabeledContent("remote_addr", value: tunnel.remoteAddr.url)
                            }

                            if let stats = conn.stats {
                                LabeledContent("rx_bytes", value: formatBytes(stats.rxBytes))
                                LabeledContent("tx_bytes", value: formatBytes(stats.txBytes))
                                LabeledContent("rx_packets", value: String(stats.rxPackets))
                                LabeledContent("tx_packets", value: String(stats.txPackets))
                                LabeledContent("latency", value: latencyString(stats.latencyUs))
                            }
                        }
                    }
                }
            }
            .navigationTitle("peer_details")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func formatBytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(value))
    }

    private func latencyString(_ us: Int) -> String {
        String(format: "%.1f ms", Double(us) / 1000.0)
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private func triState(_ value: Bool?) -> String {
        guard let value else { return "event.Unknown" }
        return value ? "Yes" : "No"
    }
}

struct NodeInfoSheet: View {
    let nodeInfo: NetworkStatus.NodeInfo?
    
    var body: some View {
        NavigationStack {
            Form {
                if let nodeInfo {
                    Section("basic_info") {
                        LabeledContent("hostname", value: nodeInfo.hostname)
                        LabeledContent("status.version", value: nodeInfo.version)
                        if let virtualIPv4 = nodeInfo.virtualIPv4 {
                            LabeledContent("virtual_ipv4", value: virtualIPv4.description)
                        }
                    }
                    
                    if let ips = nodeInfo.ips {
                        if ips.publicIPv4 != nil || ips.publicIPv6 != nil {
                            Section("ip_information") {
                                if let publicIPv4 = ips.publicIPv4 {
                                    LabeledContent("public_ipv4", value: publicIPv4.description)
                                }
                                if let publicIPv6 = ips.publicIPv6 {
                                    LabeledContent("public_ipv6", value: publicIPv6.description)
                                }
                            }
                        }
                        if let v4s = ips.interfaceIPv4s, !v4s.isEmpty {
                            Section("interface_ipv4s") {
                                ForEach(Array(Set(v4s)), id: \.hashValue) { ip in
                                    Text(ip.description)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if let v6s = ips.interfaceIPv6s, !v6s.isEmpty {
                            Section("interface_ipv6s") {
                                ForEach(Array(Set(v6s)), id: \.hashValue) { ip in
                                    Text(ip.description)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    
                    if let listeners = nodeInfo.listeners, !listeners.isEmpty {
                        Section("listeners") {
                            ForEach(listeners, id: \.url) { listener in
                                Text(listener.url)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("no_node_information_available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("node_information")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StunInfoSheet: View {
    let stunInfo: NetworkStatus.STUNInfo?
    
    var body: some View {
        NavigationStack {
            Form {
                if let stunInfo {
                    Section("nat_types") {
                        LabeledContent("udp_nat_type") {
                            Text(stunInfo.udpNATType.description)
                        }
                        LabeledContent("tcp_nat_type") {
                            Text(stunInfo.tcpNATType.description)
                        }
                    }
                    
                    Section("details") {
                        LabeledContent("last_update", value: formatDate(stunInfo.lastUpdateTime))
                        if let minPort = stunInfo.minPort {
                            LabeledContent("min_port", value: String(minPort))
                        }
                        if let maxPort = stunInfo.maxPort {
                            LabeledContent("max_port", value: String(maxPort))
                        }
                    }
                    
                    if !stunInfo.publicIPs.isEmpty {
                        Section("public_ips") {
                            ForEach(stunInfo.publicIPs, id: \.self) { ip in
                                Text(ip)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("no_stun_information_available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("stun_information")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatDate(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        StatusView<MockNEManager>()
            .environmentObject(manager)
        
        StatusView<MockNEManager>()
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
