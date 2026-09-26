import SwiftUI

/// Keeps native scrolling and controls while applying the shared content palette.
struct ShoppingFormStyle: ViewModifier {
    @State private var controlRegions = ShoppingControlRegions()
    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.shoppingControlRegions, controlRegions)
            .environment(\.shoppingControlScrollOffset, scrollOffset)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                scrollOffset = offset
            }
            .onGeometryChange(for: ShoppingControlRegions.self) { geometry in
                ShoppingControlRegions.read(from: geometry)
            } action: { regions in
                controlRegions = regions
            }
            .scrollContentBackground(.hidden)
            .background(.canvas)
            .foregroundStyle(.textPrimary)
    }
}

#Preview("Shopping surfaces", traits: .sharedShopping) {
    Form {
        Section("Products") {
            Text("Bread")
        }
        .listRowBackground(Color.surface)
    }
    .modifier(ShoppingFormStyle())
}
