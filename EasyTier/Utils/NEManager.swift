import Foundation
import Combine
import NetworkExtension
import WidgetKit

import TOMLKit
import os

protocol NEManagerProtocol: ObservableObject {
    var status: NEVPNStatus { get }
    var connectedDate: Date? { get }
    var isLoading: Bool { get }
    
    func load() async throws
    @MainActor
    func connect(profile: ProfileSummary) async throws
    func disconnect() async
    func fetchRunningInfo(_ callback: @escaping ((NetworkStatus) -> Void))
    func updateName(name: String, server: String) async
}

class NEManager: NEManagerProtocol {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "NEManager")

    private var manager: NETunnelProviderManager?
    private var connection: NEVPNConnection?
    private var observer: Any?

    @Published var status: NEVPNStatus
    @Published var connectedDate: Date?
    @Published var isLoading = true
    
    init() {
        status = .invalid
    }

    private func registerObserver() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let manager = manager {
            observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NEVPNStatusDidChange,
                object: manager.connection,
                queue: .main
            ) { [weak self] notification in
                guard let self else {
                    return
                }
                self.connection = notification.object as? NEVPNConnection
                self.status = self.connection?.status ?? .invalid
                self.connectedDate = self.connection?.connectedDate
                if self.status == .invalid {
                    self.manager = nil
                }
                
                // Sync VPN connection status to App Group for Control Widget
                self.syncWidgetState()
            }
        }
    }
    
    // Notify Control Widget to refresh its state
    private func syncWidgetState() {
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadControls(ofKind: "site.yinmo.easytier.ControlWidgets")
        }
    }
    
    private func reset() {
        manager = nil
        connection = nil
        status = .invalid
        connectedDate = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        isLoading = false
    }
    
    private func setManager(manager: NETunnelProviderManager?) {
        self.manager = manager
        connection = manager?.connection
        status = manager?.connection.status ?? .invalid
        connectedDate = manager?.connection.connectedDate
        registerObserver()
    }
    
    static func install() async throws -> NETunnelProviderManager {
        Self.logger.info("install()")
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "EasyTier"
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "site.yinmo.easytier.tunnel"
        tunnelProtocol.serverAddress = "127.0.0.1"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            return manager
        } catch {
            Self.logger.error("install() failed: \(String(describing: error))")
            throw error
        }
    }

    func load() async throws {
        Self.logger.info("load()")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = managers.first
            for m in managers {
                if m != manager {
                    try? await m.removeFromPreferences()
                    Self.logger.info("load() removed unnecessary profile")
                }
            }
            setManager(manager: manager)
            isLoading = false
        } catch {
            Self.logger.error("load() failed: \(String(describing: error))")
            reset()
            throw error
        }
    }
    
    func connect(profile: ProfileSummary) async throws {
        guard ![.connecting, .connected, .disconnecting, .reasserting].contains(status) else {
            Self.logger.warning("connect() failed: in \(String(describing: self.status)) status")
            return
        }
        guard !isLoading else {
            Self.logger.warning("connect() failed: not loaded")
            return
        }
        if status == .invalid {
            _ = try await NEManager.install()
            try await load()
        }
        guard let manager else {
            Self.logger.error("connect() failed: manager is nil")
            return
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        
        var options: [String : NSObject] = [:]
        let config = NetworkConfig(from: profile.profile, name: profile.name)

        let encoded: String
        do {
            encoded = try TOMLEncoder().encode(config).string ?? ""
        } catch {
            Self.logger.error("connect() generate config failed: \(String(describing: error))")
            throw error
        }
        Self.logger.debug("connect() config: \(encoded)")
        options["config"] = encoded as NSString
        if let ipv4 = config.ipv4 {
            options["ipv4"] = ipv4 as NSString
        }
        if let ipv6 = config.ipv6 {
            options["ipv6"] = ipv6 as NSString
        }
        if let mtu = config.flags?.mtu {
            options["mtu"] = mtu as NSNumber
        }
        if let logLevel = UserDefaults.standard.string(forKey: "logLevel") {
            options["logLevel"] = logLevel as NSString
        }
        if let routes = config.routes {
            options["routes"] = NSArray(array: routes.map { $0 as NSString })
        }
        
        // Save config to App Group for Widget use
        let defaults = UserDefaults(suiteName: "group.site.yinmo.easytier")
        var configDict: [String: String] = [:]
        for (key, value) in options {
            if let strValue = value as? String {
                configDict[key] = strValue
            }
        }
        if let configData = try? JSONEncoder().encode(configDict) {
            defaults?.set(configData, forKey: "LastVPNConfig")
            defaults?.synchronize()
        }
        
        do {
            try manager.connection.startVPNTunnel(options: options)
        } catch {
            Self.logger.error("connect() start vpn tunnel failed: \(String(describing: error))")
            throw error
        }
        Self.logger.info("connect() started")
        // Immediately sync widget state after initiating connection
        syncWidgetState()
    }
    
    func disconnect() async {
        guard let manager else {
            Self.logger.error("disconnect() failed: manager is nil")
            return
        }
        manager.connection.stopVPNTunnel()
        // Immediately sync widget state after initiating disconnection
        syncWidgetState()
    }
    
    func updateName(name: String, server: String) async {
        guard let manager else { return }
        manager.localizedDescription = name
        manager.protocolConfiguration?.serverAddress = server
        try? await manager.saveToPreferences()
    }
    
    func fetchRunningInfo(_ callback: @escaping ((NetworkStatus) -> Void)) {
        guard let manager else { return }
        guard let session = manager.connection as? NETunnelProviderSession,
              session.status != .invalid else { return }
        do {
            try session.sendProviderMessage(Data()) { data in
                guard let data else { return }
                Self.logger.debug("fetchRunningInfo() received data: \(String(data: data, encoding: .utf8) ?? data.description)")
                let info: NetworkStatus
                do {
                    info = try JSONDecoder().decode(NetworkStatus.self, from: data)
                } catch {
                    Self.logger.error("fetchRunningInfo() json deserialize failed: \(String(describing: error))")
                    return
                }
                callback(info)
            }
        } catch {
            Self.logger.error("fetchRunningInfo() failed: \(String(describing: error))")
        }
    }
}

