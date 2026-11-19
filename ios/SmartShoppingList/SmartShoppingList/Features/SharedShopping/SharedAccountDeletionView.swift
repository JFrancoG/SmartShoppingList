import AuthenticationServices
import StoreKit
import SwiftUI

struct SharedAccountDeletionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.usesPreparedShoppingPreview) private var usesPreparedPreview
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight = ShoppingControlMetrics.minimumTargetSize
    @State private var confirmsDeletion = false
    @State private var showsSubscriptions = false
    let viewModel: SharedShoppingViewModel

    private var deletion: SharedAccountDeletionViewModel { viewModel.accountDeletion }

    var body: some View {
        Form {
            Section {
                Text(deletion.statusMessage)
                    .fixedSize(horizontal: false, vertical: true)
                if deletion.isBusy {
                    ProgressView("Updating deletion request…")
                }
            }
            .listRowBackground(Color.surface)

            switch deletion.phase {
            case .review, .verifyingIdentity, .authorized:
                if let preview = deletion.preview {
                    Section("What will be deleted") {
                        Text("Your profile, sessions and local draft on this device will be deleted. You will leave every group.")
                        Text("Your contributions will be removed from shared lists and history. Data from other members will remain.")
                        if preview.legacyContentCount > 0 {
                            Text("Some older shared content has no reliable author. Its text will also be removed, including text written by other members.")
                        }
                        ForEach(preview.groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.name).font(.headline)
                                if group.willDelete {
                                    Text("This group has no other members and will be deleted.")
                                } else if group.administers {
                                    Text("The group will remain without an administrator. Another member can assume administration.")
                                } else {
                                    Text("Other members will keep this group.")
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.surface)
                }
                Section("Subscription") {
                    Text("Deleting your Smart List account does not cancel your Apple subscription. Manage it with Apple to stop renewals.")
                    Button("Manage subscription", systemImage: "creditcard") {
                        showsSubscriptions = true
                    }
                    .foregroundStyle(.appPrimary)
                    .frame(minHeight: ShoppingControlMetrics.minimumTargetSize)
                    Text("A new account will not recover deleted data. You can restore an eligible active Premium subscription using the same Apple purchase account.")
                }
                .listRowBackground(Color.surface)

                Section("Verify your identity") {
                    if let notice = deletion.notice {
                        Text(notice)
                            .foregroundStyle(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(deletion.identityMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(Color.surface)

                Section {
                    if deletion.hasAuthorization {
                        SharedAccountDeletionAction(title: "Delete account", isDestructive: true) {
                            confirmsDeletion = true
                        }
                        .disabled(!deletion.canAuthorize)
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            deletion.configureAppleRequest(request)
                        } onCompletion: { result in
                            deletion.receiveAppleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: 375)
                        .frame(height: appleButtonHeight)
                        .frame(maxWidth: .infinity)
                        .disabled(!deletion.canAuthorize)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    Button("Refresh summary", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.prepareAccountDeletion(forceRefresh: true)
                        }
                    }
                    .foregroundStyle(.appPrimary)
                    .frame(minHeight: ShoppingControlMetrics.minimumTargetSize)
                    .disabled(!deletion.canRefreshPreparation || viewModel.session == nil)
                    if deletion.pending != nil {
                        Button("Cancel preparation", systemImage: "xmark") {
                            Task {
                                await viewModel.cancelAccountDeletion()
                                if !deletion.blocksAccountUse {
                                    dismiss()
                                }
                            }
                        }
                        .foregroundStyle(.appPrimary)
                        .frame(minHeight: ShoppingControlMetrics.minimumTargetSize)
                        .disabled(!deletion.canCancelPreparation)
                    }
                }
                .listRowBackground(Color.surface)

            case .submitted, .completed, .storageFailed:
                if let notice = deletion.notice {
                    Section {
                        Text(notice)
                            .foregroundStyle(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .listRowBackground(Color.surface)
                }
                if deletion.pending?.lastStatus?.appleRevocationOutcome == .manualActionRequired {
                    Section {
                        Text("Your account data has been deleted. Apple access could not be revoked automatically. Remove Smart List from Sign in with Apple in your Apple account settings.")
                    }
                    .listRowBackground(Color.surface)
                }
                if deletion.needsStatusRefresh {
                    Section {
                        SharedAccountDeletionAction(title: "Check status") {
                            Task {
                                await viewModel.checkAccountDeletion()
                            }
                        }
                        .disabled(!deletion.canRefreshStatus)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if deletion.canCancelRequest {
                    Section {
                        Button("Cancel pending request", systemImage: "xmark") {
                            Task {
                                await viewModel.cancelAccountDeletion()
                                if !deletion.blocksAccountUse {
                                    dismiss()
                                }
                            }
                        }
                        .foregroundStyle(.appPrimary)
                        .frame(minHeight: ShoppingControlMetrics.minimumTargetSize)
                    } footer: {
                        Text("This only cancels a request that has not been accepted. An accepted deletion will continue.")
                    }
                    .listRowBackground(Color.surface)
                }
                if deletion.canDismissResult {
                    Section {
                        SharedAccountDeletionAction(title: "Done") {
                            Task {
                                if await deletion.dismissResult() {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .modifier(ShoppingFormStyle())
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showsSubscriptions)
        .task {
            guard !usesPreparedPreview else { return }
            await viewModel.prepareAccountDeletion()
        }
        .alert("Delete your account permanently?", isPresented: $confirmsDeletion) {
            Button("Delete account", role: .destructive) {
                Task {
                    await viewModel.confirmAccountDeletion()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your account and its data will be deleted. Your Apple subscription will continue until you cancel it with Apple.")
        }
    }
}

#if DEBUG
#Preview("Deletion · ES AX5", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedAccountDeletionView(viewModel: viewModel)
    }
    .task { viewModel.accountDeletion.preparePreview() }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Deleted · EN", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedAccountDeletionView(viewModel: viewModel)
    }
    .task { viewModel.accountDeletion.preparePreview(completed: true) }
    .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Deletion authorized · ES", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedAccountDeletionView(viewModel: viewModel)
    }
    .task { viewModel.accountDeletion.preparePreview(authorized: true) }
    .environment(\.locale, Locale(identifier: "es"))
}
#endif
