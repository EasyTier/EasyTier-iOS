import Foundation

nonisolated struct NetworkConfig: Codable {
    struct Flags: Codable, Equatable {
        var defaultProtocol: String?
        var devName: String?
        var enableEncryption: Bool?
        var enableIPv6: Bool?
        var mtu: Int?
        var latencyFirst: Bool?
        var enableExitNode: Bool?
        var noTUN: Bool?
        var useSmoltcp: Bool?
        var relayNetworkWhitelist: String?
        var disableP2P: Bool?
        var relayAllPeerRPC: Bool?
        var disableUDPHolePunching: Bool?
        var multiThread: Bool?
        
        // Invalid = 0, None = 1, Zstd = 2
        var dataCompressAlgo: Int?
        
        var bindDevice: Bool?
        var enableKCPProxy: Bool?
        var disableKCPInput: Bool?
        var disableRelayKCP: Bool?
        var proxyForwardBySystem: Bool?
        var acceptDNS: Bool?
        var privateMode: Bool?
        var enableQUICProxy: Bool?
        var disableQUICInput: Bool?
        var disableRelayQUIC: Bool?
        var quicListenPort: Int?
        var foreignRelayBpsLimit: UInt64?
        var multiThreadCount: Int?
        var enableRelayForeignNetworkKCP: Bool?
        var enableRelayForeignNetworkQUIC: Bool?
        var encryptionAlgorithm: String?
        var disableSymHolePunching: Bool?
        var tldDNSZone: String?
        var p2pOnly: Bool?
        var disableTCPHolePunching: Bool?

        enum CodingKeys: String, CodingKey {
            case defaultProtocol = "default_protocol"
            case devName = "dev_name"
            case enableEncryption = "enable_encryption"
            case enableIPv6 = "enable_ipv6"
            case mtu
            case latencyFirst = "latency_first"
            case enableExitNode = "enable_exit_node"
            case noTUN = "no_tun"
            case useSmoltcp = "use_smoltcp"
            case relayNetworkWhitelist = "relay_network_whitelist"
            case disableP2P = "disable_p2p"
            case relayAllPeerRPC = "relay_all_peer_rpc"
            case disableUDPHolePunching = "disable_udp_hole_punching"
            case multiThread = "multi_thread"
            case dataCompressAlgo = "data_compress_algo"
            case bindDevice = "bind_device"
            case enableKCPProxy = "enable_kcp_proxy"
            case disableKCPInput = "disable_kcp_input"
            case disableRelayKCP = "disable_relay_kcp"
            case proxyForwardBySystem = "proxy_forward_by_system"
            case acceptDNS = "accept_dns"
            case privateMode = "private_mode"
            case enableQUICProxy = "enable_quic_proxy"
            case disableQUICInput = "disable_quic_input"
            case disableRelayQUIC = "disable_relay_quic"
            case quicListenPort = "quic_listen_port"
            case foreignRelayBpsLimit = "foreign_relay_bps_limit"
            case multiThreadCount = "multi_thread_count"
            case enableRelayForeignNetworkKCP = "enable_relay_foreign_network_kcp"
            case enableRelayForeignNetworkQUIC = "enable_relay_foreign_network_quic"
            case encryptionAlgorithm = "encryption_algorithm"
            case disableSymHolePunching = "disable_sym_hole_punching"
            case tldDNSZone = "tld_dns_zone"
            case p2pOnly = "p2p_only"
            case disableTCPHolePunching = "disable_tcp_hole_punching"
        }
    }

    struct NetworkIdentity: Codable {
        var networkName: String
        var networkSecret: String?
        
        enum CodingKeys: String, CodingKey {
            case networkName = "network_name"
            case networkSecret = "network_secret"
        }
    }

    struct PeerConfig: Codable {
        var uri: String
    }

    struct ProxyNetworkConfig: Codable {
        /// Mapped from Rust `cidr::Ipv4Cidr`
        var cidr: String
        
        /// Mapped from Rust `Option<cidr::Ipv4Cidr>`
        var mappedCIDR: String?
        
        var allow: [String]?
        
        enum CodingKeys: String, CodingKey {
            case cidr
            case mappedCIDR = "mapped_cidr"
            case allow
        }
    }

    struct VPNPortalConfig: Codable {
        /// Mapped from Rust `cidr::Ipv4Cidr`
        var clientCIDR: String
        
        /// Mapped from Rust `SocketAddr`
        var wireguardListen: String
        
        enum CodingKeys: String, CodingKey {
            case clientCIDR = "client_cidr"
            case wireguardListen = "wireguard_listen"
        }
    }

    struct PortForwardConfig: Codable {
        /// Mapped from Rust `SocketAddr`
        var bindAddr: String
        
        /// Mapped from Rust `SocketAddr`
        var dstAddr: String
        
        var proto: String
        
        enum CodingKeys: String, CodingKey {
            case bindAddr = "bind_addr"
            case dstAddr = "dst_addr"
            case proto
        }
    }

    var netns: String?
    var hostname: String?
    var instanceName: String
    var instanceId: String
    var ipv4: String?
    var ipv6: String?
    var dhcp: Bool?
    var networkIdentity: NetworkIdentity?
    var listeners: [String]?
    var mappedListeners: [String]?
    
    /// Mapped from Rust `Vec<IpAddr>`
    var exitNodes: [String]?
    
    var peer: [PeerConfig]?
    var proxyNetwork: [ProxyNetworkConfig]?
    
    var vpnPortalConfig: VPNPortalConfig?
    
    /// Mapped from Rust `Vec<cidr::Ipv4Cidr>`
    var routes: [String]?
    var overrideDNS: [String]?
    
    var socks5Proxy: String?
    
    var portForward: [PortForwardConfig]?
    
    var flags: Flags?
    
    var tcpWhitelist: [String]?
    var udpWhitelist: [String]?
    var stunServers: [String]?
    var stunServersV6: [String]?

    enum CodingKeys: String, CodingKey {
        case netns
        case hostname
        case instanceName = "instance_name"
        case instanceId = "instance_id"
        case ipv4
        case ipv6
        case dhcp
        case networkIdentity = "network_identity"
        case listeners
        case mappedListeners = "mapped_listeners"
        case exitNodes = "exit_nodes"
        case peer
        case proxyNetwork = "proxy_network"
        case vpnPortalConfig = "vpn_portal_config"
        case routes
        case overrideDNS = "override_dns"
        case socks5Proxy = "socks5_proxy"
        case portForward = "port_forward"
        case flags
        case tcpWhitelist = "tcp_whitelist"
        case udpWhitelist = "udp_whitelist"
        case stunServers = "stun_servers"
        case stunServersV6 = "stun_servers_v6"
    }
    
    init(id: UUID, name: String) {
        self.instanceId = id.uuidString.lowercased()
        self.instanceName = name
    }
    
    mutating func apply(from profile: NetworkProfile) {
        // default profile for comparing
        let def = NetworkProfile(id: UUID())
        
        func takeIfChanged<T: Equatable>(_ current: T, _ original: T) -> T? {
            return current != original ? current : nil
        }
        
        func emptyAsNil<T>(_ list: [T]) -> [T]? {
            return list.isEmpty ? nil : list
        }
        
        self.instanceId = profile.id.uuidString.lowercased()
        self.instanceName = profile.networkName
        if !profile.hostname.isEmpty {
            self.hostname = profile.hostname
        } else {
            self.hostname = nil
        }
        self.dhcp = profile.dhcp
        self.networkIdentity = NetworkIdentity(networkName: profile.networkName, networkSecret: profile.networkSecret)
        
        if !profile.dhcp {
            self.ipv4 = profile.virtualIPv4.cidrString
        }
        
        switch profile.networkingMethod {
        case .defaultServer:
            self.peer = [PeerConfig(uri: defaultServerURL)]
        case .custom:
            self.peer = emptyAsNil(profile.peerURLs.compactMap { $0.text.isEmpty ? nil : PeerConfig(uri: $0.text) })
        case .standalone:
            self.peer = nil
        }
        
        self.listeners = emptyAsNil(profile.listenerURLs.compactMap { $0.text.isEmpty ? nil : $0.text })

        self.proxyNetwork = emptyAsNil(profile.proxyCIDRs.compactMap { cidr in
            let cidrString = cidr.cidrString
            guard !cidrString.isEmpty else { return nil }
            return ProxyNetworkConfig(
                cidr: cidrString,
                mappedCIDR: cidr.enableMapping ? cidr.mappedCIDRString : nil,
            )
        })

        self.portForward = emptyAsNil(profile.portForwards.map {
            PortForwardConfig(
                bindAddr: "\($0.bindAddr):\($0.bindPort)",
                dstAddr: "\($0.destAddr):\($0.destPort)",
                proto: $0.proto,
            )
        })
        
        if profile.enableVPNPortal {
            self.vpnPortalConfig = VPNPortalConfig(
                clientCIDR: profile.vpnPortalClientCIDR.cidrString,
                wireguardListen: "0.0.0.0:\(profile.vpnPortalListenPort)",
            )
        }
        
        if profile.enableManualRoutes {
            self.routes = emptyAsNil(profile.routes.map { $0.cidrString })
        }
        
        if profile.enableOverrideDNS {
            self.overrideDNS = emptyAsNil(profile.overrideDNS.compactMap { $0.text.isEmpty ? nil : $0.text })
        }
        
        self.exitNodes = emptyAsNil(profile.exitNodes.compactMap { $0.text.isEmpty ? nil : $0.text })
        
        if profile.enableSocks5 {
            self.socks5Proxy = "socks5://0.0.0.0:\(profile.socks5Port)"
        }
        
        self.mappedListeners = emptyAsNil(profile.mappedListeners.compactMap { $0.text.isEmpty ? nil : $0.text })
        
        var tempFlags = self.flags ?? Flags()
        
        tempFlags.mtu = profile.mtu
        tempFlags.latencyFirst = takeIfChanged(profile.latencyFirst, def.latencyFirst)
        tempFlags.enableExitNode = takeIfChanged(profile.enableExitNode, def.enableExitNode)
        tempFlags.noTUN = takeIfChanged(profile.noTUN, def.noTUN)
        tempFlags.useSmoltcp = takeIfChanged(profile.useSmoltcp, def.useSmoltcp)
        tempFlags.disableP2P = takeIfChanged(profile.disableP2P, def.disableP2P)
        tempFlags.relayAllPeerRPC = takeIfChanged(profile.relayAllPeerRPC, def.relayAllPeerRPC)
        tempFlags.disableUDPHolePunching = takeIfChanged(profile.disableUDPHolePunching, def.disableUDPHolePunching)
        tempFlags.multiThread = takeIfChanged(profile.multiThread, def.multiThread)
        tempFlags.bindDevice = takeIfChanged(profile.bindDevice, def.bindDevice)
        tempFlags.enableKCPProxy = takeIfChanged(profile.enableKCPProxy, def.enableKCPProxy)
        tempFlags.disableKCPInput = takeIfChanged(profile.disableKCPInput, def.disableKCPInput)
        tempFlags.proxyForwardBySystem = takeIfChanged(profile.proxyForwardBySystem, def.proxyForwardBySystem)
        tempFlags.acceptDNS = takeIfChanged(profile.enableMagicDNS, def.enableMagicDNS)
        tempFlags.enableQUICProxy = takeIfChanged(profile.enableQUICProxy, def.enableQUICProxy)
        tempFlags.disableQUICInput = takeIfChanged(profile.disableQUICInput, def.disableQUICInput)
        tempFlags.disableSymHolePunching = takeIfChanged(profile.disableSymHolePunching, def.disableSymHolePunching)
        tempFlags.tldDNSZone = takeIfChanged(profile.magicDNSTLD, def.magicDNSTLD)
        tempFlags.p2pOnly = takeIfChanged(profile.p2pOnly, def.p2pOnly)
        tempFlags.privateMode = takeIfChanged(profile.enablePrivateMode, def.enablePrivateMode)
        
        if profile.disableIPv6 != def.disableIPv6 {
            tempFlags.enableIPv6 = !profile.disableIPv6
        }
        
        if profile.disableEncryption != def.disableEncryption {
            tempFlags.enableEncryption = !profile.disableEncryption
        }
        
        if profile.enableRelayNetworkWhitelist {
            tempFlags.relayNetworkWhitelist = profile.relayNetworkWhitelist
                .compactMap { $0.text.isEmpty ? nil : $0.text }.joined(separator: " ")
        }
        
        if profile.enableDataCompression {
            tempFlags.dataCompressAlgo = 2
        }
        
        if tempFlags == Flags() {
            self.flags = nil
        } else {
            self.flags = tempFlags
        }
    }

    static func splitCIDR(_ value: String, defaultLength: String) -> (ip: String, length: String) {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return (parts[0], parts[1])
        }
        return (value, defaultLength)
    }

    static func splitHostPort(_ value: String) -> (host: String, port: Int?) {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return (value, nil)
        }
        let port = Int(parts.last ?? "")
        let host = parts.dropLast().joined(separator: ":")
        return (String(host), port)
    }

    static func parseSocks5Port(_ value: String) -> Int? {
        if let url = URL(string: value), let port = url.port {
            return port
        }
        return splitHostPort(value).port
    }
}
