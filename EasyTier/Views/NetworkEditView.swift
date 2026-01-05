import SwiftUI

struct NetworkEditView: View {
    @Bindable var summary: ProfileSummary
    @State var sel = 0
    @State private var isShowingCIDRManagement = false
    @State private var useCIDR = false

    var body: some View {
        Form {
            basicSettings

            NavigationLink("Advanced Settings") {
                advancedSettings
            }

            NavigationLink("Port Forwards") {
                portForwardsSettings
            }
        }
        .sheet(isPresented: $isShowingCIDRManagement) {
            CIDRManagementView(
                useCIDR: $useCIDR,
                proxyCIDRs: $profile.proxy_cidrs
            )
        }
    }

    private var basicSettings: some View {
        Group {
            Section("Virtual IPv4") {
                Toggle("DHCP", isOn: $summary.profile.dhcp)

                if !summary.profile.dhcp {
                    HStack {
                        TextField(
                            "IPv4 Address",
                            text: $summary.profile.virtualIPv4.ip
                        )
                        Text("/")
                        TextField(
                            "Length",
                            value: $summary.profile.virtualIPv4.length,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50)
                        .keyboardType(.numberPad)
                    }
                }
            }

            Section("Network") {
                LabeledContent("Name") {
                    TextField("easytier", text: $summary.profile.networkName)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Secret") {
                    SecureField(
                        "Empty",
                        text: $summary.profile.networkSecret
                    )
                    .multilineTextAlignment(.trailing)
                }

                Picker(
                    "Networking Method",
                    selection: $summary.profile.networkingMethod
                ) {
                    ForEach(NetworkProfile.NetworkingMethod.allCases) {
                        method in
                        Text(method.description).tag(method)
                    }
                }
                .pickerStyle(.palette)

                switch summary.profile.networkingMethod {
                case .publicServer:
                    LabeledContent("Server") {
                        Text(summary.profile.publicServerURL)
                            .multilineTextAlignment(.trailing)
                    }
                case .manual:
                    // For simplicity, using a TextField for comma-separated values.
                    // A more advanced implementation would use a token field.
                    VStack(alignment: .leading) {
                        Text("Peer URLs")
                        TextEditor(
                            text: Binding(
                                get: {
                                    summary.profile.peerURLs.joined(
                                        separator: "\n"
                                    )
                                },
                                set: {
                                    summary.profile.peerURLs = $0.split(
                                        whereSeparator: \.isNewline
                                    ).map(String.init)
                                }
                            )
                        )
                        .frame(minHeight: 100)
                        .border(Color.gray.opacity(0.2), width: 1)
                        .cornerRadius(5)
                    }
                case .standalone:
                    EmptyView()
                }

            }
        }
    }

