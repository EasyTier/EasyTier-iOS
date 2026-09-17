import Foundation
import SwiftUI

struct NetworkStatus: Codable {
    enum NATType: Int, Codable {
        case unknown = 0
        case openInternet = 1
        case noPAT = 2
        case fullCone = 3
        case restricted = 4
        case portRestricted = 5
        case symmetric = 6
        case symUDPFirewall = 7
        case symmetricEasyInc = 8
        case symmetricEasyDec = 9

        var description: LocalizedStringKey {
            switch self {
            case .unknown:          return "unknown"
            case .openInternet:     return "open_internet"
            case .noPAT:            return "no_pat"
            case .fullCone:         return "full_cone"
            case .restricted:       return "restricted"
            case .portRestricted:   return "port_restricted"
            case .symmetric:        return "symmetric"
            case .symUDPFirewall:   return "symmetric_udp_firewall"
            case .symmetricEasyInc: return "symmetric_easy_inc"
            case .symmetricEasyDec: return "symmetric_easy_dec"
            }
        }
    }

    struct UUID: Codable, Hashable {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32
    }

    struct PeerFeatureFlag: Codable, Hashable {
        var isPublicServer: Bool
        var avoidRelayData: Bool
        var kcpInput: Bool
        var noRelayKcp: Bool
        var supportConnListSync: Bool
        var quicInput: Bool
        var noRelayQuic: Bool

        enum CodingKeys: String, CodingKey {
            case isPublicServer = "is_public_server"
            case avoidRelayData = "avoid_relay_data"
            case kcpInput = "kcp_input"
            case noRelayKcp = "no_relay_kcp"
            case supportConnListSync = "support_conn_list_sync"
            case quicInput = "quic_input"
            case noRelayQuic = "no_relay_quic"
        }
    }

    struct IPv4Addr: Codable, Hashable, CustomStringConvertible {
        var addr: UInt32

        init?(_ s: String) {
            let components = s.split(separator: ".").compactMap { UInt32($0) }
            guard components.count == 4 else { return nil }
            let addr =
                (components[0] << 24) | (components[1] << 16)
                | (components[2] << 8) | components[3]
            self.addr = addr
        }

        var description: String {
            let ip = addr
            return
                "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
        }
    }

    struct IPv4CIDR: Codable, Hashable, CustomStringConvertible {
        var address: IPv4Addr
        var networkLength: Int

        var description: String {
            return "\(address.description)/\(networkLength)"
        }

        enum CodingKeys: String, CodingKey {
            case address
            case networkLength = "network_length"
        }
    }

    struct IPv6Addr: Codable, Hashable, CustomStringConvertible {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32
        
        init?(_ s: String) {
            var addr = in6_addr()
            guard inet_pton(AF_INET6, s, &addr) == 1 else {
                return nil
            }
            
            let data = withUnsafeBytes(of: addr) { Data($0) }
            
            self.part1 = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.part2 = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.part3 = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.part4 = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        }
        
        var description: String {
            var addr = in6_addr()
            let p1 = part1.bigEndian
            let p2 = part2.bigEndian
            let p3 = part3.bigEndian
            let p4 = part4.bigEndian
            
            withUnsafeMutableBytes(of: &addr) { ptr in
                ptr.storeBytes(of: p1, toByteOffset: 0, as: UInt32.self)
                ptr.storeBytes(of: p2, toByteOffset: 4, as: UInt32.self)
                ptr.storeBytes(of: p3, toByteOffset: 8, as: UInt32.self)
                ptr.storeBytes(of: p4, toByteOffset: 12, as: UInt32.self)
            }
            
            var buffer = [UInt8](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            
            if inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            // fallback
            let parts = [part1, part2, part3, part4]
            let segments = parts.flatMap { part -> [UInt16] in
                [UInt16(part >> 16), UInt16(part & 0xFFFF)]
            }
            return segments.map { String(format: "%04x", $0) }.joined(separator: ":")
        }
    }

