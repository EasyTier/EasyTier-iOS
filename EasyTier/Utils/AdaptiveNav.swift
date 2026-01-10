import SwiftUI

struct AdaptiveNav<PrimaryView, SecondaryView, Enum>: View where PrimaryView: View, SecondaryView: View, Enum: Hashable {
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
        .navigationDestination(item: (sizeClass == .compact ? $showNav : .constant(nil))) { _ in
            secondaryColumn
        }
    }
}
