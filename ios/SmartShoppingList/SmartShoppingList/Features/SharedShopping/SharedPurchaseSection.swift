import SwiftUI

struct SharedPurchaseSection: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
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
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(viewModel.items) { item in
                SharedPurchaseItemRow(
                    item: item,
                    isSelected: viewModel.isPurchaseSelected(item),
                    canSelect: viewModel.canTogglePurchaseItem(item),
                    canChange: viewModel.canChangeItem(item),
                    focusedProductID: $focusedProductID
                ) {
                    viewModel.togglePurchaseItem(item)
                } onEdit: {
                    viewModel.beginEditingItem(item)
                } onRemove: {
                    cancellationItem = item
                    confirmsCancellation = true
                }
                .listRowBackground(viewModel.isPurchaseSelected(item) ? Color.primarySoft : .surface)
            }
        } header: {
            Text("Pending products")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select the products you are buying. The others will remain pending.")
                if !viewModel.items.isEmpty {
                    Label {
                        if isVoiceOverEnabled {
                            Text("Use the product’s actions to edit or remove it.")
                        } else {
                            Text("Swipe left on a product to edit or remove it.")
                        }
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.surface)

        Section {
            if viewModel.editingItem != nil {
                Button("Review product edit") {
                    viewModel.isItemEditorPresented = true
                }
            }
            Text("Selected: \(viewModel.purchaseSelection.count) of up to 50")
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    await viewModel.finalizePurchase()
                }
            } label: {
                Text(viewModel.purchaseActionTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(ShoppingActionButtonStyle())
            .disabled(!viewModel.canFinalizePurchase)
            .accessibilityHint("Confirms only the selected products from this store for the whole group.")
        } footer: {
            Label(
                "Switching stores or leaving this screen does not confirm the purchase. Refresh to check for group changes.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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

#Preview("Purchase selection", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPurchaseSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
}
