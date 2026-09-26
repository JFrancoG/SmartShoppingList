import SwiftUI

/// Keeps native scrolling and controls while applying the shared content palette.
struct ShoppingFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
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
