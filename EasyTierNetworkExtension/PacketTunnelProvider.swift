import os
import NetworkExtension
import Network
import Foundation

import EasyTierShared

let loggerSubsystem = "\(APP_BUNDLE_ID).tunnel"
let debounceInterval = 0.5
let logger = Logger(subsystem: loggerSubsystem, category: "swift")

private struct ProviderMessageResponse: Codable {
    let ok: Bool
    let path: String?
    let error: String?
}

private final class OneShotErrorCompletion {
    private let lock = NSLock()
    private var handler: ((Error?) -> Void)?

    init(_ handler: @escaping (Error?) -> Void) {
        self.handler = handler
    }

    func finish(_ error: Error?) {
        lock.lock()
        guard let handler else {
            lock.unlock()
            return
        }
        self.handler = nil
        lock.unlock()
        handler(error)
    }
}

private struct PendingStartCompletion {
    let generation: UInt64
    let completion: OneShotErrorCompletion
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    // Hold a weak reference to the current provider for C callback bridging
    private static weak var current: PacketTunnelProvider?
    private let settingsQueue = DispatchQueue(label: "\(APP_BUNDLE_ID).tunnel.settings")
    private var tunnelGeneration: UInt64 = 0
    private var activeTunnelGeneration: UInt64?
    private var settingsApplyGeneration: UInt64?
    private var pendingStartCompletion: PendingStartCompletion?
    private var lastOptions: EasyTierOptions?
    private var lastAppliedSettings: TunnelNetworkSettingsSnapshot?
    private var needReapplySettings: Bool = false
    private var webInstanceGeneration: UInt64?
    private var forceTunRebindGeneration: UInt64?
    private var webStartupReady = false
    private var pendingWebEvents: [WebManagementEvent] = []

    private func resetTunnelSessionState() {
        lastOptions = nil
        lastAppliedSettings = nil
        needReapplySettings = false
        settingsApplyGeneration = nil
        webInstanceGeneration = nil
        forceTunRebindGeneration = nil
        webStartupReady = false
        pendingWebEvents.removeAll()
        reasserting = false
    }

    private func completeStart(generation: UInt64, error: Error?) {
        guard let pendingStartCompletion,
              pendingStartCompletion.generation == generation else {
            return
        }
        self.pendingStartCompletion = nil
        pendingStartCompletion.completion.finish(error)
    }