    struct IPv6CIDR: Codable, Hashable {
        var address: IPv6Addr
        var networkLength: Int

        enum CodingKeys: String, CodingKey {
            case address
            case networkLength = "network_length"
        }
        
        var description: String {
            return "\(address.description)/\(networkLength)"
        }
    }

    struct Url: Codable, Hashable {
        var url: String
    }

    struct MyNodeInfo: Codable {
        struct IPList: Codable {
            var publicIPv4: IPv4Addr?
            var interfaceIPv4s: [IPv4Addr]?
            var publicIPv6: IPv6Addr?
            var interfaceIPv6s: [IPv6Addr]?
            var listeners: [Url]?

            enum CodingKeys: String, CodingKey {
                case publicIPv4 = "public_ipv4"
                case interfaceIPv4s = "interface_ipv4s"
                case publicIPv6 = "public_ipv6"
                case interfaceIPv6s = "interface_ipv6s"
                case listeners
            }
        }
        var virtualIPv4: IPv4CIDR?
        var hostname: String
        var version: String
        var ips: IPList?
        var stunInfo: STUNInfo?
        var listeners: [Url]? = nil
        var vpnPortalCfg: String?
        var peerID: Int?

        enum CodingKeys: String, CodingKey {
            case virtualIPv4 = "virtual_ipv4"
            case hostname, version
            case ips
            case stunInfo = "stun_info"
            case listeners
            case vpnPortalCfg = "vpn_portal_cfg"
            case peerID = "peer_id"
        }
    }

    struct STUNInfo: Codable, Hashable {
        var udpNATType: NATType
        var tcpNATType: NATType
        var lastUpdateTime: TimeInterval
        var publicIPs: [String] = []
        var minPort: Int? = nil
        var maxPort: Int? = nil

        enum CodingKeys: String, CodingKey {
            case udpNATType = "udp_nat_type"
            case tcpNATType = "tcp_nat_type"
            case lastUpdateTime = "last_update_time"
            case publicIPs = "public_ip"
            case minPort = "min_port"
            case maxPort = "max_port"
        }
    }

    struct Route: Codable, Hashable, Identifiable {
        var id: Int { peerId }
        var peerId: Int
        var ipv4Addr: IPv4CIDR?
        var ipv6Addr: IPv6CIDR?
        var nextHopPeerId: Int
        var cost: Int
        var pathLatency: Int
        var proxyCIDRs: [String] = []
        var hostname: String
        var stunInfo: STUNInfo?
        var instId: String
        var version: String
        var nextHopPeerIdLatencyFirst: UInt?
        var costLatencyFirst: Int? = nil
        var pathLatencyLatencyFirst: Int? = nil
        var featureFlag: PeerFeatureFlag? = nil

        enum CodingKeys: String, CodingKey {
            case peerId = "peer_id"
            case ipv4Addr = "ipv4_addr"
            case ipv6Addr = "ipv6_addr"
            case nextHopPeerId = "next_hop_peer_id"
            case cost
            case pathLatency = "path_latency"
            case hostname, version
            case proxyCIDRs = "proxy_cidrs"
            case stunInfo = "stun_info"
            case instId = "inst_id"
            case nextHopPeerIdLatencyFirst = "next_hop_peer_id_latency_first"
            case costLatencyFirst = "cost_latency_first"
            case pathLatencyLatencyFirst = "path_latency_latency_first"
            case featureFlag = "feature_flag"
        }
    }

    struct PeerInfo: Codable, Hashable, Identifiable {
        var id: Int { peerId }
        var peerId: Int
        var conns: [PeerConnInfo]
        var defaultConnId: UUID? = nil
        var directlyConnectedConns: [UUID] = []

        enum CodingKeys: String, CodingKey {
            case peerId = "peer_id"
            case conns
            case defaultConnId = "default_conn_id"
            case directlyConnectedConns = "directly_connected_conns"
        }
    }

