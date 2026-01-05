import Foundation

struct NetworkStatus: Codable {
    enum NATType: Int, Codable, CustomStringConvertible {
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

        var description: String {
            switch self {
            case .unknown: "Unknown"
            case .openInternet: "Open Internet"
            case .noPAT: "No PAT"
            case .fullCone: "Full Cone"
            case .restricted: "Restricted"
            case .portRestricted: "PortRestricted"
            case .symmetric: "Symmetric"
            case .symUDPFirewall: "Symmetric UDP Firewall"
            case .symmetricEasyInc: "Symmetric Easy Inc"
            case .symmetricEasyDec: "Symmetric Easy Dec"
            }
        }
    }

    struct IPv4Addr: Codable, Hashable, CustomStringConvertible {
        var addr: UInt32

        static func fromString(_ s: String) -> IPv4Addr? {
            let components = s.split(separator: ".").compactMap { UInt32($0) }
            guard components.count == 4 else { return nil }
            let addr =
                (components[0] << 24) | (components[1] << 16)
                | (components[2] << 8) | components[3]
            return IPv4Addr(addr: addr)
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

    struct IPv6Addr: Codable, Hashable {
        var part1: UInt32
        var part2: UInt32
        var part3: UInt32
        var part4: UInt32
    }

    struct Url: Codable, Hashable {
        var url: String
    }

    struct NodeInfo: Codable {
        struct IPs: Codable {
            var publicIPv4: IPv4Addr?
            var interfaceIPv4s: [IPv4Addr]
            var publicIPv6: IPv6Addr?
            var interfaceIPv6s: [IPv6Addr]

            enum CodingKeys: String, CodingKey {
                case publicIPv4 = "public_ipv4"
                case interfaceIPv4s = "interface_ipv4s"
                case publicIPv6 = "public_ipv6"
                case interfaceIPv6s = "interface_ipv6s"
            }
        }
        var virtualIPv4: IPv4CIDR?
        var hostname: String
        var version: String
        var ips: IPs?
        var stunInfo: STUNInfo?
        var listeners: [Url]
        var vpnPortalCfg: String?

        enum CodingKeys: String, CodingKey {
            case virtualIPv4 = "virtual_ipv4"
            case hostname, version, ips, listeners
            case stunInfo = "stun_info"
            case vpnPortalCfg = "vpn_portal_cfg"
        }
    }

    struct STUNInfo: Codable, Hashable {
        var udpNATType: NATType
        var tcpNATType: NATType
        var lastUpdateTime: TimeInterval

        enum CodingKeys: String, CodingKey {
            case udpNATType = "udp_nat_type"
            case tcpNATType = "tcp_nat_type"
            case lastUpdateTime = "last_update_time"
        }
    }

    struct Route: Codable, Hashable, Identifiable {
        var id: Int { peerId }
        var peerId: Int
        var ipv4Addr: IPv4CIDR?
        var nextHopPeerId: Int
        var cost: Int
        var proxyCIDRs: [String]
        var hostname: String
        var stunInfo: STUNInfo?
        var instId: String
        var version: String

        enum CodingKeys: String, CodingKey {
            case peerId = "peer_id"
            case ipv4Addr = "ipv4_addr"
            case nextHopPeerId = "next_hop_peer_id"
            case cost, hostname, version
            case proxyCIDRs = "proxy_cidrs"
            case stunInfo = "stun_info"
            case instId = "inst_id"
        }
    }

    struct PeerInfo: Codable, Hashable, Identifiable {
        var id: Int { peerId }
        var peerId: Int
        var conns: [PeerConnInfo]

        enum CodingKeys: String, CodingKey {
            case peerId = "peer_id"
            case conns
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

        enum CodingKeys: String, CodingKey {
            case connId = "conn_id"
            case myPeerId = "my_peer_id"
            case isClient = "is_client"
            case peerId = "peer_id"
            case features, tunnel, stats
            case lossRate = "loss_rate"
        }
    }

    struct PeerRoutePair: Codable, Hashable, Identifiable {
        var id: Int { route.id }
        var route: Route
        var peer: PeerInfo?
    }

    struct TunnelInfo: Codable, Hashable {
        var tunnelType: String
        var localAddr: Url
        var remoteAddr: Url

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
    var myNodeInfo: NodeInfo?
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
