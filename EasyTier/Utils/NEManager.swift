import Foundation
import Combine
import NetworkExtension

import TOMLKit

class NEManager: ObservableObject {
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
            }
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
        print("[NEManager] install()")
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "EasyTier"
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = "site.yinmo.easytier.tunnel"
        tunnelProtocol.serverAddress = "localhost"
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        do {
            try await manager.saveToPreferences()
            return manager
        } catch {
            print("[NEManager] install() failed: \(error)")
            throw error
        }
    }

    func load() async throws {
        print("[NEManager] load()")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let manager = managers.first
            for m in managers {
                if m != manager {
                    try? await m.removeFromPreferences()
                    print("[NEManager] load() removed unecessary profile")
                }
            }
            setManager(manager: manager)
            isLoading = false
        } catch {
            print("[NEManager] load() failed: \(error)")
            reset()
            throw error
        }
    }
    
    func connect(profile: NetworkProfile) async throws {
        guard ![.connecting, .connected, .disconnecting, .reasserting].contains(status) else {
            print("[NEManager] connect() failed: in \(status) status")
            return
        }
        guard !isLoading else {
            print("[NEManager] connect() failed: not loaded")
            return
        }
        if status == .invalid {
            _ = try await NEManager.install()
            try await load()
        }
        guard let manager else {
            print("[NEManager] connect() failed: manager is nil")
            return
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        
        var options: [String : NSObject] = [:]
        let config = Config(from: profile)
        options["name"] = config.instanceName as NSObject
        let encoded: String
        do {
            encoded = try TOMLEncoder().encode(config).string ?? ""
        } catch {
            print("[NEManager] connect() generate config failed: \(error)")
            throw error
        }
        print("[NEManager] connect() config: \(encoded)")
        options["config"] = encoded as NSObject
        do {
            try manager.connection.startVPNTunnel(options: options)
        } catch {
            print("[NEManager] connect() start vpn tunnel failed: \(error)")
            throw error
        }
        print("[NEManager] connect() started")
    }
    
    func disconnect() async {
        guard let manager else {
            print("[NEManager] disconnect() failed: manager is nil")
            return
        }
        manager.connection.stopVPNTunnel()
    }
    
    func updateName(name: String, server: String) async throws {
        guard let manager else { return }
        manager.localizedDescription = name
        manager.protocolConfiguration?.serverAddress = server
        try await manager.saveToPreferences()
    }
}
