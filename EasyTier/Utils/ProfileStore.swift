import Foundation
import SwiftUI
import os
import TOMLKit
import EasyTierShared
import Combine
import UniformTypeIdentifiers

nonisolated let profileStoreLogger = Logger(subsystem: APP_BUNDLE_ID, category: "profile.store")

private func coordinatedWrite(_ data: Data, to url: URL) throws {
    var coordinationError: NSError?
    var writeError: Error?
    let fileExists = FileManager.default.fileExists(atPath: url.path)
    let options: NSFileCoordinator.WritingOptions = fileExists ? .forReplacing : []

    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
        do {
            try data.write(to: coordinatedURL, options: .atomic)
        } catch {
            writeError = error
        }
    }

    if let writeError {
        throw writeError
    }
    if let coordinationError {
        throw coordinationError
    }
}

private func coordinatedRead(from url: URL) throws -> Data {
    var coordinationError: NSError?
    var readError: Error?
    var readData = Data()

    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
        do {
            readData = try Data(contentsOf: coordinatedURL)
        } catch {
            readError = error
        }
    }

    if let readError {
        throw readError
    }
    if let coordinationError {
        throw coordinationError
    }
    return readData
}

private func coordinatedDelete(at url: URL) throws {
    var coordinationError: NSError?
    var deleteError: Error?
    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { coordinatedURL in
        do {
            try FileManager.default.removeItem(at: coordinatedURL)
        } catch {
            deleteError = error
        }
    }
    if let deleteError {
        throw deleteError
    }
    if let coordinationError {
        throw coordinationError
    }
}

private func coordinatedMove(from sourceURL: URL, to targetURL: URL) throws {
    var coordinationError: NSError?
    var moveError: Error?
    let destinationExists = FileManager.default.fileExists(atPath: targetURL.path)
    let destinationOptions: NSFileCoordinator.WritingOptions = destinationExists ? .forReplacing : []

    NSFileCoordinator(filePresenter: nil).coordinate(
        writingItemAt: sourceURL,
        options: .forMoving,
        writingItemAt: targetURL,
        options: destinationOptions,
        error: &coordinationError
    ) { coordinatedSourceURL, coordinatedTargetURL in
        do {
            if FileManager.default.fileExists(atPath: coordinatedTargetURL.path) {
                try FileManager.default.removeItem(at: coordinatedTargetURL)
            }
            try FileManager.default.moveItem(at: coordinatedSourceURL, to: coordinatedTargetURL)
        } catch {
            moveError = error
        }
    }

    if let moveError {
        throw moveError
    }
    if let coordinationError {
        throw coordinationError
    }
}

private func coordinatedDirectoryContents(at directoryURL: URL) throws -> [URL] {
    var coordinationError: NSError?
    var readError: Error?
    var result: [URL] = []

    NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: directoryURL, options: [], error: &coordinationError) { coordinatedURL in
        do {
            result = try FileManager.default.contentsOfDirectory(
                at: coordinatedURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            readError = error
        }
    }

    if let readError {
        throw readError
    }
    if let coordinationError {
        throw coordinationError
    }
    return result
}

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

struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var profile = NetworkProfile()
    private(set) var lastLoadError: Error?

    init(profile: NetworkProfile = NetworkProfile(), lastLoadError: Error? = nil) {
        self.profile = profile
        self.lastLoadError = lastLoadError
    }

    init(configuration: ReadConfiguration) throws {
        self = Self.decode(from: configuration.file.regularFileContents)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try Self.encode(profile)
        return .init(regularFileWithContents: data)
    }

    static func load(from url: URL) throws -> Self {
        let data = try coordinatedRead(from: url)
        return decode(from: data)
    }

    func save(to url: URL) throws {
        let data = try Self.encode(profile)
        try coordinatedWrite(data, to: url)
    }

    private static func decode(from data: Data?) -> Self {
        let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Self(profile: NetworkProfile())
        }
        do {
            let config = try TOMLDecoder().decode(NetworkConfig.self, from: text)
            return Self(profile: NetworkProfile(from: config))
        } catch {
            profileStoreLogger.error("document load decode failed: \(error.localizedDescription)")
            return Self(profile: NetworkProfile(), lastLoadError: error)
        }
    }

    private static func encode(_ profile: NetworkProfile) throws -> Data {
        let config = profile.toConfig()
        let encoded = try TOMLEncoder().encode(config).string ?? ""
        return encoded.data(using: .utf8) ?? Data()
    }
}

final class ProfileConflictMetadataObserver: NSObject {
    private let fileURL: URL
    private let onPotentialConflict: () -> Void
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []

