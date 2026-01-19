import SwiftUI
import NetworkExtension
import os
import TOMLKit
import UniformTypeIdentifiers
import EasyTierShared

private let dashboardLogger = Logger(subsystem: APP_BUNDLE_ID, category: "main.dashboard")
private let profileSaveDebounceInterval: TimeInterval = 0.5

struct DashboardView<Manager: NEManagerProtocol>: View {
    @Environment(\.scenePhase) var scenePhase
    @State private var profiles: [ProfileEntry] = ProfileStore.loadIndexOrEmpty().map {
        ProfileEntry(index: $0, profile: nil)
    }

    @ObservedObject var manager: Manager

    @AppStorage("lastSelected") var lastSelected: String?
    @AppStorage("profilesUseICloud") var profilesUseICloud: Bool = false
    @State var selectedProfileId: String?
    @State var isLocalPending = false

    @State var showManageSheet = false

    @State var showNewNetworkAlert = false
    @State var newNetworkInput = ""
    @State var showEditConfigNameAlert = false
    @State var editConfigNameInput = ""
    @State var editingProfileName: String?

    @State var showImportPicker = false
    @State var exportURL: IdentifiableURL?
    @State var showEditSheet = false
    @State var editText = ""

    @State var errorMessage: TextItem?

    @State private var darwinObserver: DNObserver? = nil
    @State private var pendingSaveWorkItem: DispatchWorkItem? = nil

    init(manager: Manager) {
        _manager = ObservedObject(wrappedValue: manager)
    }

    struct ProfileEntry: Identifiable, Equatable {
        var id: String { index.configName }
        var index: ProfileStore.ProfileIndex
        var profile: NetworkProfile?
    }

    var selectedProfile: NetworkProfile? {
        guard let selectedProfileId else { return nil }
        return profiles.first { $0.id == selectedProfileId }?.profile
    }

    var selectedProfileIndex: Int? {
        guard let selectedProfileId else { return nil }
        return profiles.firstIndex { $0.id == selectedProfileId }
    }

    var selectedProfileTitle: String? {
        guard let index = selectedProfileIndex else { return nil }
        return profiles[index].index.configName
    }

    var isConnected: Bool {
        [.connected, .disconnecting, .reasserting].contains(manager.status)
    }
    var isPending: Bool {
        isLocalPending || [.connecting, .disconnecting, .reasserting].contains(manager.status)
    }

