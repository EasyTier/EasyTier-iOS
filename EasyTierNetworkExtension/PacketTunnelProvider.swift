import os
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    let logger = Logger(subsystem: "site.yinmo.easytier.tunnel", category: "tunnel")

    func getErrorMsg() -> String? {
        var ptr: UnsafePointer<CChar>? = nil
        get_error_msg(&ptr)
        if let p = ptr {
            let str = String(cString: p)
            free_string(p)
            return str
        }
        return nil
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        logger.warning("startTunnel: triggered")
        let ret = (options?["config"] as? String)?.withCString { strPtr in
            return run_network_instance(strPtr)
        }
        if ret != 0 {
            let err = getErrorMsg()
            logger.error("startTunnel: \(err ?? "Unknown")")
            completionHandler(err)
        }

        self.setTunnelNetworkSettings(options?["settings"] as? NETunnelNetworkSettings) { [weak self] error in
            let tunFd = self?.packetFlow.value(forKeyPath: "socket.fileDescriptor") as! Int32
            DispatchQueue.global(qos: .default).async {
                let ret = (options?["name"] as? String)?.withCString { strPtr in
                    return set_tun_fd(strPtr, tunFd)
                }
                if ret != 0 {
                    let err = self?.getErrorMsg()
                    self?.logger.error("startTunnel: \(err ?? "Unknown")")
                    completionHandler(err)
                }
            }
            completionHandler(nil)
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let ret = retain_network_instance(nil, 0)
        if ret != 0 {
            let err = getErrorMsg()
            logger.error("stopTunnel: \(err ?? "Unknown")")
        }

        completionHandler()
    }
    
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
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
