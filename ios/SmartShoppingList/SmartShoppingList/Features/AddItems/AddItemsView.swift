import SwiftUI

struct AddItemsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var focusedControl: DraftItemAccessibilityTarget?
    @State private var editorOriginID: UUID?
    @Bindable var viewModel: ShoppingDraftViewModel
    var shared: SharedShoppingViewModel? = nil
    var onOpenSettings: () -> Void = {}

    private var showsManualEntry: Bool {
        viewModel.availability != .available || viewModel.showsManualEntry || shared?.group == nil
    }

    private var showsDraftReview: Bool {
        !viewModel.items.isEmpty && (viewModel.showsDraftReview || shared?.group == nil)
    }

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

                    if viewModel.availability == .available || viewModel.activity != .idle {
                        DraftInputSection(viewModel: viewModel)
                            .disabled(shared?.draftIsLocked == true)
                    }

                    if showsManualEntry {
                        Section {
                            Button("Add product manually", systemImage: "plus") {
                                editorOriginID = nil
                                focusedControl = nil
                                viewModel.beginAddingItem()
                            }
                            .buttonStyle(ShoppingActionButtonStyle())
                            .disabled(!viewModel.canAddItem)
                        } header: {
                            if viewModel.availability != .available {
                                Text("What would you like to add?")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.textPrimary)
                                    .textCase(nil)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .padding(.bottom, 8)
                            }
                        } footer: {
                            if viewModel.availability != .available, viewModel.activity == .idle {
                                Label {
                                    Text(viewModel.availabilityMessage)
                                } icon: {
                                    Image(systemName: "info.circle")
                                        .accessibilityHidden(true)
                                }
                                .foregroundStyle(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .disabled(shared?.draftIsLocked == true)
                    }

                    if showsDraftReview {
                        Section {
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
                            Text("Check the products and stores, then add them to your group. New store names create new stores.")
                        }
                        .listRowBackground(Color.surface)
                        .disabled(shared?.draftIsLocked == true)

                        if let shared {
                            DraftStoreClarificationSection(viewModel: shared)
                            Section {
                                Button("Add \(viewModel.items.count) products", systemImage: "plus") {
                                    Task {
                                        await shared.addDraftItems()
                                    }
                                }
                                .buttonStyle(ShoppingActionButtonStyle())
                                .disabled(!shared.canMutate || shared.group == nil || viewModel.activity != .idle)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    if let shared, shared.group == nil {
                        Section {
                            Button("Open Settings to join or create a group.", action: onOpenSettings)
                        } footer: {
                            Text("Your products are saved on this device until you have a group.")
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }

                    if viewModel.availability != .available, viewModel.activity == .idle, !viewModel.text.isEmpty {
                        Section("Saved shopping text") {
                            TextField("Shopping text", text: $viewModel.text, axis: .vertical)
                                .lineLimit(2...)
                                .accessibilityLabel("Shopping text")
                                .disabled(shared?.draftIsLocked == true)
                        }
                        .listRowBackground(Color.surface)
                    }

                    if let notice = viewModel.persistenceNotice {
                        Section("Draft storage") {
                            Text(notice)
                        }
                        .listRowBackground(Color.surface)
                    }
                }
                .modifier(ShoppingFormStyle())
                .disabled(!viewModel.hasLoaded)
                .navigationTitle(shared?.group?.name ?? String(localized: "Add"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                            .labelStyle(.iconOnly)
                    }
                }
                .sheet(isPresented: $viewModel.isEditorPresented, onDismiss: {
                    viewModel.editorPresentationDidDismiss()
                    restoreEditorFocus(using: scrollProxy)
                }) {
                    DraftItemEditor(viewModel: viewModel, shared: shared)
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

#Preview("Manual draft", traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
}

#Preview("Large text", traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Empty draft", traits: .shoppingDraft(.empty)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
}

#Preview("Missing store", traits: .shoppingDraft(.missingStore)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AddItemsView(viewModel: viewModel)
}
