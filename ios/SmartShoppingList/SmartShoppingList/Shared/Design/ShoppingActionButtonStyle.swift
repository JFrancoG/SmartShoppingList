import SwiftUI

/// Solid semantic colors keep explicit actions readable in all four appearances.
struct ShoppingActionButtonStyle: ButtonStyle {
    var widthFraction: CGFloat? = nil
    // This touch-target floor stays independent of Dynamic Type; the label can grow above it.
    var minimumHeight: CGFloat = ShoppingControlMetrics.minimumTargetSize
    var isProminent = true
    var usesCapsule = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        ShoppingActionLayout(widthFraction: widthFraction ?? (dynamicTypeSize.isAccessibilitySize ? 0.75 : 0.6)) {
            actionLabel(configuration)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(foregroundColor(pressed: configuration.isPressed))
        // A full capsule at the minimum height; keep corners bounded when multiline labels grow.
        .background(backgroundColor(pressed: configuration.isPressed), in: shape)
        .overlay {
            if isEnabled && !isProminent {
                shape.strokeBorder(.border, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: usesCapsule ? minimumHeight / 2 : 22,
            style: usesCapsule ? .circular : .continuous
        )
    }

    private func actionLabel(_ configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleOnly)
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(minWidth: ShoppingControlMetrics.minimumTargetSize, minHeight: minimumHeight)
    }

    private func foregroundColor(pressed: Bool) -> Color {
        if !isEnabled {
            return .textSecondary
        }
        if !isProminent {
            return .appPrimary
        }
        return pressed ? .textPrimary : .onPrimary
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if !isEnabled {
            return .surfaceMuted
        }
        if !isProminent {
            return pressed ? .surfaceMuted : .surface
        }
        return pressed ? .primarySoft : .appPrimary
    }
}

#Preview("Primary actions", traits: .sharedShopping) {
    VStack(spacing: 16) {
        Button("Add products") {}
        Button("Restore purchases") {}
            .buttonStyle(ShoppingActionButtonStyle(isProminent: false))
        Button("Confirm purchase") {}
            .disabled(true)
        Button("Restore purchases") {}
            .buttonStyle(ShoppingActionButtonStyle(isProminent: false))
            .disabled(true)
    }
    .buttonStyle(ShoppingActionButtonStyle())
    .padding()
    .background(.canvas)
}
