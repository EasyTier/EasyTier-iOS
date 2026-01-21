import SwiftUI

struct NetworkEditView: View {
    @Environment(\.horizontalSizeClass) var sizeClass
    @Binding var profile: NetworkProfile
    @State var showProxyCIDREditor = false
    @State var editingProxyCIDR: NetworkProfile.ProxyCIDR?
    @State var selectedPane: EditPane?

    enum EditPane: Identifiable, Hashable {
        var id: Self { self }
        case advanced
        case portForwards
    }
    
    var body: some View {
        AdaptiveNavigation(primaryColumn, secondaryColumn, showNav: $selectedPane)
    }
    
    var primaryColumn: some View {
        List(selection: $selectedPane) {
            basicSettings
            NavigationLink("advanced_settings", value: EditPane.advanced)
            NavigationLink("port_forwards", value: EditPane.portForwards)
        }
        .scrollDismissesKeyboard(.immediately)
    }
    
    var secondaryColumn: some View {
        Group {
            switch selectedPane {
            case .advanced:
                advancedSettings
            case .portForwards:
                portForwardsSettings
            case nil:
                ZStack {
                    Color(.systemGroupedBackground)
                    Image(systemName: "network")
                        .resizable()
                        .frame(width: 128, height: 128)
                        .foregroundStyle(Color.accentColor.opacity(0.2))
                }
                .ignoresSafeArea()
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    var basicSettings: some View {
        Group {
            Section("virtual_ipv4") {
                Toggle("dhcp", isOn: $profile.dhcp)

                if !profile.dhcp {
                    LabeledContent("address") {
                        IPv4Field(ip: $profile.virtualIPv4.ip, length: $profile.virtualIPv4.length)
                    }
                }
            }

            Section("network") {
                LabeledContent("network_name") {
                    TextField("easytier", text: $profile.networkName)
                        .multilineTextAlignment(.trailing)
                }

                LabeledContent("network_secret") {
                    SecureField(
                        "common_text.empty",
                        text: $profile.networkSecret
                    )
                    .multilineTextAlignment(.trailing)
                }

                Picker(
                    "networking_method",
                    selection: $profile.networkingMethod
                ) {
                    ForEach(NetworkProfile.NetworkingMethod.allCases) {
                        method in
                        Text(method.description).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch profile.networkingMethod {
                case .publicServer:
                    LabeledContent("server") {
                        Text(profile.publicServerURL)
                            .multilineTextAlignment(.trailing)
                    }
                case .manual:
                    ListEditor(newItemTitle: "common_text.add_peer", items: $profile.peerURLs, addItemFactory: { "" }, rowContent: {
                        TextField("example.peer_url", text: $0.text)
                            .font(.body.monospaced())
                    })
                case .standalone:
                    EmptyView()
                }
            }
        }
    }

    var advancedSettings: some View {
        Form {
            Section("general") {
                LabeledContent("hostname") {
                    TextField("common_text.default", text: $profile.hostname)
                        .multilineTextAlignment(.trailing)
                }

//                LabeledContent("Device Name") {
//                    TextField("Default", text: $profile.devName)
//                        .multilineTextAlignment(.trailing)
//                }

                LabeledContent("mtu") {
                    TextField(
                        "common_text.default",
                        value: $profile.mtu,
                        formatter: NumberFormatter()
                    )
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                }
            }
            
            Section {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableOverrideDNS
                )
                if profile.enableOverrideDNS {
                    ListEditor(newItemTitle: "common_text.add_dns", items: $profile.overrideDNS, addItemFactory: { "" }, rowContent: { dns in
                        HStack {
                            Text("address")
                                .foregroundStyle(.secondary)
                            Spacer()
                            IPv4Field(ip: dns.text)
                        }
                    })
                }
            } header: {
                Text("override_dns")
            } footer: {
                Text("override_dns_help")
            }
            
            proxyCIDRsSettings
            
            Section("vpn_portal_config") {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableVPNPortal
                )
                if profile.enableVPNPortal {
                    LabeledContent("vpn_portal_client_network") {
                        IPv4Field(ip: $profile.vpnPortalClientCIDR.ip, length: $profile.vpnPortalClientCIDR.length)
                    }
                    LabeledContent("vpn_portal_listen_port") {
                        TextField(
                            "example.vpn_portal_listen_port",
                            value: $profile.vpnPortalListenPort,
                            formatter: NumberFormatter()
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                    }
                }
            }
            
            Section("listener_urls") {
                ListEditor(newItemTitle: "common_text.add_listener_url", items: $profile.listenerURLs, addItemFactory: { "" }, rowContent: {
                    TextField("example.listener_url", text: $0.text)
                        .font(.body.monospaced())
                })
            }
            
            Section {
                Toggle("common_text.enable", isOn: $profile.enableRelayNetworkWhitelist)
                if profile.enableRelayNetworkWhitelist {
                    ListEditor(newItemTitle: "common_text.add_network", items: $profile.relayNetworkWhitelist, addItemFactory: { "" }, rowContent: {
                        TextField("example.network_name", text: $0.text)
                            .font(.body.monospaced())
                    })
                }
            } header: {
                Text("relay_network_whitelist")
            } footer: {
                Text("relay_network_whitelist_help")
            }
            
            Section {
                Toggle("common_text.enable", isOn: $profile.enableManualRoutes)
                if profile.enableManualRoutes {
                    ListEditor(newItemTitle: "common_text.add_route", items: $profile.routes, addItemFactory: NetworkProfile.CIDR.init, rowContent: { cidr in
                        HStack {
                            Text("cidr")
                                .foregroundStyle(.secondary)
                            Spacer()
                            IPv4Field(ip: cidr.ip, length: cidr.length)
                        }
                    })
                }
            } header: {
                Text("manual_routes")
            } footer: {
                Text("manual_routes_help")
            }
            
            Section("socks5") {
                Toggle(
                    "common_text.enable",
                    isOn: $profile.enableSocks5
                )
                if profile.enableSocks5 {
                    LabeledContent("listen_port") {
                        TextField(
                            "example.socks5_port",
                            value: $profile.socks5Port,
                            formatter: NumberFormatter()
                        )
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                    }
                }
            }
            
            Section {
                ListEditor(newItemTitle: "common_text.add_exit_node", items: $profile.exitNodes, addItemFactory: { "" }, rowContent: { ip in
                    HStack {
                        Text("address")
                            .foregroundStyle(.secondary)
                        Spacer()
                        IPv4Field(ip: ip.text)
                    }
                })
            } header: {
                Text("exit_nodes")
            } footer: {
                Text("exit_nodes_help")
            }
            
            Section {
                ListEditor(newItemTitle: "common_text.add_map_listener", items: $profile.mappedListeners, addItemFactory: { "" }, rowContent: {
                    TextField("example.mapped_listener_url", text: $0.text)
                        .font(.body.monospaced())
                })
            } header: {
                Text("mapped_listeners")
            } footer: {
                Text("mapped_listeners_help")
            }

            Section("flags_switch") {
                ForEach(NetworkProfile.boolFlags) { flag in
                    Toggle(isOn: Binding<Bool>(
                        get: { $profile.wrappedValue[keyPath: flag.keyPath] },
                        set: { $profile.wrappedValue[keyPath: flag.keyPath] = $0 }
                    )) {
                        Text(flag.label)
                        if let help = flag.help {
                            Text(help)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("advanced_settings")
        .scrollDismissesKeyboard(.immediately)
        .sheet(isPresented: $showProxyCIDREditor) {
            proxyCIDREditor
        }
    }

    var portForwardsSettings: some View {
        Form {
            ListEditor(newItemTitle: "common_text.add_port_forward", items: $profile.portForwards, addItemFactory: NetworkProfile.PortForwardSetting.init, rowContent: { $forward in
                VStack(spacing: 8) {
                    HStack {
                        Text("tunnel_proto")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("tunnel_proto", selection: $forward.proto) {
                            Text("tcp").tag("tcp")
                            Text("udp").tag("udp")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    HStack {
                        TextField("port_forwards_bind_addr", text: $forward.bindAddr)
                        Text(":")
                        TextField(
                            "port",
                            value: $forward.bindPort,
                            formatter: NumberFormatter()
                        )
                        .frame(width: 60)
                        .keyboardType(.numberPad)
                    }
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("forward_to")
                    }
                    .foregroundColor(.secondary)
                    .font(.caption)
                    HStack {
                        TextField("port_forwards_dst_addr", text: $forward.destAddr)
                        Text(":")
                        TextField(
                            "port",
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
        .navigationTitle("port_forwards")
        .scrollDismissesKeyboard(.immediately)
    }
    
    var proxyCIDRsSettings: some View {
        Section("common_text.proxy_cidr") {
            ListEditor(newItemTitle: "common_text.add_proxy_cidr", items: $profile.proxyCIDRs, addItemFactory: {
                NetworkProfile.ProxyCIDR(cidr: "0.0.0.0", enableMapping: false, mappedCIDR: "0.0.0.0", length: "0")
            }, rowContent: { proxyCIDR in
                HStack(spacing: 12) {
                    if proxyCIDR.enableMapping.wrappedValue {
                        Text("map")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(proxyCIDR.cidr.wrappedValue)/\(proxyCIDR.length.wrappedValue)")
                            .font(.body.monospaced())
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text("\(proxyCIDR.mappedCIDR.wrappedValue)/\(proxyCIDR.length.wrappedValue)")
                            .font(.body.monospaced())
                    } else {
                        Text("proxy")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(proxyCIDR.cidr.wrappedValue)/\(proxyCIDR.length.wrappedValue)")
                            .font(.body.monospaced())
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
                        Section("common_text.proxy_cidr") {
                            LabeledContent("cidr") {
                                IPv4Field(ip: proxyCIDR.cidr, length: proxyCIDR.length)
                            }
                        }
                        Section("common_text.mapped_cidr") {
                            Toggle("common_text.enable", isOn: proxyCIDR.enableMapping)
                            if proxyCIDR.enableMapping.wrappedValue {
                                LabeledContent("cidr") {
                                    IPv4Field(ip: proxyCIDR.mappedCIDR, length: proxyCIDR.length, disabledLengthEdit: true)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("common_text.edit_proxy_cidr")
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

struct NetworkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        @State var profile = NetworkProfile()
        NavigationStack {
            NetworkEditView(profile: $profile)
        }
        
        NavigationStack {
            NetworkEditView(profile: $profile)
        }
        .previewInterfaceOrientation(.landscapeLeft)
    }
}
