import AppIntents
import SwiftData
import NetworkExtension
import SwiftUI

// MARK: - App Entity

struct NetworkProfileEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "easytier_network"
    static var defaultQuery = NetworkProfileQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(from profile: ProfileSummary) {
        self.id = profile.id
        self.name = profile.name
    }
}

struct NetworkProfileQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [NetworkProfileEntity] {
        let modelContext = ModelContext(try ModelContainer(for: ProfileSummary.self, NetworkProfile.self))
        let descriptor = FetchDescriptor<ProfileSummary>(predicate: #Predicate { identifiers.contains($0.id) })
        let profiles = try modelContext.fetch(descriptor)
        return profiles.map { NetworkProfileEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [NetworkProfileEntity] {
        let modelContext = ModelContext(try ModelContainer(for: ProfileSummary.self, NetworkProfile.self))
        let descriptor = FetchDescriptor<ProfileSummary>(sortBy: [SortDescriptor(\.createdAt)])
        let profiles = try modelContext.fetch(descriptor)
        return profiles.map { NetworkProfileEntity(from: $0) }
    }
}

// MARK: - Helpers

enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noProfileFound
    case connectionFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noProfileFound:
            return "no_network_profile_found"
        case .connectionFailed(let msg):
            return "connection_failed \(msg)"
        }
    }
}

@MainActor
func getTargetProfile(_ entity: NetworkProfileEntity?) throws -> ProfileSummary {
    let container = try ModelContainer(for: ProfileSummary.self, NetworkProfile.self)
    let context = ModelContext(container)

    if let entity = entity {
        let id = entity.id
        let descriptor = FetchDescriptor<ProfileSummary>(predicate: #Predicate { $0.id == id })
        if let profile = try context.fetch(descriptor).first {
            return profile
        }
    }

    // Fallback: Use first available profile
    let descriptor = FetchDescriptor<ProfileSummary>(sortBy: [SortDescriptor(\.createdAt)])
    if let profile = try context.fetch(descriptor).first {
        return profile
    }

    throw IntentError.noProfileFound
}

// MARK: - Intents

struct ConnectIntent: AppIntent {
    static var title: LocalizedStringResource = "connect_easytier"
    static var description: IntentDescription = IntentDescription("connect_to_easytier_network")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "network")
    var network: NetworkProfileEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let profile = try getTargetProfile(network)
        let manager = NEManager()
        try await manager.load()
        try await manager.connect(profile: profile)
        return .result()
    }
}

struct DisconnectIntent: AppIntent {
    static var title: LocalizedStringResource = "disconnect_easytier"
    static var description: IntentDescription = IntentDescription("disconnect_from_easytier_network")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = NEManager()
        try await manager.load()
        await manager.disconnect()
        return .result()
    }
}

struct ToggleConnectIntent: AppIntent {
    static var title: LocalizedStringResource = "toggle_easytier"
    static var description: IntentDescription = IntentDescription("toggle_easytier_network_connection")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "network")
    var network: NetworkProfileEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = NEManager()
        try await manager.load()

        // Check current status
        // Note: manager.status might be initial state if not refreshed, but load() should refresh it.
        // However, NEManager.load() updates the manager instance which updates status via delegation.
        // We might need a small delay or rely on the fact that load() fetches the managers.

        // Since load() calls setManager which sets status, we can check it.
        // But manager.status is @Published, so accessing it directly is fine on MainActor.

        if manager.status == .connected || manager.status == .connecting {
            await manager.disconnect()
            return .result()
        } else {
            let profile = try getTargetProfile(network)
            try await manager.connect(profile: profile)
            return .result()
        }
    }
}

// MARK: - Shortcuts Provider

struct EasyTierShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConnectIntent(),
            phrases: [
                "Connect to \(.applicationName)",
                "Start \(.applicationName) VPN",
                "Start \(.applicationName)"
            ],
            shortTitle: "connect_easytier",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: DisconnectIntent(),
            phrases: [
                "Disconnect from \(.applicationName)",
                "Stop \(.applicationName) VPN",
                "Stop \(.applicationName)"
            ],
            shortTitle: "disconnect_easytier",
            systemImageName: "stop.circle"
        )

        AppShortcut(
            intent: ToggleConnectIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "Switch \(.applicationName)"
            ],
            shortTitle: "toggle_easytier",
            systemImageName: "arrow.triangle.2.circlepath.circle"
        )
    }
}