    var mainView: some View {
        Group {
            if let index = selectedProfileIndex {
                if let profile = profiles[index].profile {
                    if isConnected {
                        StatusView<Manager>(profile.networkName)
                    } else {
                        NetworkEditView(profile: bindingForProfile(at: index))
                            .disabled(isPending)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "network.slash")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(Color.accentColor)
                    Text("no_network_selected")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    func createProfile() {
        let baseName = newNetworkInput.isEmpty ? String(localized: "new_network") : newNetworkInput
        guard let sanitizedName = validatedConfigName(baseName, excludingIndex: nil) else { return }
        let profile = NetworkProfile()
        Task { @MainActor in
            do {
                let fileURL = try ProfileStore.fileURL(forConfigName: sanitizedName)
                try await ProfileStore.save(profile, to: fileURL)
                let index = ProfileStore.ProfileIndex(
                    configName: sanitizedName,
                    fileURL: fileURL
                )
                profiles.append(ProfileEntry(index: index, profile: profile))
                selectedProfileId = sanitizedName
            } catch {
                dashboardLogger.error("create profile failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    var sheetView: some View {
        NavigationStack {
            Form {
                Section("network") {
                    ForEach(profiles) { item in
                        Button {
                            if selectedProfileId == item.id {
                                selectedProfileId = nil
                            } else {
                                selectedProfileId = item.id
                            }
                        } label: {
                            HStack {
                                Text(item.id)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedProfileId == item.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingProfileName = item.id
                                editConfigNameInput = item.id
                                showEditConfigNameAlert = true
                            } label: {
                                Label("rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .onDelete { indexSet in
                        withAnimation {
                            for index in indexSet {
                                if selectedProfileId == profiles[index].id {
                                    selectedProfileId = nil
                                }
                            }
                            for index in indexSet {
                                do {
                                    try ProfileStore.deleteProfile(at: profiles[index].index.fileURL)
                                } catch {
                                    dashboardLogger.error("delete profile failed: \(error)")
                                    errorMessage = .init(error.localizedDescription)
                                }
                            }
                            profiles.remove(atOffsets: indexSet)
                        }
                    }
                }
                Section("device.management") {
                    Button {
                        showNewNetworkAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "document.badge.plus")
                            } else {
                                Image(systemName: "plus.app")
                            }
                            Text("profile.create_network")
                        }
                    }
                    Button {
                        presentEditInText()
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.4, *) {
                                Image(systemName: "long.text.page.and.pencil")
                            } else {
                                Image(systemName: "square.and.pencil")
                            }
                            Text("profile.edit_as_text")
                        }
                    }
                    Button {
                        showImportPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            if #available(iOS 18.0, *) {
                                Image(systemName: "arrow.down.document")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text("profile.import_config")
                        }
                    }
                    Button {
                        exportSelectedProfile()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                            Text("profile.export_config")
                        }
                    }
                }
            }
            .navigationTitle("device.management")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    showManageSheet = false
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .alert("add_new_network", isPresented: $showNewNetworkAlert) {
                TextField("config_name", text: $newNetworkInput)
                    .textInputAutocapitalization(.never)
                if #available(iOS 26.0, *) {
                    Button(role: .cancel) {}
                    Button("network.create", role: .confirm, action: createProfile)
                } else {
                    Button("common.cancel") {}
                    Button("network.create", action: createProfile)
                }
            }
            .alert("edit_config_name", isPresented: $showEditConfigNameAlert) {
                TextField("config_name", text: $editConfigNameInput)
                    .textInputAutocapitalization(.never)
                Button("common.cancel") {}
                Button("save") {
                    commitConfigNameEdit()
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainView
                .navigationTitle(selectedProfileTitle ?? String(localized: "select_network"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("select_network", systemImage: "chevron.up.chevron.down") {
                        showManageSheet = true
                    }
                    .disabled(isPending || isConnected)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard !isPending else { return }
                        isLocalPending = true
                        Task { @MainActor in
                            if isConnected {
                                await manager.disconnect()
                            } else if let selectedProfileIndex {
                                if let selectedProfile = await loadProfileIfNeeded(at: selectedProfileIndex) {
                                    do {
                                        let options = try NEManager.generateOptions(selectedProfile)
                                        NEManager.saveOptions(options)
                                        try await manager.connect()
                                    } catch {
                                        dashboardLogger.error("connect failed: \(error)")
                                        errorMessage = .init(error.localizedDescription)
                                    }
                                }
                            }
                            isLocalPending = false
                        }
                    } label: {
                        Label(
                            isConnected ? "stop_network" : "run_network",
                            systemImage: isConnected ? "cable.connector.slash" : "cable.connector"
                        )
                        .labelStyle(.titleAndIcon)
                        .padding(10)
                    }
                    .disabled(selectedProfileId == nil || manager.isLoading || isPending)
                    .buttonStyle(.plain)
                    .foregroundStyle(isConnected ? Color.red : Color.accentColor)
                    .animation(.interactiveSpring, value: [isConnected, isPending])
                }
            }
        }
        .onAppear {
            if selectedProfileId == nil {
                if let lastSelected,
                   let match = profiles.first(where: { $0.id == lastSelected }) {
                    selectedProfileId = match.id
                } else {
                    selectedProfileId = profiles.first?.id
                }
            }
            if let selectedProfileIndex {
                Task { @MainActor in
                    _ = await loadProfileIfNeeded(at: selectedProfileIndex)
                }
            }
            Task { @MainActor in
                try? await manager.load()
            }
            // Register Darwin notification observer for tunnel errors
            darwinObserver = DNObserver(name: "\(APP_BUNDLE_ID).error") {
                // Read the latest error from shared App Group defaults
                let defaults = UserDefaults(suiteName: APP_GROUP_ID)
                if let msg = defaults?.string(forKey: "TunnelLastError") {
                    DispatchQueue.main.async {
                        dashboardLogger.error("core stopped: \(msg)")
                        self.errorMessage = .init(msg)
                    }
                }
            }
            if let selectedProfileIndex {
                Task { @MainActor in
                    if let selectedProfile = await loadProfileIfNeeded(at: selectedProfileIndex),
                       let options = try? NEManager.generateOptions(selectedProfile) {
                        NEManager.saveOptions(options)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { _ in
            Task { @MainActor in
                await saveOptions()
                await saveAllProfiles()
            }
        }
        .onChange(of: selectedProfileId) { newValue in
            if let oldValue = lastSelected,
               let oldIndex = profiles.firstIndex(where: { $0.id == oldValue }) {
                Task { @MainActor in
                    await saveProfileIfNeeded(at: oldIndex)
                }
            }
            lastSelected = newValue
            if let selectedProfileIndex {
                Task { @MainActor in
                    if let selectedProfile = await loadProfileIfNeeded(at: selectedProfileIndex) {
                        await manager.updateName(
                            name: profiles[selectedProfileIndex].index.configName,
                            server: selectedProfile.id.uuidString
                        )
                        await saveOptions()
                    }
                }
            }
        }
        .onChange(of: profilesUseICloud) { _ in
            profiles = ProfileStore.loadIndexOrEmpty().map {
                ProfileEntry(index: $0, profile: nil)
            }
            selectedProfileId = profiles.first?.id
            Task { @MainActor in
                await saveOptions()
            }
        }
        .onChange(of: showManageSheet) { isPresented in
            if isPresented {
                profiles = ProfileStore.loadIndexOrEmpty().map {
                    ProfileEntry(index: $0, profile: nil)
                }
                if let selectedProfileId,
                   !profiles.contains(where: { $0.id == selectedProfileId }) {
                    self.selectedProfileId = profiles.first?.id
                }
                if let selectedProfileIndex {
                    Task { @MainActor in
                        if let selectedProfile = await loadProfileIfNeeded(at: selectedProfileIndex) {
                            await manager.updateName(
                                name: profiles[selectedProfileIndex].index.configName,
                                server: selectedProfile.id.uuidString
                            )
                            await saveOptions()
                        }
                    }
                }
            }
        }
        .onDisappear {
            // Release observer to remove registration
            darwinObserver = nil
            Task { @MainActor in
                await saveOptions()
                await saveAllProfiles()
            }
        }
        .sheet(isPresented: $showManageSheet) {
            sheetView
                .sheet(isPresented: $showEditSheet) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            TextEditor(text: $editText)
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                        }
                        .navigationTitle("edit_config")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("common.cancel") {
                                    showEditSheet = false
                                }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("save") {
                                    saveEditInText()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .sheet(item: $exportURL) { url in
                    ShareSheet(activityItems: [url.url])
                }
                .fileImporter(
                    isPresented: $showImportPicker,
                    allowedContentTypes: [UTType(filenameExtension: "toml") ?? .plainText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard let url = urls.first else { return }
                        importConfig(from: url)
                    case .failure(let error):
                        errorMessage = .init(error.localizedDescription)
                    }
                }
        }
        .alert(item: $errorMessage) { msg in
            dashboardLogger.error("received error: \(String(describing: msg))")
            return Alert(title: Text("common.error"), message: Text(msg.text))
        }
    }
    
    @MainActor
    private func saveOptions() async {
        if let selectedProfileIndex,
           let selectedProfile = await loadProfileIfNeeded(at: selectedProfileIndex),
           let options = try? NEManager.generateOptions(selectedProfile) {
            NEManager.saveOptions(options)
        }
    }

    @MainActor
    private func saveAllProfiles() async {
        for index in profiles.indices {
            await saveProfileIfNeeded(at: index)
        }
    }

    private func importConfig(from url: URL) {
        Task { @MainActor in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let toml = try String(contentsOf: url, encoding: .utf8)
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: toml)
                let configName = url.deletingPathExtension().lastPathComponent
                let profile = NetworkProfile(from: config)
                let fileURL = try ProfileStore.fileURL(forConfigName: configName)
                try await ProfileStore.save(profile, to: fileURL)
                let index = ProfileStore.ProfileIndex(
                    configName: configName,
                    fileURL: fileURL
                )
                profiles.append(ProfileEntry(index: index, profile: profile))
                selectedProfileId = configName
            } catch {
                dashboardLogger.error("import failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func exportSelectedProfile() {
        guard let selectedProfileIndex else {
            errorMessage = .init("Please select a network.")
            return
        }
        let fileURL = profiles[selectedProfileIndex].index.fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = .init("Config file not found.")
            return
        }
        dashboardLogger.info("exporting to: \(fileURL)")
        exportURL = .init(fileURL)
    }

    private func presentEditInText() {
        guard let selectedProfileIndex else {
            errorMessage = .init("Please select a network.")
            return
        }
        Task { @MainActor in
            guard let selectedProfile = await loadProfileIfNeeded(at: selectedProfileIndex) else {
                errorMessage = .init("Please select a network.")
                return
            }
            do {
                let config = NetworkConfig(from: selectedProfile)
                editText = try TOMLEncoder().encode(config).string ?? ""
                showEditSheet = true
            } catch {
                dashboardLogger.error("edit load failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func saveEditInText() {
        guard let selectedProfileIndex else {
            errorMessage = .init("Please select a network.")
            return
        }
        Task { @MainActor in
            do {
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: editText)
                guard var profile = await loadProfileIfNeeded(at: selectedProfileIndex) else {
                    errorMessage = .init("Please select a network.")
                    return
                }
                config.apply(to: &profile)
                profiles[selectedProfileIndex].profile = profile
                scheduleSave(for: selectedProfileIndex)
                showEditSheet = false
            } catch {
                dashboardLogger.error("edit save failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func commitConfigNameEdit() {
        guard let editingProfileName,
              let index = profiles.firstIndex(where: { $0.id == editingProfileName }) else {
            return
        }
        let trimmed = editConfigNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let sanitizedName = validatedConfigName(trimmed, excludingIndex: index) else { return }
        guard sanitizedName != profiles[index].index.configName else { return }
        let previousName = profiles[index].index.configName
        do {
            let newURL = try ProfileStore.renameProfileFile(
                from: profiles[index].index.fileURL,
                to: sanitizedName
            )
            profiles[index].index.fileURL = newURL
            profiles[index].index.configName = sanitizedName
            if selectedProfileId == previousName {
                selectedProfileId = sanitizedName
            }
        } catch {
            dashboardLogger.error("rename failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }

    private func validatedConfigName(_ raw: String, excludingIndex: Int?) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = .init("Config name cannot be empty.")
            return nil
        }
        let sanitized = ProfileStore.sanitizedFileName(trimmed, fallback: "")
        guard sanitized == trimmed else {
            errorMessage = .init("Config name contains invalid characters.")
            return nil
        }
        let hasDuplicate = profiles.enumerated().contains { item in
            if let excludingIndex, item.offset == excludingIndex {
                return false
            }
            return item.element.index.configName.caseInsensitiveCompare(sanitized) == .orderedSame
        }
        guard !hasDuplicate else {
            errorMessage = .init("Config name already exists.")
            return nil
        }
        return sanitized
    }

    @MainActor
    private func loadProfileIfNeeded(at index: Int) async -> NetworkProfile? {
        guard profiles.indices.contains(index) else { return nil }
        if let profile = profiles[index].profile {
            return profile
        }
        do {
            let profile = try await ProfileStore.loadProfile(from: profiles[index].index)
            profiles[index].profile = profile
            return profile
        } catch {
            dashboardLogger.error("load profile failed: \(error)")
            errorMessage = .init(error.localizedDescription)
            return nil
        }
    }

    @MainActor
    private func saveProfileIfNeeded(at index: Int) async {
        guard profiles.indices.contains(index) else { return }
        guard let profile = profiles[index].profile else { return }
        let fileURL = profiles[index].index.fileURL
        let profileId = profiles[index].id
        do {
            try await ProfileStore.save(profile, to: fileURL)
            if selectedProfileId == profileId {
                await saveOptions()
            }
        } catch {
            dashboardLogger.error("save profile failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }

    @MainActor
    private func scheduleSave(for index: Int) {
        let profileId = profiles[index].id
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                guard let targetIndex = profiles.firstIndex(where: { $0.id == profileId }) else { return }
                await saveProfileIfNeeded(at: targetIndex)
            }
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + profileSaveDebounceInterval, execute: workItem)
    }

    private func bindingForProfile(at index: Int) -> Binding<NetworkProfile> {
        Binding(
            get: {
                guard index < profiles.count else { return NetworkProfile() }
                return profiles[index].profile ?? NetworkProfile()
            },
            set: { newValue in
                profiles[index].profile = newValue
                scheduleSave(for: index)
            }
        )
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        DashboardView(manager: manager)
        .environmentObject(manager)
    }
}

struct IdentifiableURL: Identifiable {
    var id: URL { self.url }
    var url: URL
    init(_ url: URL) {
        self.url = url
    }
}
