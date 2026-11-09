import AuthenticationServices
import SwiftUI

struct SharedAccountSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight = ShoppingControlMetrics.minimumTargetSize
    @State private var confirmsDraftRemoval = false
    let viewModel: SharedShoppingViewModel

    var body: some View {
        if viewModel.requiresDeletedAccountCleanup {
            Section("Account deletion") {
                Text("Account deletion is confirmed. Local cleanup still needs to finish.")
                Button("Retry local cleanup") {
                    Task {
                        await viewModel.retryDeletedAccountCleanup()
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
        if viewModel.accountDeletion.isAvailable,
           viewModel.session != nil || viewModel.accountDeletion.blocksAccountUse {
            Section("Account deletion") {
                NavigationLink("Delete account") {
                    SharedAccountDeletionView(viewModel: viewModel)
                }
            }
            .listRowBackground(Color.surface)
        }
        if viewModel.session == nil, !viewModel.draft.items.isEmpty || !viewModel.draft.text.isEmpty {
            Section("Local draft") {
                Text("This draft is stored on this device. Review it before adding its products to another account.")
                Button("Delete this device’s draft", role: .destructive) {
                    confirmsDraftRemoval = true
                }
                    .disabled(viewModel.isBusy)
                    .alert("Permanently delete this device’s draft?", isPresented: $confirmsDraftRemoval) {
                        Button("Delete draft", role: .destructive) {
                            Task {
                                await viewModel.discardSignedOutDraft()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The local products and text will be removed. Shared lists will not change.")
                    }
            }
            .listRowBackground(Color.surface)
        }
        if !viewModel.isConfigured {
            Section("Group access") {
                Text("The group connection is not configured yet. You can prepare products in Add.")
                    .foregroundStyle(.textSecondary)
            }
            .listRowBackground(Color.surface)
        } else if let session = viewModel.session {
            Section("Account") {
                if let name = session.user.displayName, !name.isEmpty {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.textPrimary)
                }
                Label("Signed in with Apple", systemImage: "apple.logo")
                    .foregroundStyle(.textSecondary)
                Button("Sign out") {
                    Task {
                        await viewModel.logout()
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(viewModel.isBusy)
            }
            .listRowBackground(Color.surface)
        } else {
            Section {
                Text("Sign in with Apple to create a group or accept an invitation.")
                    .foregroundStyle(.textPrimary)
                SignInWithAppleButton(.signIn) { request in
                    viewModel.configureAppleRequest(request)
                } onCompletion: { result in
                    viewModel.receiveAppleAuthorization(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: 375)
                .frame(height: appleButtonHeight)
                .frame(maxWidth: .infinity)
                .disabled(scenePhase != .active || !viewModel.canRequestAppleLogin)

                if let error = viewModel.appleLoginPreparationError {
                    Text(error)
                        .foregroundStyle(.textSecondary)
                    Button("Retry") {
                        viewModel.retryAppleLoginPreparation()
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(viewModel.isBusy)
                } else if !viewModel.hasLoaded || viewModel.isPreparingAppleLogin {
                    ProgressView("Connecting…")
                        .foregroundStyle(.textSecondary)
                }
            } header: {
                Text("Sign in with Apple")
            } footer: {
                Text("Your draft and pending invitation are kept while you sign in.")
            }
            .listRowBackground(Color.surface)
            .task(id: scenePhase == .active && viewModel.shouldMaintainAppleLogin) {
                guard scenePhase == .active, viewModel.shouldMaintainAppleLogin else { return }
                await viewModel.maintainAppleLogin()
            }
        }
    }
}

#Preview("Account", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedAccountSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}

#Preview("Sign in", traits: .sharedShopping(.signedOut)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedAccountSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}

#Preview("Sign-in unavailable", traits: .sharedShopping(.signInUnavailable)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedAccountSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}