    struct PeerConnInfo: Codable, Hashable {
        var connId: String
        var myPeerId: Int
        var isClient: Bool
        var peerId: Int
        var features: [String]
        var tunnel: TunnelInfo?
        var stats: PeerConnStats?
        var lossRate: Double
        var networkName: String? = nil
        var isClosed: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case connId = "conn_id"
            case myPeerId = "my_peer_id"
            case isClient = "is_client"
            case peerId = "peer_id"
            case features, tunnel, stats
            case lossRate = "loss_rate"
            case networkName = "network_name"
            case isClosed = "is_closed"
        }
    }

    struct PeerRoutePair: Codable, Hashable, Identifiable {
        var id: Int { route.id }
        var route: Route
        var peer: PeerInfo?
    }

    struct TunnelInfo: Codable, Hashable {
        var tunnelType: String
        var localAddr: Url?
        var remoteAddr: Url?

        enum CodingKeys: String, CodingKey {
            case tunnelType = "tunnel_type"
            case localAddr = "local_addr"
            case remoteAddr = "remote_addr"
        }
    }

    struct PeerConnStats: Codable, Hashable {
        var rxBytes: Int
        var txBytes: Int
        var rxPackets: Int
        var txPackets: Int
        var latencyUs: Int

        enum CodingKeys: String, CodingKey {
            case rxBytes = "rx_bytes"
            case txBytes = "tx_bytes"
            case rxPackets = "rx_packets"
            case txPackets = "tx_packets"
            case latencyUs = "latency_us"
        }
    }

    var devName: String
    var myNodeInfo: MyNodeInfo?
    var events: [String]
    var routes: [Route]
    var peers: [PeerInfo]
    var peerRoutePairs: [PeerRoutePair]
    var running: Bool
    var errorMsg: String?

    enum CodingKeys: String, CodingKey {
        case devName = "dev_name"
        case myNodeInfo = "my_node_info"
        case events, routes, peers, running
        case peerRoutePairs = "peer_route_pairs"
        case errorMsg = "error_msg"
    }

    func sum(of keyPath: KeyPath<PeerConnStats, Int>) -> Int {
        peers
            .flatMap { $0.conns }
            .compactMap { $0.stats }
            .map { $0[keyPath: keyPath] }
            .reduce(0, +)
    }
}

extension NetworkStatus {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devName = try container.decodeIfPresent(String.self, forKey: .devName) ?? ""
        myNodeInfo = try container.decodeIfPresent(MyNodeInfo.self, forKey: .myNodeInfo)
        events = try container.decodeIfPresent([String].self, forKey: .events) ?? []
        routes = try container.decodeIfPresent([Route].self, forKey: .routes) ?? []
        peers = try container.decodeIfPresent([PeerInfo].self, forKey: .peers) ?? []
        peerRoutePairs = try container.decodeIfPresent([PeerRoutePair].self, forKey: .peerRoutePairs) ?? []
        running = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
        errorMsg = try container.decodeIfPresent(String.self, forKey: .errorMsg)
    }

}

// Protobuf JSON omits scalar fields whose value is the protobuf default. These
// decoders restore those defaults before exposing the snapshot to SwiftUI.
// Keep the existing numeric encoding while accepting the names emitted by pbjson.
extension NetworkStatus.NATType {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            switch name {
            case "Unknown": self = .unknown
            case "OpenInternet": self = .openInternet
            case "NoPAT": self = .noPAT
            case "FullCone": self = .fullCone
            case "Restricted": self = .restricted
            case "PortRestricted": self = .portRestricted
            case "Symmetric": self = .symmetric
            case "SymUdpFirewall": self = .symUDPFirewall
            case "SymmetricEasyInc": self = .symmetricEasyInc
            case "SymmetricEasyDec": self = .symmetricEasyDec
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown NAT type name")
            }
        } else {
            let rawValue = try container.decode(Int.self)
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown NAT type value")
            }
            self = value
        }
    }
}

