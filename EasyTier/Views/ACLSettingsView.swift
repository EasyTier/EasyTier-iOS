import SwiftUI

struct ACLSettingsView: View {
    @Binding var acl: ACLConfig?
    @State private var showDisableConfirmation = false

    private var aclBinding: Binding<ACLConfig> {
        Binding(
            get: { acl ?? .init() },
            set: { acl = $0 }
        )
    }

    private var groupNames: [String] {
        acl?.aclV1.group.declares
            .map(\.groupName)
            .filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        Form {
            Section {
                Toggle("acl.enabled", isOn: Binding(
                    get: { acl != nil },
                    set: { enabled in
                        if enabled {
                            withAnimation { acl = acl ?? .init() }
                        } else if acl?.isEmpty ?? true {
                            withAnimation { acl = nil }
                        } else {
                            showDisableConfirmation = true
                        }
                    }
                ))
            } footer: {
                Text("acl.help")
            }

            if acl != nil {
                Section {
                    ListEditor(
                        newItemTitle: "acl.add_chain",
                        items: aclBinding.aclV1.chains,
                        addItemFactory: { ACLChain() },
                        showsAddButton: false,
                        rowContent: { chain in
                            NavigationLink {
                                ACLChainEditorView(chain: chain, groupNames: groupNames)
                            } label: {
                                ACLChainRow(chain: chain.wrappedValue)
                            }
                        })

                    addChainMenu
                } header: {
                    Text("acl.chains")
                } footer: {
                    Text("acl.chain_order_help")
                }

                Section {
                    NavigationLink {
                        ACLGroupEditorView(acl: aclBinding)
                    } label: {
                        LabeledContent {
                            Text("\(groupNames.count)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("acl.groups", systemImage: "person.3")
                        }
                    }
                } footer: {
                    Text("acl.groups_help")
                }
            }
        }
        .navigationTitle("acl.title")
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .confirmationDialog(
            "acl.disable_confirmation",
            isPresented: $showDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button("acl.disable", role: .destructive) {
                withAnimation { acl = nil }
            }
        } message: {
            Text("acl.disable_confirmation_message")
        }
        .listEditingToolbar(
            isVisible: acl != nil && !(acl?.aclV1.chains.isEmpty ?? true)
        )
    }

    @ViewBuilder
    private var addChainMenu: some View {
#if os(iOS)
        addChainMenuContent
#else
        addChainMenuContent
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.accentColor)
#endif
    }

    private var addChainMenuContent: some View {
        Menu {
            ForEach(ACLChainType.configurableCases) { type in
                Button {
                    addChain(type)
                } label: {
                    Label(type.localizedKey, systemImage: type.systemImage)
                }
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("acl.add_chain")
            }
        }
    }

    private func addChain(_ type: ACLChainType) {
        withAnimation {
            var config = acl ?? .init()
            config.aclV1.chains.append(
                ACLChain(name: type.defaultName, chainType: type)
            )
            acl = config
        }
    }

}

