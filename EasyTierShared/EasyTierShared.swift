import NetworkExtension
import os

public let APP_BUNDLE_ID: String = "site.yinmo.easytier"
public let APP_GROUP_ID: String = "group.site.yinmo.easytier"
public let ICLOUD_CONTAINER_ID: String = "iCloud.site.yinmo.easytier"
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
    public var dns: [String] = []
    
    public init() {}
}

public struct TunnelNetworkSettingsSnapshot: Codable {
    public struct IPv4Route: Codable {
        public var destination: String
        public var subnetMask: String

        public init(destination: String, subnetMask: String) {
            self.destination = destination
            self.subnetMask = subnetMask
        }
    }

    public struct IPv6Route: Codable {
        public var destination: String
        public var networkPrefixLength: UInt32

        public init(destination: String, networkPrefixLength: UInt32) {
            self.destination = destination
            self.networkPrefixLength = networkPrefixLength
        }
    }

    public struct IPv4: Codable {
        public var addresses: [String]
        public var subnetMasks: [String]
        public var includedRoutes: [IPv4Route]?
        public var excludedRoutes: [IPv4Route]?

        public init(
            addresses: [String],
            subnetMasks: [String],
            includedRoutes: [IPv4Route]? = nil,
            excludedRoutes: [IPv4Route]? = nil
        ) {
            self.addresses = addresses
            self.subnetMasks = subnetMasks
            self.includedRoutes = includedRoutes
            self.excludedRoutes = excludedRoutes
        }
    }

    public struct IPv6: Codable {
        public var addresses: [String]
        public var networkPrefixLengths: [UInt32]
        public var includedRoutes: [IPv6Route]?
        public var excludedRoutes: [IPv6Route]?

        public init(
            addresses: [String],
            networkPrefixLengths: [UInt32],
            includedRoutes: [IPv6Route]? = nil,
            excludedRoutes: [IPv6Route]? = nil
        ) {
            self.addresses = addresses
            self.networkPrefixLengths = networkPrefixLengths
            self.includedRoutes = includedRoutes
            self.excludedRoutes = excludedRoutes
        }
    }

    public struct DNS: Codable {
        public var servers: [String]
        public var searchDomains: [String]?
        public var matchDomains: [String]?

        public init(servers: [String], searchDomains: [String]? = nil, matchDomains: [String]? = nil) {
            self.servers = servers
            self.searchDomains = searchDomains
            self.matchDomains = matchDomains
        }
    }

    public var ipv4: IPv4?
    public var ipv6: IPv6?
    public var dns: DNS?
    public var mtu: UInt32?

    public init(ipv4: IPv4? = nil, ipv6: IPv6? = nil, dns: DNS? = nil, mtu: UInt32? = nil) {
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.dns = dns
        self.mtu = mtu
    }
}

public enum ProviderCommand: String, Codable, CaseIterable {
    case exportOSLog = "export_oslog"
    case runningInfo = "running_info"
    case lastNetworkSettings = "last_network_settings"
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
