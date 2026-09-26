import SwiftUI

struct SharedGroupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var storeIsFocused: Bool
    @Bindable var viewModel: SharedShoppingViewModel
    var onOpenSettings: () -> Void = {}

    private var storeControlsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
    }

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)

                if viewModel.group != nil {
                    Section("Shopping list") {
                        storeControlsLayout {
                            Picker("Store", selection: $viewModel.selectedStoreID) {
                                Text("Select a store").tag(Optional<UUID>.none)
                                ForEach(viewModel.stores) { store in
                                    Text(store.name).tag(Optional(store.id))
                                }
                            }
                            .pickerStyle(.navigationLink)
                            .disabled(viewModel.isBusy || !viewModel.sessionIsVerified || viewModel.storeQuery.activity != .idle)
                            .accessibilityFocused($storeIsFocused)
                            if viewModel.storeQuery.activity == .idle {
                                Button("Find store by voice", systemImage: "mic") {
                                    viewModel.startStoreDictation()
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(ShoppingIconButtonStyle())
                                .disabled(!viewModel.canQueryStore)
                            }
                        }
                        StoreQueryView(viewModel: viewModel.storeQuery, shared: viewModel, showsMicrophone: false)
                        if viewModel.stores.isEmpty {
                            Text("Add products to start your first shopping list.")
                                .foregroundStyle(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .listRowBackground(Color.surface)
                    if viewModel.selectedStoreID != nil {
                        SharedPurchaseSection(viewModel: viewModel)
                    }
                } else if viewModel.hasLoaded && !viewModel.isBusy {
                    Section {
                        Text("Set up your group in Settings to share a shopping list.")
                            .foregroundStyle(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings", action: onOpenSettings)
                            .buttonStyle(ShoppingActionButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .modifier(ShoppingFormStyle())
            .navigationTitle(viewModel.group.map { Text($0.name) } ?? Text("Shop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!viewModel.hasLoaded || viewModel.isBusy || !viewModel.isConfigured)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task(id: viewModel.selectedStoreID) {
                await viewModel.loadSelectedStore()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    viewModel.interruptStoreDictation()
                }
            }
            .onDisappear {
                viewModel.interruptStoreDictation()
            }
            .onChange(of: viewModel.group?.id) { _, _ in
                viewModel.closeStoreQuery()
            }
            .onChange(of: viewModel.isStoreQueryVisible) { wasVisible, isVisible in
                if wasVisible && !isVisible {
                    storeIsFocused = true
                }
            }
        }
    }
}

#Preview("Shopping list", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}

#Preview("Signed out", traits: .sharedShopping(.signedOut)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}

#Preview("Shopping list, large text", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