// ProtoJSON represents 64-bit integers as decimal strings; older snapshots used numbers.
private struct ProtobufInteger<Value: FixedWidthInteger & Decodable>: Decodable {
    let value: Value

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            guard let value = Value(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid or out-of-range integer")
            }
            self.value = value
        } else {
            value = try container.decode(Value.self)
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeCounter(forKey key: Key) throws -> Int {
        let value = try decodeIfPresent(ProtobufInteger<UInt64>.self, forKey: key)?.value ?? 0
        guard let counter = Int(exactly: value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Counter exceeds Int range")
        }
        return counter
    }
}

extension NetworkStatus.UUID {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        part1 = try container.decodeIfPresent(UInt32.self, forKey: .part1) ?? 0
        part2 = try container.decodeIfPresent(UInt32.self, forKey: .part2) ?? 0
        part3 = try container.decodeIfPresent(UInt32.self, forKey: .part3) ?? 0
        part4 = try container.decodeIfPresent(UInt32.self, forKey: .part4) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case part1, part2, part3, part4 }
}

extension NetworkStatus.PeerFeatureFlag {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isPublicServer = try container.decodeIfPresent(Bool.self, forKey: .isPublicServer) ?? false
        avoidRelayData = try container.decodeIfPresent(Bool.self, forKey: .avoidRelayData) ?? false
        kcpInput = try container.decodeIfPresent(Bool.self, forKey: .kcpInput) ?? false
        noRelayKcp = try container.decodeIfPresent(Bool.self, forKey: .noRelayKcp) ?? false
        supportConnListSync = try container.decodeIfPresent(Bool.self, forKey: .supportConnListSync) ?? false
        quicInput = try container.decodeIfPresent(Bool.self, forKey: .quicInput) ?? false
        noRelayQuic = try container.decodeIfPresent(Bool.self, forKey: .noRelayQuic) ?? false
    }
}

extension NetworkStatus.IPv4Addr {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addr = try container.decodeIfPresent(UInt32.self, forKey: .addr) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case addr }
}

extension NetworkStatus.IPv4CIDR {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(NetworkStatus.IPv4Addr.self, forKey: .address)
        networkLength = try container.decodeIfPresent(Int.self, forKey: .networkLength) ?? 0
    }
}

extension NetworkStatus.IPv6Addr {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        part1 = try container.decodeIfPresent(UInt32.self, forKey: .part1) ?? 0
        part2 = try container.decodeIfPresent(UInt32.self, forKey: .part2) ?? 0
        part3 = try container.decodeIfPresent(UInt32.self, forKey: .part3) ?? 0
        part4 = try container.decodeIfPresent(UInt32.self, forKey: .part4) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case part1, part2, part3, part4 }
}

extension NetworkStatus.IPv6CIDR {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(NetworkStatus.IPv6Addr.self, forKey: .address)
        networkLength = try container.decodeIfPresent(Int.self, forKey: .networkLength) ?? 0
    }
}

extension NetworkStatus.Url {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
    }

    private enum CodingKeys: String, CodingKey { case url }
}

extension NetworkStatus.MyNodeInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        virtualIPv4 = try container.decodeIfPresent(NetworkStatus.IPv4CIDR.self, forKey: .virtualIPv4)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        ips = try container.decodeIfPresent(IPList.self, forKey: .ips)
        stunInfo = try container.decodeIfPresent(NetworkStatus.STUNInfo.self, forKey: .stunInfo)
        listeners = try container.decodeIfPresent([NetworkStatus.Url].self, forKey: .listeners)
        vpnPortalCfg = try container.decodeIfPresent(String.self, forKey: .vpnPortalCfg)
        peerID = try container.decodeIfPresent(Int.self, forKey: .peerID)
    }
}

extension NetworkStatus.STUNInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        udpNATType = try container.decodeIfPresent(NetworkStatus.NATType.self, forKey: .udpNATType) ?? .unknown
        tcpNATType = try container.decodeIfPresent(NetworkStatus.NATType.self, forKey: .tcpNATType) ?? .unknown
        lastUpdateTime = TimeInterval(try container.decodeIfPresent(ProtobufInteger<Int64>.self, forKey: .lastUpdateTime)?.value ?? 0)
        publicIPs = try container.decodeIfPresent([String].self, forKey: .publicIPs) ?? []
        minPort = try container.decodeIfPresent(Int.self, forKey: .minPort)
        maxPort = try container.decodeIfPresent(Int.self, forKey: .maxPort)
    }
}

