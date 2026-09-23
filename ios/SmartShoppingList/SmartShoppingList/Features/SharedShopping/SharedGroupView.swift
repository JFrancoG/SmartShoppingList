import AuthenticationServices
import SwiftUI

struct SharedGroupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var appleButtonHeight = 44.0
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)

                if !viewModel.isConfigured {
                    Section("Group access") {
                        Text("The group connection is not configured yet. You can prepare products in Add.")
                    }
                } else if viewModel.session == nil {
                    Section {
                        Text("Sign in with Apple to create a group or accept an invitation.")
                        Button("Prepare Sign in with Apple") {
                            Task {
                                await viewModel.prepareAppleLogin()
                            }
                        }
                        .disabled(!viewModel.hasLoaded || viewModel.isBusy)

                        if viewModel.challenge != nil {
                            SignInWithAppleButton(.signIn) { request in
                                viewModel.configureAppleRequest(request)
                            } onCompletion: { result in
                                viewModel.receiveAppleAuthorization(result)
                            }
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: appleButtonHeight)
                            .disabled(viewModel.isBusy)
                        }
                    } header: {
                        Text("Sign in with Apple")
                    } footer: {
                        Text("Your draft and pending invitation are kept while you sign in.")
                    }
                }

                if viewModel.pendingInvitation != nil {
                    Section("Pending invitation") {
                        if let invitation = viewModel.invitationPreview {
                            VStack(alignment: .leading) {
                                Text(invitation.group.name)
                                    .font(.headline)
                                Text("Expires on \(invitation.expiresAt, format: .dateTime.day().month().year().hour().minute())")
                                    .foregroundStyle(.secondary)
                                if invitation.alreadyAccepted {
                                    Text("You have already accepted this invitation.")
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                            Button("Accept invitation", systemImage: "person.badge.plus") {
                                Task {
                                    await viewModel.acceptInvitation()
                                }
                            }
                            .disabled(!viewModel.canMutate)
                        } else {
                            Text("Sign in and refresh to check the group before accepting.")
                        }
                        Button("Discard invitation", role: .destructive) {
                            Task {
                                await viewModel.discardInvitation()
                            }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }

                if let session = viewModel.session {
                    if let group = viewModel.group {
                        Section("Your group") {
                            Text(group.name)
                                .font(.headline)
                            if viewModel.isCreator {
                                Button("Manage invitations", systemImage: "person.badge.plus") {
                                    Task {
                                        await viewModel.openInvitations()
                                    }
                                }
                                .disabled(!viewModel.canMutate)
                            }
                        }
                        Section("Supermarket") {
                            Picker("Store", selection: $viewModel.selectedStoreID) {
                                Text("Select a store").tag(Optional<UUID>.none)
                                ForEach(viewModel.stores) { store in
                                    Text(store.name).tag(Optional(store.id))
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .disabled(viewModel.isBusy || !viewModel.sessionIsVerified)
                            if viewModel.stores.isEmpty {
                                Text("No stores loaded. You can confirm a store when adding products.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if viewModel.selectedStoreID != nil {
                            SharedPurchaseSection(viewModel: viewModel)
                        }
                    } else {
                        Section {
                            TextField("Group name", text: $viewModel.groupName)
                                .textInputAutocapitalization(.sentences)
                                .disabled(!viewModel.canMutate)
                            Button("Create group", systemImage: "person.2") {
                                Task {
                                    await viewModel.createGroup()
                                }
                            }
                            .disabled(!viewModel.canMutate)
                        } header: {
                            Text("Create a group")
                        } footer: {
                            Text("You can also open an invitation to join another group. Each account belongs to one group only.")
                        }
                    }
                    Section("Session") {
                        if let name = session.user.displayName {
                            Text(name)
                        }
                        Button("Sign out") {
                            Task {
                                await viewModel.logout()
                            }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }
            }
            .navigationTitle("Group")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .disabled(!viewModel.hasLoaded || viewModel.isBusy || !viewModel.isConfigured)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task(id: viewModel.selectedStoreID) {
                await viewModel.loadSelectedStore()
            }
            .sheet(isPresented: $viewModel.isInvitationsPresented) {
                SharedInvitationsView(viewModel: viewModel)
            }
        }
    }
}

#Preview("Grupo y productos", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}

#Preview("Acceso pendiente", traits: .sharedShopping(.signedOut)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}

#Preview("Invitación y texto grande", traits: .sharedShopping(.invitation)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
