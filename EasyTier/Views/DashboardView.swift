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
    @ObservedObject var manager: Manager
    
    @AppStorage("lastSelected") var lastSelected: String?
    @AppStorage("profilesUseICloud") var profilesUseICloud: Bool = false
    
    @State var selectedProfile: NetworkProfile?
    @State var selectedProfileName: String?
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

    @State var darwinObserver: DNObserver? = nil
    @State var pendingSaveWorkItem: DispatchWorkItem? = nil
    
    init(manager: Manager) {
        _manager = ObservedObject(wrappedValue: manager)
    }

    struct ProfileEntry: Identifiable, Equatable {
        var id: String { configName }
        var configName: String
        var profile: NetworkProfile?
    }

    var isConnected: Bool {
        [.connected, .disconnecting, .reasserting].contains(manager.status)
    }
    var isPending: Bool {
        isLocalPending || [.connecting, .disconnecting, .reasserting].contains(manager.status)
    }

    var mainView: some View {
        Group {
            if let $profile = Binding($selectedProfile) {
                if isConnected {
                    StatusView<Manager>($profile.wrappedValue.networkName)
                } else {
                    NetworkEditView(profile: Binding(
                        get: { $profile.wrappedValue },
                        set: { newValue in
                            $profile.wrappedValue = newValue
                            if selectedProfileName != nil {
                                scheduleSave()
                            }
                        }
                    ))
                        .disabled(isPending)
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
        guard let sanitizedName = availableConfigName(baseName) else { return }
        let profile = NetworkProfile()
        Task { @MainActor in
            do {
                try await ProfileStore.save(profile, named: sanitizedName)
                selectedProfileName = sanitizedName
                selectedProfile = profile
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
                    let profiles = ProfileStore.loadIndexOrEmpty().map{ IdenticalTextItem($0) }
                    ForEach(profiles) { item in
                        Button {
                            if selectedProfileName == item.id {
                                selectedProfileName = nil
                                selectedProfile = nil
                            } else {
                                Task { @MainActor in
                                    await loadProfile(item.id)
                                }
                            }
                        } label: {
                            HStack {
                                Text(item.id)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedProfileName == item.id {
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
                                do {
                                    try ProfileStore.deleteProfile(named: profiles[index].id)
                                } catch {
                                    dashboardLogger.error("delete profile failed: \(error)")
                                    errorMessage = .init(error.localizedDescription)
                                }
                            }
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
                .navigationTitle(selectedProfileName ?? String(localized: "select_network"))
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
                            } else if let selectedProfile {
                                do {
                                    let options = try NEManager.generateOptions(selectedProfile)
                                    NEManager.saveOptions(options)
                                    try await manager.connect()
                                } catch {
                                    dashboardLogger.error("connect failed: \(error)")
                                    errorMessage = .init(error.localizedDescription)
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
                    .disabled(selectedProfileName == nil || manager.isLoading || isPending)
                    .buttonStyle(.plain)
                    .foregroundStyle(isConnected ? Color.red : Color.accentColor)
                    .animation(.interactiveSpring, value: [isConnected, isPending])
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                try? await manager.load()
                if selectedProfileName == nil,
                   let lastSelected {
                    await loadProfile(lastSelected)
                    if let selectedProfile,
                       let options = try? NEManager.generateOptions(selectedProfile) {
                        NEManager.saveOptions(options)
                    }
                }
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
        }
        .onChange(of: scenePhase) { _ in
            Task { @MainActor in
                await saveProfile()
            }
        }
        .onChange(of: profilesUseICloud) { _ in
            selectedProfile = nil
            selectedProfileName = nil
        }
        .onDisappear {
            // Release observer to remove registration
            darwinObserver = nil
            Task { @MainActor in
                await saveProfile()
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
    private func loadProfile(_ named: String) async {
        selectedProfileName = named
        do {
            selectedProfile = try await ProfileStore.loadProfile(named: named)
        } catch {
            dashboardLogger.error("load profile failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }
    
    @MainActor
    private func saveProfile(saveOptions: Bool = true) async {
        if saveOptions,
           let selectedProfile,
           let options = try? NEManager.generateOptions(selectedProfile) {
            NEManager.saveOptions(options)
        }
        if let selectedProfile, let selectedProfileName {
            do {
                try await ProfileStore.save(selectedProfile, named: selectedProfileName)
            } catch {
                dashboardLogger.error("save failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
        pendingSaveWorkItem?.cancel()
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
                let rawName = url.deletingPathExtension().lastPathComponent
                guard let configName = availableConfigName(rawName) else { return }
                let profile = NetworkProfile(from: config)
                try await ProfileStore.save(profile, named: configName)
                selectedProfileName = configName
                selectedProfile = profile
            } catch {
                dashboardLogger.error("import failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func exportSelectedProfile() {
        guard let selectedProfileName else {
            errorMessage = .init("Please select a network.")
            return
        }
        let fileURL = try? ProfileStore.fileURL(forConfigName: selectedProfileName)
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = .init("Config file not found.")
            return
        }
        dashboardLogger.info("exporting to: \(fileURL)")
        exportURL = .init(fileURL)
    }

    private func presentEditInText() {
        Task { @MainActor in
            guard let selectedProfile else {
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
        Task { @MainActor in
            do {
                let config = try TOMLDecoder().decode(NetworkConfig.self, from: editText)
                guard var profile = selectedProfile else {
                    errorMessage = .init("Please select a network.")
                    return
                }
                config.apply(to: &profile)
                selectedProfile = profile
                scheduleSave()
                showEditSheet = false
            } catch {
                dashboardLogger.error("edit save failed: \(error)")
                errorMessage = .init(error.localizedDescription)
            }
        }
    }

    private func commitConfigNameEdit() {
        guard let selectedProfileName,
              let editingProfileName else { return }
        let trimmed = editConfigNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed != editingProfileName else { return }
        guard let sanitizedName = validatedConfigName(trimmed) else { return }
        do {
            try ProfileStore.renameProfileFile(
                from: selectedProfileName,
                to: sanitizedName
            )
            if selectedProfileName == editingProfileName {
                self.selectedProfileName = sanitizedName
            }
        } catch {
            dashboardLogger.error("rename failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }

    private func validatedConfigName(_ raw: String) -> String? {
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
        let hasDuplicate = ProfileStore.loadIndexOrEmpty().enumerated().contains { item in
            return item.element.caseInsensitiveCompare(sanitized) == .orderedSame
        }
        guard !hasDuplicate else {
            errorMessage = .init("Config name already exists.")
            return nil
        }
        return sanitized
    }

    private func availableConfigName(_ raw: String) -> String? {
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
        let existingNames = ProfileStore.loadIndexOrEmpty().enumerated().compactMap { item -> String? in
            return item.element
        }
        if !existingNames.contains(where: { $0.caseInsensitiveCompare(sanitized) == .orderedSame }) {
            return sanitized
        }
        var suffix = 2
        while suffix < 10_000 {
            let candidate = "\(sanitized) \(suffix)"
            if !existingNames.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return candidate
            }
            suffix += 1
        }
        errorMessage = .init("Config name already exists.")
        return nil
    }

    @MainActor
    private func scheduleSave() {
        dashboardLogger.debug("scheduleSave() triggered")
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                dashboardLogger.debug("scheduleSave() saving")
                await saveProfile()
            }
        }
        pendingSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + profileSaveDebounceInterval, execute: workItem)
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
