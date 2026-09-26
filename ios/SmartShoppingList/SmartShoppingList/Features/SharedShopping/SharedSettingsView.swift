import SwiftUI

struct SharedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SharedShoppingViewModel
    var canPresentNotice = true

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)
                SharedPendingInvitationSection(viewModel: viewModel)

                if let group = viewModel.group {
                    Section("Group") {
                        Text(group.name)
                            .font(.headline)
                            .foregroundStyle(.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if viewModel.isCreator {
                            Button("Manage invitations", systemImage: "person.badge.plus") {
                                Task {
                                    await viewModel.openInvitations()
                                }
                            }
                            .buttonStyle(ShoppingActionButtonStyle())
                            .disabled(!viewModel.canMutate)
                        }
                    }
                    .listRowBackground(Color.surface)
                } else if viewModel.session != nil {
                    Section {
                        LabeledContent {
                            TextField("Group name", text: $viewModel.groupName)
                                .labelsHidden()
                                .textInputAutocapitalization(.sentences)
                                .disabled(!viewModel.canMutate)
                        } label: {
                            Text("Group name")
                        }
                        Button("Create group", systemImage: "person.2") {
                            Task {
                                await viewModel.createGroup()
                            }
                        }
                        .buttonStyle(ShoppingActionButtonStyle())
                        .disabled(!viewModel.canMutate)
                    } header: {
                        Text("Create a group")
                    } footer: {
                        Text("You can also open an invitation to join another group. Each account belongs to one group only.")
                    }
                    .listRowBackground(Color.surface)
                }

                SharedAccountSection(viewModel: viewModel)
            }
            .modifier(ShoppingFormStyle())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(viewModel.isBusy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!viewModel.hasLoaded || viewModel.isBusy || !viewModel.isConfigured)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(isPresented: $viewModel.isInvitationsPresented, onDismiss: {
                viewModel.invitationsPresentationDidDismiss()
            }) {
                SharedInvitationsView(viewModel: viewModel)
            }
            .onChange(of: viewModel.session?.user.id) { _, _ in
                viewModel.isInvitationsPresented = false
            }
            .onChange(of: viewModel.group?.id) { _, _ in
                viewModel.isInvitationsPresented = false
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedNotice,
            isEnabled: canPresentNotice && viewModel.canPresentRootNotice,
            dismiss: viewModel.dismissPresentedNotice
        ))
    }
}

#Preview("Settings", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedSettingsView(viewModel: viewModel)
}

#Preview("Settings - sign in", traits: .sharedShopping(.signedOut)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedSettingsView(viewModel: viewModel)
}

#Preview("Settings - invitation and accessibility text", traits: .sharedShopping(.invitation)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedSettingsView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
