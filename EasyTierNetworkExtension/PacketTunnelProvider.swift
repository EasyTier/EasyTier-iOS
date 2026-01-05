import os
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    let logger = Logger(subsystem: "site.yinmo.easytier.tunnel", category: "swift")
    
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
        let appGroupID = "group.site.yinmo.easytier"
        let filename = "easytier.log"
        let level = "info"
        
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
        
        if let ipv4CIDR = (options["ipv4"] as? String)?.split(separator: "/"), ipv4CIDR.count == 2 {
            let ip = ipv4CIDR[0], cidrStr = ipv4CIDR[1]
            if let cidr = Int(cidrStr),
                let mask = cidrToSubnetMask(cidr) {
                settings.ipv4Settings = .init(
                    addresses: [String(ip)],
                    subnetMasks: [mask]
                )
            }
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
        if let mtu = options["mtu"] as? NSNumber {
            settings.mtu = mtu
        }
        
        return settings
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.warning("startTunnel(): triggered")
        guard let options else {
            logger.error("startTunnel() options is nil")
            completionHandler("options is nil")
            return
        }
        
        guard let config = options["config"] as? String else {
            logger.error("startTunnel() config is empty")
            completionHandler("config is empty")
            return
        }
        initRustLogger()
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = config.withCString { strPtr in
            return run_network_instance(strPtr, &errPtr)
        }
        guard ret == 0 else {
            let err = extractRustString(errPtr)
            logger.error("startTunnel() failed to run: \(err ?? "Unknown", privacy: .public)")
            completionHandler(err)
            return
        }

        self.setTunnelNetworkSettings(prepareSettings(options)) { [weak self] error in
            if let error {
                self?.logger.error("startTunnel() failed to setTunnelNetworkSettings: \(error, privacy: .public)")
                completionHandler(error)
                return
            }
            let tunFd = self?.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 ?? self?.tunnelFileDescriptor
            guard let tunFd else {
                self?.logger.error("startTunnel() no available tun fd")
                completionHandler("no available tun fd")
                return
            }
            DispatchQueue.global(qos: .default).async {
                var errPtr: UnsafePointer<CChar>? = nil
                let ret = set_tun_fd(tunFd, &errPtr)
                guard ret == 0 else {
                    let err = self?.extractRustString(errPtr)
                    self?.logger.error("startTunnel() failed to set tun fd to \(tunFd): \(err, privacy: .public)")
                    completionHandler(err)
                    return
                }
            }
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.info("stopTunnel(): triggered")
        let ret = stop_network_instance()
        if ret != 0 {
            logger.error("stopTunnel() failed")
        }
        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        logger.info("handleAppMessage(): triggered")
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
