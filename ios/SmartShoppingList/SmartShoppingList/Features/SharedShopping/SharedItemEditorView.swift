import SwiftUI

struct SharedItemEditorView: View {
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Product details") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Product name", text: $viewModel.editName, axis: .vertical)
                        if let message = viewModel.editLengthMessage(for: .name) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Quantity (optional)", text: $viewModel.editQuantity, axis: .vertical)
                        if let message = viewModel.editLengthMessage(for: .quantity) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Picker("Store", selection: $viewModel.editStoreID) {
                        ForEach(viewModel.stores) { store in
                            Text(store.name).tag(Optional(store.id))
                        }
                        Text("New store").tag(nil as UUID?)
                    }
                    if viewModel.editStoreID == nil {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("New store name", text: $viewModel.editNewStore, axis: .vertical)
                            if let message = viewModel.editLengthMessage(for: .store) {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .listRowBackground(Color.surface)
                .disabled(!viewModel.canMutate)
                Section {
                    if let message = viewModel.editValidationMessage, !viewModel.editHasLengthIssue {
                        Text(message)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if viewModel.storeItemsState == .loading {
                        ProgressView("Loading pending products…")
                    } else if viewModel.storeItemsState != .loaded {
                        Text("Refresh the list before reviewing this product.")
                    } else if viewModel.itemEditRequiresReview {
                        if let current = viewModel.latestEditingItem {
                            Text("The product has changed. Review its current details before saving your proposal.")
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
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(!viewModel.canSaveItemEdit)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                SharedOperationSection(viewModel: viewModel)
            }
            .modifier(ShoppingFormStyle())
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
                    .labelStyle(.iconOnly)
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

#Preview("Edit pending product", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedItemEditorView(viewModel: viewModel)
        .task {
            if let item = viewModel.items.first {
                viewModel.beginEditingItem(item)
            }
        }
}

#Preview("Length limits", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedItemEditorView(viewModel: viewModel)
        .task {
            if let item = viewModel.items.first {
                viewModel.beginEditingItem(item)
                viewModel.editName = "Wholemeal hamburger buns with sesame seeds for the weekend barbecue"
                viewModel.editStoreID = nil
                viewModel.editNewStore = "The supermarket near the station in the city centre"
            }
        }
}
