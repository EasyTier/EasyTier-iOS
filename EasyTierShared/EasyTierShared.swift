import NetworkExtension
import os

public let APP_BUNDLE_ID: String = "site.yinmo.easytier"
public let APP_GROUP_ID: String = "group.site.yinmo.easytier"
public let LOG_FILENAME: String = "easytier.log"

public enum LogLevel: String, Codable, CaseIterable {
    case trace = "trace"
    case debug = "debug"
    case info = "info"
    case warn = "warn"
    case error = "error"
}

public struct EasyTierOptions: Codable {
    public var config: String = ""
    public var ipv4: String?
    public var ipv6: String?
    public var mtu: UInt32?
    public var routes: [String] = []
    public var logLevel: LogLevel = .info
    public var magicDNS: Bool = false
    
    public init() {}
}

public func connectWithManager(_ manager: NETunnelProviderManager, logger: Logger? = nil) async throws {
    manager.isEnabled = true
    if let defaults = UserDefaults(suiteName: APP_GROUP_ID) {
        manager.protocolConfiguration?.includeAllNetworks = defaults.bool(forKey: "includeAllNetworks")
        manager.protocolConfiguration?.excludeLocalNetworks = defaults.bool(forKey: "excludeLocalNetworks")
        if #available(iOS 16.4, *) {
            manager.protocolConfiguration?.excludeCellularServices = defaults.bool(forKey: "excludeCellularServices")
            manager.protocolConfiguration?.excludeAPNs = defaults.bool(forKey: "excludeAPNs")
        }
        if #available(iOS 17.4, *) {
            manager.protocolConfiguration?.excludeDeviceCommunication = defaults.bool(forKey: "excludeDeviceCommunication")
        }
        manager.protocolConfiguration?.enforceRoutes = defaults.bool(forKey: "enforceRoutes")
        if let logger {
            logger.debug("connect with protocol configuration: \(manager.protocolConfiguration)")
        }
    }
    try await manager.saveToPreferences()
    try manager.connection.startVPNTunnel()
}
