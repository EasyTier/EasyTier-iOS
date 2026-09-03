@preconcurrency import NetworkExtension
import os

public let APP_BUNDLE_ID: String = "cn.easytier"
public let APP_GROUP_ID: String = "group.cn.easytier"
public let ICLOUD_CONTAINER_ID: String = "iCloud.cn.easytier"
public let LOG_FILENAME: String = "easytier.log"

public enum LogLevel: String, Codable, CaseIterable {
    case trace = "trace"
    case debug = "debug"
    case info = "info"
    case warn = "warn"
    case error = "error"
}

public enum EasyTierConnectionMode: String, Codable, CaseIterable {
    case local
    case web
}

public struct WebManagementOptions: Codable, Equatable {
    public var server: String
    public var machineID: String
    public var hostname: String

    public init(server: String = "", machineID: String = "", hostname: String = "") {
        self.server = server
        self.machineID = machineID
        self.hostname = hostname
    }
}

public struct EasyTierOptions: Codable {
    public var mode: EasyTierConnectionMode = .local
    public var webManagement: WebManagementOptions?
    public var config: String = ""
    public var ipv4: String?
    public var ipv6: String?
    public var mtu: Int?
    public var routes: [String] = []
    public var logLevel: LogLevel = .info
    public var magicDNS: Bool = false
    public var dns: [String] = []

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case mode, webManagement, config, ipv4, ipv6, mtu, routes, logLevel, magicDNS, dns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(EasyTierConnectionMode.self, forKey: .mode) ?? .local
        webManagement = try container.decodeIfPresent(WebManagementOptions.self, forKey: .webManagement)
        config = try container.decodeIfPresent(String.self, forKey: .config) ?? ""
        ipv4 = try container.decodeIfPresent(String.self, forKey: .ipv4)
        ipv6 = try container.decodeIfPresent(String.self, forKey: .ipv6)
        mtu = try container.decodeIfPresent(Int.self, forKey: .mtu)
        routes = try container.decodeIfPresent([String].self, forKey: .routes) ?? []
        logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
        magicDNS = try container.decodeIfPresent(Bool.self, forKey: .magicDNS) ?? false
        dns = try container.decodeIfPresent([String].self, forKey: .dns) ?? []
    }
}

public enum WebManagementState: String, Codable {
    case connectingServer = "connecting_server"
    case waitingConfig = "waiting_config"
    case running
    case error
}

public struct WebTunnelOptions: Codable, Equatable {
    public var ipv4: String?
    public var ipv6: String?
    public var mtu: Int?
    public var routes: [String]
    public var magicDNS: Bool
    public var dns: [String]

    public func asEasyTierOptions(logLevel: LogLevel) -> EasyTierOptions {
        var result = EasyTierOptions()
        result.mode = .web
        result.ipv4 = ipv4
        result.ipv6 = ipv6
        result.mtu = mtu
        result.routes = routes
        result.logLevel = logLevel
        result.magicDNS = magicDNS
        result.dns = dns
        return result
    }
}

public struct WebManagementStatus: Codable, Equatable {
    public var status: WebManagementState
    public var serverConnected: Bool
    public var instanceID: String?
    public var instanceName: String?
    public var networkName: String?
    public var generation: UInt64
    public var error: String?
    public var options: WebTunnelOptions?
}

public struct WebManagementEvent: Codable, Equatable {
    public var event: String
    public var instanceID: String
    public var instanceName: String
    public var networkName: String
    public var generation: UInt64

    private enum CodingKeys: String, CodingKey {
        case event, generation
        case instanceID = "instance_id"
        case instanceName = "instance_name"
        case networkName = "network_name"
    }
}

public struct TunnelNetworkSettingsSnapshot: Codable, Equatable {
    public struct IPv4Subnet: Codable, Hashable {
        public var address: String
        public var subnetMask: String

        public init(address: String, subnetMask: String) {
            self.address = address
            self.subnetMask = subnetMask
        }
    }

    public struct IPv6Subnet: Codable, Hashable {
        public var address: String
        public var networkPrefixLength: Int

        public init(address: String, networkPrefixLength: Int) {
            self.address = address
            self.networkPrefixLength = networkPrefixLength
        }
    }

    public struct IPv4: Codable, Equatable {
        public var subnets: Set<IPv4Subnet>
        public var includedRoutes: Set<IPv4Subnet>?
        public var excludedRoutes: Set<IPv4Subnet>?

