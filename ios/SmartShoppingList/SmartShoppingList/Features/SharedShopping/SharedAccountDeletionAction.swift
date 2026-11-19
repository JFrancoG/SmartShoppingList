import SwiftUI

/// A full-width action for the account-deletion flow, outside its information cards.
struct SharedAccountDeletionAction: View {
    let title: LocalizedStringKey
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil) {
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(AccountDeletionActionStyle(isDestructive: isDestructive))
    }
}

private struct AccountDeletionActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isDestructive: Bool

    // The corner radius and target floor are container geometry, independent of text size.
    private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    func makeBody(configuration: Configuration) -> some View {
        ShoppingActionLayout(widthFraction: 1) {
            configuration.label
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: ShoppingControlMetrics.minimumTargetSize)
        }
        .foregroundStyle(foregroundColor(pressed: configuration.isPressed))
        .background(backgroundColor(pressed: configuration.isPressed), in: shape)
        .overlay {
            if isEnabled && isDestructive && configuration.isPressed {
                shape.strokeBorder(.danger, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
    }

    private func foregroundColor(pressed: Bool) -> Color {
        if !isEnabled {
            return .textSecondary
        }
        if isDestructive {
            return .danger
        }
        return pressed ? .textPrimary : .onPrimary
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if !isEnabled {
            return .surfaceMuted
        }
        if isDestructive {
            return .dangerSoft
        }
        return pressed ? .primarySoft : .appPrimary
    }
}

#Preview("Deletion actions", traits: .sharedShopping) {
    VStack(spacing: 16) {
        SharedAccountDeletionAction(title: "Check status") {}
        SharedAccountDeletionAction(title: "Delete account", isDestructive: true) {}
        SharedAccountDeletionAction(title: "Done") {}
            .disabled(true)
    }
    .padding()
    .background(.canvas)
}
