import SwiftUI

/// Gives content actions a consistent outline; toolbars use the system's native buttons.
struct ShoppingIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 17
    private var sideLength: CGFloat {
        max(44, symbolSize + 24)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: symbolSize))
            .frame(width: sideLength, height: sideLength)
            .foregroundStyle(foregroundColor(role: configuration.role))
            .background(configuration.isPressed ? Color.surfaceMuted : .surface, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }

    private func foregroundColor(role: ButtonRole?) -> Color {
        guard isEnabled else { return .textSecondary }
        return role == .destructive ? .danger : .appPrimary
    }
}

#Preview("Product actions", traits: .sharedShopping) {
    HStack(spacing: 8) {
        Button("Dictate", systemImage: "mic") {}
        Button("Edit product", systemImage: "pencil") {}
        Button("No longer needed", systemImage: "trash", role: .destructive) {}
    }
    .labelStyle(.iconOnly)
    .buttonStyle(ShoppingIconButtonStyle())
    .padding()
    .background(.surface)
}