    fileprivate var advancedSettings: some View {
        Form {
            Section("General") {
                LabeledContent("Hostname") {
                    TextField("Default", text: $summary.profile.hostname.bound)
                        .multilineTextAlignment(.trailing)
                }

                Toggle(
                    "Enable VPN Portal",
                    isOn: $summary.profile.enableVPNPortal
                )
                if summary.profile.enableVPNPortal {
                    HStack {
                        TextField(
                            "Client Network Address",
                            text: $summary.profile
                                .vpnPortalClientCIDR.ip
                        )
                        Text("/")
                        TextField(
                            "Length",
                            value: $summary.profile
                                .vpnPortalClientCIDR.length,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50)
                    }
                    TextField(
                        "Listen Port",
                        value: $summary.profile.vpnPortalListenPort,
                        formatter: NumberFormatter()
                    )
                }

                MultiLineTextField(
                    title: "Listener URLs",
                    items: $summary.profile.listenerURLs
                )

                LabeledContent("Device Name") {
                    TextField("Default", text: $summary.profile.devName)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("MTU")
                    TextField(
                        "MTU",
                        value: $summary.profile.mtu,
                        formatter: NumberFormatter()
                    )
                    .help(
                        "Default: 1380 (encrypted) or 1360 (unencrypted). Range: 400-1380."
                    )
                }

                Toggle(
                    "Enable Relay Network Whitelist",
                    isOn: $summary.profile.enableRelayNetworkWhitelist
                )
                if summary.profile.enableRelayNetworkWhitelist {
                    MultiLineTextField(
                        title: "Relay Network Whitelist",
                        items: $summary.profile.relayNetworkWhitelist
                    )
                }

                Toggle(
                    "Enable Manual Routes",
                    isOn: $summary.profile.enableManualRoutes
                )
                if summary.profile.enableManualRoutes {
                    MultiLineTextField(
                        title: "Manual Routes",
                        items: $summary.profile.routes
                    )
                }

                Toggle(
                    "Enable SOCKS5 Server",
                    isOn: $summary.profile.enableSocks5
                )
                if summary.profile.enableSocks5 {
                    TextField(
                        "SOCKS5 Port",
                        value: $summary.profile.socks5Port,
                        formatter: NumberFormatter()
                    )
                }

                MultiLineTextField(
                    title: "Exit Nodes",
                    items: $summary.profile.exitNodes
                )
                MultiLineTextField(
                    title: "Mapped Listeners",
                    items: $summary.profile.mappedListeners
                )
            }

            Section("Routing") {
                Button(action: {
                    useCIDR = !profile.proxy_cidrs.isEmpty
                    isShowingCIDRManagement = true
                }) {
                    LabeledContent("Proxy CIDRs") {
                        Text("\(profile.proxy_cidrs.count) items")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Feature") {
                ForEach(NetworkProfile.boolFlags) { flag in
                    Toggle(isOn: binding($summary.profile, to: flag.keyPath)) {
                        Text(flag.label)
                        if let help = flag.help {
                            Text(help)
                        }
                    }
                }
            }
        }
        .navigationTitle("Advanced Settings")
    }

    fileprivate var portForwardsSettings: some View {
        Form {
            ForEach($summary.profile.portForwards) { $forward in
                VStack {
                    HStack {
                        Picker("", selection: $forward.proto) {
                            Text("TCP").tag("tcp")
                            Text("UDP").tag("udp")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)

                        Spacer()

                        Button(action: {
                            summary.profile.portForwards.removeAll {
                                $0.id == forward.id
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    HStack {
                        TextField("Bind IP", text: $forward.bindIP)
                        Text(":")
                        TextField(
                            "Port",
                            value: $forward.bindPort,
                            formatter: NumberFormatter()
                        ).frame(width: 60)
                    }
                    HStack {
                        Image(systemName: "arrow.down")
                            .foregroundColor(.secondary)
                        Text("Forward to").foregroundColor(.secondary)
                    }
                    HStack {
                        TextField("Destination IP", text: $forward.dstIP)
                        Text(":")
                        TextField(
                            "Port",
                            value: $forward.dstPort,
                            formatter: NumberFormatter()
                        ).frame(width: 60)
                    }
                }
                .padding(.vertical, 5)
            }

            Button(
                "Add Port Forward",
                systemImage: "plus",
                action: {
                    summary.profile.portForwards.append(NetworkProfile.PortForwardSetting())
                }
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("Port Forwards")
    }
}

// MARK: - Helper Views and Extensions

private struct MultiLineTextField: View {
    let title: String
    @Binding var items: [String]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            TextEditor(
                text: Binding(
                    get: { items.joined(separator: "\n") },
                    set: {
                        items = $0.split(whereSeparator: \.isNewline).map(
                            String.init
                        )
                    }
                )
            )
            .frame(minHeight: 80)
            .font(.system(.body, design: .monospaced))
            .padding(4)
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(
                    Color.gray.opacity(0.5)
                )
            )
        }
    }
}

extension Optional where Wrapped == String {
    fileprivate var bound: String {
        get { self ?? "" }
        set { self = newValue.isEmpty ? nil : newValue }
    }
}

extension Optional where Wrapped == Int {
    fileprivate var bound: Int {
        get { self ?? 0 }
        set { self = newValue }
    }
}

private func binding<Root, Value>(
    _ root: Binding<Root>,
    to keyPath: WritableKeyPath<Root, Value>
) -> Binding<Value> {
    Binding<Value>(
        get: { root.wrappedValue[keyPath: keyPath] },
        set: { root.wrappedValue[keyPath: keyPath] = $0 }
    )
}

private struct BoolFlag: Identifiable {
    let id = UUID()
    let keyPath: WritableKeyPath<NetworkProfile, Bool>
    let label: String
    let help: String?
}

extension NetworkProfile {
    fileprivate static let boolFlags: [BoolFlag] = [
        .init(
            keyPath: \.latencyFirst,
            label: "Latency-First Mode",
            help:
                "Ignore hop count and select the path with the lowest total latency."
        ),
        .init(
            keyPath: \.useSmoltcp,
            label: "Use User-Space Protocol Stack",
            help:
                "Use a user-space TCP/IP stack to avoid issues with OS firewalls."
        ),
        .init(
            keyPath: \.disableIPv6,
            label: "Disable IPv6",
            help: "Disable IPv6 functionality for this node."
        ),
        .init(
            keyPath: \.enableKCPProxy,
            label: "Enable KCP Proxy",
            help: "Convert TCP traffic to KCP to reduce latency."
        ),
        .init(
            keyPath: \.disableKCPInput,
            label: "Disable KCP Input",
            help: "Disable inbound KCP traffic."
        ),
        .init(
            keyPath: \.enableQUICProxy,
            label: "Enable QUIC Proxy",
            help: "Convert TCP traffic to QUIC to reduce latency."
        ),
        .init(
            keyPath: \.disableQUICInput,
            label: "Disable QUIC Input",
            help: "Disable inbound QUIC traffic."
        ),
        .init(
            keyPath: \.disableP2P,
            label: "Disable P2P",
            help: "Route all traffic through a manually specified relay server."
        ),
        .init(
            keyPath: \.p2pOnly,
            label: "P2P Only",
            help:
                "Only communicate with peers that have established P2P connections."
        ),
        .init(
            keyPath: \.bindDevice,
            label: "Bind to Physical Device Only",
            help: "Use only the physical network interface."
        ),
        .init(
            keyPath: \.noTUN,
            label: "No TUN Mode",
            help:
                "Do not use a TUN interface. This node will be accessible but cannot initiate connections to others without SOCKS5."
        ),
        .init(
            keyPath: \.enableExitNode,
            label: "Enable Exit Node",
            help: "Allow this node to be an exit node."
        ),
        .init(
            keyPath: \.relayAllPeerRPC,
            label: "Relay All Peer RPC",
            help:
                "Relay all peer RPC packets, even for peers not in the whitelist."
        ),
        .init(
            keyPath: \.multiThread,
            label: "Multi-Threaded Runtime",
            help: "Use a multi-thread runtime for performance."
        ),
        .init(
            keyPath: \.proxyForwardBySystem,
            label: "System Forwarding for Proxy",
            help: "Forward packets to proxy networks via the system kernel."
        ),
        .init(
            keyPath: \.disableEncryption,
            label: "Disable Encryption",
            help:
                "Disable encryption for peer communication. Must be the same on all peers."
        ),
        .init(
            keyPath: \.disableUDPHolePunching,
            label: "Disable UDP Hole Punching",
            help: "Disable the UDP hole punching mechanism."
        ),
        .init(
            keyPath: \.disableSymHolePunching,
            label: "Disable Symmetric NAT Hole Punching",
            help: "Disable special handling for symmetric NATs."
        ),
        .init(
            keyPath: \.enableMagicDNS,
            label: "Enable Magic DNS",
            help:
                "Access nodes in the network by their hostname via a special DNS."
        ),
        .init(
            keyPath: \.enablePrivateMode,
            label: "Enable Private Mode",
            help:
                "Do not allow handshake or relay for nodes with a different network name or secret."
        ),
    ]
}

struct CIDRManagementView: View {
    @Environment(\.dismiss) var dismiss

    @Binding var useCIDR: Bool
    @Binding var proxyCIDRs: [String]

    @State private var editingIndex: Int? = nil
    @State private var isShowingEditor = false
    @State private var newCIDRText = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    Toggle("Use CIDR", isOn: $useCIDR)
                }
                .onChange(of: useCIDR) { newValue in
                    if !newValue {
                        proxyCIDRs.removeAll()
                    }
                }

                if useCIDR {
                    Section("Saved CIDRs") {
                        Button(action: {
                            newCIDRText = ""
                            editingIndex = nil
                            isShowingEditor = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Proxy CIDR")
                            }
                        }

                        ForEach(Array(proxyCIDRs.enumerated()), id: \.element) {
                            index,
                            cidr in
                            Button(action: {
                                newCIDRText = cidr
                                editingIndex = index
                                isShowingEditor = true
                            }) {
                                HStack {
                                    Text(cidr).font(
                                        .system(.body, design: .monospaced)
                                    )
                                    Spacer()
                                    Image(systemName: "pencil.circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Proxy CIDRs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingEditor) {
                CIDREditView(fullText: $newCIDRText) { savedText in
                    if let index = editingIndex {
                        let isDuplicate = proxyCIDRs.enumerated().contains {
                            $0.offset != index && $0.element == savedText
                        }
                        if !isDuplicate {
                            proxyCIDRs[index] = savedText
                        }
                    } else {
                        if !proxyCIDRs.contains(savedText) {
                            proxyCIDRs.append(savedText)
                        }
                    }
                    useCIDR = true
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        proxyCIDRs.remove(atOffsets: offsets)
        if proxyCIDRs.isEmpty {
            useCIDR = false
        }
    }
}

struct CIDREditView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var fullText: String
    var onSave: (String) -> Void

    enum Field: Hashable { case octet1, octet2, octet3, octet4, prefix }
    @FocusState private var focusedField: Field?

    @State private var octets: [String] = ["", "", "", ""]
    @State private var prefixLength: Int = 24

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("CIDR Configuration")) {
                    HStack(spacing: 5) {
                        ForEach(0..<4) { index in
                            TextField("0", text: $octets[index])
                                .focused(
                                    $focusedField,
                                    equals: getField(for: index)
                                )
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .onChange(of: octets[index]) {
                                    [oldValue = octets[index]] newValue in
                                    handleIPInput(
                                        index: index,
                                        newValue: newValue,
                                        oldValue: oldValue
                                    )
                                }

                            if index < 3 {
                                Text(".").foregroundColor(.secondary)
                            }
                        }

                        Text("/").foregroundColor(.secondary)

                        TextField(
                            "24",
                            value: $prefixLength,
                            formatter: NumberFormatter()
                        )
                        .focused($focusedField, equals: .prefix)
                        .keyboardType(.numberPad)
                        .frame(width: 45)
                        .multilineTextAlignment(.center)
                        .onChange(of: prefixLength) { val in
                            if val > 32 { prefixLength = 32 }
                            if val < 0 { prefixLength = 0 }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    Text(fullText.isEmpty ? "Add CIDR" : "Edit CIDR")
                        .font(.headline)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        validateAndSave()
                    }
                    .bold()
                }
            }
            .onAppear {
                parseCIDR()
                focusedField = .octet1
            }
        }
    }

    private func handleIPInput(index: Int, newValue: String, oldValue: String) {
        if newValue.isEmpty && !oldValue.isEmpty {
            if index > 0 { focusedField = getField(for: index - 1) }
            octets[index] = ""
            return
        }

        var filtered = newValue.filter { "0123456789".contains($0) }
        if let num = Int(filtered) {
            if num > 255 { filtered = "255" }
        }

        if filtered != newValue { octets[index] = filtered }

        if filtered.count >= 3 {
            if index < 3 {
                focusedField = getField(for: index + 1)
            } else {
                focusedField = .prefix
            }
        }
    }

    private func getField(for index: Int) -> Field {
        switch index {
        case 0: return .octet1
        case 1: return .octet2
        case 2: return .octet3
        case 3: return .octet4
        default: return .octet1
        }
    }

    private func parseCIDR() {
        guard !fullText.isEmpty else { return }
        let mainParts = fullText.split(separator: "/")

        let ipParts = mainParts[0].split(separator: ".")
        if ipParts.count == 4 {
            for i in 0..<4 {
                if let val = Int(ipParts[i]), (0...255).contains(val) {
                    octets[i] = String(val)
                }
            }
        }

        if mainParts.count == 2, let p = Int(mainParts[1]), (0...32).contains(p)
        {
            prefixLength = p
        }
    }

    private func validateAndSave() {
        let validatedOctets = octets.compactMap { str -> String? in
            if let val = Int(str), (0...255).contains(val) {
                return String(val)
            }
            return nil
        }

        guard validatedOctets.count == 4 else {
            return
        }

        let combined =
            "\(validatedOctets.joined(separator: "."))/\(prefixLength)"
        onSave(combined)
        dismiss()
    }
}

struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        @Bindable var summary = ProfileSummary(id: UUID(), name: "example")
        NavigationView {
            NetworkEditView(summary: summary)
        }
    }
}

struct Advanced_Settings_Previews: PreviewProvider {
    static var previews: some View {
        @Bindable var summary = ProfileSummary(id: UUID(), name: "example")
        NetworkEditView(summary: summary).advancedSettings
    }
}