    private func failStart(generation: UInt64, error: Error, stopNetwork: Bool) {
        guard activeTunnelGeneration == generation else {
            completeStart(generation: generation, error: error)
            return
        }

        activeTunnelGeneration = nil
        resetTunnelSessionState()
        if PacketTunnelProvider.current === self {
            PacketTunnelProvider.current = nil
        }
        if stopNetwork, stop_network_instance() != 0 {
            logger.error("failStart() failed to stop network instance")
        }
        completeStart(generation: generation, error: error)
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

    private func handleRunningInfoChanged() {
        logger.warning("handleRunningInfoChanged(): triggered")
        enqueueSettingsUpdate()
    }
    
    private func registerRustStopCallback() {
        // Register FFI stop callback to capture crashes/stop events
        let rustStopCallback: @convention(c) () -> Void = {
            PacketTunnelProvider.current?.handleRustStop()
        }
        var regErrPtr: UnsafePointer<CChar>? = nil
        let regRet = register_stop_callback(rustStopCallback, &regErrPtr)
        if regRet != 0 {
            let regErr = extractRustString(regErrPtr)
            logger.error("startTunnel() failed to register stop callback: \(regErr ?? "Unknown", privacy: .public)")
        } else {
            logger.info("startTunnel() registered FFI stop callback")
        }
    }
    
    private func handleRustStop() {
        // Called from FFI callback on an arbitrary thread
        var msgPtr: UnsafePointer<CChar>? = nil
        var errPtr: UnsafePointer<CChar>? = nil
        let ret = get_latest_error_msg(&msgPtr, &errPtr)
        if ret == 0, let msg = extractRustString(msgPtr) {
            logger.error("handleRustStop(): \(msg, privacy: .public)")
            // Inform host app and cancel the tunnel on global queue
            DispatchQueue.main.async {
                self.notifyHostAppError(msg)
                self.cancelTunnelWithError(msg)
            }
        } else if let err = extractRustString(errPtr) {
            logger.error("handleRustStop() failed to get latest error: \(err, privacy: .public)")
        }
    }

    private func enqueueSettingsUpdate() {
        settingsQueue.async { [weak self] in
            guard let self else { return }
            guard let generation = self.activeTunnelGeneration else {
                logger.info("enqueueSettingsUpdate() ignored without an active tunnel")
                return
            }
            if self.settingsApplyGeneration == generation {
                logger.info("enqueueSettingsUpdate() update in progress, waiting")
                self.needReapplySettings = true
                return
            }
            logger.info("enqueueSettingsUpdate() starting settings update")
            self.applyNetworkSettings(generation: generation) { error in
                guard let error else { return }
                logger.error("enqueueSettingsUpdate() failed with error: \(error, privacy: .public)")
            }
        }
    }

    private func applyNetworkSettings(
        generation: UInt64,
        completion: @escaping ((any Error)?) -> Void
    ) {
        guard activeTunnelGeneration == generation else {
            completion("tunnel session is no longer active")
            return
        }
        guard settingsApplyGeneration == nil else {
            logger.error("applyNetworkSettings() still in progress")
            completion("still in progress")
            return
        }
        settingsApplyGeneration = generation
        needReapplySettings = false
        reasserting = true

        settingsQueue.asyncAfter(deadline: .now() + debounceInterval) { [weak self] in
            guard let self else {
                completion("packet tunnel provider was deallocated")
                return
            }
            guard self.activeTunnelGeneration == generation,
                  self.settingsApplyGeneration == generation else {
                completion("tunnel session is no longer active")
                return
            }
            guard let options = self.lastOptions else {
                logger.error("applyNetworkSettings() cannot get options")
                self.finishNetworkSettingsApply(
                    generation: generation,
                    snapshot: nil,
                    error: "cannot get options",
                    completion: completion
                )
                return
            }

            let settings = buildSettings(options)
            let newSnapshot = self.snapshotSettings(settings)
            let forceTunRebind = self.forceTunRebindGeneration != nil
            if newSnapshot == self.lastAppliedSettings && !forceTunRebind {
                logger.warning("applyNetworkSettings() new settings are exactly the same as last applied, skipping")
                self.finishNetworkSettingsApply(
                    generation: generation,
                    snapshot: newSnapshot,
                    error: nil,
                    completion: completion
                )
                return
            }

            let needSetTunFd = forceTunRebind || self.shouldUpdateTunFd(old: self.lastAppliedSettings, new: newSnapshot)
            logger.info("applyNetworkSettings() need set tunfd: \(needSetTunFd), settings: \(settings, privacy: .public)")
            self.setTunnelNetworkSettings(settings) { [weak self] error in
                guard let self else {
                    completion(error ?? "packet tunnel provider was deallocated")
                    return
                }
                self.settingsQueue.async {
                    guard self.activeTunnelGeneration == generation,
                          self.settingsApplyGeneration == generation else {
                        completion("tunnel session is no longer active")
                        return
                    }
                    if let error {
                        logger.error("applyNetworkSettings() failed to set tunnel settings: \(error, privacy: .public)")
                        self.notifyHostAppError(error.localizedDescription)
                        self.finishNetworkSettingsApply(
                            generation: generation,
                            snapshot: newSnapshot,
                            error: error,
                            completion: completion
                        )
                        return
                    }
                    if needSetTunFd {
                        guard let tunFd = self.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32
                                ?? tunnelFileDescriptor() else {
                            let message = "no available tun fd"
                            logger.error("applyNetworkSettings() no available tun fd")
                            self.notifyHostAppError(message)
                            self.finishNetworkSettingsApply(
                                generation: generation,
                                snapshot: newSnapshot,
                                error: message,
                                completion: completion
                            )
                            return
                        }
                        logger.info("applyNetworkSettings() found fd: \(tunFd, privacy: .public)")
                        guard setNonBlocking(fd: tunFd) else {
                            let message = "failed to set tun fd non-blocking"
                            logger.error("applyNetworkSettings() failed to set fd \(tunFd, privacy: .public) non-blocking")
                            self.notifyHostAppError(message)
                            self.finishNetworkSettingsApply(
                                generation: generation,
                                snapshot: newSnapshot,
                                error: message,
                                completion: completion
                            )
                            return
                        }
                        var errPtr: UnsafePointer<CChar>? = nil
                        let ret = set_tun_fd(tunFd, &errPtr)
                        guard ret == 0 else {
                            let message = extractRustString(errPtr) ?? "Unknown"
                            logger.error("applyNetworkSettings() failed to set tun fd to \(tunFd): \(message, privacy: .public)")
                            self.notifyHostAppError(message)
                            self.finishNetworkSettingsApply(
                                generation: generation,
                                snapshot: newSnapshot,
                                error: message,
                                completion: completion
                            )
                            return
                        }
                    }
                    logger.info("applyNetworkSettings() settings applied")
                    self.forceTunRebindGeneration = nil
                    self.finishNetworkSettingsApply(
                        generation: generation,
                        snapshot: newSnapshot,
                        error: nil,
                        completion: completion
                    )
                }
            }
        }
    }

    private func fetchWebManagementStatus() throws -> WebManagementStatus {
        var jsonPtr: UnsafePointer<CChar>? = nil
        var errPtr: UnsafePointer<CChar>? = nil
        guard get_config_server_status(&jsonPtr, &errPtr) == 0,
              let json = extractRustString(jsonPtr),
              let data = json.data(using: .utf8) else {
            throw extractRustString(errPtr) ?? "cannot get Web management status"
        }
        return try JSONDecoder().decode(WebManagementStatus.self, from: data)
    }

    private func acknowledgeWebSetup(generation: UInt64, error: Error?) {
        if let error {
            error.localizedDescription.withCString {
                _ = complete_config_server_instance_setup(generation, false, $0)
            }
        } else {
            _ = complete_config_server_instance_setup(generation, true, nil)
        }
    }

    private func applyEmptyWebSettings(completion: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        setTunnelNetworkSettings(settings) { [weak self] error in
            self?.settingsQueue.async {
                if error == nil {
                    self?.lastAppliedSettings = self?.snapshotSettings(settings)
                    self?.lastOptions = nil
                    self?.forceTunRebindGeneration = nil
                }
                completion(error)
            }
        }
    }

    private func handleWebManagementEvent(_ event: WebManagementEvent) {
        settingsQueue.async { [weak self] in
            guard let self, self.activeTunnelGeneration != nil else { return }
            guard self.webStartupReady else {
                self.pendingWebEvents.append(event)
                return
            }
            self.postDarwinNotification("\(APP_BUNDLE_ID).web-management")
            switch event.event {
            case "run":
                do {
                    let status = try self.fetchWebManagementStatus()
                    guard let options = status.options else {
                        throw "Web instance has no tunnel options"
                    }
                    self.webInstanceGeneration = event.generation
                    self.forceTunRebindGeneration = event.generation
                    self.lastOptions = options.asEasyTierOptions(logLevel: self.lastOptions?.logLevel ?? .info)
                    guard let tunnelGeneration = self.activeTunnelGeneration else {
                        throw "tunnel session is no longer active"
                    }
                    self.applyNetworkSettings(generation: tunnelGeneration) { error in
                        self.acknowledgeWebSetup(generation: event.generation, error: error)
                        if let error {
                            self.notifyHostAppError(error.localizedDescription)
                            self.cancelTunnelWithError(error)
                        } else {
                            self.postDarwinNotification("\(APP_BUNDLE_ID).web-management")
                        }
                    }
                } catch {
                    self.acknowledgeWebSetup(generation: event.generation, error: error)
                    self.notifyHostAppError(error.localizedDescription)
                    self.cancelTunnelWithError(error)
                }
            case "delete":
                self.webInstanceGeneration = event.generation
                self.applyEmptyWebSettings { error in
                    if let error {
                        self.notifyHostAppError(error.localizedDescription)
                        self.cancelTunnelWithError(error)
                    } else {
                        self.postDarwinNotification("\(APP_BUNDLE_ID).web-management")
                    }
                }
            default:
                logger.warning("unknown Web management event: \(event.event, privacy: .public)")
            }
        }
    }

    private func startWebManagement(
        options: EasyTierOptions,
        generation: UInt64
    ) {
        guard let web = options.webManagement,
              !web.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !web.machineID.isEmpty else {
            failStart(generation: generation, error: "Web management options are incomplete", stopNetwork: false)
            return
        }
        registerRunningInfoCallback()
        let callback: @convention(c) (UnsafePointer<CChar>?) -> Void = { pointer in
            guard let pointer,
                  let data = String(cString: pointer).data(using: .utf8),
                  let event = try? JSONDecoder().decode(WebManagementEvent.self, from: data) else {
                return
            }
            PacketTunnelProvider.current?.handleWebManagementEvent(event)
        }
        var errPtr: UnsafePointer<CChar>? = nil
        let result = web.server.withCString { server in
            web.hostname.withCString { hostname in
                web.machineID.withCString { machineID in
                    start_config_server_client(server, hostname, machineID, callback, &errPtr)
                }
            }
        }
        guard result == 0 else {
            let message = extractRustString(errPtr) ?? "cannot start Web management"
            notifyHostAppError(message)
            failStart(generation: generation, error: message, stopNetwork: false)
            return
        }
        applyEmptyWebSettings { error in
            if let error {
                self.failStart(generation: generation, error: error, stopNetwork: true)
            } else {
                self.webStartupReady = true
                let pendingEvents = self.pendingWebEvents
                self.pendingWebEvents.removeAll()
                self.completeStart(generation: generation, error: nil)
                self.postDarwinNotification("\(APP_BUNDLE_ID).web-management")
                for event in pendingEvents {
                    self.handleWebManagementEvent(event)
                }
            }
        }
    }

    private func finishNetworkSettingsApply(
        generation: UInt64,
        snapshot: TunnelNetworkSettingsSnapshot?,
        error: Error?,
        completion: @escaping (Error?) -> Void
    ) {
        guard activeTunnelGeneration == generation,
              settingsApplyGeneration == generation else {
            completion(error ?? "tunnel session is no longer active")
            return
        }

        if error == nil, let snapshot {
            lastAppliedSettings = snapshot
        }
        let shouldReapply = needReapplySettings
        needReapplySettings = false
        settingsApplyGeneration = nil
        reasserting = false
        completion(error)

        guard shouldReapply else { return }
        settingsQueue.async { [weak self] in
            guard let self,
                  self.activeTunnelGeneration == generation,
                  self.settingsApplyGeneration == nil else {
                return
            }
            self.applyNetworkSettings(generation: generation) { error in
                guard let error else { return }
                logger.error("applyNetworkSettings() deferred update failed: \(error, privacy: .public)")
            }
        }
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.warning("startTunnel(): triggered")
        let completion = OneShotErrorCompletion(completionHandler)
        settingsQueue.async {
            self.tunnelGeneration &+= 1
            let generation = self.tunnelGeneration

            if let pendingStartCompletion = self.pendingStartCompletion {
                self.pendingStartCompletion = nil
                pendingStartCompletion.completion.finish("tunnel start was superseded")
            }
            self.resetTunnelSessionState()
            self.activeTunnelGeneration = generation
            self.pendingStartCompletion = .init(generation: generation, completion: completion)
            PacketTunnelProvider.current = self

            let defaults = UserDefaults(suiteName: APP_GROUP_ID)
            guard let configData = defaults?.data(forKey: "VPNConfig"),
                  let options = try? JSONDecoder().decode(EasyTierOptions.self, from: configData) else {
                let message = "options is nil"
                logger.error("startTunnel() options is nil")
                self.notifyHostAppError(message)
                self.failStart(generation: generation, error: message, stopNetwork: false)
                return
            }
            self.lastOptions = options

            initRustLogger(level: options.logLevel)
            if options.mode == .web {
                self.startWebManagement(options: options, generation: generation)
                return
            }
            var errPtr: UnsafePointer<CChar>? = nil
            let ret = options.config.withCString { strPtr in
                return run_network_instance(strPtr, &errPtr)
            }
            guard ret == 0 else {
                let message = extractRustString(errPtr) ?? "Unknown"
                logger.error("startTunnel() failed to run: \(message, privacy: .public)")
                self.notifyHostAppError(message)
                self.failStart(generation: generation, error: message, stopNetwork: false)
                return
            }
            self.registerRustStopCallback()
            self.registerRunningInfoCallback()
            self.applyNetworkSettings(generation: generation) { error in
                guard self.activeTunnelGeneration == generation else {
                    self.completeStart(
                        generation: generation,
                        error: error ?? "tunnel session is no longer active"
                    )
                    return
                }
                if let error {
                    self.failStart(generation: generation, error: error, stopNetwork: true)
                } else {
                    self.completeStart(generation: generation, error: nil)
                }
            }
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.warning("stopTunnel(): triggered")
        settingsQueue.async {
            self.tunnelGeneration &+= 1
            self.activeTunnelGeneration = nil
            let pendingStartCompletion = self.pendingStartCompletion
            self.pendingStartCompletion = nil
            self.resetTunnelSessionState()
            if PacketTunnelProvider.current === self {
                PacketTunnelProvider.current = nil
            }

            let ret = stop_network_instance()
            if ret != 0 {
                logger.error("stopTunnel() failed")
            }
            pendingStartCompletion?.completion.finish("tunnel stopped before startup completed")
            completionHandler()
        }
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        logger.debug("handleAppMessage(): triggered")
        // Add code here to handle the message.
        guard let completionHandler else { return }
        if let raw = String(data: messageData, encoding: .utf8),
           let command = ProviderCommand(rawValue: raw) {
            switch command {
            case .clearLog:
                var errPtr: UnsafePointer<CChar>? = nil
                if clear_logger(&errPtr) == 0 {
                    let response = ProviderMessageResponse(ok: true, path: nil, error: nil)
                    let data = try? JSONEncoder().encode(response)
                    completionHandler(data)
                } else {
                    let err = extractRustString(errPtr) ?? "Unknown"
                    logger.error("handleAppMessage() clear logger failed: \(err, privacy: .public)")
                    let response = ProviderMessageResponse(ok: false, path: nil, error: err)
                    let data = try? JSONEncoder().encode(response)
                    completionHandler(data)
                }
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
            case .lastNetworkSettings:
                settingsQueue.async { [weak self] in
                    guard let lastAppliedSettings = self?.lastAppliedSettings else {
                        completionHandler(nil)
                        return
                    }
                    do {
                        let data = try JSONEncoder().encode(lastAppliedSettings)
                        completionHandler(data)
                    } catch {
                        logger.error("handleAppMessage() encode settings failed: \(error, privacy: .public)")
                        completionHandler(nil)
                    }
                }
            case .webManagementStatus:
                do {
                    let status = try fetchWebManagementStatus()
                    completionHandler(try JSONEncoder().encode(status))
                } catch {
                    logger.error("handleAppMessage() Web status failed: \(error.localizedDescription, privacy: .public)")
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
