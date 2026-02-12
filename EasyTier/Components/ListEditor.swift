import SwiftUI

struct ListEditor<Element, RowContent>: View where Element: Identifiable, RowContent: View {
    var newItemTitle: LocalizedStringKey
    
    @Binding var items: [Element]
    
    var addItemFactory: () -> Element
    
    @ViewBuilder var rowContent: (Binding<Element>) -> RowContent

    var body: some View {
#if os(iOS)
        Group {
            ForEach($items) { $item in
                rowContent($item)
            }
            .onDelete(perform: deleteItem)
            .onMove(perform: moveItem)
            
            Button(action: addItem) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(newItemTitle)
                }
            }
        }
#else
        if !items.isEmpty {
            List($items, editActions: [.all]) { $item in
                rowContent($item)
                    .frame(minHeight: 26)
                    .contextMenu {
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
        Button(action: addItem) {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(newItemTitle)
            }
        }
        .buttonStyle(.borderless)
        .tint(.accentColor)
#endif
    }
    
    private func addItem() {
        withAnimation {
            let newItem = addItemFactory()
            items.append(newItem)
        }
    }
    
    private func deleteItem(at offsets: IndexSet) {
        withAnimation {
            items.remove(atOffsets: offsets)
        }
    }
    
    private func moveItem(from source: IndexSet, to destination: Int) {
        withAnimation {
            items.move(fromOffsets: source, toOffset: destination)
        }
    }
}
