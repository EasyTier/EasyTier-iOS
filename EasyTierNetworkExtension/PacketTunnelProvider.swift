import os
import NetworkExtension
import Network
import Foundation

import EasyTierShared


enum ProviderCommand: String {
    case exportOSLog = "export_oslog"
    case runningInfo = "running_info"
}

let logger = Logger(subsystem: APP_BUNDLE_ID, category: "swift")

private struct ProviderMessageResponse: Codable {
    let ok: Bool
    let path: String?
    let error: String?
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    // Hold a weak reference to the current provider for C callback bridging
    private static weak var current: PacketTunnelProvider?
    private var lastOptions: EasyTierOptions?
    private var lastIPState = TunnelIPState()

    private func handleRustStop() {
        // Called from FFI callback on an arbitrary thread
        var msgPtr: UnsafePointer<CChar>? = nil
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = get_latest_error_msg(&msgPtr, &errPtr)
        if ret == 0, let msg = extractRustString(msgPtr) {
            logger.error("handleRustStop(): \(msg, privacy: .public)")
            // Inform host app and cancel the tunnel on global queue
            DispatchQueue.global().async {
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
        if let defaults = UserDefaults(suiteName: APP_GROUP_ID) {
            defaults.set(message, forKey: "TunnelLastError")
            defaults.synchronize()
        }
        // Wake the host app via Darwin notification
        postDarwinNotification("\(APP_BUNDLE_ID).error")
    }

    private func handleRunningInfoChanged() {
        logger.warning("handleRunningInfoChanged(): triggered")
        enqueueSettingsUpdate()
    }

    private func enqueueSettingsUpdate() {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            if self.reasserting {
                logger.info("enqueueSettingsUpdate(): update in progress, skipping")
                return
            }
            self.reasserting = true
            logger.info("enqueueSettingsUpdate(): starting settings update")
            self.applyNetworkSettings() { [weak self] _ in
                self?.reasserting = false
            }
        }
    }

    private func applyNetworkSettings(_ completion: @escaping ((any Error)?) -> Void) {
        guard let options = lastOptions else {
            logger.error("applyNetworkSettings() cannot get options")
            completion("cannot get options")
            return
        }
        let settings = buildSettings(options)
        logger.info("applyNetworkSettings() applying settings")
        let oldState = lastIPState
        lastIPState = .init(from: settings)
        let needSetTunFd = lastIPState != oldState && !lastIPState.isEmpty
        self.setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completion(error)
                return
            }
            if let error {
                logger.error("handleRunningInfoChanged() failed to setTunnelNetworkSettings: \(error, privacy: .public)")
                self.notifyHostAppError(error.localizedDescription)
                completion(error)
                return
            }
            if needSetTunFd {
                let tunFd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 ?? tunnelFileDescriptor()
                if let tunFd {
                    var errPtr: UnsafePointer<CChar>? = nil
                    let ret = set_tun_fd(tunFd, &errPtr)
                    guard ret == 0 else {
                        let err = extractRustString(errPtr)
                        logger.error("handleRunningInfoChanged() failed to set tun fd to \(tunFd): \(err, privacy: .public)")
                        self.notifyHostAppError(err ?? "Unknown")
                        completion("failed to set tun fd")
                        return
                    }
                } else {
                    logger.error("handleRunningInfoChanged() no available tun fd")
                    notifyHostAppError("no available tun fd")
                }
            }
            logger.info("applyNetworkSettings() settings applied")
            completion(nil)
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
        
        let defaults = UserDefaults(suiteName: APP_GROUP_ID)
        guard let configData = defaults?.data(forKey: "VPNConfig"),
              let options = try? JSONDecoder().decode(EasyTierOptions.self, from: configData) else {
            logger.error("startTunnel() options is nil")
            self.notifyHostAppError("options is nil")
            completionHandler("options is nil")
            return
        }
        self.lastOptions = options
        
        initRustLogger(level: options.logLevel)
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = options.config.withCString { strPtr in
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
        applyNetworkSettings() {
            completionHandler($0)
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
        logger.debug("handleAppMessage(): triggered")
        // Add code here to handle the message.
        guard let completionHandler else { return }
        if let raw = String(data: messageData, encoding: .utf8),
           let command = ProviderCommand(rawValue: raw) {
            switch command {
            case .exportOSLog:
                do {
                    let url = try OSLogExporter.exportToAppGroup(appGroupID: APP_GROUP_ID)
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
