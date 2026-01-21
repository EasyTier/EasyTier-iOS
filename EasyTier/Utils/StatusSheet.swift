import SwiftUI

import EasyTierShared

struct NetworkSettingsSheet: View {
    @Binding var settings: TunnelNetworkSettingsSnapshot?

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    if let ipv4 = settings.ipv4 {
                        Section("ipv4") {
                            labeledLines("address", values: formatIPv4Addresses(ipv4.addresses, subnetMasks: ipv4.subnetMasks))
                        }
                        if let routes = ipv4.includedRoutes, !routes.isEmpty {
                            Section("ipv4_routes_included") {
                                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                                    Text(formatIPv4Route(route))
                                }
                            }
                        }
                        if let routes = ipv4.excludedRoutes, !routes.isEmpty {
                            Section("ipv4_routes_excluded") {
                                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                                    Text(formatIPv4Route(route))
                                }
                            }
                        }
                    }

                    if let ipv6 = settings.ipv6 {
                        Section("ipv6") {
                            labeledLines("address", values: formatIPv6Addresses(ipv6.addresses, prefixLengths: ipv6.networkPrefixLengths))
                        }
                        if let routes = ipv6.includedRoutes, !routes.isEmpty {
                            Section("ipv6_routes_included") {
                                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                                    Text("\(route.destination)/\(route.networkPrefixLength)")
                                }
                            }
                        }
                        if let routes = ipv6.excludedRoutes, !routes.isEmpty {
                            Section("ipv6_routes_excluded") {
                                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                                    Text("\(route.destination)/\(route.networkPrefixLength)")
                                }
                            }
                        }
                    }

                    if let dns = settings.dns {
                        Section("dns") {
                            labeledLines("server", values: dns.servers)
                            if let search = dns.searchDomains, !search.isEmpty {
                                labeledLines("search_domains", values: search)
                            }
                            if let match = dns.matchDomains, !match.isEmpty {
                                labeledLines("match_domains", values: formatMatchDomains(match))
                            }
                        }
                    }

                    if let mtu = settings.mtu {
                        Section("mtu") {
                            LabeledContent("mtu", value: String(mtu))
                        }
                    }
                } else {
                    Section {
                        Text("no_settings_available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("network_settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func labeledLines(_ label: LocalizedStringKey, values: [String]) -> some View {
        LabeledContent(label) {
            Text(values.isEmpty ? String(localized: "not_available") : values.joined(separator: "\n"))
        }
    }

    private func formatIPv4Addresses(_ addresses: [String], subnetMasks: [String]) -> [String] {
        let count = min(addresses.count, subnetMasks.count)
        guard count > 0 else { return addresses }
        var results: [String] = []
        results.reserveCapacity(count)
        for index in 0..<count {
            let address = addresses[index]
            let mask = subnetMasks[index]
            if let prefix = ipv4PrefixLength(from: mask) {
                results.append("\(address)/\(prefix)")
            } else {
                results.append(address)
            }
        }
        if addresses.count > count {
            results.append(contentsOf: addresses[count...])
        }
        return results
    }

    private func formatIPv6Addresses(_ addresses: [String], prefixLengths: [UInt32]) -> [String] {
        let count = min(addresses.count, prefixLengths.count)
        guard count > 0 else { return addresses }
        var results: [String] = []
        results.reserveCapacity(count)
        for index in 0..<count {
            results.append("\(addresses[index])/\(prefixLengths[index])")
        }
        if addresses.count > count {
            results.append(contentsOf: addresses[count...])
        }
        return results
    }

    private func formatMatchDomains(_ domains: [String]) -> [String] {
        domains.map { domain in
            domain.isEmpty ? String(localized: "all_domains") : domain
        }
    }

    private func formatIPv4Route(_ route: TunnelNetworkSettingsSnapshot.IPv4Route) -> String {
        if let prefix = ipv4PrefixLength(from: route.subnetMask) {
            return "\(route.destination)/\(prefix)"
        }
        return "\(route.destination)/\(route.subnetMask)"
    }

    private func ipv4PrefixLength(from mask: String) -> Int? {
        let parts = mask.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            value = (value << 8) | octet
        }
        var prefix = 0
        var seenZero = false
        for bit in (0..<32).reversed() {
            let isSet = (value & (1 << bit)) != 0
            if isSet {
                if seenZero { return nil }
                prefix += 1
            } else {
                seenZero = true
            }
        }
        return prefix
    }
}

struct PeerConnDetailSheet: View {
    @Binding var status: NetworkStatus?
    let peerRouteID: Int

    var pair: NetworkStatus.PeerRoutePair? {
        status?.peerRoutePairs.first { $0.id == peerRouteID }
    }

    var conns: [NetworkStatus.PeerConnInfo] {
        pair?.peer?.conns ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                if let pair {
                    Section("peer") {
                        LabeledContent("hostname", value: pair.route.hostname)
                        LabeledContent("peer_id", value: String(pair.route.peerId))
                        if let ipv4 = pair.route.ipv4Addr {
                            LabeledContent("ipv4_addr", value: ipv4.description)
                        }
                        if let ipv6 = pair.route.ipv6Addr {
                            LabeledContent("ipv6_addr", value: ipv6.description)
                        }
                        LabeledContent("inst_id", value: String(pair.route.instId))
                        LabeledContent("version", value: String(pair.route.version))
                        LabeledContent("next_hop_peer_id", value: String(pair.route.nextHopPeerId))
                        LabeledContent("cost", value: String(pair.route.cost))
                        LabeledContent("path_latency", value: latencyValueString(pair.route.pathLatency))
                        if let nextHopLatencyFirst = pair.route.nextHopPeerIdLatencyFirst {
                            LabeledContent("next_hop_peer_id_latency_first", value: String(nextHopLatencyFirst))
                        }
                        if let costLatencyFirst = pair.route.costLatencyFirst {
                            LabeledContent("cost_latency_first", value: String(costLatencyFirst))
                        }
                        if let pathLatencyLatencyFirst = pair.route.pathLatencyLatencyFirst {
                            LabeledContent("path_latency_latency_first", value: latencyValueString(pathLatencyLatencyFirst))
                        }
                        if let featureFlags = pair.route.featureFlag {
                            LabeledContent("feature_flag", value: featureFlagString(featureFlags))
                        }
                        if let peerInfo = pair.peer {
                            if let defaultConnId = peerInfo.defaultConnId {
                                LabeledContent("default_conn_id", value: uuidString(defaultConnId))
                            }
                            if !peerInfo.directlyConnectedConns.isEmpty {
                                LabeledContent(
                                    "directly_connected_conns",
                                    value: peerInfo.directlyConnectedConns.map(uuidString).joined(separator: "\n")
                                )
                            }
                        }
                    }

                    if !pair.route.proxyCIDRs.isEmpty {
                        Section("proxy_cidrs") {
                            ForEach(pair.route.proxyCIDRs, id: \.hashValue) {
                                Text($0)
                            }
                        }
                    }

                    if conns.isEmpty {
                        Section("connections") {
                            Text("no_connection_details_available")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(conns, id: \.connId) { conn in
                            Section("connection_\(conn.connId)") {
                                LabeledContent("peer_id", value: String(conn.peerId))
                                LabeledContent("role", value: conn.isClient ? "Client" : "Server")
                                LabeledContent("loss_rate", value: percentString(conn.lossRate))
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
                } else {
                    Section {
                        Text("no_peer_information_available")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .textSelection(.enabled)
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

    private func latencyValueString(_ value: Int) -> String {
        "\(value) ms"
    }

    private func percentString(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private func triState(_ value: Bool?) -> String {
        guard let value else { return "event.Unknown" }
        return value ? "Yes" : "No"
    }

    private func uuidString(_ value: NetworkStatus.UUID) -> String {
        String(format: "%08x-%08x-%08x-%08x", value.part1, value.part2, value.part3, value.part4)
    }

    private func featureFlagString(_ flags: NetworkStatus.PeerFeatureFlag) -> String {
        var enabled: [String] = []
        if flags.isPublicServer { enabled.append("is_public_server") }
        if flags.avoidRelayData { enabled.append("avoid_relay_data") }
        if flags.kcpInput { enabled.append("kcp_input") }
        if flags.noRelayKcp { enabled.append("no_relay_kcp") }
        if flags.supportConnListSync { enabled.append("support_conn_list_sync") }
        return enabled.isEmpty ? "None" : enabled.joined(separator: ", ")
    }
}

struct NodeInfoSheet: View {
    @Binding var status: NetworkStatus?

    var nodeInfo: NetworkStatus.MyNodeInfo? {
        status?.myNodeInfo
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let nodeInfo {
                    Section("general") {
                        LabeledContent("hostname", value: nodeInfo.hostname)
                        LabeledContent("version", value: nodeInfo.version)
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
                                }
                            }
                        }
                        if let v6s = ips.interfaceIPv6s, !v6s.isEmpty {
                            Section("interface_ipv6s") {
                                ForEach(Array(Set(v6s)), id: \.hashValue) { ip in
                                    Text(ip.description)
                                }
                            }
                        }
                    }
                    
                    if let listeners = nodeInfo.listeners, !listeners.isEmpty {
                        Section("listeners") {
                            ForEach(listeners, id: \.url) { listener in
                                Text(listener.url)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("no_node_information_available")
                    }
                }
            }
            .textSelection(.enabled)
            .navigationTitle("node_information")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StunInfoSheet: View {
    @Binding var status: NetworkStatus?

    var stunInfo: NetworkStatus.STUNInfo? {
        status?.myNodeInfo?.stunInfo
    }
    
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
            .textSelection(.enabled)
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
