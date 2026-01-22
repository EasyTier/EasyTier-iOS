import Foundation
import SwiftUI

struct BoolFlag: Identifiable {
    let id = UUID()
    let keyPath: WritableKeyPath<NetworkProfile, Bool>
    let label: LocalizedStringKey
    let help: LocalizedStringKey?
}

struct NetworkProfile: Identifiable, Equatable {
    enum NetworkingMethod: Int, Codable, CaseIterable, Identifiable {
        var id: Self { self }
        case publicServer = 0
        case manual = 1
        case standalone = 2
        
        var description: LocalizedStringKey {
            switch self {
            case .publicServer: return "public_server"
            case .manual: return "manual"
            case .standalone: return "standalone"
            }
        }
    }

    nonisolated struct PortForwardSetting: Codable, Hashable, Identifiable {
        var id = UUID()
        var bindAddr: String = ""
        var bindPort: Int = 0
        var destAddr: String = ""
        var destPort: Int = 0
        var proto: String = "tcp"
    }

    nonisolated struct CIDR: Codable, Hashable, Identifiable {
        var id = UUID()
        var ip: String = "0.0.0.0"
        var length: String = "32"
        
        var cidrString: String {
            "\(ip)/\(length)"
        }
    }

    nonisolated struct ProxyCIDR: Codable, Hashable, Identifiable {
        var id = UUID()
        var cidr: String = "0.0.0.0"
        var enableMapping: Bool = false
        var mappedCIDR: String = "0.0.0.0"
        var length: String = "32"
    }
    
    var id: UUID
    var networkName: String = "easytier"
    var dhcp: Bool = true
    var virtualIPv4: CIDR = CIDR(ip: "10.126.126.1", length: "24")
    var hostname: String = ""
    var networkSecret: String = ""

    var networkingMethod: NetworkingMethod = NetworkingMethod.publicServer

    var publicServerURL: String = "tcp://public.easytier.top:11010"
    var peerURLs: [TextItem] = []

    var proxyCIDRs: [ProxyCIDR] = []

    var enableVPNPortal: Bool = false
    var vpnPortalListenPort: Int = 22022
    var vpnPortalClientCIDR: CIDR = CIDR(ip: "10.126.126.0", length: "24")

    var listenerURLs: [TextItem] = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010", "wg://0.0.0.0:11011"]
    var latencyFirst: Bool = false

    var useSmoltcp: Bool = false
    var disableIPv6: Bool = false
    var enableKCPProxy: Bool = false
    var disableKCPInput: Bool = false
    var enableQUICProxy: Bool = false
    var disableQUICInput: Bool = false
    var disableP2P: Bool = false
    var p2pOnly: Bool = false
    var bindDevice: Bool = true
    var noTUN: Bool = false
    var enableExitNode: Bool = false
    var relayAllPeerRPC: Bool = false
    var multiThread: Bool = true
    var proxyForwardBySystem: Bool = false
    var disableEncryption: Bool = false
    var disableUDPHolePunching: Bool = false
    var disableSymHolePunching: Bool = false

    var enableRelayNetworkWhitelist: Bool = false
    var relayNetworkWhitelist: [TextItem] = []

    var enableManualRoutes: Bool = false
    var routes: [CIDR] = []
    
    var portForwards: [PortForwardSetting] = []

    var exitNodes: [TextItem] = []

    var enableSocks5: Bool = false
    var socks5Port: Int = 1080

    var mtu: Int? = nil
    var mappedListeners: [TextItem] = []

    var enableMagicDNS: Bool = false
    var enablePrivateMode: Bool = false
    var enableOverrideDNS: Bool = false
    var overrideDNS: [TextItem] = []

    init(id: UUID = UUID()) {
        self.id = id
    }
    
    static let boolFlags: [BoolFlag] = [
        .init(
            keyPath: \.latencyFirst,
            label: "use_latency_first",
            help: "latency_first_help"
        ),
        .init(
            keyPath: \.useSmoltcp,
            label: "use_smoltcp",
            help: "use_smoltcp_help"
        ),
        .init(
            keyPath: \.disableIPv6,
            label: "disable_ipv6",
            help: "disable_ipv6_help"
        ),
        .init(
            keyPath: \.enableKCPProxy,
            label: "enable_kcp_proxy",
            help: "enable_kcp_proxy_help"
        ),
        .init(
            keyPath: \.disableKCPInput,
            label: "disable_kcp_input",
            help: "disable_kcp_input_help"
        ),
        .init(
            keyPath: \.enableQUICProxy,
            label: "enable_quic_proxy",
            help: "enable_quic_proxy_help"
        ),
        .init(
            keyPath: \.disableQUICInput,
            label: "disable_quic_input",
            help: "disable_quic_input_help"
        ),
        .init(
            keyPath: \.disableP2P,
            label: "disable_p2p",
            help: "disable_p2p_help"
        ),
        .init(
            keyPath: \.p2pOnly,
            label: "p2p_only",
            help: "p2p_only_help"
        ),
        .init(
            keyPath: \.bindDevice,
            label: "bind_device",
            help: "bind_device_help"
        ),
        .init(
            keyPath: \.noTUN,
            label: "no_tun",
            help: "no_tun_help"
        ),
        .init(
            keyPath: \.enableExitNode,
            label: "enable_exit_node",
            help: "enable_exit_node_help"
        ),
        .init(
            keyPath: \.relayAllPeerRPC,
            label: "relay_all_peer_rpc",
            help: "relay_all_peer_rpc_help"
        ),
        .init(
            keyPath: \.multiThread,
            label: "multi_thread",
            help: "multi_thread_help"
        ),
        .init(
            keyPath: \.proxyForwardBySystem,
            label: "proxy_forward_by_system",
            help: "proxy_forward_by_system_help"
        ),
        .init(
            keyPath: \.disableEncryption,
            label: "disable_encryption",
            help: "disable_encryption_help"
        ),
        .init(
            keyPath: \.disableUDPHolePunching,
            label: "disable_udp_hole_punching",
            help: "disable_udp_hole_punching_help"
        ),
        .init(
            keyPath: \.disableSymHolePunching,
            label: "disable_sym_hole_punching",
            help: "disable_sym_hole_punching_help"
        ),
        .init(
            keyPath: \.enableMagicDNS,
            label: "enable_magic_dns",
            help: "enable_magic_dns_help"
        ),
        .init(
            keyPath: \.enablePrivateMode,
            label: "enable_private_mode",
            help: "enable_private_mode_help"
        ),
    ]
}
