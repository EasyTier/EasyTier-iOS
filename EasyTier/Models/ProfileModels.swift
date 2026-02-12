import Foundation
import SwiftUI

struct BoolFlag: Identifiable {
    let id = UUID()
    let keyPath: WritableKeyPath<NetworkProfile, Bool>
    let label: LocalizedStringKey
    let help: LocalizedStringKey?
}

nonisolated let defaultServerURL: String = "tcp://public.easytier.top:11010"

nonisolated struct NetworkProfile: Identifiable, Equatable {
    enum NetworkingMethod: Int, Codable, CaseIterable, Identifiable {
        var id: Self { self }
        case defaultServer = 0
        case custom = 1
        case standalone = 2
        
        var description: LocalizedStringKey {
            switch self {
            case .defaultServer: return "default_server"
            case .custom: return "custom"
            case .standalone: return "standalone"
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
    }

    struct CIDR: Codable, Hashable, Identifiable {
        var id = UUID()
        var ip: String = ""
        var length: String = ""
        
        var cidrString: String {
            if ip.isEmpty && length.isEmpty {
                ""
            } else {
                "\(ip)/\(length)"
            }
        }
    }

    struct ProxyCIDR: Codable, Hashable, Identifiable {
        var id = UUID()
        var cidr: String = ""
        var enableMapping: Bool = false
        var mappedCIDR: String = ""
        var length: String = ""
        
        var cidrString: String {
            if cidr.isEmpty || length.isEmpty {
                ""
            } else {
                "\(cidr)/\(length)"
            }
        }
        
        var mappedCIDRString: String {
            if mappedCIDR.isEmpty && length.isEmpty {
                ""
            } else {
                "\(mappedCIDR)/\(length)"
            }
        }
    }
    
    var id: UUID
    var networkName: String = "easytier"
    var dhcp: Bool = true
    var virtualIPv4: CIDR = CIDR(ip: "10.126.126.1", length: "24")
    var hostname: String = ""
    var networkSecret: String = ""

    var networkingMethod: NetworkingMethod = NetworkingMethod.defaultServer
    var peerURLs: [TextItem] = []

    var proxyCIDRs: [ProxyCIDR] = []

    var enableVPNPortal: Bool = false
    var vpnPortalListenPort: Int = 22022
    var vpnPortalClientCIDR: CIDR = CIDR(ip: "10.126.126.0", length: "24")

    var listenerURLs: [TextItem] = []
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
    var enableDataCompression: Bool = false

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
    var magicDNSTLD: String = "et.net."
    
    var enablePrivateMode: Bool = false
    var enableOverrideDNS: Bool = false
    var overrideDNS: [TextItem] = []
    
    var baseConfig: AlwaysEqual<NetworkConfig?> = .init(nil)

    init(id: UUID = UUID()) {
        self.id = id
    }
    
    init(from config: NetworkConfig) {
        let id = UUID(uuidString: config.instanceId) ?? UUID()
        var profile = NetworkProfile(id: id)
        profile.baseConfig = .init(config)
        
        if let hostname = config.hostname, !hostname.isEmpty {
            profile.hostname = hostname
        }
        profile.networkName = config.networkIdentity?.networkName ?? ""
        profile.networkSecret = config.networkIdentity?.networkSecret ?? ""

        if let dhcp = config.dhcp {
            profile.dhcp = dhcp
        }
        if let ipv4 = config.ipv4 {
            let parsed = NetworkConfig.splitCIDR(ipv4, defaultLength: profile.virtualIPv4.length)
            profile.virtualIPv4 = .init(ip: parsed.ip, length: parsed.length)
            profile.dhcp = false
        }

        if let peer = config.peer, !peer.isEmpty {
            if peer.count == 1 && peer[0].uri == defaultServerURL {  // future: public server list
                profile.networkingMethod = .defaultServer
            } else {
                profile.networkingMethod = .custom
                profile.peerURLs = peer.map { .init($0.uri) }
            }
        } else {
            profile.networkingMethod = .standalone
        }

        if let listeners = config.listeners {
            profile.listenerURLs = listeners.map { .init($0) }
        } else {
            profile.listenerURLs = []
        }

        if let proxyNetwork = config.proxyNetwork, !proxyNetwork.isEmpty {
            profile.proxyCIDRs = proxyNetwork.map { item in
                let parsed = NetworkConfig.splitCIDR(item.cidr, defaultLength: "32")
                var entry = NetworkProfile.ProxyCIDR(
                    cidr: parsed.ip,
                    enableMapping: false,
                    mappedCIDR: "",
                    length: parsed.length
                )
                if let mappedCIDR = item.mappedCIDR, !mappedCIDR.isEmpty {
                    let mapped = NetworkConfig.splitCIDR(mappedCIDR, defaultLength: parsed.length)
                    entry.enableMapping = true
                    entry.mappedCIDR = mapped.ip
                    entry.length = mapped.length
                }
                return entry
            }
        }

        if let portForward = config.portForward, !portForward.isEmpty {
            profile.portForwards = portForward.compactMap { item in
                let bind = NetworkConfig.splitHostPort(item.bindAddr)
                let dest = NetworkConfig.splitHostPort(item.dstAddr)
                guard let bindPort = bind.port, let destPort = dest.port else {
                    return nil
                }
                return NetworkProfile.PortForwardSetting(
                    bindAddr: bind.host,
                    bindPort: bindPort,
                    destAddr: dest.host,
                    destPort: destPort,
                    proto: item.proto
                )
            }
        }

        if let vpnPortalConfig = config.vpnPortalConfig {
            profile.enableVPNPortal = true
            let parsed = NetworkConfig.splitCIDR(vpnPortalConfig.clientCIDR, defaultLength: profile.vpnPortalClientCIDR.length)
            profile.vpnPortalClientCIDR = .init(ip: parsed.ip, length: parsed.length)
            if let port = NetworkConfig.splitHostPort(vpnPortalConfig.wireguardListen).port {
                profile.vpnPortalListenPort = port
            }
        }

        if let routes = config.routes {
            profile.enableManualRoutes = true
            profile.routes = routes.map { item in
                let parsed = NetworkConfig.splitCIDR(item, defaultLength: "32")
                return .init(ip: parsed.ip, length: parsed.length)
            }
        }

        if let overrideDNS = config.overrideDNS {
            profile.enableOverrideDNS = true
            profile.overrideDNS = overrideDNS.map { .init($0) }
        }

        if let exitNodes = config.exitNodes {
            profile.exitNodes = exitNodes.map { .init($0) }
        }

        if let socks5Proxy = config.socks5Proxy, let port = NetworkConfig.parseSocks5Port(socks5Proxy) {
            profile.enableSocks5 = true
            profile.socks5Port = port
        }

        if let mappedListeners = config.mappedListeners {
            profile.mappedListeners = mappedListeners.map { .init($0) }
        }

        if let flags = config.flags {
            if let mtu = flags.mtu {
                profile.mtu = mtu
            }
            if let latencyFirst = flags.latencyFirst {
                profile.latencyFirst = latencyFirst
            }
            if let enableExitNode = flags.enableExitNode {
                profile.enableExitNode = enableExitNode
            }
            if let noTUN = flags.noTUN {
                profile.noTUN = noTUN
            }
            if let useSmoltcp = flags.useSmoltcp {
                profile.useSmoltcp = useSmoltcp
            }
            if let disableP2P = flags.disableP2P {
                profile.disableP2P = disableP2P
            }
            if let relayAllPeerRPC = flags.relayAllPeerRPC {
                profile.relayAllPeerRPC = relayAllPeerRPC
            }
            if let disableUDPHolePunching = flags.disableUDPHolePunching {
                profile.disableUDPHolePunching = disableUDPHolePunching
            }
            if let multiThread = flags.multiThread {
                profile.multiThread = multiThread
            }
            if let bindDevice = flags.bindDevice {
                profile.bindDevice = bindDevice
            }
            if let enableKCPProxy = flags.enableKCPProxy {
                profile.enableKCPProxy = enableKCPProxy
            }
            if let disableKCPInput = flags.disableKCPInput {
                profile.disableKCPInput = disableKCPInput
            }
            if let proxyForwardBySystem = flags.proxyForwardBySystem {
                profile.proxyForwardBySystem = proxyForwardBySystem
            }
            if let enableQUICProxy = flags.enableQUICProxy {
                profile.enableQUICProxy = enableQUICProxy
            }
            if let disableQUICInput = flags.disableQUICInput {
                profile.disableQUICInput = disableQUICInput
            }
            if let disableSymHolePunching = flags.disableSymHolePunching {
                profile.disableSymHolePunching = disableSymHolePunching
            }
            if let p2pOnly = flags.p2pOnly {
                profile.p2pOnly = p2pOnly
            }
            if let enableIPv6 = flags.enableIPv6 {
                profile.disableIPv6 = !enableIPv6
            }
            if let enableEncryption = flags.enableEncryption {
                profile.disableEncryption = !enableEncryption
            }
            if let relayNetworkWhitelist = flags.relayNetworkWhitelist {
                let items = relayNetworkWhitelist
                    .split { $0 == " " || $0 == "\n" || $0 == "\t" }
                    .map { String($0) }
                profile.enableRelayNetworkWhitelist = !items.isEmpty
                profile.relayNetworkWhitelist = items.map { .init($0) }
            }
            if let acceptDNS = flags.acceptDNS {
                profile.enableMagicDNS = acceptDNS
            }
            if let tldDNSZone = flags.tldDNSZone {
                profile.magicDNSTLD = tldDNSZone
            }
            if let privateMode = flags.privateMode {
                profile.enablePrivateMode = privateMode
            }
            if let dataCompressAlgo = flags.dataCompressAlgo {
                profile.enableDataCompression = dataCompressAlgo == 2
            }
        }
        self = profile
    }
    
    func toConfig() -> NetworkConfig {
        var config = self.baseConfig.value ?? .init(id: id, name: networkName)
        config.apply(from: self)
        return config
    }
    
    @MainActor static let boolFlags: [BoolFlag] = [
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
            keyPath: \.enablePrivateMode,
            label: "enable_private_mode",
            help: "enable_private_mode_help"
        ),
        .init(
            keyPath: \.enableDataCompression,
            label: "enable_data_compression",
            help: "enable_data_compression_help"
        ),  
    ]
}

nonisolated struct AlwaysEqual<T>: Equatable {
    var value: T
    
    static func == (lhs: AlwaysEqual<T>, rhs: AlwaysEqual<T>) -> Bool {
        true
    }
    
    init(_ value: T) {
        self.value = value
    }
}
