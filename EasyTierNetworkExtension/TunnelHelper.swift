import Foundation
import NetworkExtension
import os

import EasyTierShared

let magicDNSCIDR = RunningIPv4CIDR(from: "100.100.100.101/32")!

struct TunnelIPState: Equatable {
    let v4Address: String?
    let v4SubnetMask: String?
    
    let v6Address: String?
    let v6PrefixLength: Int?

    init(from settings: NEPacketTunnelNetworkSettings?) {
        let v4 = settings?.ipv4Settings
        self.v4Address = v4?.addresses.first
        self.v4SubnetMask = v4?.subnetMasks.first

        let v6 = settings?.ipv6Settings
        self.v6Address = v6?.addresses.first
        self.v6PrefixLength = v6?.networkPrefixLengths.first?.intValue
    }
    
    init() {
        v4Address = nil
        v4SubnetMask = nil
        v6Address = nil
        v6PrefixLength = nil
    }
    
    var isEmpty: Bool {
        return v4Address == nil && v6Address == nil
    }
}

func tunnelFileDescriptor() -> Int32? {
    logger.warning("tunnelFileDescriptor() use fallback")
    var ctlInfo = ctl_info()
    withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
            _ = strcpy($0, "com.apple.net.utun_control")
        }
    }
    for fd: Int32 in 0...1024 {
        var addr = sockaddr_ctl()
        var ret: Int32 = -1
        var len = socklen_t(MemoryLayout.size(ofValue: addr))
        withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                ret = getpeername(fd, $0, &len)
            }
        }
        if ret != 0 || addr.sc_family != AF_SYSTEM {
            continue
        }
        if ctlInfo.ctl_id == 0 {
            ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
            if ret != 0 {
                continue
            }
        }
        if addr.sc_id == ctlInfo.ctl_id {
            logger.info("tunnelFileDescriptor() found fd: \(fd, privacy: .public)")
            return fd
        }
    }
    return nil
}

func initRustLogger(level: LogLevel) {
    guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: APP_GROUP_ID) else {
        logger.error("initRustLogger() failed: App Group container not found")
        return
    }
    let path = containerURL.appendingPathComponent(LOG_FILENAME).path
    logger.info("initRustLogger() write to: \(path, privacy: .public)")
    
    var errPtr: UnsafePointer<CChar>? = nil
    let ret = path.withCString { pathPtr in
        level.rawValue.withCString { levelPtr in
            return init_logger(pathPtr, levelPtr, &errPtr)
        }
    }
    if ret != 0 {
        let err = extractRustString(errPtr)
        logger.error("initRustLogger() failed to init: \(err ?? "Unknown", privacy: .public)")
    }
}

func extractRustString(_ strPtr: UnsafePointer<CChar>?) -> String? {
    guard let strPtr else {
        logger.error("extractRustString(): nullptr")
        return nil
    }
    let str = String(cString: strPtr)
    free_string(strPtr)
    return str
}

func fetchRunningInfo() -> RunningInfo? {
    var infoPtr: UnsafePointer<CChar>? = nil
    var errPtr: UnsafePointer<CChar>? = nil
    if get_running_info(&infoPtr, &errPtr) == 0, let info = extractRustString(infoPtr) {
        guard let data = info.data(using: .utf8) else {
            logger.error("fetchRunningInfo() invalid utf8 data")
            return nil
        }
        do {
            let decoded = try JSONDecoder().decode(RunningInfo.self, from: data)
            logger.info("fetchRunningInfo() routes: \(decoded.routes.count)")
            return decoded
        } catch {
            logger.error("fetchRunningInfo() json decode failed: \(error, privacy: .public)")
        }
    } else if let err = extractRustString(errPtr) {
        logger.error("fetchRunningInfo() failed: \(err, privacy: .public)")
    }
    return nil
}

func buildIPv4Routes(info: RunningInfo?, options: EasyTierOptions) -> [NEIPv4Route] {
    var cidrs = Set<RunningIPv4CIDR>()
    if !options.routes.isEmpty {
        logger.info("buildIPv4Routes() found manual routes: \(options.routes.count)")
        for route in options.routes {
            if let normalized = normalizeCIDR(route) {
                cidrs.insert(normalized)
            }
        }
    } else {
        if let routes = info?.routes {
            for route in routes {
                for cidr in route.proxyCIDRs {
                    if let normalized = normalizeCIDR(cidr) {
                        cidrs.insert(normalized)
                    }
                }
            }
        }
        if let ipv4 = options.ipv4, let cidr = RunningIPv4CIDR(from: ipv4) {
            cidrs.insert(.init(address: ipv4MaskedSubnet(cidr), length: cidr.networkLength))
        }
        if let ipv4 = info?.myNodeInfo?.virtualIPv4 {
            cidrs.insert(.init(address: ipv4MaskedSubnet(ipv4), length: ipv4.networkLength))
        }
        if options.magicDNS {
            cidrs.insert(magicDNSCIDR)
        }
        if cidrs.isEmpty {
            logger.warning("buildIPv4Routes() no routes")
        }
    }
    return cidrs.compactMap { cidr in
        guard let mask = cidrToSubnetMask(cidr.networkLength) else {
            logger.warning("buildIPv4Routes() invalid cidr length: \(cidr.networkLength, privacy: .public)")
            return nil
        }
        return NEIPv4Route(destinationAddress: cidr.address.description, subnetMask: mask)
    }
}

func buildDNSServers(options: EasyTierOptions) -> NEDNSSettings? {
    guard options.magicDNS else { return nil }
    let settings = NEDNSSettings(servers: [magicDNSCIDR.address.description])
    settings.matchDomains = ["et.net"]
    logger.info("buildDNSServers() enabled magic dns")
    settings.searchDomains = ["et.net"]
    return settings
}

func normalizeCIDR(_ cidr: String) -> RunningIPv4CIDR? {
    guard var cidrStruct = RunningIPv4CIDR(from: cidr) else { return nil }
    cidrStruct.address = ipv4MaskedSubnet(cidrStruct)
    return cidrStruct
}

func cidrToSubnetMask(_ cidr: Int) -> String? {
    guard cidr >= 0 && cidr <= 32 else { return nil }
    
    let mask: UInt32 = cidr == 0 ? 0 : UInt32.max << (32 - cidr)
    
    let octet1 = (mask >> 24) & 0xFF
    let octet2 = (mask >> 16) & 0xFF
    let octet3 = (mask >> 8) & 0xFF
    let octet4 = mask & 0xFF
    
    return "\(octet1).\(octet2).\(octet3).\(octet4)"
}

func ipv4MaskedSubnet(_ cidr: RunningIPv4CIDR) -> RunningIPv4Addr {
    let mask: UInt32 = cidr.networkLength == 0 ? 0 : UInt32.max << (32 - cidr.networkLength)
    return RunningIPv4Addr(addr: cidr.address.addr & mask)
}

