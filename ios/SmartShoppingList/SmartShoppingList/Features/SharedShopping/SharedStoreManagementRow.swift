import SwiftUI

struct SharedStoreManagementRow: View {
    @State private var confirmsChange = false
    @ScaledMetric(relativeTo: .body) private var spacing = 8
    @Bindable var viewModel: SharedShoppingViewModel
    let store: SharedStore
    let action: SharedStoreAction

    private var actionTitle: LocalizedStringKey { action == .archive ? "Archive store" : "Restore store" }
    private var confirmationTitle: LocalizedStringKey { action == .archive ? "Archive store?" : "Restore store?" }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            VStack(alignment: .leading, spacing: spacing) {
                Text(store.name)
                    .font(.headline)
                if let count = store.pendingItemCount,
                   let maximum = viewModel.groupCapacity?.limits.pendingItemsPerStore.maximum {
                    Text("Pending products: \(count) of \(maximum)")
                        .foregroundStyle(.textSecondary)
                }
                if let archivedAt = store.archivedAt {
                    Text("Archived on \(archivedAt, format: .dateTime.day().month(.abbreviated).year())")
                        .foregroundStyle(.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Button(actionTitle) {
                confirmsChange = true
            }
            .buttonStyle(ShoppingActionButtonStyle())
            .accessibilityLabel(
                action == .archive ? Text("Archive store: \(store.name)") : Text("Restore store: \(store.name)")
            )
            .disabled(!viewModel.canChangeStoreState(store, action: action))
            if let message = viewModel.storeActionMessage(store, action: action) {
                Text(message)
                    .foregroundStyle(.textSecondary)
            }
        }
        .alert(confirmationTitle, isPresented: $confirmsChange) {
            Button(actionTitle) {
                Task {
                    await viewModel.changeStoreState(store, action: action)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if action == .archive {
                Text("Archive \(store.name)? It will stop appearing in shopping lists and will keep its history.")
            } else {
                Text("Restore \(store.name)? It will use one active store place in this group.")
            }
        }
    }
}

#Preview("Store row · ES · AX5", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        ForEach(viewModel.stores) { store in
            SharedStoreManagementRow(viewModel: viewModel, store: store, action: .archive)
        }
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Archived row · EN · Large", traits: .sharedShopping(.storeManagement)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        ForEach(viewModel.archivedStores) { store in
            SharedStoreManagementRow(viewModel: viewModel, store: store, action: .restore)
        }
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .large)
}
