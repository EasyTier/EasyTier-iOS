import SwiftUI

struct NetworkEditView: View {
    @Binding var profile: NetworkProfile
    @State var sel = 0

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
    }

    private var basicSettings: some View {
        Group {
            Section("Virtual IPv4") {
                Toggle("DHCP", isOn: $profile.dhcp)

                if !profile.dhcp {
                    HStack {
                        TextField(
                            "IPv4 Address",
                            text: $profile.virtualIPv4.ip
                        )
                        Text("/")
                        TextField(
                            "Length",
                            value: $profile.virtualIPv4.length,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50)
                        .keyboardType(.numberPad)
                    }
                }
            }

            Section("Network") {
                LabeledContent("Name") {
                    TextField("easytier", text: $profile.networkName)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("Secret") {
                    SecureField(
                        "Empty",
                        text: $profile.networkSecret
                    )
                    .multilineTextAlignment(.trailing)
                }

                Picker(
                    "Networking Method",
                    selection: $profile.networkingMethod
                ) {
                    ForEach(NetworkingMethod.allCases) {
                        method in
                        Text(verbatim: "\(method)".capitalized).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch profile.networkingMethod {
                case .publicServer:
                    LabeledContent("Server") {
                        Text(profile.publicServerURL)
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
                                    profile.peerURLs.joined(
                                        separator: "\n"
                                    )
                                },
                                set: {
                                    profile.peerURLs = $0.split(
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
                    TextField("Default", text: $profile.hostname.bound)
                        .multilineTextAlignment(.trailing)
                }

                // TODO: FIXME
//                MultiLineTextField(
//                    title: "Proxy CIDRs",
//                    items: $profile.proxyCIDRs
//                )

                Toggle(
                    "Enable VPN Portal",
                    isOn: $profile.enableVPNPortal
                )
                if profile.enableVPNPortal {
                    HStack {
                        TextField(
                            "Client Network Address",
                            text: $profile
                                .vpnPortalClientCIDR.ip
                        )
                        Text("/")
                        TextField(
                            "Length",
                            value: $profile
                                .vpnPortalClientCIDR.length,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 50)
                    }
                    TextField(
                        "Listen Port",
                        value: $profile.vpnPortalListenPort,
                        formatter: NumberFormatter()
                    )
                }

                MultiLineTextField(
                    title: "Listener URLs",
                    items: $profile.listenerURLs
                )

                LabeledContent("Device Name") {
                    TextField("Default", text: $profile.devName)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("MTU")
                    TextField(
                        "MTU",
                        value: $profile.mtu,
                        formatter: NumberFormatter()
                    )
                    .help(
                        "Default: 1380 (encrypted) or 1360 (unencrypted). Range: 400-1380."
                    )
                }

                Toggle(
                    "Enable Relay Network Whitelist",
                    isOn: $profile.enableRelayNetworkWhitelist
                )
                if profile.enableRelayNetworkWhitelist {
                    MultiLineTextField(
                        title: "Relay Network Whitelist",
                        items: $profile.relayNetworkWhitelist
                    )
                }

                Toggle(
                    "Enable Manual Routes",
                    isOn: $profile.enableManualRoutes
                )
                if profile.enableManualRoutes {
                    MultiLineTextField(
                        title: "Manual Routes",
                        items: $profile.routes
                    )
                }

                Toggle(
                    "Enable SOCKS5 Server",
                    isOn: $profile.enableSocks5
                )
                if profile.enableSocks5 {
                    TextField(
                        "SOCKS5 Port",
                        value: $profile.socks5Port,
                        formatter: NumberFormatter()
                    )
                }

                MultiLineTextField(
                    title: "Exit Nodes",
                    items: $profile.exitNodes
                )
                MultiLineTextField(
                    title: "Mapped Listeners",
                    items: $profile.mappedListeners
                )
            }

            Section("Feature") {
                ForEach(NetworkProfile.boolFlags) { flag in
                    Toggle(isOn: binding($profile, to: flag.keyPath)) {
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
            ForEach($profile.portForwards) { $forward in
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
                            profile.portForwards.removeAll {
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
                    profile.portForwards.append(PortForwardSetting())
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

struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        @State var profile = NetworkProfile(id: UUID())
        NavigationView {
            NetworkEditView(profile: $profile)
        }
    }
}

struct Advanced_Settings_Previews: PreviewProvider {
    static var previews: some View {
        @State var profile = NetworkProfile(id: UUID())
        NetworkEditView(profile: $profile).advancedSettings
    }
}
