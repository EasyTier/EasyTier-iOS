import Foundation

final class DarwinNotificationObserver {
    private let name: String
    private let callback: () -> Void
    
    nonisolated private var cfName: CFNotificationName {
        return CFNotificationName(name as CFString)
    }

    init(name: String, callback: @escaping () -> Void) {
        self.name = name
        self.callback = callback
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        CFNotificationCenterAddObserver(
            center,
            observer,
            { (_, observer, _, _, _) in
                guard let observer = observer else { return }
                
                let instance = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
                
                DispatchQueue.main.async {
                    instance.callback()
                }
            },
            cfName.rawValue,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        CFNotificationCenterRemoveObserver(center, observer, cfName, nil)
    }
}
