import SwiftData
import SwiftUI
import NetworkExtension
import os
import TOMLKit
import UniformTypeIdentifiers
import EasyTierShared

private let dashboardLogger = Logger(subsystem: APP_BUNDLE_ID, category: "main.dashboard")

struct DashboardView<Manager: NEManagerProtocol>: View {
    @Environment(\.modelContext) var context
    @Environment(\.scenePhase) var scenePhase
    @Query(sort: \ProfileSummary.createdAt) var networks: [ProfileSummary]

    @EnvironmentObject var manager: Manager

    @AppStorage("lastSelected") var lastSelected: String?
    @State var selectedProfileId: UUID?
    @State var isLocalPending = false

    @State var showManageSheet = false

    @State var showNewNetworkAlert = false
    @State var newNetworkInput = ""

    @State var showImportPicker = false
    @State var exportURL: IdentifiableURL?
    @State var showEditSheet = false
    @State var editText = ""

    @State var errorMessage: TextItem?

    @State private var darwinObserver: DNObserver? = nil

    var selectedProfile: ProfileSummary? {
        guard let selectedProfileId else { return nil }
        return networks.first {
            $0.id == selectedProfileId
        }
    }

    var isConnected: Bool {
        [.connected, .disconnecting, .reasserting].contains(manager.status)
    }
    var isPending: Bool {
        isLocalPending || [.connecting, .disconnecting, .reasserting].contains(manager.status)
    }

    var mainView: some View {
        Group {
            if let selectedProfile {
                @Bindable var profile = selectedProfile
                if isConnected {
                    StatusView<Manager>()
                } else {
                    NetworkEditView(name: $profile.name, profile: $profile.profile)
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
        let profile = ProfileSummary(
            name: newNetworkInput.isEmpty
                ? "easytier" : newNetworkInput,
            context: context
        )
        context.insert(profile)
        selectedProfileId = profile.id
    }

    var sheetView: some View {
        NavigationStack {
            Form {
                Section("network") {
                    ForEach(networks, id: \.self) { item in
                        Button {
                            if selectedProfileId == item.id {
                                selectedProfileId = nil
                            } else {
                                selectedProfileId = item.id
                            }
                        } label: {
                            HStack {
                                Text(item.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedProfileId == item.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        withAnimation {
                            for index in indexSet {
                                if selectedProfile == networks[index] {
                                    selectedProfileId = nil
                                }
                                context.delete(networks[index])
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
                TextField("network_name", text: $newNetworkInput)
                    .textInputAutocapitalization(.never)
                if #available(iOS 26.0, *) {
                    Button(role: .cancel) {}
                    Button("network.create", role: .confirm, action: createProfile)
                } else {
                    Button("common.cancel") {}
                    Button("network.create", action: createProfile)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainView
                .navigationTitle(selectedProfile?.name ?? String(localized: "select_network"))
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
                        Task {
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
                    .disabled(selectedProfileId == nil || manager.isLoading || isPending)
                    .buttonStyle(.plain)
                    .foregroundStyle(isConnected ? Color.red : Color.accentColor)
                    .animation(.interactiveSpring, value: [isConnected, isPending])
                }
            }
        }
        .onAppear {
            if selectedProfileId == nil {
                selectedProfileId = networks.first {
                    $0.id.uuidString == lastSelected
                }?.id
            }
            Task {
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
            if let selectedProfile, let options = try? NEManager.generateOptions(selectedProfile) {
                NEManager.saveOptions(options)
            }
        }
        .onChange(of: scenePhase) { _, _ in
            saveOptions()
        }
        .onChange(of: selectedProfile) {
            lastSelected = selectedProfile?.id.uuidString
            guard let selectedProfile else { return }
            Task {
                await manager.updateName(name: selectedProfile.name, server: selectedProfile.id.uuidString)
            }
            saveOptions()
        }
        .onDisappear {
            // Release observer to remove registration
            darwinObserver = nil
            saveOptions()
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
    
    private func saveOptions() {
        Task {
            if let selectedProfile,
               let options = try? NEManager.generateOptions(selectedProfile) {
                NEManager.saveOptions(options)
            }
        }
    }

    private func importConfig(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let toml = try String(contentsOf: url, encoding: .utf8)
            let config = try TOMLDecoder().decode(NetworkConfig.self, from: toml)
            let name = config.preferredName.isEmpty ? "easytier" : config.preferredName
            let profile = ProfileSummary(name: name, context: context)
            config.apply(to: profile.profile)
            context.insert(profile)
            selectedProfileId = profile.id
        } catch {
            dashboardLogger.error("import failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }

    private func exportSelectedProfile() {
        guard let selectedProfile else {
            errorMessage = .init("Please select a network.")
            return
        }
        do {
            let config = NetworkConfig(from: selectedProfile.profile, name: selectedProfile.name)
            let encoded = try TOMLEncoder().encode(config).string ?? ""
            let safeName = selectedProfile.name.isEmpty ? "easytier" : selectedProfile.name
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeName).toml")
            try encoded.write(to: url, atomically: true, encoding: .utf8)
            dashboardLogger.info("exporting to: \(url)")
            exportURL = .init(url)
        } catch {
            dashboardLogger.error("export failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }

    private func presentEditInText() {
        guard let selectedProfile else {
            errorMessage = .init("Please select a network.")
            return
        }
        do {
            let config = NetworkConfig(from: selectedProfile.profile, name: selectedProfile.name)
            editText = try TOMLEncoder().encode(config).string ?? ""
            showEditSheet = true
        } catch {
            dashboardLogger.error("edit load failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }

    private func saveEditInText() {
        guard let selectedProfile else {
            errorMessage = .init("Please select a network.")
            return
        }
        do {
            let config = try TOMLDecoder().decode(NetworkConfig.self, from: editText)
            config.apply(to: selectedProfile.profile)
            let name = config.preferredName
            if !name.isEmpty {
                selectedProfile.name = name
            }
            showEditSheet = false
        } catch {
            dashboardLogger.error("edit save failed: \(error)")
            errorMessage = .init(error.localizedDescription)
        }
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        @StateObject var manager = MockNEManager()
        DashboardView<MockNEManager>()
        .modelContainer(
            try! ModelContainer(
                for: Schema([ProfileSummary.self, NetworkProfile.self]),
                configurations: ModelConfiguration(
                    isStoredInMemoryOnly: true
                )
            )
        )
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
