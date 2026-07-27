import SwiftUI

struct ListEditor<Element, RowContent>: View where Element: Identifiable, RowContent: View {
    var newItemTitle: LocalizedStringKey
    
    @Binding var items: [Element]
    
    var addItemFactory: () -> Element
    var addItemAction: (() -> Void)?
    var deleteItemsAction: ((IndexSet) -> Void)?
    var showsAddButton: Bool
    var rowActionTitle: LocalizedStringKey?
    var rowActionSystemImage: String
    var rowActionTint: Color
    var rowAction: ((Binding<Element>) -> Void)?
    
    @ViewBuilder var rowContent: (Binding<Element>) -> RowContent

    init(
        newItemTitle: LocalizedStringKey,
        items: Binding<[Element]>,
        addItemFactory: @escaping () -> Element,
        addItemAction: (() -> Void)? = nil,
        deleteItemsAction: ((IndexSet) -> Void)? = nil,
        showsAddButton: Bool = true,
        rowActionTitle: LocalizedStringKey? = nil,
        rowActionSystemImage: String = "ellipsis.circle",
        rowActionTint: Color = .accentColor,
        rowAction: ((Binding<Element>) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (Binding<Element>) -> RowContent
    ) {
        self.newItemTitle = newItemTitle
        _items = items
        self.addItemFactory = addItemFactory
        self.addItemAction = addItemAction
        self.deleteItemsAction = deleteItemsAction
        self.showsAddButton = showsAddButton
        self.rowActionTitle = rowActionTitle
        self.rowActionSystemImage = rowActionSystemImage
        self.rowActionTint = rowActionTint
        self.rowAction = rowAction
        self.rowContent = rowContent
    }

    var body: some View {
#if os(iOS)
        Group {
            ForEach($items) { $item in
                if let rowActionTitle, let rowAction {
                    rowContent($item)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                rowAction($item)
                            } label: {
                                Label(rowActionTitle, systemImage: rowActionSystemImage)
                            }
                            .tint(rowActionTint)
                        }
                } else {
                    rowContent($item)
                }
            }
            .onDelete(perform: deleteItem)
            .onMove(perform: moveItem)
            
            if showsAddButton {
                Button(action: addItem) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(newItemTitle)
                    }
                }
            }
        }
#else
        if !items.isEmpty {
            List($items, editActions: [.all]) { $item in
                rowContent($item)
                    .frame(minHeight: 26)
                    .contextMenu {
                        if let rowActionTitle, let rowAction {
                            Button {
                                rowAction($item)
                            } label: {
                                Label(rowActionTitle, systemImage: rowActionSystemImage)
                            }
                        }
                        Button(role: .destructive) {
                            if let index = items.firstIndex(where: { $item.wrappedValue.id == $0.id }) {
                                deleteItem(at: .init(integer: index))
                            }
                        } label: {
                            Label("delete", systemImage: "trash")
                                .tint(.red)
                        }
                    }
            }
        }
        if showsAddButton {
            Button(action: addItem) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(newItemTitle)
                }
            }
            .buttonStyle(.borderless)
            .tint(.accentColor)
        }
#endif
    }
    
    private func addItem() {
        if let addItemAction {
            addItemAction()
            return
        }
        withAnimation {
            let newItem = addItemFactory()
            items.append(newItem)
        }
    }
    
    private func deleteItem(at offsets: IndexSet) {
        withAnimation {
            if let deleteItemsAction {
                deleteItemsAction(offsets)
            } else {
                items.remove(atOffsets: offsets)
            }
        }
    }
    
    private func moveItem(from source: IndexSet, to destination: Int) {
        withAnimation {
            items.move(fromOffsets: source, toOffset: destination)
        }
    }
}

extension View {
    func listEditingToolbar(
        isVisible: Bool,
        placement: ToolbarItemPlacement = .primaryAction
    ) -> some View {
#if os(iOS)
        self.toolbar {
            ToolbarItem(placement: placement) {
                if isVisible {
                    EditButton()
                }
            }
        }
#else
        self
#endif
    }
}
