import SwiftUI

struct SharedItemEditorView: View {
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Product details") {
                    TextField("Product name", text: $viewModel.editName, axis: .vertical)
                    TextField("Quantity (optional)", text: $viewModel.editQuantity, axis: .vertical)
                    Picker("Store", selection: $viewModel.editStoreID) {
                        ForEach(viewModel.stores) { store in
                            Text(store.name).tag(Optional(store.id))
                        }
                        Text("New store").tag(nil as UUID?)
                    }
                    if viewModel.editStoreID == nil {
                        TextField("New store name", text: $viewModel.editNewStore, axis: .vertical)
                    }
                }
                .disabled(!viewModel.canMutate)
                Section {
                    Text("Name: up to 160 characters. Quantity and store: up to 80 characters.")
                        .foregroundStyle(.secondary)
                    if let message = viewModel.editValidationMessage {
                        Text(message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if viewModel.storeItemsState == .loading {
                        ProgressView("Loading pending products…")
                    } else if viewModel.storeItemsState != .loaded {
                        Text("Refresh the list before reviewing this product.")
                    } else if viewModel.itemEditRequiresReview {
                        Text("The product has changed. Review its current details before saving your proposal.")
                        if let current = viewModel.latestEditingItem {
                            Text(current.name)
                            if let quantity = current.quantity {
                                Text(quantity)
                            }
                            Button("I have reviewed the current product") {
                                viewModel.reviewLatestItem()
                            }
                            .disabled(!viewModel.canMutate)
                        } else {
                            Text("This product is no longer in this store. Close the editor and refresh the list.")
                        }
                    }
                    Button("Save product changes") {
                        Task {
                            await viewModel.saveItemEdit()
                        }
                    }
                    .disabled(!viewModel.canSaveItemEdit)
                }
                SharedOperationSection(viewModel: viewModel)
            }
            .navigationTitle("Edit product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.isItemEditorPresented = false
                    }
                    .disabled(viewModel.isBusy)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .interactiveDismissDisabled(viewModel.isBusy)
            .modifier(ShoppingNoticeModifier(
                notice: viewModel.presentedNotice,
                isEnabled: viewModel.isItemEditorPresented,
                dismiss: viewModel.dismissPresentedNotice
            ))
        }
    }
}

#Preview("Editar pendiente", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedItemEditorView(viewModel: viewModel)
        .task {
            if let item = viewModel.items.first {
                viewModel.beginEditingItem(item)
            }
        }
}
