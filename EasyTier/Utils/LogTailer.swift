import Foundation
import SwiftUI
import Combine

import EasyTierShared

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

class LogTailer: ObservableObject {
    @Published var logContent: [LogLine] = []
    @Published var errorMessage: TextItem?
    @Published var isWatching: Bool = false
    
    @AppStorage("logPreservedLines") var logPreservedLines: Int = 1000
    
    private var fileHandle: FileHandle?
    private var source: DispatchSourceFileSystemObject?
    
    /// Starts watching a specific file in an App Group
    func startWatching(appGroupID: String, filename: String, fromStart: Bool) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            self.errorMessage = .init("Invalid App Group ID.")
            return
        }
        
        let fileURL = containerURL.appendingPathComponent(filename)
        
        // Ensure file exists to avoid crash when opening; create if missing
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            self.fileHandle = handle
            
            // Initial Read
            if fromStart {
                let data = handle.readDataToEndOfFile()
                if let str = String(data: data, encoding: .utf8) {
                    updateLog(str, replaceAll: true)
                }
            }
            
            // Setup DispatchSource to watch for writes
            let fileDescriptor = handle.fileDescriptor
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: .write,
                queue: DispatchQueue.main
            )
            
            source.setEventHandler { [weak self] in
                self?.readNewData()
            }
            
            source.setCancelHandler {
                try? handle.close()
            }
            
            source.resume()
            self.source = source
            self.isWatching = true
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = .init("Could not open file: \(error.localizedDescription)")
            }
        }
    }
    
    private func readNewData() {
        guard let handle = fileHandle else { return }
        
        // Read only what has been appended
        let data = handle.readDataToEndOfFile()
        
        if let newString = String(data: data, encoding: .utf8), !newString.isEmpty {
            updateLog(newString)
        }
    }
    
    private func updateLog(_ logs: String, replaceAll: Bool = false) {
        let newLines = logs
            .split(separator: "\n")
            .suffix(logPreservedLines)
            .map { LogLine(text: String($0)) }
        let lines =
            (replaceAll ? [] : self.logContent).suffix(
                logPreservedLines - newLines.count
            ) + newLines

        DispatchQueue.main.async {
            self.logContent = lines
        }
    }
    
    func stop() {
        source?.cancel()
        source = nil
        fileHandle = nil
        isWatching = false
    }
    
    deinit {
        source?.cancel()
        source = nil
        fileHandle = nil
    }
}
