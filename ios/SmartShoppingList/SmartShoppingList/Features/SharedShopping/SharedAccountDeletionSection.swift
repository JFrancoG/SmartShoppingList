import SwiftUI

enum SharedAccountDeletionDestination: Hashable {
    case details
}

struct SharedAccountDeletionSection: View {
    let viewModel: SharedShoppingViewModel

    private var deletion: SharedAccountDeletionViewModel { viewModel.accountDeletion }

    var body: some View {
        if deletion.isAvailable,
           viewModel.session != nil || deletion.pending != nil || deletion.storageFailed {
            Section("Account deletion") {
                switch deletion.phase {
                case .review, .verifyingIdentity, .authorized:
                    if deletion.pending != nil {
                        Text("You have not confirmed deletion. Cancel preparation to use your account, or continue reviewing it.")
                            .fixedSize(horizontal: false, vertical: true)
                        if let notice = deletion.notice {
                            Text(notice)
                                .foregroundStyle(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Cancel preparation", systemImage: "xmark") {
                            Task {
                                await viewModel.cancelAccountDeletion()
                            }
                        }
                        .foregroundStyle(.appPrimary)
                        .frame(minHeight: ShoppingControlMetrics.minimumTargetSize)
                        .disabled(!deletion.canCancelPreparation)
                    }
                case .submitted, .completed, .storageFailed:
                    Text(deletion.statusMessage)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notice = deletion.notice {
                        Text(notice)
                            .foregroundStyle(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if deletion.isBusy {
                        ProgressView("Updating deletion request…")
                    }
                }
                NavigationLink(value: SharedAccountDeletionDestination.details) {
                    if deletion.pending != nil || deletion.storageFailed {
                        Text("View details")
                    } else {
                        Text("Delete account")
                    }
                }
            }
            .listRowBackground(Color.surface)

            if deletion.needsStatusRefresh {
                Section {
                    SharedAccountDeletionAction(title: "Check status") {
                        Task {
                            await viewModel.checkAccountDeletion()
                        }
                    }
                    .disabled(!viewModel.canRefresh)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }
}

#if DEBUG
#Preview("Prepared deletion in Settings", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedAccountDeletionSection(viewModel: viewModel)
        }
        .modifier(ShoppingFormStyle())
        .navigationDestination(for: SharedAccountDeletionDestination.self) { _ in
            SharedAccountDeletionView(viewModel: viewModel)
        }
    }
    .task { viewModel.accountDeletion.preparePreview() }
}

#Preview("Submitted deletion in Settings", traits: .sharedShopping(.deletionPending)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        Form {
            SharedAccountDeletionSection(viewModel: viewModel)
        }
        .modifier(ShoppingFormStyle())
        .navigationDestination(for: SharedAccountDeletionDestination.self) { _ in
            SharedAccountDeletionView(viewModel: viewModel)
        }
    }
}
#endif
