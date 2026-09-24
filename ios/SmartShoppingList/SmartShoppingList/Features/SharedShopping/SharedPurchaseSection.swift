import SwiftUI

struct SharedPurchaseSection: View {
    let viewModel: SharedShoppingViewModel

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
            }
        } header: {
            Text("Pending · \(viewModel.selectedStoreName)")
        } footer: {
            Text("Select the products you are buying. The others will remain pending.")
        }

        Section {
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
    }
}

#Preview("Selección de compra", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPurchaseSection(viewModel: viewModel)
    }
}
