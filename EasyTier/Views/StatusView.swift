import Combine
import SwiftUI

struct StatusView<Manager: NEManagerProtocol>: View {
    @EnvironmentObject var manager: Manager
    @State var timerSubscription: AnyCancellable?
    @State var status: NetworkStatus?
    @State var selectedInfoKind: InfoKind = .peerInfo
    
    var name: String
    
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

    let timer = Timer.publish(every: 1, on: .main, in: .common)

    var body: some View {
        Form {
            Section("Local") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
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
                    StatItem(
                        label: "Virtual IP",
                        value: status?.myNodeInfo?.virtualIPv4?.description ?? "N/A",
                        icon: "network"
                    )
                    StatItem(
                        label: "NAT Type",
                        value: status?.myNodeInfo?.stunInfo?.udpNATType.description ?? "N/A",
                        icon: "shield"
                    )
                }
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
                    ForEach(status?.peerRoutePairs ?? []) { pair in
                        PeerRowView(pair: pair)
                    }
                case .eventLog:
                    TimelineLogPanel(events: status?.events ?? [])
                }
            }
        }
        .onAppear {
            timerSubscription = timer.autoconnect().sink { _ in
                manager.fetchRunningInfo { info in
                    status = info
                }
            }
        }
        .onDisappear {
            if let timerSubscription {
                timerSubscription.cancel()
            }
            timerSubscription = nil
        }
    }
}

struct PeerRowView: View {
    let pair: NetworkStatus.PeerRoutePair

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
        HStack(alignment: .center, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "server.rack")
                    .foregroundStyle(.blue)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(pair.route.hostname)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                VStack(alignment: .leading, spacing: 4) {
                    {
                        var infoLine1: [String] = []
                        infoLine1.append("ID: \(String(pair.route.peerId))")
                        infoLine1.append(pair.route.cost == 1 ? "P2P" : "Relay \(pair.route.cost)")
                        if let conns = pair.peer?.conns, !conns.isEmpty {
                            let types = conns.compactMap(\.tunnel?.tunnelType);
                            if !types.isEmpty {
                                infoLine1.append(Array(Set(types)).sorted().joined(separator: "&").uppercased())
                            }
                        }
                        return Text(infoLine1.joined(separator: " "))
                    }()
                    
                    if let ip = pair.route.ipv4Addr {
                        Text("IP: \(ip.description)")
                    }
                }
                .labelIconToTitleSpacing(0)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Metrics
            VStack(alignment: .trailing, spacing: 4) {
                if let latency {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill")
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
        case 0..<60_000: return .green
        case 60_000..<200_000: return .orange
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
                .labelIconToTitleSpacing(2)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
        }
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

struct StatusView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        StatusView<MockNEManager>(name: "Example")
            .environmentObject(manager)
    }
}