class MockNEManager: NEManagerProtocol {
    @Published var status: NEVPNStatus = .disconnected
    @Published var connectedDate: Date? = nil
    @Published var isLoading: Bool = true

    // Simulate a successful load
    func load() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        isLoading = false
        status = .disconnected
    }

    // Simulate connecting
    func connect(profile: ProfileSummary) async throws {
        status = .connecting
        // Simulate network delay
        try await Task.sleep(nanoseconds: 2_000_000_000)
        status = .connected
        connectedDate = Date()
    }

    func disconnect() async {
        status = .disconnecting
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        status = .disconnected
        connectedDate = nil
    }

    func updateName(name: String, server: String) async { }

    func fetchRunningInfo(_ callback: @escaping ((NetworkStatus) -> Void)) {
        callback(MockNEManager.dummyRunningInfo)
    }
    
    static var dummyRunningInfo: NetworkStatus {
        let id = UUID().uuidString

        let myNodeInfo = NetworkStatus.NodeInfo(
            virtualIPv4: NetworkStatus.IPv4CIDR(address: NetworkStatus.IPv4Addr("10.144.144.10")!, networkLength: 24),
            hostname: "My iPhone",
            version: "0.10.1",
            ips: .init(
                publicIPv4: NetworkStatus.IPv4Addr("8.8.8.8"),
                interfaceIPv4s: [NetworkStatus.IPv4Addr("192.168.1.100")!],
                publicIPv6: nil as NetworkStatus.IPv6Addr?,
                interfaceIPv6s: []
            ),
            stunInfo: NetworkStatus.STUNInfo(udpNATType: .symmetricEasyInc, tcpNATType: .fullCone, lastUpdateTime: Date().timeIntervalSince1970 - 10),
            listeners: [NetworkStatus.Url(url: "tcp://0.0.0.0:11010"), NetworkStatus.Url(url: "udp://0.0.0.0:11010")],
            vpnPortalCfg: "[Interface]\nPrivateKey = [REDACTED]\nAddress = 10.144.144.1/24\nListenPort = 22022\n\n[Peer]\nPublicKey = [REDACTED]\nAllowedIPs = 10.144.144.2/32"
        )
        
        let peerRoute1 = NetworkStatus.Route(peerId: 123, ipv4Addr: .init(address: .init("10.144.144.10")!, networkLength: 24), nextHopPeerId: 123, cost: 1, pathLatency: 8, proxyCIDRs: [], hostname: "peer-1-ubuntu", stunInfo: NetworkStatus.STUNInfo(udpNATType: .fullCone, tcpNATType: .symmetric, lastUpdateTime: Date().timeIntervalSince1970 - 20), instId: id, version: "0.10.0")
        let peerRoute2 = NetworkStatus.Route(peerId: 456, ipv6Addr: .init(address: .init("fd00::1")!, networkLength: 64), nextHopPeerId: 789, cost: 2, pathLatency: 8, proxyCIDRs: [], hostname: "peer-2-relayed-windows", stunInfo: NetworkStatus.STUNInfo(udpNATType: .symmetric, tcpNATType: .restricted, lastUpdateTime: Date().timeIntervalSince1970 - 30), instId: id, version: "0.9.8")
        let peerRoute3 = NetworkStatus.Route(peerId: 256, ipv4Addr: .init(address: .init("10.144.144.14")!, networkLength: 32), ipv6Addr: .init(address: .init("fd00::2")!, networkLength: 48), nextHopPeerId: 789, cost: 1, pathLatency: 8, proxyCIDRs: [], hostname: "peer-3-relayed-verylong-verylong-verylong-verylong", stunInfo: NetworkStatus.STUNInfo(udpNATType: .openInternet, tcpNATType: .openInternet, lastUpdateTime: Date().timeIntervalSince1970 - 20), instId: id, version: "1.9.8")
        
        let conn1 = NetworkStatus.PeerConnInfo(connId: "conn-1", myPeerId: 0, isClient: true, peerId: 123, features: [], tunnel: NetworkStatus.TunnelInfo(tunnelType: "tcp", localAddr: NetworkStatus.Url(url:"192.168.1.100:55555"), remoteAddr: NetworkStatus.Url(url:"1.2.3.4:11010")), stats: NetworkStatus.PeerConnStats(rxBytes: 102400, txBytes: 204800, rxPackets: 100, txPackets: 200, latencyUs: 180000), lossRate: 0.01)
        let conn2 = NetworkStatus.PeerConnInfo(connId: "conn-2", myPeerId: 0, isClient: true, peerId: 256, features: [], tunnel: NetworkStatus.TunnelInfo(tunnelType: "udp", localAddr: NetworkStatus.Url(url:"192.168.1.100:55555"), remoteAddr: NetworkStatus.Url(url:"1.2.3.4:11010")), stats: NetworkStatus.PeerConnStats(rxBytes: 102400, txBytes: 204800, rxPackets: 100, txPackets: 200, latencyUs: 5000), lossRate: 0.01)

        let peer1 = NetworkStatus.PeerInfo(peerId: 123, conns: [conn1])
        let peer2 = NetworkStatus.PeerInfo(peerId: 256, conns: [conn1, conn2])
        
        return NetworkStatus(
            devName: "utun10",
            myNodeInfo: myNodeInfo,
            events: [
                "{\"time\":\"2026-01-04T14:31:55.012731+08:00\",\"event\":{\"PeerAdded\":4129348860}}",
                "{\"time\":\"2026-01-04T14:31:55.012711+08:00\",\"event\":{\"PeerConnAdded\":{\"conn_id\":\"11fdb3dd-9f35-4ab3-b255-133f1c7dad38\",\"my_peer_id\":3967454550,\"peer_id\":4129348860,\"features\":[],\"tunnel\":{\"tunnel_type\":\"tcp\",\"local_addr\":{\"url\":\"tcp://192.168.31.19:58758\"},\"remote_addr\":{\"url\":\"tcp://public.easytier.top:11010\"}},\"stats\":{\"rx_bytes\":91,\"tx_bytes\":93,\"rx_packets\":1,\"tx_packets\":1,\"latency_us\":0},\"loss_rate\":0.0,\"is_client\":true,\"network_name\":\"sijie-easytier-public\",\"is_closed\":false}}}",
                "{\"time\":\"2026-01-04T14:31:54.872468+08:00\",\"event\":{\"ListenerAdded\":\"wg://0.0.0.0:11011\"}}",
                "{\"time\":\"2026-01-04T14:31:54.866061+08:00\",\"event\":{\"Connecting\":\"tcp://public.easytier.top:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.869940+08:00\",\"event\":{\"ListenerAdded\":\"wg://[::]:11011\"}}",
                "{\"time\":\"2026-01-04T14:31:53.869581+08:00\",\"event\":{\"ListenerAddFailed\":[\"wg://0.0.0.0:11011\",\"error: IOError(Os { code: 48, kind: AddrInUse, message: \\\"Address already in use\\\" }), retry listen later...\"]}}",
                "{\"time\":\"2026-01-04T14:31:53.868529+08:00\",\"event\":{\"ListenerAdded\":\"udp://[::]:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.868207+08:00\",\"event\":{\"ListenerAdded\":\"udp://0.0.0.0:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.865719+08:00\",\"event\":{\"ListenerAdded\":\"tcp://0.0.0.0:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.865237+08:00\",\"event\":{\"ListenerAdded\":\"tcp://[::]:11010\"}}",
                "{\"time\":\"2026-01-04T14:31:53.863019+08:00\",\"event\":{\"ListenerAdded\":\"ring://360e18ba-81de-4bd0-b32a-07958ee9c917\"}}"
            ],
            routes: [peerRoute1, peerRoute2, peerRoute3],
            peers: [peer1, peer2],
            peerRoutePairs: [
                NetworkStatus.PeerRoutePair(route: peerRoute1, peer: peer1),
                NetworkStatus.PeerRoutePair(route: peerRoute2, peer: nil),
                NetworkStatus.PeerRoutePair(route: peerRoute3, peer: peer2)
            ],
            running: true,
            errorMsg: nil
        )
    }
}
