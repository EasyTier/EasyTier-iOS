import SwiftUI

struct AdaptiveNav<PrimaryView, SecondaryView, Enum>: View where PrimaryView: View, SecondaryView: View, Enum: Identifiable & Hashable {
    @Environment(\.horizontalSizeClass) var sizeClass
    @ViewBuilder var primaryColumn: PrimaryView
    @ViewBuilder var secondaryColumn: SecondaryView
    @Binding var showNav: Enum?
    
    init(_ primary: PrimaryView, _ secondary: SecondaryView, showNav: Binding<Enum?>) {
        primaryColumn = primary
        secondaryColumn = secondary
        _showNav = showNav
    }
    
    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    primaryColumn
                        .frame(maxWidth: columnWidth)
                    secondaryColumn
                }
            } else {
                primaryColumn
            }
        }
        .adaptiveNavigationDestination(item: (sizeClass == .compact ? $showNav : .constant(nil)), destination: { secondaryColumn })
    }
}

extension View {
    func adaptiveNavigationDestination<Enum: Identifiable & Hashable, Destination: View>(
        item: Binding<Enum?>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if #available(iOS 18.0, *) {
            return self.navigationDestination(item: item) { _ in
                destination()
            }
        } else {
            return self.sheet(item: item) { _ in
                NavigationStack {
                    destination()
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }
}
