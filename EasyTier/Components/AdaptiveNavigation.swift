import SwiftUI

struct AdaptiveNavigation<PrimaryView, SecondaryView, Enum>: View where PrimaryView: View, SecondaryView: View, Enum: Identifiable & Hashable {
#if os(macOS)
    let sizeClass = UserInterfaceSizeClass.compact
#else
    @Environment(\.horizontalSizeClass) var sizeClass
#endif
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
                        .columnGutter(.trailing)
                        .frame(maxWidth: columnMaxWidth)
                    secondaryColumn
                        .columnGutter(.leading)
                }
            } else {
                primaryColumn
            }
        }
        .adaptiveNavigationDestination(item: (sizeClass == .compact ? $showNav : .constant(nil)), destination: { secondaryColumn })
    }
}

extension View {
    func columnGutter(_ edge: HorizontalEdge, minimum: CGFloat = 10) -> some View {
        modifier(ColumnGutter(edge: edge, minimum: minimum))
    }

    func adaptiveNavigationDestination<Enum: Identifiable & Hashable, Destination: View>(
        item: Binding<Enum?>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            return self.navigationDestination(item: item) { _ in
                destination()
            }
        } else {
            return self.navigationDestination(
                isPresented: Binding(
                    get: { item.wrappedValue != nil },
                    set: { isPresented in
                        if !isPresented {
                            item.wrappedValue = nil
                        }
                    }
                )
            ) {
                destination()
            }
        }
    }
}

private struct ColumnGutter: ViewModifier {
    let edge: HorizontalEdge
    let minimum: CGFloat
    @State private var extra: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: edge, spacing: 0) {
                Color.clear.frame(width: extra)
            }
            .background {
                if #available(iOS 27.1, macOS 27.1, *) {
                    GeometryReader { proxy in
                        let margins = proxy.contentMargins(for: .container, edges: edge == .leading ? .leading : .trailing)
                        let systemMargin = edge == .leading ? margins.leading : margins.trailing
                        Color.clear.onChange(of: systemMargin, initial: true) { _, newValue in
                            extra = max(0, minimum - newValue)
                        }
                    }
                }
            }
    }
}
