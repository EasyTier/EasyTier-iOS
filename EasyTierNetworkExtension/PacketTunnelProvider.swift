import os
import NetworkExtension
import Foundation

let appName = "site.yinmo.easytier.tunnel"
let appGroupID = "group.site.yinmo.easytier"
let magicDNSIP = "100.100.100.101"
let magicDNSCIDR = "100.100.100.101/32"

class PacketTunnelProvider: NEPacketTunnelProvider {
    // Hold a weak reference to the current provider for C callback bridging
    private static weak var current: PacketTunnelProvider?

    let logger = Logger(subsystem: appName, category: "swift")
    private var lastOptions: [String: NSObject]?
    
    private var tunnelFileDescriptor: Int32? {
        logger.warning("tunnelFileDescriptor: use fallback")
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
                return fd
            }
        }
        return nil
    }
    
    func initRustLogger() {
        let filename = "easytier.log"
        let level = "trace"
        
        guard var containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            logger.error("initRustLogger() failed: App Group container not found")
            return
        }
        containerURL.append(component: filename)
        let path = containerURL.path(percentEncoded: false)
        logger.warning("initRustLogger() write to: \(path)")
        
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = path.withCString { pathPtr in
            level.withCString { levelPtr in
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
    
    private func handleRustStop() {
        // Called from FFI callback on an arbitrary thread
        var msgPtr: UnsafePointer<CChar>? = nil
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = get_latest_error_msg(&msgPtr, &errPtr)
        if ret == 0, let msg = extractRustString(msgPtr) {
            logger.error("handleRustStop(): \(msg, privacy: .public)")
            // Inform host app and cancel the tunnel on main queue
            DispatchQueue.main.async {
                self.notifyHostAppError(msg)
                self.cancelTunnelWithError(msg)
            }
        } else if let err = extractRustString(errPtr) {
            logger.error("handleRustStop() failed to get latest error: \(err, privacy: .public)")
        }
    }
    
    private func postDarwinNotification(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }
    
    private func notifyHostAppError(_ message: String) {
        // Persist the latest error into shared defaults so the host app can read details
        if let defaults = UserDefaults(suiteName: appGroupID) {
            defaults.set(message, forKey: "TunnelLastError")
            defaults.synchronize()
        }
        // Wake the host app via Darwin notification
        postDarwinNotification("\(appName).error")
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
    
    func prepareSettings(_ options: [String : NSObject]) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "0.0.0.0")
        let runningInfo = fetchRunningInfo()
        if runningInfo == nil {
            logger.warning("prepareSettings() running info is nil")
        }

        if let ipv4 = runningInfo?.myNodeInfo?.virtualIPv4,
           let mask = cidrToSubnetMask(ipv4.networkLength) {
            logger.info("prepareSettings() ipv4 \(ipv4.address.description)/\(ipv4.networkLength)")
            let ipv4Settings = NEIPv4Settings(
                addresses: [ipv4.address.description],
                subnetMasks: [mask]
            )
            let routes = buildIPv4Routes(from: runningInfo)
            if routes.isEmpty {
                logger.warning("prepareSettings() no ipv4 routes")
            } else {
                logger.info("prepareSettings() ipv4 routes: \(routes.count)")
            }
            if !routes.isEmpty {
                ipv4Settings.includedRoutes = routes
            }
            settings.ipv4Settings = ipv4Settings
        }

        if let ipv6CIDR = (options["ipv6"] as? String)?.split(separator: "/"), ipv6CIDR.count == 2 {
            let ip = ipv6CIDR[0], cidrStr = ipv6CIDR[1]
            if let cidr = Int(cidrStr) {
                settings.ipv6Settings = .init(
                    addresses: [String(ip)],
                    networkPrefixLengths: [NSNumber(value: cidr)]
                )
            }
        }

        if let dns = buildDNSServers(from: runningInfo, options: options) {
            settings.dnsSettings = NEDNSSettings(servers: dns)
        }
        
        settings.mtu = options["mtu"] as? NSNumber

        logger.warning("prepareSettings() result: \(settings, privacy: .public)")

        return settings
    }

    private func fetchRunningInfo() -> RunningInfo? {
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

    private func buildIPv4Routes(from info: RunningInfo?) -> [NEIPv4Route] {
        guard let info else { return [] }
        var cidrs = Set<String>()
        for route in info.routes {
            for cidr in route.proxyCIDRs {
                if let normalized = normalizeCIDR(cidr) {
                    cidrs.insert(normalized)
                }
            }
        }
//        if let ipv4 = info.myNodeInfo?.virtualIPv4 {
//            cidrs.insert("\(ipv4.address)/\(ipv4.networkLength)")
//        }
        if let dns = buildDNSServers(from: info, options: nil),
           dns.contains(magicDNSIP) {
            cidrs.insert(magicDNSCIDR)
        }
        if cidrs.isEmpty {
            logger.warning("buildIPv4Routes() no proxy cidrs")
        }
        var routes: [NEIPv4Route] = cidrs.compactMap { cidr in
            let parts = cidr.split(separator: "/")
            guard parts.count == 2, let maskLen = Int(parts[1]),
                  let mask = cidrToSubnetMask(maskLen) else {
                logger.warning("buildIPv4Routes() invalid cidr: \(cidr)")
                return nil
            }
            return NEIPv4Route(destinationAddress: String(parts[0]), subnetMask: mask)
        }
//        routes.append(NEIPv4Route.default())
        return routes
    }

    private func buildDNSServers(from info: RunningInfo?, options: [String: NSObject]?) -> [String]? {
        if let dns = options?["dns"] as? String, !dns.isEmpty {
            logger.info("buildDNSServers() use options dns: \(dns)")
            return [dns]
        }
        guard let info else { return nil }
        let hasMagicDNSRoute = info.routes.contains { route in
            route.proxyCIDRs.contains { normalizeCIDR($0) == magicDNSCIDR }
        }
        if hasMagicDNSRoute {
            logger.info("buildDNSServers() enable magic dns")
        }
        return hasMagicDNSRoute ? [magicDNSIP] : nil
    }

    private func normalizeCIDR(_ cidr: String) -> String? {
        if cidr.contains("/") {
            return cidr
        }
        guard !cidr.isEmpty else { return nil }
        return "\(cidr)/32"
    }

    private func handleRunningInfoChanged() {
        logger.warning("handleRunningInfoChanged(): triggered")
        guard let options = lastOptions else {
            logger.warning("handleRunningInfoChanged() options is nil")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setTunnelNetworkSettings(self.prepareSettings(options)) { error in
                if let error {
                    self.logger.error("handleRunningInfoChanged() setTunnelNetworkSettings failed: \(error, privacy: .public)")
                    self.notifyHostAppError(error.localizedDescription)
                } else {
                    self.logger.info("handleRunningInfoChanged() updated tunnel settings")
                }
            }
        }
    }

    private func registerRunningInfoCallback() {
        let infoChangedCallback: @convention(c) () -> Void = {
            PacketTunnelProvider.current?.handleRunningInfoChanged()
        }
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = register_running_info_callback(infoChangedCallback, &errPtr)
        if ret != 0 {
            let err = extractRustString(errPtr)
            logger.error("registerRunningInfoCallback() failed: \(err ?? "Unknown", privacy: .public)")
        } else {
            logger.info("registerRunningInfoCallback() registered")
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.warning("startTunnel(): triggered")
        PacketTunnelProvider.current = self
        guard let options else {
            logger.error("startTunnel() options is nil")
            self.notifyHostAppError("options is nil")
            completionHandler("options is nil")
            return
        }
        
        guard let config = options["config"] as? String else {
            logger.error("startTunnel() config is empty")
            self.notifyHostAppError("config is empty")
            completionHandler("config is empty")
            return
        }
        self.lastOptions = options
        initRustLogger()
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = config.withCString { strPtr in
            return run_network_instance(strPtr, &errPtr)
        }
        guard ret == 0 else {
            let err = extractRustString(errPtr)
            logger.error("startTunnel() failed to run: \(err ?? "Unknown", privacy: .public)")
            self.notifyHostAppError(err ?? "Unknown")
            completionHandler(err)
            return
        }
        // Register FFI stop callback to capture crashes/stop events
        let rustStopCallback: @convention(c) () -> Void = {
            PacketTunnelProvider.current?.handleRustStop()
        }
        do {
            var regErrPtr: UnsafePointer<CChar>? = nil
            let regRet = register_stop_callback(rustStopCallback, &regErrPtr)
            if regRet != 0 {
                let regErr = extractRustString(regErrPtr)
                logger.error("startTunnel() failed to register stop callback: \(regErr ?? "Unknown", privacy: .public)")
            } else {
                logger.info("startTunnel() registered FFI stop callback")
            }
        }
        registerRunningInfoCallback()

        self.setTunnelNetworkSettings(prepareSettings(options)) { [weak self] error in
            if let error {
                self?.logger.error("startTunnel() failed to setTunnelNetworkSettings: \(error, privacy: .public)")
                self?.notifyHostAppError(error.localizedDescription)
                completionHandler(error)
                return
            }
            let tunFd = self?.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 ?? self?.tunnelFileDescriptor
            guard let tunFd else {
                self?.logger.error("startTunnel() no available tun fd")
                self?.notifyHostAppError("no available tun fd")
                completionHandler("no available tun fd")
                return
            }
            DispatchQueue.global(qos: .default).async {
                var errPtr: UnsafePointer<CChar>? = nil
                let ret = set_tun_fd(tunFd, &errPtr)
                guard ret == 0 else {
                    let err = self?.extractRustString(errPtr)
                    self?.logger.error("startTunnel() failed to set tun fd to \(tunFd): \(err, privacy: .public)")
                    self?.notifyHostAppError(err ?? "Unknown")
                    completionHandler(err)
                    return
                }
            }
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.warning("stopTunnel(): triggered")
        let ret = stop_network_instance()
        if ret != 0 {
            logger.error("stopTunnel() failed")
        }
        PacketTunnelProvider.current = nil
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        logger.warning("handleAppMessage(): triggered")
        // Add code here to handle the message.
        guard let completionHandler else { return }
        var infoPtr: UnsafePointer<CChar>? = nil
        var errPtr: UnsafePointer<CChar>? = nil
        if get_running_info(&infoPtr, &errPtr) == 0, let info = extractRustString(infoPtr) {
            completionHandler(info.data(using: .utf8))
            return
        } else if let err = extractRustString(errPtr) {
            logger.error("handleAppMessage() failed: \(err, privacy: .public)")
        }
        completionHandler(nil)
    }
    
    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }
    
    override func wake() {
        // Add code here to wake up.
    }
}

extension String: @retroactive Error {}

private struct RunningInfo: Decodable {
    var myNodeInfo: RunningNodeInfo?
    var routes: [RunningRoute]

    enum CodingKeys: String, CodingKey {
        case myNodeInfo = "my_node_info"
        case routes
    }
}

private struct RunningNodeInfo: Decodable {
    var virtualIPv4: RunningIPv4CIDR?

    enum CodingKeys: String, CodingKey {
        case virtualIPv4 = "virtual_ipv4"
    }
}

private struct RunningRoute: Decodable {
    var proxyCIDRs: [String]

    enum CodingKeys: String, CodingKey {
        case proxyCIDRs = "proxy_cidrs"
    }
}

private struct RunningIPv4CIDR: Decodable {
    var address: RunningIPv4Addr
    var networkLength: Int

    enum CodingKeys: String, CodingKey {
        case address
        case networkLength = "network_length"
    }
}

private struct RunningIPv4Addr: Decodable {
    var addr: UInt32

    var description: String {
        let ip = addr
        return "\((ip >> 24) & 0xFF).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
    }
}
