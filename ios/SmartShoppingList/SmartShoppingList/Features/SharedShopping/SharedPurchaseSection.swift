import SwiftUI

struct SharedPurchaseSection: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    let viewModel: SharedShoppingViewModel
    let onRemove: (SharedItem) -> Void
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
                    onRemove(item)
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
            ShoppingControlGroup {
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
                    Text("Confirm purchase")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(ShoppingActionButtonStyle())
                .disabled(!viewModel.canFinalizePurchase)
                .accessibilityLabel(Text(viewModel.purchaseActionTitle))
                .accessibilityHint("Confirms only the selected products from this store for the whole group.")
            }
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
    SharedGroupView(viewModel: viewModel)
}
