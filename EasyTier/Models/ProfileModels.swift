import Foundation
import SwiftData

struct BoolFlag: Identifiable {
    let id = UUID()
    let keyPath: WritableKeyPath<NetworkProfile, Bool>
    let label: String
    let help: String?
}

@Model
final class ProfileSummary {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade) var profile: NetworkProfile
    
    convenience init(name: String, context: ModelContext) {
        self.init(id: UUID(), name: name)
        context.insert(self)
    }
    
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        let profile = NetworkProfile(id: id)
        self.profile = profile
    }
}

@Model
final class NetworkProfile {
    enum NetworkingMethod: Int, Codable, CaseIterable, Identifiable, CustomStringConvertible {
        var id: Self { self }
        case publicServer = 0
        case manual = 1
        case standalone = 2
        
        var description: String {
            switch self {
            case .publicServer: return "Public Server"
            case .manual: return "Manual"
            case .standalone: return "Standalone"
            }
        }
    }

    struct PortForwardSetting: Codable, Hashable, Identifiable {
        var id = UUID()
        var bindAddr: String = ""
        var bindPort: Int = 0
        var destAddr: String = ""
        var destPort: Int = 0
        var proto: String = "tcp"
        
        private enum CodingKeys: String, CodingKey {
            case bindAddr, bindPort, destAddr, destPort, proto
        }
    }

    nonisolated
    struct CIDR: Codable, Hashable {
        var ip: String
        var length: String
        
        var cidrString: String {
            "\(ip)/\(length)"
        }
        
        private enum CodingKeys: String, CodingKey {
            case ip, length
        }
    }

    struct ProxyCIDR: Codable, Hashable, Identifiable {
        var id = UUID()
        var cidr: String = "0.0.0.0"
        var enableMapping: Bool = false
        var mappedCIDR: String = "0.0.0.0"
        var length: String = "32"
        
        private enum CodingKeys: String, CodingKey {
            case cidr, enableMapping, mappedCIDR, length
        }
    }
    
    @Attribute(.unique) var id: UUID

    var dhcp: Bool = true
    var virtualIPv4: CIDR = CIDR(ip: "10.144.144.0", length: "24")
    var hostname: String? = nil
    var networkName: String = "default"
    var networkSecret: String = ""

    var networkingMethod: NetworkingMethod = NetworkingMethod.publicServer

    var publicServerURL: String = "tcp://public.easytier.top:11010"
    var peerURLs: [String] = []

    var proxyCIDRs: [ProxyCIDR] = []

    var enableVPNPortal: Bool = false
    var vpnPortalListenPort: Int = 22022
    var vpnPortalClientCIDR: CIDR = CIDR(ip: "10.144.144.0", length: "24")

    var listenerURLs: [String] = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010", "wg://0.0.0.0:11011"]
    var latencyFirst: Bool = false

    var useSmoltcp: Bool = false
    var disableIPv6: Bool = false
    var enableKCPProxy: Bool = false
    var disableKCPInput: Bool = false
    var enableQUICProxy: Bool = false
    var disableQUICInput: Bool = false
    var disableP2P: Bool = false
    var p2pOnly: Bool = false
    var bindDevice: Bool = false
    var noTUN: Bool = false
    var enableExitNode: Bool = false
    var relayAllPeerRPC: Bool = false
    var multiThread: Bool = false
    var proxyForwardBySystem: Bool = false
    var disableEncryption: Bool = false
    var disableUDPHolePunching: Bool = false
    var disableSymHolePunching: Bool = false

    var enableRelayNetworkWhitelist: Bool = false
    var relayNetworkWhitelist: [String] = []

    var enableManualRoutes: Bool = false
    var routes: [String] = []
    
    var portForwards: [PortForwardSetting] = []

    var exitNodes: [String] = []

    var enableSocks5: Bool = false
    var socks5Port: Int = 1080

    var mtu: UInt32? = nil
    var mappedListeners: [String] = []

    var enableMagicDNS: Bool = false
    var enablePrivateMode: Bool = false

    init(id: UUID) {
        self.id = id
    }
    
    static let boolFlags: [BoolFlag] = [
        .init(
            keyPath: \.latencyFirst,
            label: "Latency-First Mode",
            help:
                "Ignore hop count and select the path with the lowest total latency."
        ),
        .init(
            keyPath: \.useSmoltcp,
            label: "Use User-Space Protocol Stack",
            help:
                "Use a user-space TCP/IP stack to avoid issues with OS firewalls."
        ),
        .init(
            keyPath: \.disableIPv6,
            label: "Disable IPv6",
            help: "Disable IPv6 functionality for this node."
        ),
        .init(
            keyPath: \.enableKCPProxy,
            label: "Enable KCP Proxy",
            help: "Convert TCP traffic to KCP to reduce latency."
        ),
        .init(
            keyPath: \.disableKCPInput,
            label: "Disable KCP Input",
            help: "Disable inbound KCP traffic."
        ),
        .init(
            keyPath: \.enableQUICProxy,
            label: "Enable QUIC Proxy",
            help: "Convert TCP traffic to QUIC to reduce latency."
        ),
        .init(
            keyPath: \.disableQUICInput,
            label: "Disable QUIC Input",
            help: "Disable inbound QUIC traffic."
        ),
        .init(
            keyPath: \.disableP2P,
            label: "Disable P2P",
            help: "Route all traffic through a manually specified relay server."
        ),
        .init(
            keyPath: \.p2pOnly,
            label: "P2P Only",
            help:
                "Only communicate with peers that have established P2P connections."
        ),
        .init(
            keyPath: \.bindDevice,
            label: "Bind to Physical Device Only",
            help: "Use only the physical network interface."
        ),
        .init(
            keyPath: \.noTUN,
            label: "No TUN Mode",
            help:
                "Do not use a TUN interface. This node will be accessible but cannot initiate connections to others without SOCKS5."
        ),
        .init(
            keyPath: \.enableExitNode,
            label: "Enable Exit Node",
            help: "Allow this node to be an exit node."
        ),
        .init(
            keyPath: \.relayAllPeerRPC,
            label: "Relay All Peer RPC",
            help:
                "Relay all peer RPC packets, even for peers not in the whitelist."
        ),
        .init(
            keyPath: \.multiThread,
            label: "Multi-Threaded Runtime",
            help: "Use a multi-thread runtime for performance."
        ),
        .init(
            keyPath: \.proxyForwardBySystem,
            label: "System Forwarding for Proxy",
            help: "Forward packets to proxy networks via the system kernel."
        ),
        .init(
            keyPath: \.disableEncryption,
            label: "Disable Encryption",
            help:
                "Disable encryption for peer communication. Must be the same on all peers."
        ),
        .init(
            keyPath: \.disableUDPHolePunching,
            label: "Disable UDP Hole Punching",
            help: "Disable the UDP hole punching mechanism."
        ),
        .init(
            keyPath: \.disableSymHolePunching,
            label: "Disable Symmetric NAT Hole Punching",
            help: "Disable special handling for symmetric NATs."
        ),
        .init(
            keyPath: \.enableMagicDNS,
            label: "Enable Magic DNS",
            help:
                "Access nodes in the network by their hostname via a special DNS."
        ),
        .init(
            keyPath: \.enablePrivateMode,
            label: "Enable Private Mode",
            help:
                "Do not allow handshake or relay for nodes with a different network name or secret."
        ),
    ]
}
