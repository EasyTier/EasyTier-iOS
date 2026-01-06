import SwiftUI

struct ListEditor<Element, RowContent>: View where Element: Identifiable, RowContent: View {
    var newItemTitle: String? = nil
    
    @Binding var items: [Element]
    
    var addItemFactory: () -> Element
    
    @ViewBuilder var rowContent: (Binding<Element>) -> RowContent

    var body: some View {
        Group {
            ForEach($items) { $item in
                rowContent($item)
            }
            .onDelete(perform: deleteItem)
            .onMove(perform: moveItem)
            
            Button(action: addItem) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(newItemTitle ?? "Add a new item")
                }
            }
        }
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
