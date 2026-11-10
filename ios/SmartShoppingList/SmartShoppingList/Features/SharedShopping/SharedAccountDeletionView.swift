import AuthenticationServices
import StoreKit
import SwiftUI

struct SharedAccountDeletionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight = ShoppingControlMetrics.minimumTargetSize
    @State private var confirmsDeletion = false
    @State private var showsSubscriptions = false
    let viewModel: SharedShoppingViewModel

    private var deletion: SharedAccountDeletionViewModel { viewModel.accountDeletion }

    var body: some View {
        Form {
            Section {
                Text(deletion.statusMessage)
                if deletion.isBusy {
                    ProgressView("Updating deletion request…")
                }
                if let notice = deletion.notice {
                    Text(notice).foregroundStyle(.textSecondary)
                }
            }
            .listRowBackground(Color.surface)

            if deletion.acceptedUserID == nil {
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
                Section {
                    Text("Deleting your Smart List account does not cancel your Apple subscription. Manage it with Apple to stop renewals.")
                    Button("Manage subscription") {
                        showsSubscriptions = true
                    }
                    Text("A new account will not recover deleted data. You can restore an eligible active Premium subscription using the same Apple purchase account.")
                }
                .listRowBackground(Color.surface)

                Section {
                    if deletion.canAuthorize && !deletion.hasAuthorization {
                        SignInWithAppleButton(.continue) { request in
                            deletion.configureAppleRequest(request)
                        } onCompletion: { result in
                            deletion.receiveAppleAuthorization(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: 375)
                        .frame(height: appleButtonHeight)
                        .frame(maxWidth: .infinity)
                    }
                    if deletion.hasAuthorization {
                        Button("Delete my account and data", role: .destructive) {
                            confirmsDeletion = true
                        }
                            .disabled(!deletion.canAuthorize)
                    }
                    Button("Refresh deletion details") {
                        Task {
                            await viewModel.prepareAccountDeletion()
                        }
                    }
                    .disabled(deletion.isBusy || deletion.storageFailed || viewModel.session == nil)
                    if deletion.pending != nil {
                        Button("Cancel deletion request") {
                            Task {
                                await viewModel.cancelAccountDeletion()
                                if !deletion.blocksAccountUse {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(deletion.isBusy)
                    }
                }
                .listRowBackground(Color.surface)
            }

            if deletion.pending != nil {
                Section {
                    Button("Check deletion status") {
                        Task {
                            await viewModel.checkAccountDeletion()
                        }
                    }
                    .disabled(deletion.isBusy)
                    if deletion.pending?.lastStatus?.appleRevocationOutcome == .manualActionRequired {
                        Text("Your account data has been deleted. Apple access could not be revoked automatically. Remove Smart List from Sign in with Apple in your Apple account settings.")
                    }
                    if deletion.canDismissResult {
                        Button("Done") {
                            Task {
                                await deletion.dismissResult()
                                if !deletion.blocksAccountUse {
                                    dismiss()
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.surface)
            }
        }
        .modifier(ShoppingFormStyle())
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showsSubscriptions)
        .task {
            await viewModel.prepareAccountDeletion()
        }
        .onChange(of: deletion.accessibilityMessage) { _, message in
            AccessibilityNotification.Announcement(message).post()
        }
        .alert("Delete your account permanently?", isPresented: $confirmsDeletion) {
            Button("Delete my account and data", role: .destructive) {
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
#endif
