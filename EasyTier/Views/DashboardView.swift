import SwiftData
import SwiftUI
import NetworkExtension
import os

private let DashboardLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "App", category: "Dashboard")

struct DashboardView<Manager: NEManagerProtocol>: View {
    @Environment(\.modelContext) var context
    @Query(sort: \ProfileSummary.createdAt) var networks: [ProfileSummary]
    
    @EnvironmentObject var manager: Manager

    @AppStorage("lastSelected") var lastSelected: String?
    @State var selectedProfileId: UUID?
    @State var isLocalPending = false
    
    @State var showSheet = false

    @State var showNewNetworkAlert = false
    @State var newNetworkInput = ""
    
    @State var errorMessage: TextItem?

    @State private var darwinObserver: DNObserver? = nil
    
    var selectedProfile: ProfileSummary? {
        guard let selectedProfileId else { return nil }
        return networks.first {
            $0.id == selectedProfileId
        }
    }
    
    var isConnected: Bool {
        [.connected, .disconnecting].contains(manager.status)
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
                    Text("Please select a network.")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
    
    var sheetView: some View {
        NavigationStack {
            Form {
                Section("Network") {
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
                Section("Manage") {
                    Button {
                        showNewNetworkAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "document.badge.plus")
                            Text("Create a network")
                        }
                    }
                    Button {
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.document")
                            Text("Import from file")
                        }
                    }
                    Button {
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "long.text.page.and.pencil")
                            Text("Edit in text")
                        }
                    }
                }
            }
            .navigationTitle("Manage Networks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    showSheet = false
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
            .alert("New Network", isPresented: $showNewNetworkAlert) {
                TextField("Name of the new network", text: $newNetworkInput)
                    .textInputAutocapitalization(.never)
                Button(role: .cancel) {}
                Button(role: .confirm) {
                    let profile = ProfileSummary(
                        name: newNetworkInput.isEmpty
                            ? "easytier" : newNetworkInput,
                        context: context
                    )
                    context.insert(profile)
                    selectedProfileId = profile.id
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    var body: some View {
        NavigationStack {
            mainView
            .navigationTitle(selectedProfile?.name ?? "Select Network")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Select Network", systemImage: "chevron.up.chevron.down") {
                        showSheet = true
                    }
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
                                    try await manager.connect(profile: selectedProfile)
                                } catch {
                                    DashboardLogger.error("connect failed: \(error)")
                                    errorMessage = .init(error.localizedDescription)
                                }
                            }
                            isLocalPending = false
                        }
                    } label: {
                        Label(
                            isConnected ? "Disconnect" : "Connect",
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
            darwinObserver = DNObserver(name: "site.yinmo.easytier.tunnel.error") {
                // Read the latest error from shared App Group defaults
                let defaults = UserDefaults(suiteName: "group.site.yinmo.easytier")
                if let msg = defaults?.string(forKey: "TunnelLastError") {
                    DispatchQueue.main.async {
                        DashboardLogger.error("core stopped: \(msg)")
                        self.errorMessage = .init(msg)
                    }
                }
            }
        }
        .onChange(of: selectedProfile) {
            lastSelected = selectedProfile?.id.uuidString
            guard let selectedProfile else { return }
            Task {
                await manager.updateName(name: selectedProfile.name, server: selectedProfile.id.uuidString)
            }
        }
        .onDisappear {
            // Release observer to remove registration
            darwinObserver = nil
        }
        .sheet(isPresented: $showSheet) {
            sheetView
        }
        .alert(item: $errorMessage) { msg in
            DashboardLogger.error("received error: \(String(describing: msg))")
            return Alert(title: Text("Error"), message: Text(msg.text))
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

