import SwiftUI

struct SharedPurchaseSection: View {
    let viewModel: SharedShoppingViewModel
    @State private var cancellationItem: SharedItem?
    @State private var confirmsCancellation = false
    @State private var editorSourceID: UUID?
    @AccessibilityFocusState(for: .voiceOver) private var focusedProductID: UUID?

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
                .accessibilityFocused($focusedProductID, equals: item.id)
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
        .alert("Cancel pending product?", isPresented: $confirmsCancellation, presenting: cancellationItem) { item in
            Button("No longer needed", role: .destructive) {
                Task {
                    await viewModel.cancelItem(item)
                }
            }
            Button("Keep product", role: .cancel) {}
        } message: { item in
            Text("Remove \(item.name) from the group’s pending list without recording a purchase?")
        }
        .onChange(of: viewModel.isItemEditorPresentationActive) { _, isActive in
            if isActive {
                editorSourceID = viewModel.editingItem?.id
                focusedProductID = nil
            } else {
                guard viewModel.presentedNotice == nil, let editorSourceID,
                      viewModel.items.contains(where: { $0.id == editorSourceID }) else { return }
                focusedProductID = editorSourceID
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