    init(fileURL: URL, onPotentialConflict: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onPotentialConflict = onPotentialConflict
    }

    deinit {
        stop()
    }

    func start() {
        let fileName = fileURL.lastPathComponent
        query.searchScopes = [
            NSMetadataQueryUbiquitousDocumentsScope,
            fileURL.deletingLastPathComponent().path
        ]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: nil
            ) { [weak self] _ in
                self?.handleQueryChanged()
            }
        )
        observers.append(
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: nil
            ) { [weak self] _ in
                self?.handleQueryChanged()
            }
        )

        query.start()
    }

    func stop() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        query.stop()
    }

    private func handleQueryChanged() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let target = fileURL.standardizedFileURL
        for item in query.results {
            guard let metadata = item as? NSMetadataItem,
                  let resultURL = metadata.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                continue
            }
            if resultURL.standardizedFileURL == target {
                onPotentialConflict()
                return
            }
        }
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

@MainActor
final class ProfileSession: ObservableObject, Equatable {
    static func == (lhs: ProfileSession, rhs: ProfileSession) -> Bool {
        lhs.name == rhs.name
    }

    let name: String
    let fileURL: URL
    var document: ProfileDocument
    private let queue = ProfileSessionQueue()
    private var conflictObserver: ProfileConflictMetadataObserver?
    private var hasNotifiedConflict = false

    init(name: String, fileURL: URL, document: ProfileDocument) {
        self.name = name
        self.fileURL = fileURL
        self.document = document
        registerConflictObserver()
    }

    @MainActor
    deinit {
        unregisterConflictObserver()
    }

    func save() async throws {
        try await queue.enqueue {
            if ProfileStore.hasUnresolvedConflict(at: self.fileURL) {
                profileStoreLogger.error("document in conflict: \(self.fileURL.path)")
                throw ProfileStoreError.conflict(self.fileURL)
            }
            try self.document.save(to: self.fileURL)
            self.notifyConflictIfNeeded()
        }
    }

    func close() async {
        unregisterConflictObserver()
    }

    private func registerConflictObserver() {
        let observer = ProfileConflictMetadataObserver(fileURL: fileURL) { [weak self] in
            Task { @MainActor in
                self?.notifyConflictIfNeeded()
            }
        }
        conflictObserver = observer
        observer.start()
        Task { @MainActor in
            self.notifyConflictIfNeeded()
        }
    }

    private func unregisterConflictObserver() {
        if let conflictObserver {
            conflictObserver.stop()
            self.conflictObserver = nil
        }
    }

    private func notifyConflictIfNeeded() {
        let inConflict = ProfileStore.hasUnresolvedConflict(at: fileURL)
        if inConflict && !hasNotifiedConflict {
            hasNotifiedConflict = true
            profileStoreLogger.error("document state changed to conflict: \(self.fileURL.path)")
            NotificationCenter.default.post(
                name: .profileDocumentConflictDetected,
                object: nil,
                userInfo: [
                    "configName": name,
                    "fileURL": fileURL
                ]
            )
        } else if !inConflict {
            hasNotifiedConflict = false
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
        let fileURLs = try coordinatedDirectoryContents(at: directoryURL)
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
        try coordinatedWrite(data, to: fileURL)
    }

    static func renameProfileFile(from configName: String, to newConfigName: String) throws {
        let directoryURL = try profilesDirectoryURL()
        try ensureDirectory(for: directoryURL)
        let sourceURL = directoryURL.appendingPathComponent("\(sanitizedFileName(configName, fallback: configName)).toml")
        let targetURL = directoryURL.appendingPathComponent("\(sanitizedFileName(newConfigName, fallback: newConfigName)).toml")
        guard sourceURL != targetURL else { return }
        try coordinatedMove(from: sourceURL, to: targetURL)
    }

    static func deleteProfile(named configName: String) throws {
        let fileURL = try fileURL(forConfigName: configName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try coordinatedDelete(at: fileURL)
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

        if hasUnresolvedConflict(at: fileURL) {
            profileStoreLogger.error("document in conflict: \(fileURL.path)")
            throw ProfileStoreError.conflict(fileURL)
        }

        let document = try ProfileDocument.load(from: fileURL)
        if let error = document.lastLoadError {
            throw error
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
        let data = try coordinatedRead(from: versionedURL)
        try coordinatedWrite(data, to: url)
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

    fileprivate static func hasUnresolvedConflict(at url: URL) -> Bool {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url)
        return !(conflicts?.isEmpty ?? true)
    }
}
