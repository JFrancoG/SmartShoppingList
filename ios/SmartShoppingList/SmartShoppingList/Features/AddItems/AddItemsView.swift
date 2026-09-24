import SwiftUI

struct AddItemsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var focusedControl: DraftItemAccessibilityTarget?
    @State private var editorOriginID: UUID?
    @Bindable var viewModel: ShoppingDraftViewModel
    var shared: SharedShoppingViewModel? = nil

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
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
                            editorOriginID = nil
                            focusedControl = nil
                            viewModel.beginAddingItem()
                        }
                        .disabled(!viewModel.canAddItem)

                        if viewModel.items.isEmpty {
                            Text("There are no products in the draft yet.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(viewModel.items) { item in
                            DraftItemRow(item: item, accessibilityFocus: $focusedControl) {
                                editorOriginID = item.id
                                focusedControl = nil
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

                    if let notice = viewModel.persistenceNotice {
                        Section("Draft storage") {
                            Text(notice)
                        }
                    }
                }
                .disabled(!viewModel.hasLoaded)
                .navigationTitle("Add")
                .sheet(isPresented: $viewModel.isEditorPresented, onDismiss: {
                    viewModel.editorPresentationDidDismiss()
                    restoreEditorFocus(using: scrollProxy)
                }) {
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
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedNotice,
            isEnabled: shared == nil && !viewModel.isEditorPresentationActive,
            dismiss: viewModel.dismissPresentedNotice
        ))
    }

    private func restoreEditorFocus(using scrollProxy: ScrollViewProxy) {
        let originID = editorOriginID
        editorOriginID = nil
        guard let originID, viewModel.items.contains(where: { $0.id == originID }) else { return }
        let target = DraftItemAccessibilityTarget.edit(originID)
        scrollProxy.scrollTo(target)
        focusedControl = target
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
