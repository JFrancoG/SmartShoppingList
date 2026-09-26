import SwiftUI

struct SharedInvitationsView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)
                Section {
                    Button("Create invitation", systemImage: "link") {
                        Task {
                            await viewModel.createInvitation()
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(!viewModel.canMutate || !viewModel.isCreator)
                    if let url = viewModel.shareURL {
                        ShareLink(item: url) {
                            Label("Share invitation", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ShoppingActionButtonStyle())
                    }
                } header: {
                    Text("New link")
                } footer: {
                    Text("Each link lets one person join within 24 hours. Share it now: the link cannot be retrieved after reopening the app.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                Section("Created invitations") {
                    if viewModel.invitations.isEmpty {
                        Text("No invitations loaded.")
                            .foregroundStyle(.textSecondary)
                    }
                    ForEach(viewModel.invitations) { invitation in
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Created on \(invitation.createdAt, format: .dateTime.day().month().year().hour().minute().second())")
                                Text("Expires on \(invitation.expiresAt, format: .dateTime.day().month().year().hour().minute())")
                                    .foregroundStyle(.textSecondary)
                                if invitation.acceptedAt != nil {
                                    Label("Accepted", systemImage: "person.crop.circle.badge.checkmark")
                                        .foregroundStyle(.success)
                                } else if invitation.revokedAt != nil {
                                    Label("Revoked", systemImage: "xmark.circle")
                                        .foregroundStyle(.textSecondary)
                                } else {
                                    Text("Not accepted")
                                }
                            }
                            .accessibilityElement(children: .combine)
                            if invitation.acceptedAt == nil && invitation.revokedAt == nil {
                                Button("Revoke link", role: .destructive) {
                                    Task {
                                        await viewModel.revokeInvitation(invitation)
                                    }
                                }
                                .buttonStyle(ShoppingActionButtonStyle())
                                .disabled(!viewModel.canMutate || !viewModel.isCreator)
                                .accessibilityHint("Prevents anyone from using this invitation to join the group.")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(Color.surface)
            }
            .modifier(ShoppingFormStyle())
            .navigationTitle("Invitations")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(viewModel.isBusy)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedNotice,
            isEnabled: viewModel.isInvitationsPresented,
            dismiss: viewModel.dismissPresentedNotice
        ))
    }
}

#Preview("Group invitations", traits: .sharedShopping(.invitations)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedInvitationsView(viewModel: viewModel)
}

#Preview("Invitations - accessibility text", traits: .sharedShopping(.invitations)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedInvitationsView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
