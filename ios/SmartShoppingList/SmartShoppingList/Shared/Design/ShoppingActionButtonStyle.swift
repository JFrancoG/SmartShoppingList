import SwiftUI

/// Solid semantic colors keep explicit actions readable in all four appearances.
struct ShoppingActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            actionLabel(configuration)
                .containerRelativeFrame(.horizontal) { width, _ in
                    width * (dynamicTypeSize.isAccessibilitySize ? 0.75 : 0.6)
                }
            actionLabel(configuration)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(foregroundColor(pressed: configuration.isPressed))
        .background(
            backgroundColor(pressed: configuration.isPressed),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
    }

    private func actionLabel(_ configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleOnly)
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 44)
    }

    private func foregroundColor(pressed: Bool) -> Color {
        if !isEnabled {
            return .textSecondary
        }
        return pressed ? .textPrimary : .onPrimary
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if !isEnabled {
            return .surfaceMuted
        }
        return pressed ? .primarySoft : .appPrimary
    }
}

#Preview("Primary actions", traits: .sharedShopping) {
    VStack(spacing: 16) {
        Button("Add products") {}
        Button("Confirm purchase") {}
            .disabled(true)
    }
    .buttonStyle(ShoppingActionButtonStyle())
    .padding()
    .background(.canvas)
}
