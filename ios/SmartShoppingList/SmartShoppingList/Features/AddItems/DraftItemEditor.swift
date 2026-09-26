import SwiftUI

struct DraftItemEditor: View {
    @Bindable var viewModel: ShoppingDraftViewModel
    var shared: SharedShoppingViewModel? = nil

    private var addsDirectly: Bool { viewModel.isAddingItem && shared?.group != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Product", text: $viewModel.editorItem.name, axis: .vertical)
                            .accessibilityHint("Include any variants you need, such as lactose-free.")
                        if let message = viewModel.editorLengthMessage(for: .name) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Quantity", text: $viewModel.editorItem.quantity, axis: .vertical)
                            .accessibilityLabel("Quantity, optional")
                        if let message = viewModel.editorLengthMessage(for: .quantity) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Store", text: $viewModel.editorItem.store, axis: .vertical)
                        if let message = viewModel.editorLengthMessage(for: .store) {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .listRowBackground(Color.surface)
                .disabled(shared?.isBusy == true)

                if let shared, addsDirectly {
                    DraftStoreClarificationSection(viewModel: shared, storeName: viewModel.editorItem.store)
                }

                Section {
                    Button {
                        if let shared, addsDirectly {
                            Task {
                                await shared.addManualItem()
                            }
                        } else {
                            viewModel.saveEditor()
                        }
                    } label: {
                        if addsDirectly {
                            Text("Add product")
                        } else {
                            Text("Save product")
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(
                        viewModel.editorHasLengthIssue || shared?.draftIsLocked == true
                            || (addsDirectly && shared?.canMutate != true)
                    )
                } footer: {
                    if addsDirectly {
                        Text("Adds this product to the specified store. A new store is created if needed.")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .modifier(ShoppingFormStyle())
            .navigationTitle("Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditor()
                    }
                    .disabled(shared?.isBusy == true)
                }
            }
            .interactiveDismissDisabled(shared?.isBusy == true)
        }
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedEditorNotice ?? shared?.presentedNotice,
            isEnabled: viewModel.isEditorPresented,
            dismiss: { notice in
                if notice.source == .editor {
                    viewModel.dismissPresentedNotice(notice)
                } else {
                    shared?.dismissPresentedNotice(notice)
                }
            }
        ))
    }
}

#Preview(traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
}

#Preview("Missing store", traits: .shoppingDraft(.missingStore)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
}

#Preview("New product", traits: .shoppingDraft(.empty)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
}

#Preview("Add to group", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel.draft, shared: viewModel)
        .onAppear {
            viewModel.draft.beginAddingItem()
            viewModel.draft.editorItem.name = "Bread"
            viewModel.draft.editorItem.quantity = "2"
            viewModel.draft.editorItem.store = "Mercadona Centro"
        }
}

#Preview("Length limits", traits: .shoppingDraft(.empty)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
        .onAppear {
            viewModel.beginAddingItem()
            viewModel.editorItem.name = "Wholemeal hamburger buns with sesame seeds for the weekend barbecue"
            viewModel.editorItem.store = "The supermarket near the station in the city centre"
        }
}
