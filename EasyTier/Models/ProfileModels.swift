import Foundation
import SwiftData

enum NetworkingMethod: Int, Codable, CaseIterable, Identifiable {
    var id: Self { self }
    case publicServer = 0
    case manual = 1
    case standalone = 2
}

struct PortForwardSetting: Codable, Hashable, Identifiable {
    var id = UUID()
    var bindIP: String = ""
    var bindPort: Int = 0
    var dstIP: String = ""
    var dstPort: Int = 0
    var proto: String = "tcp"
    
    private enum CodingKeys: String, CodingKey {
        case bindIP, bindPort, dstIP, dstPort, proto
    }
}

nonisolated
struct CIDR: Codable, Hashable {
    var ip: String
    var length: Int
    
    var cidrString: String {
        "\(ip)/\(length)"
    }
    
    private enum CodingKeys: String, CodingKey {
        case ip, length
    }
}

struct ProxyCIDR: Codable, Hashable {
    var from: String
    var to: String
    var length: Int
}

@Model
final class ProfileSummary {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade) var profile: NetworkProfile
    
    init(name: String, context: ModelContext) {
        let id = UUID()
        self.id = id
        self.name = name
        self.createdAt = Date()
        let profile = NetworkProfile(id: id)
        self.profile = profile
        context.insert(profile)
    }
}

@Model
final class NetworkProfile {
    @Attribute(.unique) var id: UUID

    var dhcp: Bool = true
    var virtualIPv4: CIDR = CIDR(ip: "10.144.144.0", length: 24)
    var hostname: String? = nil
    var networkName: String = "default"
    var networkSecret: String = ""

    var networkingMethod: NetworkingMethod = NetworkingMethod.publicServer

    var publicServerURL: String = "tcp://public.easytier.top:11010"
    var peerURLs: [String] = []

    var proxyCIDRs: [ProxyCIDR] = []

    var enableVPNPortal: Bool = false
    var vpnPortalListenPort: Int = 22022
    var vpnPortalClientCIDR: CIDR = CIDR(ip: "10.144.144.0", length: 24)

    var listenerURLs: [String] = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010", "wg://0.0.0.0:11011"]
    var latencyFirst: Bool = false

    var devName: String = "utun10"

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
}
