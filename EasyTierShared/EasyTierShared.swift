public let APP_BUNDLE_ID: String = "group.site.yinmo.easytier"
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
    public var dns: [String] = []
    
    public init() {}
}
