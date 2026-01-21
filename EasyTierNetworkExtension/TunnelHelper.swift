import Foundation
import NetworkExtension
import os

import EasyTierShared

extension PacketTunnelProvider {
    func snapshotSettings(_ settings: NEPacketTunnelNetworkSettings) -> TunnelNetworkSettingsSnapshot {
        let ipv4 = settings.ipv4Settings.map { ipv4 in
            TunnelNetworkSettingsSnapshot.IPv4(
                addresses: ipv4.addresses,
                subnetMasks: ipv4.subnetMasks,
                includedRoutes: mapIPv4Routes(ipv4.includedRoutes),
                excludedRoutes: mapIPv4Routes(ipv4.excludedRoutes)
            )
        }
        let ipv6 = settings.ipv6Settings.map { ipv6 in
            TunnelNetworkSettingsSnapshot.IPv6(
                addresses: ipv6.addresses,
                networkPrefixLengths: ipv6.networkPrefixLengths.map { UInt32($0.intValue) },
                includedRoutes: mapIPv6Routes(ipv6.includedRoutes),
                excludedRoutes: mapIPv6Routes(ipv6.excludedRoutes)
            )
        }
        let dns = settings.dnsSettings.map { dns in
            TunnelNetworkSettingsSnapshot.DNS(
                servers: dns.servers,
                searchDomains: dns.searchDomains,
                matchDomains: dns.matchDomains
            )
        }
        return .init(
            ipv4: ipv4,
            ipv6: ipv6,
            dns: dns,
            mtu: settings.mtu?.uint32Value
        )
    }

    func shouldUpdateTunFd(old: TunnelNetworkSettingsSnapshot?, new: TunnelNetworkSettingsSnapshot) -> Bool {
        guard hasIPAddresses(new) else { return false }
        guard let old else { return true }
        let oldV4 = old.ipv4?.addresses.first
        let oldV6 = old.ipv6?.addresses.first
        let newV4 = new.ipv4?.addresses.first
        let newV6 = new.ipv6?.addresses.first
        return oldV4 != newV4 || oldV6 != newV6
    }

    private func hasIPAddresses(_ settings: TunnelNetworkSettingsSnapshot) -> Bool {
        let v4 = settings.ipv4?.addresses.first?.isEmpty == false
        let v6 = settings.ipv6?.addresses.first?.isEmpty == false
        return v4 || v6
    }

    private func mapIPv4Routes(_ routes: [NEIPv4Route]?) -> [TunnelNetworkSettingsSnapshot.IPv4Route]? {
        guard let routes, !routes.isEmpty else { return nil }
        return routes.map {
            .init(destination: $0.destinationAddress, subnetMask: $0.destinationSubnetMask)
        }
    }

    private func mapIPv6Routes(_ routes: [NEIPv6Route]?) -> [TunnelNetworkSettingsSnapshot.IPv6Route]? {
        guard let routes, !routes.isEmpty else { return nil }
        return routes.map {
            .init(destination: $0.destinationAddress, networkPrefixLength: UInt32($0.destinationNetworkPrefixLength.intValue))
        }
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
            loggerSubsystem.withCString { subsystemPtr in
                return init_logger(pathPtr, levelPtr, subsystemPtr, &errPtr)
            }
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