extension NetworkStatus.Route {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try container.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
        ipv4Addr = try container.decodeIfPresent(NetworkStatus.IPv4CIDR.self, forKey: .ipv4Addr)
        ipv6Addr = try container.decodeIfPresent(NetworkStatus.IPv6CIDR.self, forKey: .ipv6Addr)
        nextHopPeerId = try container.decodeIfPresent(Int.self, forKey: .nextHopPeerId) ?? 0
        cost = try container.decodeIfPresent(Int.self, forKey: .cost) ?? 0
        pathLatency = try container.decodeIfPresent(Int.self, forKey: .pathLatency) ?? 0
        proxyCIDRs = try container.decodeIfPresent([String].self, forKey: .proxyCIDRs) ?? []
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname) ?? ""
        stunInfo = try container.decodeIfPresent(NetworkStatus.STUNInfo.self, forKey: .stunInfo)
        instId = try container.decodeIfPresent(String.self, forKey: .instId) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        nextHopPeerIdLatencyFirst = try container.decodeIfPresent(UInt.self, forKey: .nextHopPeerIdLatencyFirst)
        costLatencyFirst = try container.decodeIfPresent(Int.self, forKey: .costLatencyFirst)
        pathLatencyLatencyFirst = try container.decodeIfPresent(Int.self, forKey: .pathLatencyLatencyFirst)
        featureFlag = try container.decodeIfPresent(NetworkStatus.PeerFeatureFlag.self, forKey: .featureFlag)
    }
}

extension NetworkStatus.PeerInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        peerId = try container.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
        conns = try container.decodeIfPresent([NetworkStatus.PeerConnInfo].self, forKey: .conns) ?? []
        defaultConnId = try container.decodeIfPresent(NetworkStatus.UUID.self, forKey: .defaultConnId)
        directlyConnectedConns = try container.decodeIfPresent([NetworkStatus.UUID].self, forKey: .directlyConnectedConns) ?? []
    }
}

extension NetworkStatus.PeerConnInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connId = try container.decodeIfPresent(String.self, forKey: .connId) ?? ""
        myPeerId = try container.decodeIfPresent(Int.self, forKey: .myPeerId) ?? 0
        isClient = try container.decodeIfPresent(Bool.self, forKey: .isClient) ?? false
        peerId = try container.decodeIfPresent(Int.self, forKey: .peerId) ?? 0
        features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
        tunnel = try container.decodeIfPresent(NetworkStatus.TunnelInfo.self, forKey: .tunnel)
        stats = try container.decodeIfPresent(NetworkStatus.PeerConnStats.self, forKey: .stats)
        lossRate = try container.decodeIfPresent(Double.self, forKey: .lossRate) ?? 0
        networkName = try container.decodeIfPresent(String.self, forKey: .networkName)
        isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed)
    }
}

extension NetworkStatus.TunnelInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tunnelType = try container.decodeIfPresent(String.self, forKey: .tunnelType) ?? ""
        localAddr = try container.decodeIfPresent(NetworkStatus.Url.self, forKey: .localAddr)
        remoteAddr = try container.decodeIfPresent(NetworkStatus.Url.self, forKey: .remoteAddr)
    }
}

extension NetworkStatus.PeerConnStats {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rxBytes = try container.decodeCounter(forKey: .rxBytes)
        txBytes = try container.decodeCounter(forKey: .txBytes)
        rxPackets = try container.decodeCounter(forKey: .rxPackets)
        txPackets = try container.decodeCounter(forKey: .txPackets)
        latencyUs = try container.decodeCounter(forKey: .latencyUs)
    }
}
