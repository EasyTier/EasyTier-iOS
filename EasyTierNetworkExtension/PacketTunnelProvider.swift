import os
import NetworkExtension
import Foundation

let appName = "site.yinmo.easytier.tunnel"
let appGroupID = "group.site.yinmo.easytier"

enum ProviderCommand: String {
    case exportOSLog = "export_oslog"
    case runningInfo = "running_info"
}

let logger = Logger(subsystem: appName, category: "swift")

private struct ProviderMessageResponse: Codable {
    let ok: Bool
    let path: String?
    let error: String?
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    // Hold a weak reference to the current provider for C callback bridging
    private static weak var current: PacketTunnelProvider?

    private var lastOptions: [String: NSObject] = [:]
    private let settingsUpdateQueue = DispatchQueue(label: "site.yinmo.easytier.tunnel.settings-update")
    private var isApplyingSettings = false
    private var needReapplySettings = false
    
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
    
    private func prepareSettings(_ options: [String : NSObject]) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let runningInfo = fetchRunningInfo()
        if runningInfo == nil {
            logger.warning("prepareSettings() running info is nil")
        }

        let ipv4Settings: NEIPv4Settings
        if let ipv4 = runningInfo?.myNodeInfo?.virtualIPv4,
           let mask = cidrToSubnetMask(ipv4.networkLength) {
            ipv4Settings = NEIPv4Settings(
                addresses: [ipv4.address.description],
                subnetMasks: [mask]
            )
        } else if let ipv4 = options["ipv4"] as? String,
                  let cidr = RunningIPv4CIDR(from: ipv4),
                  let mask = cidrToSubnetMask(cidr.networkLength) {
            ipv4Settings = NEIPv4Settings(
                addresses: [cidr.address.description],
                subnetMasks: [mask]
            )
        } else {
            logger.warning("prepareSettings() no ipv4 address, skipping all")
            return NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        }
        let routes = buildIPv4Routes(info: runningInfo, options: options)
        if !routes.isEmpty {
            logger.info("prepareSettings() ipv4 routes: \(routes.count)")
            ipv4Settings.includedRoutes = routes
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

        if let dns = buildDNSServers(options: options) {
            settings.dnsSettings = dns
        }
        
        settings.mtu = options["mtu"] as? NSNumber
        logger.info("prepareSettings(): \(settings, privacy: .public)")

        return settings
    }

    private func handleRunningInfoChanged() {
        logger.warning("handleRunningInfoChanged(): triggered")
        enqueueSettingsUpdate()
    }

    private func enqueueSettingsUpdate() {
        settingsUpdateQueue.async { [weak self] in
            guard let self else { return }
            if self.isApplyingSettings {
                logger.info("enqueueSettingsUpdate(): update in progress, waiting")
                self.needReapplySettings = true
                return
            }
            self.isApplyingSettings = true
            self.needReapplySettings = false
            logger.info("enqueueSettingsUpdate(): starting settings update")
            DispatchQueue.main.async { [weak self] in
                self?.applyNetworkSettings()
            }
        }
    }

    private func applyNetworkSettings() {
        let settings = prepareSettings(lastOptions)
        self.reasserting = true
        logger.info("applyNetworkSettings(): applying settings")
        self.setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            self.reasserting = false
            if let error {
                logger.error("handleRunningInfoChanged() failed to setTunnelNetworkSettings: \(error, privacy: .public)")
                self.notifyHostAppError(error.localizedDescription)
                self.finishSettingsUpdate()
                return
            }
            self.finishSettingsUpdate()
            logger.info("applyNetworkSettings(): settings applied")
        }
    }

    private func finishSettingsUpdate() {
        settingsUpdateQueue.async { [weak self] in
            guard let self else { return }
            self.isApplyingSettings = false
            guard self.needReapplySettings else {
                // only update tun fd when it is the last setting update
                let tunFd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 ?? tunnelFileDescriptor()
                if let tunFd {
                    DispatchQueue.global(qos: .default).async { [weak self] in
                        var errPtr: UnsafePointer<CChar>? = nil
                        let ret = set_tun_fd(tunFd, &errPtr)
                        guard ret == 0 else {
                            let err = extractRustString(errPtr)
                            logger.error("handleRunningInfoChanged() failed to set tun fd to \(tunFd): \(err, privacy: .public)")
                            self?.notifyHostAppError(err ?? "Unknown")
                            return
                        }
                    }
                } else {
                    logger.error("handleRunningInfoChanged() no available tun fd")
                    notifyHostAppError("no available tun fd")
                }
                return
            }
            self.needReapplySettings = false
            self.isApplyingSettings = true
            logger.info("finishSettingsUpdate(): reapplying settings")
            DispatchQueue.main.async { [weak self] in
                self?.applyNetworkSettings()
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
        initRustLogger(level: options["logLevel"] as? String ?? "info")
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
        self.lastOptions = options
        enqueueSettingsUpdate()
        completionHandler(nil)
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
        logger.debug("handleAppMessage(): triggered")
        // Add code here to handle the message.
        guard let completionHandler else { return }
        if let raw = String(data: messageData, encoding: .utf8),
           let command = ProviderCommand(rawValue: raw) {
            switch command {
            case .exportOSLog:
                do {
                    let url = try OSLogExporter.exportToAppGroup(appGroupID: appGroupID)
                    let response = ProviderMessageResponse(ok: true, path: url.path, error: nil)
                    let data = try JSONEncoder().encode(response)
                    completionHandler(data)
                } catch {
                    let response = ProviderMessageResponse(ok: false, path: nil, error: error.localizedDescription)
                    let data = try? JSONEncoder().encode(response)
                    completionHandler(data)
                }
            case .runningInfo:
                var infoPtr: UnsafePointer<CChar>? = nil
                var errPtr: UnsafePointer<CChar>? = nil
                if get_running_info(&infoPtr, &errPtr) == 0, let info = extractRustString(infoPtr) {
                    completionHandler(info.data(using: .utf8))
                } else if let err = extractRustString(errPtr) {
                    logger.error("handleAppMessage() failed: \(err, privacy: .public)")
                    completionHandler(nil)
                } else {
                    completionHandler(nil)
                }
            }
            return
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
