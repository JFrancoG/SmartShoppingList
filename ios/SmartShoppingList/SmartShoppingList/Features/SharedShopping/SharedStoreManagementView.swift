import SwiftUI

struct SharedStoreManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SharedShoppingViewModel
    var refreshesOnAppear = true

    var body: some View {
        Form {
            SharedOperationSection(viewModel: viewModel)
            if viewModel.storeManagementState == .loading {
                ProgressView("Loading stores and capacity…")
            }
            if let message = viewModel.storeManagementMessage {
                Section {
                    Text(message)
                        .foregroundStyle(.textSecondary)
                }
                .listRowBackground(Color.surface)
            }
            if let capacity = viewModel.groupCapacity,
               let maximum = capacity.limits.storesPerGroup.maximum,
               let pendingMaximum = capacity.limits.pendingItemsPerStore.maximum {
                Section {
                    LabeledContent("Group", value: viewModel.group?.name ?? "")
                    LabeledContent("Active stores") {
                        Text("\(capacity.activeStoreCount) of \(maximum)")
                    }
                    LabeledContent("Pending product limit per store", value: pendingMaximum.formatted())
                } header: {
                    Text("Current capacity")
                } footer: {
                    Text("Capacity is shared by the group and follows its current administrator’s plan. Existing stores and products are kept if usage exceeds a limit.")
                }
                .listRowBackground(Color.surface)
            }
            Section("Active stores") {
                ForEach(viewModel.stores) { store in
                    SharedStoreManagementRow(viewModel: viewModel, store: store, action: .archive)
                }
                if viewModel.stores.isEmpty, viewModel.storeManagementState == .loaded {
                    Text("There are no active stores.")
                        .foregroundStyle(.textSecondary)
                }
            }
            .listRowBackground(Color.surface)
            Section {
                ForEach(viewModel.archivedStores) { store in
                    SharedStoreManagementRow(viewModel: viewModel, store: store, action: .restore)
                }
                if viewModel.archivedStores.isEmpty, viewModel.storeManagementState == .loaded {
                    Text("There are no archived stores.")
                        .foregroundStyle(.textSecondary)
                }
            } header: {
                Text("Archived stores")
            } footer: {
                Text("An archived store keeps its identity and history. Restore it before adding products to it again.")
            }
            .listRowBackground(Color.surface)
        }
        .modifier(ShoppingFormStyle())
        .navigationTitle("Stores and capacity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh stores and capacity", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.loadStoreManagement()
                    }
                }
                .labelStyle(.iconOnly)
                .disabled(viewModel.isBusy)
            }
        }
        .task {
            guard refreshesOnAppear else { return }
            await viewModel.load()
            await viewModel.loadStoreManagement()
        }
        .refreshable {
            await viewModel.loadStoreManagement()
        }
        .onChange(of: viewModel.group?.id) { _, _ in
            dismiss()
        }
    }
}

#Preview("Stores · ES · Large", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedStoreManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .large)
}

#Preview("Stores · ES · XXXL", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedStoreManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Stores · ES · AX5", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedStoreManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Stores · EN · Large", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedStoreManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .large)
}

#Preview("Stores · EN · XXXL", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedStoreManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Stores · EN · AX5", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedStoreManagementView(viewModel: viewModel, refreshesOnAppear: false)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
