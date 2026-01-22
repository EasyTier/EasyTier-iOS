import Foundation

struct NetworkConfig: Codable {
    struct Flags: Codable {
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
        var quicListenPort: Int?
        var foreignRelayBpsLimit: UInt64?
        var multiThreadCount: Int?
        var enableRelayForeignNetworkKCP: Bool?
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
            case quicListenPort = "quic_listen_port"
            case foreignRelayBpsLimit = "foreign_relay_bps_limit"
            case multiThreadCount = "multi_thread_count"
            case enableRelayForeignNetworkKCP = "enable_relay_foreign_network_kcp"
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
    
    
    init(from profile: NetworkProfile) {
        // default profile for comparing
        let def = NetworkProfile(id: UUID())
        
        func takeIfChanged<T: Equatable>(_ current: T, _ original: T) -> T? {
            return current != original ? current : nil
        }
        
        self.instanceId = profile.id.uuidString.lowercased()
        if !profile.hostname.isEmpty {
            self.hostname = profile.hostname
        }
        self.dhcp = profile.dhcp
        self.instanceName = profile.networkName
        self.networkIdentity = NetworkIdentity(networkName: profile.networkName, networkSecret: profile.networkSecret)
        
        if !profile.dhcp {
            self.ipv4 = profile.virtualIPv4.cidrString
        }
        
        switch profile.networkingMethod {
        case .publicServer:
            self.peer = [PeerConfig(uri: profile.publicServerURL)]
        case .manual:
            self.peer = profile.peerURLs.compactMap { $0.text.isEmpty ? nil : PeerConfig(uri: $0.text) }
        case .standalone:
            break
        }
        
        if !profile.listenerURLs.isEmpty {
            self.listeners = profile.listenerURLs.compactMap { $0.text.isEmpty ? nil : $0.text }
        }
        
        if !profile.proxyCIDRs.isEmpty {
            self.proxyNetwork = profile.proxyCIDRs.map { cidr in
                ProxyNetworkConfig(
                    cidr: "\(cidr.cidr)/\(cidr.length)",
                    mappedCIDR: cidr.enableMapping ? cidr.mappedCIDR : nil,
                )
            }
        }
        
        if !profile.portForwards.isEmpty {
            self.portForward = profile.portForwards.map {
                PortForwardConfig(
                    bindAddr: "\($0.bindAddr):\($0.bindPort)",
                    dstAddr: "\($0.destAddr):\($0.destPort)",
                    proto: $0.proto,
                )
            }
        }
        
        if profile.enableVPNPortal {
            self.vpnPortalConfig = VPNPortalConfig(
                clientCIDR: profile.vpnPortalClientCIDR.cidrString,
                wireguardListen: "0.0.0.0:\(profile.vpnPortalListenPort)",
            )
        }
        
        if profile.enableManualRoutes {
            self.routes = profile.routes.map { $0.cidrString }
        }
        
        if profile.enableOverrideDNS {
            self.overrideDNS = profile.overrideDNS.compactMap { $0.text.isEmpty ? nil : $0.text }
        }
        
        if !profile.exitNodes.isEmpty {
            self.exitNodes = profile.exitNodes.compactMap { $0.text.isEmpty ? nil : $0.text }
        }
        
        if profile.enableSocks5 {
            self.socks5Proxy = "socks5://0.0.0.0:\(profile.socks5Port)"
        }
        
        if !profile.mappedListeners.isEmpty {
            self.mappedListeners = profile.mappedListeners.compactMap { $0.text.isEmpty ? nil : $0.text }
        }
        
        var tempFlags = Flags()
        
//        tempFlags.devName = takeIfChanged(profile.devName, def.devName)
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
        
        self.flags = tempFlags
    }
}

extension NetworkConfig {
    func apply(to profile: inout NetworkProfile) {
        let def = NetworkProfile(id: profile.id)

        profile.dhcp = def.dhcp
        profile.virtualIPv4 = def.virtualIPv4
        profile.hostname = def.hostname
        profile.networkSecret = def.networkSecret
        profile.networkingMethod = def.networkingMethod
        profile.publicServerURL = def.publicServerURL
        profile.peerURLs = def.peerURLs
        profile.proxyCIDRs = def.proxyCIDRs
        profile.enableVPNPortal = def.enableVPNPortal
        profile.vpnPortalListenPort = def.vpnPortalListenPort
        profile.vpnPortalClientCIDR = def.vpnPortalClientCIDR
        profile.listenerURLs = def.listenerURLs
        profile.latencyFirst = def.latencyFirst
        profile.useSmoltcp = def.useSmoltcp
        profile.disableIPv6 = def.disableIPv6
        profile.enableKCPProxy = def.enableKCPProxy
        profile.disableKCPInput = def.disableKCPInput
        profile.enableQUICProxy = def.enableQUICProxy
        profile.disableQUICInput = def.disableQUICInput
        profile.disableP2P = def.disableP2P
        profile.p2pOnly = def.p2pOnly
        profile.bindDevice = def.bindDevice
        profile.noTUN = def.noTUN
        profile.enableExitNode = def.enableExitNode
        profile.relayAllPeerRPC = def.relayAllPeerRPC
        profile.multiThread = def.multiThread
        profile.proxyForwardBySystem = def.proxyForwardBySystem
        profile.disableEncryption = def.disableEncryption
        profile.disableUDPHolePunching = def.disableUDPHolePunching
        profile.disableSymHolePunching = def.disableSymHolePunching
        profile.enableRelayNetworkWhitelist = def.enableRelayNetworkWhitelist
        profile.relayNetworkWhitelist = def.relayNetworkWhitelist
        profile.enableManualRoutes = def.enableManualRoutes
        profile.routes = def.routes
        profile.enableOverrideDNS = def.enableOverrideDNS
        profile.overrideDNS = def.overrideDNS
        profile.portForwards = def.portForwards
        profile.exitNodes = def.exitNodes
        profile.enableSocks5 = def.enableSocks5
        profile.socks5Port = def.socks5Port
        profile.mtu = def.mtu
        profile.mappedListeners = def.mappedListeners
        profile.enableMagicDNS = def.enableMagicDNS
        profile.enablePrivateMode = def.enablePrivateMode

        if let hostname, !hostname.isEmpty {
            profile.hostname = hostname
        }
        profile.networkName = networkIdentity?.networkName ?? ""
        profile.networkSecret = networkIdentity?.networkSecret ?? ""

        if let dhcp {
            profile.dhcp = dhcp
        }
        if let ipv4 {
            let parsed = splitCIDR(ipv4, defaultLength: profile.virtualIPv4.length)
            profile.virtualIPv4 = .init(ip: parsed.ip, length: parsed.length)
            profile.dhcp = false
        }

        if let peer, !peer.isEmpty {
            if peer.count == 1 && peer[0].uri == def.publicServerURL {  // future: public server list
                profile.networkingMethod = .publicServer
                profile.publicServerURL = peer[0].uri
            } else {
                profile.networkingMethod = .manual
                profile.peerURLs = peer.map { .init($0.uri) }
            }
        } else {
            profile.networkingMethod = .standalone
        }

        if let listeners, !listeners.isEmpty {
            profile.listenerURLs = listeners.map { .init($0) }
        }

        if let proxyNetwork, !proxyNetwork.isEmpty {
            profile.proxyCIDRs = proxyNetwork.map { item in
                let parsed = splitCIDR(item.cidr, defaultLength: "32")
                var entry = NetworkProfile.ProxyCIDR(
                    cidr: parsed.ip,
                    enableMapping: false,
                    mappedCIDR: "0.0.0.0",
                    length: parsed.length
                )
                if let mappedCIDR = item.mappedCIDR, !mappedCIDR.isEmpty {
                    let mapped = splitCIDR(mappedCIDR, defaultLength: parsed.length)
                    entry.enableMapping = true
                    entry.mappedCIDR = mapped.ip
                    entry.length = mapped.length
                }
                return entry
            }
        }

        if let portForward, !portForward.isEmpty {
            profile.portForwards = portForward.compactMap { item in
                let bind = splitHostPort(item.bindAddr)
                let dest = splitHostPort(item.dstAddr)
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

        if let vpnPortalConfig {
            profile.enableVPNPortal = true
            let parsed = splitCIDR(vpnPortalConfig.clientCIDR, defaultLength: profile.vpnPortalClientCIDR.length)
            profile.vpnPortalClientCIDR = .init(ip: parsed.ip, length: parsed.length)
            if let port = splitHostPort(vpnPortalConfig.wireguardListen).port {
                profile.vpnPortalListenPort = port
            }
        }

        if let routes {
            profile.enableManualRoutes = true
            profile.routes = routes.map { item in
                let parsed = splitCIDR(item, defaultLength: "32")
                return .init(ip: parsed.ip, length: parsed.length)
            }
        }

        if let overrideDNS {
            profile.enableOverrideDNS = true
            profile.overrideDNS = overrideDNS.map { .init($0) }
        }

        if let exitNodes {
            profile.exitNodes = exitNodes.map { .init($0) }
        }

        if let socks5Proxy, let port = parseSocks5Port(socks5Proxy) {
            profile.enableSocks5 = true
            profile.socks5Port = port
        }

        if let mappedListeners {
            profile.mappedListeners = mappedListeners.map { .init($0) }
        }

        if let flags {
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
            if let privateMode = flags.privateMode {
                profile.enablePrivateMode = privateMode
            }
        }
    }

    private func splitCIDR(_ value: String, defaultLength: String) -> (ip: String, length: String) {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return (parts[0], parts[1])
        }
        return (value, defaultLength)
    }

    private func splitHostPort(_ value: String) -> (host: String, port: Int?) {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return (value, nil)
        }
        let port = Int(parts.last ?? "")
        let host = parts.dropLast().joined(separator: ":")
        return (String(host), port)
    }

    private func parseSocks5Port(_ value: String) -> Int? {
        if let url = URL(string: value), let port = url.port {
            return port
        }
        return splitHostPort(value).port
    }
}

extension NetworkProfile {
    init(from config: NetworkConfig) {
        let id = UUID(uuidString: config.instanceId) ?? UUID()
        var profile = NetworkProfile(id: id)
        config.apply(to: &profile)
        self = profile
    }
}
