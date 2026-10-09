import SwiftUI

struct SharedGroupTransferSection: View {
    let viewModel: SharedShoppingViewModel
    let transfer: SharedGroupTransfer

    var body: some View {
        Section {
            if let member = viewModel.groupMember(id: transfer.recipientUserId) {
                LabeledContent("Proposed administrator") {
                    SharedGroupMemberLabel(
                        member: member,
                        isCurrentUser: member.id == viewModel.session?.user.id,
                        isAdministrator: false,
                        showsIdentifier: viewModel.memberNeedsIdentifier(member)
                    )
                }
            } else {
                Text("Proposed member ID: \(transfer.recipientUserId.uuidString.lowercased())")
            }
            Text("Expires on \(transfer.expiresAt, format: .dateTime.day().month().year().hour().minute())")
                .foregroundStyle(.textSecondary)
            if viewModel.administration?.capabilities.canAcceptTransfer == true {
                Button("Accept administration", systemImage: "checkmark") {
                    Task {
                        await viewModel.resolveGroupTransfer(.accept)
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(!viewModel.canMutate)
                Button("Decline transfer", role: .destructive) {
                    Task {
                        await viewModel.resolveGroupTransfer(.reject)
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(!viewModel.canMutate || viewModel.administration?.capabilities.canRejectTransfer != true)
            }
            if viewModel.administration?.capabilities.canWithdrawTransfer == true {
                Button("Withdraw proposal", role: .destructive) {
                    Task {
                        await viewModel.resolveGroupTransfer(.withdraw)
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(!viewModel.canMutate)
            }
        } header: {
            Text("Pending transfer")
        } footer: {
            Text("Accepting makes you responsible for invitations and group administration. The previous administrator stays as a member.")
            Text("Group capacity follows the new administrator’s plan. Existing data is kept; if a limit is exceeded, only additions that increase usage are blocked.")
        }
        .listRowBackground(Color.surface)
    }
}

#Preview("Transfer · ES", traits: .sharedShopping(.groupTransferRecipient)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        if let transfer = viewModel.administration?.pendingTransfer {
            SharedGroupTransferSection(viewModel: viewModel, transfer: transfer)
        }
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Transfer · EN", traits: .sharedShopping(.groupTransferRecipient)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        if let transfer = viewModel.administration?.pendingTransfer {
            SharedGroupTransferSection(viewModel: viewModel, transfer: transfer)
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .large)
}
