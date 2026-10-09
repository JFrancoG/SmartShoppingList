import SwiftUI

struct SharedGroupManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeparture = false
    @State private var confirmsClosure = false
    @Bindable var viewModel: SharedShoppingViewModel
    var refreshesOnAppear = true

    var body: some View {
        Form {
            SharedOperationSection(viewModel: viewModel)
            if viewModel.groupManagementState == .loading {
                ProgressView("Loading group management…")
            } else if viewModel.groupManagementState != .loaded {
                Section {
                    Text("Refresh to load the current members and administration.")
                        .foregroundStyle(.textSecondary)
                }
                .listRowBackground(Color.surface)
            }
            if viewModel.groupManagementState == .loaded, let administration = viewModel.administration {
                Section("Members") {
                    ForEach(viewModel.groupMembers) { member in
                        SharedGroupMemberLabel(
                            member: member,
                            isCurrentUser: member.id == viewModel.session?.user.id,
                            isAdministrator: member.id == administration.group.administratorUserId,
                            showsIdentifier: viewModel.memberNeedsIdentifier(member)
                        )
                    }
                }
                .listRowBackground(Color.surface)
                if let transfer = administration.pendingTransfer {
                    SharedGroupTransferSection(viewModel: viewModel, transfer: transfer)
                } else if administration.capabilities.canProposeTransfer {
                    Section {
                        Picker("New administrator", selection: $viewModel.selectedSuccessorID) {
                            Text("Choose a member").tag(Optional<UUID>.none)
                            ForEach(viewModel.groupSuccessorCandidates) { member in
                                SharedGroupMemberLabel(
                                    member: member,
                                    isCurrentUser: false,
                                    isAdministrator: false,
                                    showsIdentifier: viewModel.memberNeedsIdentifier(member)
                                )
                                .tag(Optional(member.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .disabled(!viewModel.canMutate)
                        Button("Propose transfer", systemImage: "arrow.left.arrow.right") {
                            Task {
                                await viewModel.proposeGroupTransfer()
                            }
                        }
                        .buttonStyle(ShoppingActionButtonStyle())
                        .disabled(!viewModel.canProposeGroupTransfer)
                    } header: {
                        Text("Transfer administration")
                    } footer: {
                        Text("The chosen member must accept within 7 days. You remain administrator until acceptance and then stay as a member.")
                    }
                    .listRowBackground(Color.surface)
                }
                Section {
                    if administration.capabilities.canLeave {
                        if administration.capabilities.requiresClosureConfirmation {
                            Button("Close group and leave", role: .destructive) {
                                confirmsClosure = true
                            }
                                .buttonStyle(ShoppingActionButtonStyle())
                                .disabled(!viewModel.canMutate)
                        } else {
                            Button("Leave group", role: .destructive) {
                                confirmsDeparture = true
                            }
                                .buttonStyle(ShoppingActionButtonStyle())
                                .disabled(!viewModel.canMutate)
                        }
                    } else {
                        Text("Transfer administration to another member before leaving the group.")
                            .foregroundStyle(.textSecondary)
                    }
                } header: {
                    Text("Group membership")
                } footer: {
                    Text("Leaving keeps your local draft. Group purchases and history are preserved on the server.")
                }
                .listRowBackground(Color.surface)
            }
        }
        .modifier(ShoppingFormStyle())
        .navigationTitle("Group management")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh members and administration", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.loadGroupManagement()
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(viewModel.isBusy)
            }
        }
        .task {
            guard refreshesOnAppear else { return }
            await viewModel.load()
            await viewModel.loadGroupManagement()
        }
        .refreshable {
            await viewModel.loadGroupManagement()
        }
        .onChange(of: viewModel.group?.id) { _, _ in
            dismiss()
        }
        .alert("Leave group?", isPresented: $confirmsDeparture) {
            Button("Leave group", role: .destructive) {
                Task {
                    await viewModel.leaveGroup(confirmClosure: false)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will lose access to this group. You will need a new invitation to join again. Your draft is kept.")
        }
        .alert("Close group and leave?", isPresented: $confirmsClosure) {
            Button("Close group and leave", role: .destructive) {
                Task {
                    await viewModel.leaveGroup(confirmClosure: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You are the last member. The group will close and its invitations will stop working. Its history is preserved, but reopening is not available.")
        }
    }
}

#Preview("Management · ES · Large", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .large)
}

#Preview("Management · ES · XXXL", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Management · ES · AX5", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Management · EN · Large", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .large)
}

#Preview("Management · EN · XXXL", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Management · EN · AX5", traits: .sharedShopping(.groupManagementOwner)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Receive transfer · ES · AX5", traits: .sharedShopping(.groupTransferRecipient)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Receive transfer · EN · AX5", traits: .sharedShopping(.groupTransferRecipient)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedGroupManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