        public init(
            addresses: [String],
            subnetMasks: [String],
            includedRoutes: [IPv4Subnet]? = nil,
            excludedRoutes: [IPv4Subnet]? = nil
        ) {
            subnets = .init()
            for (index, address) in addresses.enumerated() {
                subnets.insert(
                    IPv4Subnet(address: address, subnetMask: subnetMasks[index])
                )
            }
            if let includedRoutes, !includedRoutes.isEmpty {
                self.includedRoutes = Set(includedRoutes)
            }
            if let excludedRoutes, !excludedRoutes.isEmpty {
                self.excludedRoutes = Set(excludedRoutes)
            }
        }
    }

    public struct IPv6: Codable, Equatable {
        public var subnets: Set<IPv6Subnet>
        public var includedRoutes: Set<IPv6Subnet>?
        public var excludedRoutes: Set<IPv6Subnet>?

        public init(
            addresses: [String],
            networkPrefixLengths: [Int],
            includedRoutes: [IPv6Subnet]? = nil,
            excludedRoutes: [IPv6Subnet]? = nil
        ) {
            subnets = .init()
            for (index, address) in addresses.enumerated() {
                subnets.insert(
                    IPv6Subnet(
                        address: address,
                        networkPrefixLength: networkPrefixLengths[index]
                    )
                )
            }
            if let includedRoutes {
                self.includedRoutes = Set(includedRoutes)
            }
            if let excludedRoutes {
                self.excludedRoutes = Set(excludedRoutes)
            }
        }
    }

    public struct DNS: Codable, Equatable {
        public var servers: Set<String>
        public var searchDomains: Set<String>?
        public var matchDomains: Set<String>?

        public init(
            servers: [String],
            searchDomains: [String]? = nil,
            matchDomains: [String]? = nil
        ) {
            self.servers = Set(servers)
            if let searchDomains {
                self.searchDomains = Set(searchDomains)
            }
            if let matchDomains {
                self.matchDomains = Set(matchDomains)
            }
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
    case clearLog = "clear_log"
    case exportOSLog = "export_oslog"
    case runningInfo = "running_info"
    case lastNetworkSettings = "last_network_settings"
    case webManagementStatus = "web_management_status"
}

public enum TunnelManagerError: LocalizedError {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "EasyTier VPN configuration is unavailable."
        }
    }
}

private func configureManagerForConnection(_ manager: NETunnelProviderManager, logger: Logger?) {
    manager.isEnabled = true
    if let defaults = UserDefaults(suiteName: APP_GROUP_ID) {
        manager.protocolConfiguration?.includeAllNetworks = defaults.bool(forKey: "includeAllNetworks")
        manager.protocolConfiguration?.excludeLocalNetworks = defaults.bool(forKey: "excludeLocalNetworks")
        if #available(iOS 16.4, macOS 13.3, *) {
            manager.protocolConfiguration?.excludeCellularServices = defaults.bool(forKey: "excludeCellularServices")
            manager.protocolConfiguration?.excludeAPNs = defaults.bool(forKey: "excludeAPNs")
        }
        if #available(iOS 17.4, macOS 14.4, *) {
            manager.protocolConfiguration?.excludeDeviceCommunication = defaults.bool(forKey: "excludeDeviceCommunication")
        }
        manager.protocolConfiguration?.enforceRoutes = defaults.bool(forKey: "enforceRoutes")
        if let logger {
            logger.debug("connect with protocol configuration: \(manager.protocolConfiguration)")
        }
    }
}

public func connectWithManager(_ manager: NETunnelProviderManager, logger: Logger? = nil) async throws {
    configureManagerForConnection(manager, logger: logger)
    try await manager.saveToPreferences()
    try manager.connection.startVPNTunnel()
}

public func connectWithManager(_ manager: NETunnelProviderManager, logger: Logger? = nil, completionHandler: (@Sendable ((any Error)?) -> Void)? = nil) {
    configureManagerForConnection(manager, logger: logger)
    manager.saveToPreferences() { error in
        if let error {
            completionHandler?(error)
            return
        }
        do {
            try manager.connection.startVPNTunnel()
        } catch {
            completionHandler?(error)
            return
        }
        completionHandler?(nil)
    }
}
