import Foundation
import SwiftUI
import os
import TOMLKit
import UIKit
import EasyTierShared
import Combine

nonisolated let profileStoreLogger = Logger(subsystem: APP_BUNDLE_ID, category: "profile.store")

extension Notification.Name {
    static let profileDocumentConflictDetected = Notification.Name("ProfileDocumentConflictDetected")
}

enum ProfileStoreError: LocalizedError {
    case conflict(URL)
    case conflictResolutionFailed

    var errorDescription: String? {
        switch self {
        case .conflict(let url):
            return "iCloud conflict detected: \(url.lastPathComponent)"
        case .conflictResolutionFailed:
            return "Failed to resolve iCloud conflict."
        }
    }
}

struct ConflictInfo: Identifiable {
    let id = UUID()
    let local: Bool
    let deviceName: String?
    let modificationDate: Date?
}

final class ProfileDocument: UIDocument {
    var profile = NetworkProfile()
    private(set) var lastLoadError: Error?

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        profileStoreLogger.debug("ProfileDocument.load()")
        lastLoadError = nil
        let data: Data?
        if let rawData = contents as? Data {
            data = rawData
        } else if let wrapper = contents as? FileWrapper {
            data = wrapper.regularFileContents
        } else {
            data = nil
        }
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile = NetworkProfile()
            return
        }
        do {
            let config = try TOMLDecoder().decode(NetworkConfig.self, from: text)
            profile = NetworkProfile(from: config)
        } catch {
            lastLoadError = error
            profileStoreLogger.error("document load decode failed: \(error.localizedDescription)")
            profile = NetworkProfile()
        }
    }

    override func contents(forType typeName: String) throws -> Any {
        profileStoreLogger.debug("ProfileDocument.contents()")
        let config = profile.toConfig()
        let encoded = try TOMLEncoder().encode(config).string ?? ""
        return encoded.data(using: .utf8) ?? Data()
    }

    func markDirty() {
        updateChangeCount(.done)
    }
}

actor ProfileSessionQueue {
    private var lastTask: Task<Void, Error>? = nil

    func enqueue(_ operation: @MainActor @Sendable @escaping () async throws -> Void) async throws {
        let previous = lastTask
        let task = Task {
            if let previous {
                do {
                    _ = try await previous.value
                } catch {
                    profileStoreLogger.error("previous save task failed: \(error.localizedDescription)")
                }
            }
            try await operation()
        }
        lastTask = task
        try await task.value
    }
}

final class ProfileSession: ObservableObject, Equatable {
    static func == (lhs: ProfileSession, rhs: ProfileSession) -> Bool {
        lhs.name == rhs.name
    }
    
    let name: String
    let fileURL: URL
    let document: ProfileDocument
    private let queue = ProfileSessionQueue()
    private var stateObserver: NSObjectProtocol?
    private var hasNotifiedConflict = false

    init(name: String, fileURL: URL, document: ProfileDocument) {
        self.name = name
        self.fileURL = fileURL
        self.document = document
        self.document.markDirty()
        registerConflictObserver()
    }

    deinit {
        unregisterConflictObserver()
    }

    func save() async throws {
        try await queue.enqueue {
            if self.document.documentState.contains(.closed) {
                try await ProfileStore.openDocument(self.document)
            }
            if self.document.documentState.contains(.inConflict) {
                profileStoreLogger.error("document in conflict: \(self.fileURL.path)")
                throw ProfileStoreError.conflict(self.fileURL)
            }
            self.document.markDirty()
            let fileExists = FileManager.default.fileExists(atPath: self.fileURL.path)
            let operation: UIDocument.SaveOperation = fileExists ? .forOverwriting : .forCreating
            try await ProfileStore.saveDocument(self.document, to: self.fileURL, for: operation)
        }
    }

    func close() async {
        unregisterConflictObserver()
        await ProfileStore.closeDocument(self.document)
    }

    private func registerConflictObserver() {
        stateObserver = NotificationCenter.default.addObserver(
            forName: UIDocument.stateChangedNotification,
            object: document,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let inConflict = self.document.documentState.contains(.inConflict)
            if inConflict && !self.hasNotifiedConflict {
                self.hasNotifiedConflict = true
                profileStoreLogger.error("document state changed to conflict: \(self.fileURL.path)")
                NotificationCenter.default.post(
                    name: .profileDocumentConflictDetected,
                    object: nil,
                    userInfo: [
                        "configName": self.name,
                        "fileURL": self.fileURL
                    ]
                )
            } else if !inConflict {
                self.hasNotifiedConflict = false
            }
        }
    }

    private func unregisterConflictObserver() {
        if let stateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
            self.stateObserver = nil
        }
    }
}

final class SelectedProfileSession: ObservableObject {
    @Published var session: ProfileSession? {
        didSet {
            sessionCancellable = session?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }

    private var sessionCancellable: AnyCancellable?
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

    static func save(_ profile: NetworkProfile, named configName: String) throws {
        let fileURL = try fileURL(forConfigName: configName)
        let config = profile.toConfig()
        let encoded = try TOMLEncoder().encode(config).string ?? ""
        let data = encoded.data(using: .utf8) ?? Data()
        try data.write(to: fileURL, options: .atomic)
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

    static func openSession(named configName: String) async throws -> ProfileSession {
        let fileURL = try fileURL(forConfigName: configName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let document = ProfileDocument(fileURL: fileURL)
        try await openDocument(document)
        let loadError = document.lastLoadError
        let inConflict = document.documentState.contains(.inConflict)
        if let error = loadError {
            await closeDocument(document)
            throw error
        }
        if inConflict {
            profileStoreLogger.error("document in conflict: \(fileURL.path)")
            await closeDocument(document)
            throw ProfileStoreError.conflict(fileURL)
        }
        return ProfileSession(name: configName, fileURL: fileURL, document: document)
    }

    static func resolveConflictUseLocal(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }
        for version in conflicts {
            version.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    static func resolveConflictUseRemote(at url: URL) throws {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }
        let latest = conflicts.max { lhs, rhs in
            (lhs.modificationDate ?? .distantPast) < (rhs.modificationDate ?? .distantPast)
        }
        guard let versionedURL = latest?.url else {
            throw ProfileStoreError.conflictResolutionFailed
        }
        let data = try Data(contentsOf: versionedURL)
        try data.write(to: url, options: .atomic)
        for version in conflicts {
            version.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    static func conflictInfos(at url: URL) -> [ConflictInfo] {
        var infos: [ConflictInfo] = []
        if let current = NSFileVersion.currentVersionOfItem(at: url) {
            infos.append(
                .init(
                    local: true,
                    deviceName: current.localizedNameOfSavingComputer,
                    modificationDate: current.modificationDate
                )
            )
        }
        if let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) {
            for version in conflicts {
                infos.append(
                    .init(
                        local: false,
                        deviceName: version.localizedNameOfSavingComputer,
                        modificationDate: version.modificationDate
                    )
                )
            }
        }
        return infos
    }

    static func waitForConflictResolved(
        at url: URL,
        timeout: TimeInterval = 2.0,
        pollInterval: TimeInterval = 0.5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
            if conflicts?.isEmpty ?? true {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw ProfileStoreError.conflictResolutionFailed
    }

    fileprivate static func openDocument(_ document: ProfileDocument) async throws {
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

    fileprivate static func saveDocument(
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

    fileprivate static func closeDocument(_ document: ProfileDocument) async {
        await withCheckedContinuation { continuation in
            document.close { _ in
                continuation.resume()
            }
        }
    }
}
