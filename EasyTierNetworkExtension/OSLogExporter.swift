import Foundation
import OSLog

enum OSLogExporter {
    private static var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    enum ExportError: Error {
        case containerUnavailable
        case emptyLogs
    }

    static func exportToAppGroup(appGroupID: String) throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw ExportError.containerUnavailable
        }
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let startPosition = store.position(timeIntervalSinceLatestBoot: 0)
        let entries = try store.getEntries(at: startPosition)
        var output = ""

        for entry in entries {
            if let log = entry as? OSLogEntryLog {
                output.append(format(log))
                output.append("\n")
            } else if let signpost = entry as? OSLogEntrySignpost {
                output.append(format(signpost))
                output.append("\n")
            }
        }

        guard !output.isEmpty else {
            throw ExportError.emptyLogs
        }

        let filename = "EasyTier-NE-oslog-\(Int(Date().timeIntervalSince1970)).log"
        let url = containerURL.appendingPathComponent(filename)
        try output.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func format(_ log: OSLogEntryLog) -> String {
        let timestamp = dateFormatter.string(from: log.date)
        let level = formatLevel(log.level)
        let subsystem = log.subsystem
        let category = log.category
        return "[\(timestamp)] [\(level)] [\(subsystem)] [\(category)] \(log.composedMessage)"
    }

    private static func format(_ signpost: OSLogEntrySignpost) -> String {
        let timestamp = dateFormatter.string(from: signpost.date)
        let type = String(describing: signpost.signpostType).uppercased()
        let subsystem = signpost.subsystem
        let category = signpost.category
        let name = signpost.signpostName
        return "[\(timestamp)] [SIGNPOST \(type)] [\(subsystem)] [\(category)] \(name)"
    }

    private static func formatLevel(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .notice:
            return "NOTICE"
        case .error:
            return "ERROR"
        case .fault:
            return "FAULT"
        default:
            return "UNKNOWN"
        }
    }
}