private struct ACLChainRow: View {
    let chain: ACLChain

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: chain.chainType.systemImage)
                .foregroundStyle(chain.enabled ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(chain.name.isEmpty ? chain.chainType.defaultName : chain.name)
                    .foregroundStyle(chain.enabled ? .primary : .secondary)
                HStack(spacing: 5) {
                    Text(chain.chainType.localizedKey)
                    Text("•")
                    Text("\(chain.rules.count)")
                    Text("acl.rules")
                    Text("•")
                    Text(chain.defaultAction.localizedKey)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !chain.enabled {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ACLChainEditorView: View {
    @Binding var chain: ACLChain
    let groupNames: [String]

    var body: some View {
        Form {
            Section {
                Toggle("acl.chain_enabled", isOn: $chain.enabled)
                LabeledContent("acl.chain_name") {
                    TextField("acl.chain_name", text: $chain.name)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("acl.chain_type") {
                    Picker("acl.chain_type", selection: $chain.chainType) {
                        ForEach(ACLChainType.configurableCases) { type in
                            Text(type.localizedKey).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("acl.default_action") {
                    Picker("acl.default_action", selection: $chain.defaultAction) {
                        ForEach(ACLAction.configurableCases) { action in
                            Text(action.localizedKey).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }

            Section("acl.chain_description") {
                TextField("acl.chain_description_placeholder", text: $chain.description, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                ForEach($chain.rules) { $rule in
                    NavigationLink {
                        ACLRuleEditorView(rule: $rule, groupNames: groupNames)
                    } label: {
                        ACLRuleRow(rule: rule)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            removeRule(id: rule.id)
                        } label: {
                            Label("delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: removeRules)
                .onMove(perform: moveRules)

                Button {
                    addRule()
                } label: {
                    Label("acl.add_rule", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("acl.rules")
            } footer: {
                Text("acl.rule_order_help")
            }
        }
        .navigationTitle(chain.name.isEmpty ? "ACL Chain" : chain.name)
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .listEditingToolbar(isVisible: !chain.rules.isEmpty)
    }

    private func addRule() {
        chain.rules.append(ACLRule())
        normalizePriorities()
    }

    private func removeRules(at offsets: IndexSet) {
        chain.rules.remove(atOffsets: offsets)
    }

    private func removeRule(id: UUID) {
        chain.rules.removeAll { $0.id == id }
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        chain.rules.move(fromOffsets: source, toOffset: destination)
        normalizePriorities()
    }

    private func normalizePriorities() {
        for index in chain.rules.indices {
            chain.rules[index].priority = UInt32(chain.rules.count - index - 1)
        }
    }
}

private struct ACLRuleRow: View {
    let rule: ACLRule

    private var criteria: String {
        var parts: [String] = []
        if !rule.sourceIPs.isEmpty { parts.append("src \(rule.sourceIPs.joined(separator: ", "))") }
        if !rule.destinationIPs.isEmpty { parts.append("dst \(rule.destinationIPs.joined(separator: ", "))") }
        if !rule.sourcePorts.isEmpty { parts.append("sport \(rule.sourcePorts.joined(separator: ", "))") }
        if !rule.ports.isEmpty { parts.append("dport \(rule.ports.joined(separator: ", "))") }
        if !rule.sourceGroups.isEmpty { parts.append("src @\(rule.sourceGroups.joined(separator: ", @"))") }
        if !rule.destinationGroups.isEmpty { parts.append("dst @\(rule.destinationGroups.joined(separator: ", @"))") }
        return parts.isEmpty ? "*" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.action == .drop ? "hand.raised.fill" : "checkmark.shield.fill")
                .foregroundStyle(rule.enabled ? rule.action.tint : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name.isEmpty ? String(localized: "acl.unnamed_rule") : rule.name)
                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                HStack(spacing: 5) {
                    Text(rule.protocolType.localizedKey)
                    Text("•")
                    Text(rule.action.localizedKey)
                    Text("• P\(rule.priority)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(criteria)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ACLRuleEditorView: View {
    @Binding var rule: ACLRule
    let groupNames: [String]

    private var showsPorts: Bool {
        rule.protocolType == .any || rule.protocolType == .tcp || rule.protocolType == .udp
    }

    var body: some View {
        Form {
            Section {
                Toggle("acl.rule_enabled", isOn: $rule.enabled)
                LabeledContent("acl.rule_name") {
                    TextField("acl.rule_name", text: $rule.name)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("acl.protocol") {
                    Picker("acl.protocol", selection: $rule.protocolType) {
                        ForEach(ACLProtocol.configurableCases) { protocolType in
                            Text(protocolType.localizedKey).tag(protocolType)
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("acl.action") {
                    Picker("acl.action", selection: $rule.action) {
                        ForEach(ACLAction.configurableCases) { action in
                            Text(action.localizedKey).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                LabeledContent("acl.priority") {
                    Text("\(rule.priority)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Section("acl.rule_description") {
                TextField("acl.rule_description_placeholder", text: $rule.description, axis: .vertical)
                    .lineLimit(2...4)
            }

            ACLStringListEditor(
                title: "acl.source_ips",
                addTitle: "acl.add_source_ip",
                placeholder: "10.126.126.0/24",
                values: $rule.sourceIPs
            )
            ACLStringListEditor(
                title: "acl.destination_ips",
                addTitle: "acl.add_destination_ip",
                placeholder: "10.126.126.2/32",
                values: $rule.destinationIPs
            )

            if showsPorts {
                ACLStringListEditor(
                    title: "acl.source_ports",
                    addTitle: "acl.add_source_port",
                    placeholder: "80 or 1000-2000",
                    values: $rule.sourcePorts
                )
                ACLStringListEditor(
                    title: "acl.destination_ports",
                    addTitle: "acl.add_destination_port",
                    placeholder: "443 or 1000-2000",
                    values: $rule.ports
                )
            }

            ACLGroupSelectionSection(
                title: "acl.source_groups",
                groupNames: groupNames,
                selection: $rule.sourceGroups
            )
            ACLGroupSelectionSection(
                title: "acl.destination_groups",
                groupNames: groupNames,
                selection: $rule.destinationGroups
            )

            Section {
                Toggle("acl.stateful", isOn: $rule.stateful)
                LabeledContent("acl.rate_limit") {
                    TextField("0", text: uint32Binding($rule.rateLimit), prompt: Text("0"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .numberKeyboardType()
                        .frame(maxWidth: 140)
                }
                LabeledContent("acl.burst_limit") {
                    TextField("0", text: uint32Binding($rule.burstLimit), prompt: Text("0"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .numberKeyboardType()
                        .frame(maxWidth: 140)
                }
            } header: {
                Text("advanced_settings")
            } footer: {
                if rule.rateLimit > 0 && rule.burstLimit == 0 {
                    Label("acl.burst_required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    Text("acl.rate_limit_help")
                }
            }
        }
        .navigationTitle(rule.name.isEmpty ? String(localized: "acl.edit_rule") : rule.name)
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .onChange(of: rule.rateLimit) { newValue in
            if newValue > 0 && rule.burstLimit == 0 {
                rule.burstLimit = max(1, newValue)
            }
        }
    }
}

private struct ACLStringListEditor: View {
    let title: LocalizedStringKey
    let addTitle: LocalizedStringKey
    let placeholder: String
    @Binding var values: [String]

    var body: some View {
        Section {
            ForEach(Array(values.indices), id: \.self) { index in
                HStack {
                    TextField("", text: valueBinding(at: index), prompt: Text(verbatim: placeholder))
                        .labelsHidden()
                        .font(.body.monospaced())
                        .adaptiveNoTextInputAutocapitalization()
                        .autocorrectionDisabled()
                    Button(role: .destructive) {
                        guard values.indices.contains(index) else { return }
                        values.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                values.append("")
            } label: {
                Label(addTitle, systemImage: "plus.circle.fill")
            }
        } header: {
            Text(title)
        }
    }

    private func valueBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { values.indices.contains(index) ? values[index] : "" },
            set: { newValue in
                guard values.indices.contains(index) else { return }
                values[index] = newValue
            }
        )
    }
}

private struct ACLGroupSelectionSection: View {
    let title: LocalizedStringKey
    let groupNames: [String]
    @Binding var selection: [String]

    private var options: [String] {
        Array(Set(groupNames + selection)).sorted()
    }

    var body: some View {
        Section {
            if options.isEmpty {
                Text("acl.no_groups")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(options, id: \.self) { groupName in
                    Toggle(groupName, isOn: selectionBinding(groupName))
                }
            }
        } header: {
            Text(title)
        }
    }

    private func selectionBinding(_ groupName: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(groupName) },
            set: { selected in
                if selected {
                    if !selection.contains(groupName) { selection.append(groupName) }
                } else {
                    selection.removeAll { $0 == groupName }
                }
            }
        )
    }
}

private struct ACLGroupEditContext: Identifiable {
    let id = UUID()
    let index: Int?
    let originalName: String
    let identity: ACLGroupIdentity
}

private struct ACLGroupEditorView: View {
    @Binding var acl: ACLConfig
    @State private var editingGroup: ACLGroupEditContext?

    var body: some View {
        Form {
            Section {
                ListEditor(
                    newItemTitle: "acl.add_group",
                    items: $acl.aclV1.group.declares,
                    addItemFactory: { ACLGroupIdentity() },
                    addItemAction: beginAddingGroup,
                    deleteItemsAction: removeGroups,
                    rowContent: { group in
                        let identity = group.wrappedValue
                        Button {
                            beginEditingGroup(identity)
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.key.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                Text(identity.groupName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    })
            } header: {
                Text("acl.group_declarations")
            } footer: {
                Text("acl.group_declarations_help")
            }

            Section {
                if acl.aclV1.group.declares.isEmpty {
                    Text("acl.no_groups")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(acl.aclV1.group.declares) { identity in
                        Toggle(identity.groupName, isOn: membershipBinding(identity.groupName))
                    }
                }
            } header: {
                Text("acl.local_memberships")
            } footer: {
                Text("acl.local_memberships_help")
            }
        }
        .navigationTitle("acl.groups")
        .scrollDismissesKeyboard(.immediately)
        .formStyle(.grouped)
        .listEditingToolbar(isVisible: !acl.aclV1.group.declares.isEmpty)
        .sheet(item: $editingGroup) { context in
            NavigationStack {
                ACLGroupIdentityEditorView(
                    identity: context.identity,
                    existingNames: existingNames(excluding: context.index)
                ) { savedIdentity in
                    saveGroup(savedIdentity, context: context)
                }
            }
        }
    }

    private func beginAddingGroup() {
        editingGroup = ACLGroupEditContext(
            index: nil,
            originalName: "",
            identity: .init()
        )
    }

    private func beginEditingGroup(_ identity: ACLGroupIdentity) {
        guard let index = acl.aclV1.group.declares.firstIndex(where: { $0.id == identity.id }) else {
            return
        }
        editingGroup = ACLGroupEditContext(
            index: index,
            originalName: identity.groupName,
            identity: identity
        )
    }

    private func existingNames(excluding index: Int?) -> Set<String> {
        Set(acl.aclV1.group.declares.enumerated().compactMap { itemIndex, item in
            itemIndex == index ? nil : item.groupName
        })
    }

    private func membershipBinding(_ groupName: String) -> Binding<Bool> {
        Binding(
            get: { acl.aclV1.group.members.contains(groupName) },
            set: { member in
                if member {
                    if !acl.aclV1.group.members.contains(groupName) {
                        acl.aclV1.group.members.append(groupName)
                    }
                } else {
                    acl.aclV1.group.members.removeAll { $0 == groupName }
                }
            }
        )
    }

    private func saveGroup(_ identity: ACLGroupIdentity, context: ACLGroupEditContext) {
        withAnimation {
            if let index = context.index, acl.aclV1.group.declares.indices.contains(index) {
                acl.aclV1.group.declares[index] = identity
                if context.originalName != identity.groupName {
                    renameGroup(from: context.originalName, to: identity.groupName)
                }
            } else {
                acl.aclV1.group.declares.append(identity)
            }
        }
    }

    private func renameGroup(from oldName: String, to newName: String) {
        acl.aclV1.group.members = acl.aclV1.group.members.map { $0 == oldName ? newName : $0 }
        for chainIndex in acl.aclV1.chains.indices {
            for ruleIndex in acl.aclV1.chains[chainIndex].rules.indices {
                acl.aclV1.chains[chainIndex].rules[ruleIndex].sourceGroups =
                    acl.aclV1.chains[chainIndex].rules[ruleIndex].sourceGroups.map { $0 == oldName ? newName : $0 }
                acl.aclV1.chains[chainIndex].rules[ruleIndex].destinationGroups =
                    acl.aclV1.chains[chainIndex].rules[ruleIndex].destinationGroups.map { $0 == oldName ? newName : $0 }
            }
        }
    }

    private func removeGroups(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            removeGroupWithoutAnimation(at: index)
        }
    }

    private func removeGroupWithoutAnimation(at index: Int) {
        guard acl.aclV1.group.declares.indices.contains(index) else { return }
        let name = acl.aclV1.group.declares[index].groupName
        acl.aclV1.group.declares.remove(at: index)
        acl.aclV1.group.members.removeAll { $0 == name }
        for chainIndex in acl.aclV1.chains.indices {
            for ruleIndex in acl.aclV1.chains[chainIndex].rules.indices {
                acl.aclV1.chains[chainIndex].rules[ruleIndex].sourceGroups.removeAll { $0 == name }
                acl.aclV1.chains[chainIndex].rules[ruleIndex].destinationGroups.removeAll { $0 == name }
            }
        }
    }
}

private struct ACLGroupIdentityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var identity: ACLGroupIdentity
    let existingNames: Set<String>
    let onSave: (ACLGroupIdentity) -> Void

    init(
        identity: ACLGroupIdentity,
        existingNames: Set<String>,
        onSave: @escaping (ACLGroupIdentity) -> Void
    ) {
        _identity = State(initialValue: identity)
        self.existingNames = existingNames
        self.onSave = onSave
    }

    private var normalizedName: String {
        identity.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !normalizedName.isEmpty && !existingNames.contains(normalizedName)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("acl.group_name") {
                    TextField("acl.group_name", text: $identity.groupName)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .adaptiveNoTextInputAutocapitalization()
                        .autocorrectionDisabled()
                }
                LabeledContent("acl.group_secret") {
                    SecureField(
                        "common_text.empty",
                        text: $identity.groupSecret,
                        prompt: Text("common_text.empty")
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                }
            } footer: {
                if existingNames.contains(normalizedName) {
                    Text("acl.duplicate_group")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("acl.edit_group")
        .adaptiveNavigationBarTitleInline()
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    identity.groupName = normalizedName
                    onSave(identity)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
    }
}

private func uint32Binding(_ value: Binding<UInt32>) -> Binding<String> {
    Binding(
        get: { String(value.wrappedValue) },
        set: { value.wrappedValue = UInt32($0) ?? 0 }
    )
}

private extension ACLChainType {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .unspecified: "acl.unspecified"
        case .inbound: "acl.inbound"
        case .outbound: "acl.outbound"
        case .forward: "acl.forward"
        }
    }

    var defaultName: String {
        switch self {
        case .unspecified: "Unspecified"
        case .inbound: "Inbound"
        case .outbound: "Outbound"
        case .forward: "Forward"
        }
    }

    var systemImage: String {
        switch self {
        case .unspecified: "questionmark.shield"
        case .inbound: "arrow.down.left"
        case .outbound: "arrow.up.right"
        case .forward: "arrow.left.arrow.right"
        }
    }
}

private extension ACLAction {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .noop: "acl.noop"
        case .allow: "acl.allow"
        case .drop: "acl.drop"
        }
    }

    var tint: Color {
        switch self {
        case .noop: .secondary
        case .allow: .green
        case .drop: .red
        }
    }
}

private extension ACLProtocol {
    var localizedKey: LocalizedStringKey {
        switch self {
        case .unspecified: "acl.unspecified"
        case .tcp: "TCP"
        case .udp: "UDP"
        case .icmp: "ICMP"
        case .icmpV6: "ICMPv6"
        case .any: "acl.any"
        }
    }
}

#if DEBUG
@available(iOS 17.0, macOS 14.0, *)
#Preview("ACL Settings") {
    @Previewable @State var acl: ACLConfig? = ACLConfig(
        aclV1: ACLV1(chains: [
            ACLChain(
                name: "Inbound",
                chainType: .inbound,
                rules: [
                    ACLRule(
                        name: "Allow SSH from admin",
                        priority: 100,
                        protocolType: .tcp,
                        ports: ["22"],
                        sourceGroups: ["admin"]
                    )
                ],
                defaultAction: .drop
            )
        ], group: ACLGroupInfo(
            declares: [ACLGroupIdentity(groupName: "admin", groupSecret: "secret")],
            members: ["admin"]
        ))
    )
    NavigationStack {
        ACLSettingsView(acl: $acl)
    }
}
#endif
