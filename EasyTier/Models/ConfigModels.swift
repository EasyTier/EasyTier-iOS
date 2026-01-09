import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

struct NetworkConfig: Codable {
    private static var defaultDeviceName: String? {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return Host.current().localizedName
        #endif
    }
    struct Flags: Codable {
        var defaultProtocol: String?
        var devName: String?
        var enableEncryption: Bool?
        var enableIPv6: Bool?
        var mtu: UInt32?
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
        var quicListenPort: UInt32?
        var foreignRelayBpsLimit: UInt64?
        var multiThreadCount: UInt32?
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
        case socks5Proxy = "socks5_proxy"
        case portForward = "port_forward"
        case flags
        case tcpWhitelist = "tcp_whitelist"
        case udpWhitelist = "udp_whitelist"
        case stunServers = "stun_servers"
        case stunServersV6 = "stun_servers_v6"
    }
    
    
    init(from profile: NetworkProfile, name: String) {
        // default profile for comparing
        let def = NetworkProfile(id: UUID())
        let useRealDeviceNameAsDefault = UserDefaults.standard.object(forKey: "useRealDeviceNameAsDefault") as? Bool ?? true
        
        func takeIfChanged<T: Equatable>(_ current: T, _ original: T) -> T? {
            return current != original ? current : nil
        }
        
        self.instanceId = profile.id.uuidString.lowercased()
        if let hostname = profile.hostname, !hostname.isEmpty {
            self.hostname = hostname
        } else if useRealDeviceNameAsDefault {
            self.hostname = Self.defaultDeviceName
        } else {
            self.hostname = nil
        }
        self.dhcp = profile.dhcp
        self.instanceName = name
        self.networkIdentity = NetworkIdentity(networkName: name, networkSecret: profile.networkSecret)
        
        if !profile.dhcp {
            self.ipv4 = profile.virtualIPv4.cidrString
        }
        
        switch profile.networkingMethod {
        case .publicServer:
            self.peer = [PeerConfig(uri: profile.publicServerURL)]
        case .manual:
            self.peer = profile.peerURLs.map { PeerConfig(uri: $0.text) }
        case .standalone:
            break
        }
        
        if !profile.listenerURLs.isEmpty {
            self.listeners = profile.listenerURLs.map { $0.text }
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
        
        if !profile.exitNodes.isEmpty {
            self.exitNodes = profile.exitNodes.map { $0.text }
        }
        
        if profile.enableSocks5 {
            self.socks5Proxy = "socks5://0.0.0.0:\(profile.socks5Port)"
        }
        
        if !profile.mappedListeners.isEmpty {
            self.mappedListeners = profile.mappedListeners.map { $0.text }
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
        tempFlags.enableQUICProxy = takeIfChanged(profile.enableQUICProxy, def.enableQUICProxy)
        tempFlags.disableQUICInput = takeIfChanged(profile.disableQUICInput, def.disableQUICInput)
        tempFlags.disableSymHolePunching = takeIfChanged(profile.disableSymHolePunching, def.disableSymHolePunching)
        tempFlags.p2pOnly = takeIfChanged(profile.p2pOnly, def.p2pOnly)
        
        if profile.disableIPv6 != def.disableIPv6 {
            tempFlags.enableIPv6 = !profile.disableIPv6
        }
        
        if profile.disableEncryption != def.disableEncryption {
            tempFlags.enableEncryption = !profile.disableEncryption
        }
        
        if profile.enableRelayNetworkWhitelist {
            tempFlags.relayNetworkWhitelist = profile.relayNetworkWhitelist.map { $0.text }.joined(separator: " ")
        }
        
        self.flags = tempFlags
    }
}
