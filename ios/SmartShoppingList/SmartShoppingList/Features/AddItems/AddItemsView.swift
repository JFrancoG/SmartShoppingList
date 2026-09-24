import SwiftUI

struct AddItemsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: ShoppingDraftViewModel
    var shared: SharedShoppingViewModel? = nil

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.hasLoaded {
                    ProgressView("Restoring draft…")
                }

                if let shared {
                    SharedOperationSection(viewModel: shared)
                }

                DraftInputSection(viewModel: viewModel)
                    .disabled(shared?.draftIsLocked == true)

                Section {
                    Button("Add product manually", systemImage: "plus") {
                        viewModel.beginAddingItem()
                    }
                    .disabled(!viewModel.canAddItem)

                    if viewModel.items.isEmpty {
                        Text("There are no products in the draft yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.items) { item in
                        DraftItemRow(item: item) {
                            viewModel.beginEditingItem(item)
                        } onRemove: {
                            viewModel.removeItem(id: item.id)
                        }
                    }
                } header: {
                    Text("Products · \(viewModel.items.count)")
                } footer: {
                    Text("Review each product, its quantity and store. You can add up to 50 products per batch.")
                }
                .disabled(shared?.draftIsLocked == true)

                Section {
                    Button("Review draft", systemImage: "checklist") {
                        viewModel.reviewDraft()
                    }
                    .disabled(viewModel.items.isEmpty || viewModel.activity != .idle)

                    if viewModel.preparedItems != nil {
                        Text("Draft reviewed. It has not been sent to the group yet.")
                        if let shared {
                            Button("Choose stores and confirm", systemImage: "person.2") {
                                Task {
                                    await shared.prepareReview()
                                }
                            }
                            .disabled(!shared.canMutate || shared.group == nil)
                            if shared.group == nil {
                                Text("Open your group in Shop to send these products.")
                            }
                        }
                    }
                } footer: {
                    Text("Products remain in your draft until you confirm adding them to the group.")
                }
                .disabled(shared?.draftIsLocked == true)

                if let notice = viewModel.notice {
                    Section {
                        Text(notice)
                        Button("Dismiss notice") {
                            viewModel.dismissNotice()
                        }
                    }
                }

                if let notice = viewModel.persistenceNotice {
                    Section("Draft storage") {
                        Text(notice)
                    }
                }
            }
            .disabled(!viewModel.hasLoaded)
            .navigationTitle("Add")
            .sheet(isPresented: $viewModel.isEditorPresented) {
                DraftItemEditor(viewModel: viewModel)
            }
            .task {
                await viewModel.load()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .active:
                    viewModel.setActive(true)
                case .background:
                    viewModel.setActive(false)
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onDisappear {
                viewModel.setActive(false)
            }
        }
    }
}

#Preview("Borrador manual", traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
}

#Preview("Texto grande", traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Sin productos", traits: .shoppingDraft(.empty)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
}

#Preview("Tienda pendiente", traits: .shoppingDraft(.missingStore)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
}
