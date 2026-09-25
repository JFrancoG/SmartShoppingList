import SwiftUI

struct SharedPurchaseSection: View {
    let viewModel: SharedShoppingViewModel
    @State private var cancellationItem: SharedItem?
    @State private var confirmsCancellation = false

    var body: some View {
        Section {
            if viewModel.storeItemsState == .loading {
                ProgressView("Loading pending products…")
            } else if let message = viewModel.storeItemsMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.items) { item in
                Button {
                    viewModel.togglePurchaseItem(item)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: viewModel.isPurchaseSelected(item) ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .font(.headline)
                            if let quantity = item.quantity {
                                Text(quantity)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canTogglePurchaseItem(item))
                .accessibilityValue(viewModel.isPurchaseSelected(item) ? Text("Selected") : Text("Not selected"))
                .accessibilityHint("Changes the local selection. The purchase is saved when you tap Finish shopping.")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Edit product", systemImage: "pencil") {
                        viewModel.beginEditingItem(item)
                    }
                    .disabled(!viewModel.canChangeItem(item))
                    Button("No longer needed", systemImage: "trash", role: .destructive) {
                        cancellationItem = item
                        confirmsCancellation = true
                    }
                    .disabled(!viewModel.canChangeItem(item))
                }
                .contextMenu {
                    Button("Edit product", systemImage: "pencil") {
                        viewModel.beginEditingItem(item)
                    }
                    .disabled(!viewModel.canChangeItem(item))
                    Button("No longer needed", systemImage: "trash", role: .destructive) {
                        cancellationItem = item
                        confirmsCancellation = true
                    }
                    .disabled(!viewModel.canChangeItem(item))
                }
            }
        } header: {
            Text("Pending · \(viewModel.selectedStoreName)")
        } footer: {
            Text("Select the products you are buying. The others will remain pending.")
        }

        Section {
            if viewModel.editingItem != nil {
                Button("Review product edit") {
                    viewModel.isItemEditorPresented = true
                }
            }
            Text("Selected: \(viewModel.purchaseSelection.count) of up to 50")
            if viewModel.purchaseSelectionNeedsReview {
                Label("Some selected products have changed or are no longer pending.", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Deselect changed products") {
                    viewModel.discardChangedPurchaseSelections()
                }
                .disabled(!viewModel.canMutate)
            }
            Button {
                Task {
                    await viewModel.finalizePurchase()
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "cart.badge.checkmark")
                        .accessibilityHidden(true)
                    Text(viewModel.purchaseActionTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .disabled(!viewModel.canFinalizePurchase)
            .accessibilityHint("Confirms only the selected products from this store for the whole group.")
        } header: {
            Text("Confirm purchase")
        } footer: {
            Text("Switching stores or leaving this screen does not confirm the purchase. Refresh to check for group changes.")
        }
        .confirmationDialog("Cancel pending product?", isPresented: $confirmsCancellation, titleVisibility: .visible) {
            if let item = cancellationItem {
                Button("No longer needed", role: .destructive) {
                    Task {
                        await viewModel.cancelItem(item)
                    }
                }
                Button("Keep product", role: .cancel) {
                    cancellationItem = nil
                }
            }
        } message: {
            if let item = cancellationItem {
                Text("Remove \(item.name) from the group’s pending list without recording a purchase?")
            }
        }
    }
}

#Preview("Selección de compra", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPurchaseSection(viewModel: viewModel)
    }
}
