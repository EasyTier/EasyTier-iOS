import SwiftUI

struct NetworkEditView: View {
    @Binding var name: String
    @Binding var profile: NetworkProfile
    @State var showProxyCIDREditor = false
    @State var editingProxyCIDR: NetworkProfile.ProxyCIDR?

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

    var basicSettings: some View {
        Group {
            Section("Virtual IPv4") {
                Toggle("DHCP", isOn: $profile.dhcp)

                if !profile.dhcp {
                    LabeledContent("Address") {
                        IPv4Field(ip: $profile.virtualIPv4.ip, length: $profile.virtualIPv4.length)
                    }
                }
            }

            Section("Network") {
                LabeledContent("Name") {
                    TextField("easytier", text: $name)
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
                    ForEach(NetworkProfile.NetworkingMethod.allCases) {
                        method in
                        Text(method.description).tag(method)
                    }
                }
                .pickerStyle(.palette)

                switch profile.networkingMethod {
                case .publicServer:
                    LabeledContent("Server") {
                        Text(profile.publicServerURL)
                            .multilineTextAlignment(.trailing)
                    }
                case .manual:
                    ListEditor(newItemTitle: "Add Peer", items: $profile.peerURLs, addItemFactory: { "" }, rowContent: {
                        TextField("e.g.: tcp://8.8.8.8:11010", text: $0.text)
                            .fontDesign(.monospaced)
                    })
                case .standalone:
                    EmptyView()
                }
            }
        }
    }

