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
    
    enum InfoKind: Identifiable, CaseIterable, CustomStringConvertible {
        var id: Self { self }
        case peerInfo
        case eventLog
        
        var description: String {
            switch self {
            case .peerInfo: "Peer Info"
            case .eventLog: "Event Log"
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
            Section("Status") {
                localStatus
            }

            if let error = status?.errorMsg {
                Section("Error") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("Information") {
                Picker(
                    "Information to Show",
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
                Section("Status") {
                    localStatus
                }

                if let error = status?.errorMsg {
                    Section("Error") {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(error)
                        }
                        .foregroundStyle(.red)
                    }
                }
                
                Section("Peer Info") {
                    peerInfo
                }
            }
            .frame(maxWidth: columnWidth)
            Form {
                Section("Event Log") {
                    TimelineLogPanel(events: status?.events ?? [])
                }
            }
        }
    }
    
    var localStatus: some View {
        Group {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status?.myNodeInfo?.hostname ?? "N/A")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("v\(status?.myNodeInfo?.version ?? "N/A")")
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
                        label: "Virtual IP",
                        value: status?.myNodeInfo?.virtualIPv4?.description ?? "N/A",
                        icon: "network"
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    showStunInfo = true
                } label: {
                    StatItem(
                        label: "NAT Type",
                        value: status?.myNodeInfo?.stunInfo?.udpNATType.description ?? "N/A",
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
                    Text("Loss: \(String(format: "%.0f", lossRate * 100))%")
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

    enum TrafficType {
        case Tx
        case Rx
    }
    
    var unifiedValue: Float {
        guard let value else { return Float.nan }
        let v = Float(value)
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
        switch abs(value ?? 0) {
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
                    Text("Upload")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            case .Rx:
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.blue.opacity(0.3), .blue)
                    Text("Download")
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
    }
}

struct StatItem: View {
    let label: String
    let value: String
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

    enum ActiveStatus: String {
        case Stopped = "Stopped"
        case Running = "Running"
        case Loading = "Loading"

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
            Text("No parsed events")
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
                    Text("N/A")
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
                Section("Peer") {
                    LabeledContent("Hostname", value: pair.route.hostname)
                    LabeledContent("Peer ID", value: String(pair.route.peerId))
                }

                if conns.isEmpty {
                    Section("Connections") {
                        Text("No connection details available.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(conns, id: \.connId) { conn in
                        Section("Connection \(conn.connId)") {
                            LabeledContent("Role", value: conn.isClient ? "Client" : "Server")
                            LabeledContent("Loss Rate", value: percentString(conn.lossRate))
                            LabeledContent("Network", value: conn.networkName ?? "N/A")
                            LabeledContent("Closed", value: triState(conn.isClosed))

                            LabeledContent("Features", value: conn.features.isEmpty ? "None" : conn.features.joined(separator: ", "))

                            if let tunnel = conn.tunnel {
                                LabeledContent("Tunnel Type", value: tunnel.tunnelType.uppercased())
                                LabeledContent("Local", value: tunnel.localAddr.url)
                                LabeledContent("Remote", value: tunnel.remoteAddr.url)
                            }

                            if let stats = conn.stats {
                                LabeledContent("Rx Bytes", value: formatBytes(stats.rxBytes))
                                LabeledContent("Tx Bytes", value: formatBytes(stats.txBytes))
                                LabeledContent("Rx Packets", value: String(stats.rxPackets))
                                LabeledContent("Tx Packets", value: String(stats.txPackets))
                                LabeledContent("Latency", value: latencyString(stats.latencyUs))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Peer Details")
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
        guard let value else { return "Unknown" }
        return value ? "Yes" : "No"
    }
}

struct NodeInfoSheet: View {
    let nodeInfo: NetworkStatus.NodeInfo?
    
    var body: some View {
        NavigationStack {
            Form {
                if let nodeInfo {
                    Section("Basic Info") {
                        LabeledContent("Hostname", value: nodeInfo.hostname)
                        LabeledContent("Version", value: nodeInfo.version)
                        if let virtualIPv4 = nodeInfo.virtualIPv4 {
                            LabeledContent("Virtual IPv4", value: virtualIPv4.description)
                        }
                    }
                    
                    if let ips = nodeInfo.ips {
                        if ips.publicIPv4 != nil || ips.publicIPv6 != nil {
                            Section("IP Information") {
                                if let publicIPv4 = ips.publicIPv4 {
                                    LabeledContent("Public IPv4", value: publicIPv4.description)
                                }
                                if let publicIPv6 = ips.publicIPv6 {
                                    LabeledContent("Public IPv6", value: publicIPv6.description)
                                }
                            }
                        }
                        if let v4s = ips.interfaceIPv4s, !v4s.isEmpty {
                            Section("Interface IPv4s") {
                                ForEach(Array(Set(v4s)), id: \.hashValue) { ip in
                                    Text(ip.description)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if let v6s = ips.interfaceIPv6s, !v6s.isEmpty {
                            Section("Interface IPv6s") {
                                ForEach(Array(Set(v6s)), id: \.hashValue) { ip in
                                    Text(ip.description)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    
                    if let listeners = nodeInfo.listeners, !listeners.isEmpty {
                        Section("Listeners") {
                            ForEach(listeners, id: \.url) { listener in
                                Text(listener.url)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("No node information available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Node Information")
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
                    Section("NAT Types") {
                        LabeledContent("UDP NAT Type", value: stunInfo.udpNATType.description)
                        LabeledContent("TCP NAT Type", value: stunInfo.tcpNATType.description)
                    }
                    
                    Section("Details") {
                        LabeledContent("Last Update", value: formatDate(stunInfo.lastUpdateTime))
                        if let minPort = stunInfo.minPort {
                            LabeledContent("Min Port", value: String(minPort))
                        }
                        if let maxPort = stunInfo.maxPort {
                            LabeledContent("Max Port", value: String(maxPort))
                        }
                    }
                    
                    if !stunInfo.publicIPs.isEmpty {
                        Section("Public IPs") {
                            ForEach(stunInfo.publicIPs, id: \.self) { ip in
                                Text(ip)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("No STUN information available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("STUN Information")
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
