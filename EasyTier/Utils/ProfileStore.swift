import Foundation
import os
import TOMLKit
import UIKit
import EasyTierShared

private let profileStoreLogger = Logger(subsystem: APP_BUNDLE_ID, category: "profile.store")

final class ProfileDocument: UIDocument {
    var text: String = ""

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        if let data = contents as? Data {
            text = String(data: data, encoding: .utf8) ?? ""
            return
        }
        if let wrapper = contents as? FileWrapper,
           let data = wrapper.regularFileContents {
            text = String(data: data, encoding: .utf8) ?? ""
            return
        }
        text = ""
    }

    override func contents(forType typeName: String) throws -> Any {
        return text.data(using: .utf8) ?? Data()
    }
}

enum ProfileStore {
    static func loadIndexOrEmpty() -> [String] {
        do {
            return try loadIndex()
        } catch {
            profileStoreLogger.error("load index failed: \(String(describing: error))")
            return []
        }
    }

    static func loadIndex() throws -> [String] {
        let directoryURL = try profilesDirectoryURL()
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var profiles: [String] = []
        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "toml" {
            let configName = fileURL.deletingPathExtension().lastPathComponent
            profiles.append(configName)
        }
        return profiles.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func loadProfile(named configName: String) async throws -> NetworkProfile {
        let fileURL = try fileURL(forConfigName: configName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let document = ProfileDocument(fileURL: fileURL)
        try await openDocument(document)
        defer {
            Task {
                await closeDocument(document)
            }
        }
        let config = try TOMLDecoder().decode(NetworkConfig.self, from: document.text)
        return NetworkProfile(from: config)
    }

    static func save(_ profile: NetworkProfile, named configName: String) async throws {
        let config = NetworkConfig(from: profile)
        let encoded = try TOMLEncoder().encode(config).string ?? ""
        let fileURL = try fileURL(forConfigName: configName)
        profileStoreLogger.debug("saving to \(fileURL.path): \(encoded)")
        let document = ProfileDocument(fileURL: fileURL)
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        if fileExists {
            try await openDocument(document)
        }
        document.text = encoded
        let operation: UIDocument.SaveOperation = fileExists ? .forOverwriting : .forCreating
        try await saveDocument(document, to: fileURL, for: operation)
        if fileExists {
            await closeDocument(document)
        }
    }

    static func renameProfileFile(from configName: String, to newConfigName: String) throws {
        let directoryURL = try profilesDirectoryURL()
        try ensureDirectory(for: directoryURL)
        let sourceURL = directoryURL.appendingPathComponent("\(sanitizedFileName(configName, fallback: configName)).toml")
        let targetURL = directoryURL.appendingPathComponent("\(sanitizedFileName(newConfigName, fallback: newConfigName)).toml")
        guard sourceURL != targetURL else { return }
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: sourceURL, to: targetURL)
    }

    static func deleteProfile(named configName: String) throws {
        let fileURL = try fileURL(forConfigName: configName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func profilesDirectoryURL() throws -> URL {
        if shouldUseICloud(),
           let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: ICLOUD_CONTAINER_ID) {
            let documentsURL = ubiquityURL.appendingPathComponent("Documents", isDirectory: true)
            profileStoreLogger.debug("saving to iCloud: \(documentsURL)")
            return documentsURL
        }
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        profileStoreLogger.debug("saving to local: \(documentsURL)")
        return documentsURL
    }

    private static func ensureDirectory(for directory: URL) throws {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func fileURL(forConfigName configName: String) throws -> URL {
        let directoryURL = try profilesDirectoryURL()
        try ensureDirectory(for: directoryURL)
        let fileName = sanitizedFileName(configName, fallback: configName)
        return directoryURL.appendingPathComponent("\(fileName).toml")
    }

    static func sanitizedFileName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallback
        }
        let invalid = CharacterSet(charactersIn: "/:")
        let parts = trimmed.components(separatedBy: invalid)
        let sanitized = parts.filter { !$0.isEmpty }.joined(separator: "_")
        return sanitized.isEmpty ? fallback : sanitized
    }

    private static func shouldUseICloud() -> Bool {
        return UserDefaults.standard.bool(forKey: "profilesUseICloud")
    }

    private static func openDocument(_ document: ProfileDocument) async throws {
        try await withCheckedThrowingContinuation { continuation in
            document.open { success in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private static func saveDocument(
        _ document: ProfileDocument,
        to url: URL,
        for operation: UIDocument.SaveOperation
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            document.save(to: url, for: operation) { success in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                }
            }
        }
    }

    private static func closeDocument(_ document: ProfileDocument) async {
        await withCheckedContinuation { continuation in
            document.close { _ in
                continuation.resume()
            }
        }
    }
}