    var advancedSettings: some View {
        Form {
            Section {
                LabeledContent("Hostname") {
                    TextField("Default", text: $profile.hostname.bound)
                        .multilineTextAlignment(.trailing)
                }

//                LabeledContent("Device Name") {
//                    TextField("Default", text: $profile.devName)
//                        .multilineTextAlignment(.trailing)
//                }

                LabeledContent("MTU") {
                    TextField(
                        "Default",
                        value: $profile.mtu,
                        formatter: NumberFormatter()
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                }
            } header: {
                Text("General")
            } footer: {
                Text("MTU Default: 1380 (encrypted) or 1360 (unencrypted). Range: 400-1380.")
            }
            
            proxyCIDRsSettings
            
            Section("VPN Portal") {
                Toggle(
                    "Enable",
                    isOn: $profile.enableVPNPortal
                )
                if profile.enableVPNPortal {
                    LabeledContent("Address") {
                        IPv4Field(ip: $profile.vpnPortalClientCIDR.ip, length: $profile.vpnPortalClientCIDR.length)
                    }
                    LabeledContent("Listen Port") {
                        TextField(
                            "e.g. 22022",
                            value: $profile.vpnPortalListenPort,
                            formatter: NumberFormatter()
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                    }
                }
            }
            
            Section("Listener URLs") {
                ListEditor(newItemTitle: "Add Listener URL", items: $profile.listenerURLs, addItemFactory: { "" }, rowContent: {
                    TextField("e.g: tcp://1.1.1.1:11010", text: $0.text)
                        .fontDesign(.monospaced)
                })
            }
            
            Section {
                Toggle("Enable", isOn: $profile.enableRelayNetworkWhitelist)
                if profile.enableRelayNetworkWhitelist {
                    ListEditor(newItemTitle: "Add Network", items: $profile.relayNetworkWhitelist, addItemFactory: { "" }, rowContent: {
                        TextField("e.g.: net1", text: $0.text)
                            .fontDesign(.monospaced)
                    })
                }
            } header: {
                Text("Network Whitelist")
            } footer: {
                Text("""
                    Only forward traffic from the whitelist networks, supporting wildcard strings, multiple network names can be separated by spaces.
                    If this parameter is empty, forwarding is disabled. By default, all networks are allowed.
                    e.g.: '\\*' (all networks), 'def\\*' (networks with the prefix 'def'), 'net1 net2' (only allow net1 and net2)
                    """)
            }
            
            Section {
                Toggle("Enable", isOn: $profile.enableManualRoutes)
                if profile.enableManualRoutes {
                    ListEditor(newItemTitle: "Add Route", items: $profile.routes, addItemFactory: NetworkProfile.CIDR.init, rowContent: {
                        IPv4Field(ip: $0.ip, length: $0.length)
                    })
                }
            } header: {
                Text("Manual Route")
            } footer: {
                Text("""
                    Assign routes cidr manually, will disable subnet proxy and wireguard routes propagated from peers. e.g.: 192.168.0.0/16
                    """)
            }
            
            Section("SOCKS5 Server") {
                Toggle(
                    "Enable",
                    isOn: $profile.enableSocks5
                )
                if profile.enableSocks5 {
                    LabeledContent("Listen Port") {
                        TextField(
                            "e.g. 1080",
                            value: $profile.socks5Port,
                            formatter: NumberFormatter()
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                    }
                }
            }
            
            Section {
                ListEditor(newItemTitle: "Add Exit Node", items: $profile.exitNodes, addItemFactory: { "" }, rowContent: {
                    TextField("Node IP, e.g. 192.168.8.8", text: $0.text)
                        .fontDesign(.monospaced)
                })
            } header: {
                Text("Exit Nodes")
            } footer: {
                Text("""
                    Exit nodes to forward all traffic to, a virtual ipv4 address, priority is determined by the order of the list
                    """)
            }
            
            Section {
                ListEditor(newItemTitle: "Add Map Listener", items: $profile.mappedListeners, addItemFactory: { "" }, rowContent: {
                    TextField("e.g.: tcp://123.123.123.123:11223", text: $0.text)
                        .fontDesign(.monospaced)
                })
            } header: {
                Text("Map Listeners")
            } footer: {
                Text("""
                    Manually specify the public address of the listener, other nodes can use this address to connect to this node.
                    e.g.: tcp://123.123.123.123:11223, can specify multiple.
                    """)
            }

            Section("Feature") {
                ForEach(NetworkProfile.boolFlags) { flag in
                    Toggle(isOn: Binding<Bool>(
                        get: { $profile.wrappedValue[keyPath: flag.keyPath] },
                        set: { $profile.wrappedValue[keyPath: flag.keyPath] = $0 }
                    )) {
                        Text(flag.label)
                        if let help = flag.help {
                            Text(help)
                        }
                    }
                }
            }
        }
        .navigationTitle("Advanced Settings")
        .sheet(isPresented: $showProxyCIDREditor) {
            proxyCIDREditor
        }
    }

    var portForwardsSettings: some View {
        Form {
            ListEditor(newItemTitle: "Add Port Forward", items: $profile.portForwards, addItemFactory: NetworkProfile.PortForwardSetting.init, rowContent: { $forward in
                VStack(spacing: 8) {
                    HStack {
                        Text("Protocol:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Protocol", selection: $forward.proto) {
                            Text("TCP").tag("tcp")
                            Text("UDP").tag("udp")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    HStack {
                        TextField("Bind Address", text: $forward.bindAddr)
                        Text(":")
                        TextField(
                            "Port",
                            value: $forward.bindPort,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 60)
                        .keyboardType(.numberPad)
                    }
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("Forward to")
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                    HStack {
                        TextField("Destination Address", text: $forward.destAddr)
                        Text(":")
                        TextField(
                            "Port",
                            value: $forward.destPort,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 60)
                        .keyboardType(.numberPad)
                    }
                }
                .padding(.vertical, 5)
            })
        }
        .navigationTitle("Port Forwards")
    }
    
    var proxyCIDRsSettings: some View {
        Section("Proxy CIDRs") {
            ListEditor(newItemTitle: "Add Proxy CIDR", items: $profile.proxyCIDRs, addItemFactory: {
                NetworkProfile.ProxyCIDR(cidr: "0.0.0.0", enableMapping: false, mappedCIDR: "0.0.0.0", length: "0")
            }, rowContent: { proxyCIDR in
                HStack(spacing: 12) {
                    if proxyCIDR.enableMapping.wrappedValue {
                        Text("Map:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(proxyCIDR.cidr.wrappedValue)/\(proxyCIDR.length.wrappedValue)")
                            .fontDesign(.monospaced)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text("\(proxyCIDR.mappedCIDR.wrappedValue)/\(proxyCIDR.length.wrappedValue)")
                            .fontDesign(.monospaced)
                    } else {
                        Text("Proxy:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(proxyCIDR.cidr.wrappedValue)/\(proxyCIDR.length.wrappedValue)")
                            .fontDesign(.monospaced)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editingProxyCIDR = proxyCIDR.wrappedValue
                    showProxyCIDREditor = true
                }
            })
        }
    }
    
    var proxyCIDREditor: some View {
        NavigationStack {
            Group {
                if let proxyCIDR = Binding($editingProxyCIDR) {
                    Form {
                        Section("Proxy CIDR") {
                            LabeledContent("CIDR") {
                                IPv4Field(ip: proxyCIDR.cidr, length: proxyCIDR.length)
                            }
                        }
                        Section("Mapped CIDR") {
                            Toggle("Enable", isOn: proxyCIDR.enableMapping)
                            if proxyCIDR.enableMapping.wrappedValue {
                                LabeledContent("CIDR") {
                                    IPv4Field(ip: proxyCIDR.mappedCIDR, length: proxyCIDR.length, disabledLengthEdit: true)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Proxy CIDR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    showProxyCIDREditor = false
                    if let editingProxyCIDR {
                        if let index = (profile.proxyCIDRs.firstIndex { $0.id == editingProxyCIDR.id }) {
                            profile.proxyCIDRs[index] = editingProxyCIDR
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
            }
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

struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        @State var profile = NetworkProfile(id: UUID())
        @State var name = ""
        NavigationStack {
            NetworkEditView(name: $name, profile: $profile)
        }
    }
}
