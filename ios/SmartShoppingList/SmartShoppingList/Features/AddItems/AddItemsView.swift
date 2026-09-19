import SwiftUI

struct AddItemsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var viewModel: ShoppingDraftViewModel
    var shared: SharedShoppingViewModel? = nil

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.hasLoaded {
                    ProgressView("Recuperando el borrador…")
                }

                if let shared {
                    SharedOperationSection(viewModel: shared)
                }

                DraftInputSection(viewModel: viewModel)
                    .disabled(shared?.draftIsLocked == true)

                Section {
                    Button("Añadir producto a mano", systemImage: "plus") {
                        viewModel.beginAddingItem()
                    }
                    .disabled(!viewModel.canAddItem)

                    if viewModel.items.isEmpty {
                        Text("Todavía no hay productos en el borrador.")
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
                    Text("Productos · \(viewModel.items.count)")
                } footer: {
                    Text("Revisa cada producto, su cantidad y la tienda. Puedes añadir hasta 50 productos por lote.")
                }
                .disabled(shared?.draftIsLocked == true)

                Section {
                    Button("Revisar borrador", systemImage: "checklist") {
                        viewModel.reviewDraft()
                    }
                    .disabled(viewModel.items.isEmpty || viewModel.activity != .idle)

                    if viewModel.preparedItems != nil {
                        Text("Borrador revisado. Todavía no se ha enviado al grupo.")
                        if let shared {
                            Button("Elegir tiendas y confirmar", systemImage: "person.2") {
                                Task {
                                    await shared.prepareReview()
                                }
                            }
                            .disabled(!shared.canMutate || shared.group == nil)
                            if shared.group == nil {
                                Text("Accede a tu grupo en Comprar para enviar estos productos.")
                            }
                        }
                    }
                } footer: {
                    Text("Los productos siguen siendo un borrador hasta que confirmes su incorporación al grupo.")
                }
                .disabled(shared?.draftIsLocked == true)

                if let notice = viewModel.notice {
                    Section {
                        Text(notice)
                        Button("Cerrar aviso") {
                            viewModel.dismissNotice()
                        }
                    }
                }

                if let notice = viewModel.persistenceNotice {
                    Section("Conservación del borrador") {
                        Text(notice)
                    }
                }
            }
            .disabled(!viewModel.hasLoaded)
            .navigationTitle("Añadir")
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
