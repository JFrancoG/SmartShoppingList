import AuthenticationServices
import SwiftUI

struct SharedAccountSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight = 44.0
    let viewModel: SharedShoppingViewModel

    var body: some View {
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
                Button("Prepare Sign in with Apple") {
                    Task {
                        await viewModel.prepareAppleLogin()
                    }
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(!viewModel.hasLoaded || viewModel.isBusy)

                if viewModel.challenge != nil {
                    SignInWithAppleButton(.signIn) { request in
                        viewModel.configureAppleRequest(request)
                    } onCompletion: { result in
                        viewModel.receiveAppleAuthorization(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: 375)
                    .frame(height: appleButtonHeight)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isBusy)
                }
            } header: {
                Text("Sign in with Apple")
            } footer: {
                Text("Your draft and pending invitation are kept while you sign in.")
            }
            .listRowBackground(Color.surface)
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
