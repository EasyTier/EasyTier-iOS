import Foundation

struct RunningInfo: Decodable {
    var myNodeInfo: RunningNodeInfo?
    var routes: [RunningRoute]

    enum CodingKeys: String, CodingKey {
        case myNodeInfo = "my_node_info"
        case routes
    }
}

extension RunningInfo {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        myNodeInfo = try container.decodeIfPresent(RunningNodeInfo.self, forKey: .myNodeInfo)
        // Protobuf JSON omits the route list when no peers are known yet.
        routes = try container.decodeIfPresent([RunningRoute].self, forKey: .routes) ?? []
    }
}

struct RunningNodeInfo: Decodable {
    var virtualIPv4: RunningIPv4CIDR?

    enum CodingKeys: String, CodingKey {
        case virtualIPv4 = "virtual_ipv4"
    }
}

struct RunningRoute: Decodable {
    var proxyCIDRs: [String]

    enum CodingKeys: String, CodingKey {
        case proxyCIDRs = "proxy_cidrs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Protobuf JSON omits empty lists for peers without advertised subnets.
        proxyCIDRs = try container.decodeIfPresent([String].self, forKey: .proxyCIDRs) ?? []
    }
}

struct RunningIPv4CIDR: Decodable, Hashable {
    var address: RunningIPv4Addr
    var networkLength: Int

    init?(from string: String) {
        // Expect CIDR notation like "192.168.1.10/24"
        let toParsed = string.contains("/") ? string : string + "/32"
        let parts = toParsed.split(separator: "/")
        guard parts.count == 2,
              let addr = RunningIPv4Addr(from: String(parts[0])),
              let length = Int(parts[1]),
              (0...32).contains(length) else {
            return nil
        }
        self.address = addr
        self.networkLength = length
    }
    
    init(address: RunningIPv4Addr, length: Int) {
        self.address = address
        networkLength = length
    }

    enum CodingKeys: String, CodingKey {
        case address
        case networkLength = "network_length"
    }
}

struct RunningIPv4Addr: Decodable, Hashable {
    var addr: UInt32
    
    init(addr: UInt32) {
        self.addr = addr
    }

    init?(from string: String) {
        // Expect dotted-quad IPv4, e.g., "192.168.1.10"
        let parts = string.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var bytes = [UInt32]()
        bytes.reserveCapacity(4)
        for p in parts {
            guard let val = UInt32(p), val <= 255 else { return nil }
            bytes.append(val)
        }
        // Pack into network-order (big-endian) 32-bit integer
        self.addr = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]
    }

    var description: String {
        let ip = addr
        return "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
    }
}

// Restore omitted protobuf scalar defaults, matching the main app's status models.
extension RunningIPv4CIDR {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(RunningIPv4Addr.self, forKey: .address)
        networkLength = try container.decodeIfPresent(Int.self, forKey: .networkLength) ?? 0
    }
}

extension RunningIPv4Addr {
    private enum CodingKeys: String, CodingKey { case addr }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addr = try container.decodeIfPresent(UInt32.self, forKey: .addr) ?? 0
    }
}

