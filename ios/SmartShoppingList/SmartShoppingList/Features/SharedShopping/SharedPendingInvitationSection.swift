import SwiftUI

struct SharedPendingInvitationSection: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        if viewModel.pendingInvitation != nil {
            Section("Pending invitation") {
                if let invitation = viewModel.invitationPreview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(invitation.group.name)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                        Text("Expires on \(invitation.expiresAt, format: .dateTime.day().month().year().hour().minute())")
                            .foregroundStyle(.textSecondary)
                        if invitation.alreadyAccepted {
                            Text("You have already accepted this invitation.")
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)

                    Button("Accept invitation", systemImage: "person.badge.plus") {
                        Task {
                            await viewModel.acceptInvitation()
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(!viewModel.canMutate)
                } else {
                    Text("Sign in and refresh to check the group before accepting.")
                        .foregroundStyle(.textSecondary)
                }
                Button("Discard invitation", role: .destructive) {
                    Task {
                        await viewModel.discardInvitation()
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(viewModel.isBusy)
            }
            .listRowBackground(Color.surface)
        }
    }
}

#Preview("Pending invitation", traits: .sharedShopping(.invitation)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPendingInvitationSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}

#Preview("Pending invitation - accessibility text", traits: .sharedShopping(.invitation)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPendingInvitationSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.dynamicTypeSize, .accessibility5)
}
