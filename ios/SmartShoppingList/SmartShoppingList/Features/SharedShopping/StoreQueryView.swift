import SwiftUI

/// Inline controls in Shop's store section; speaking never opens a separate screen.
struct StoreQueryView: View {
    @AccessibilityFocusState private var messageIsFocused: Bool
    @Bindable var viewModel: StoreQueryViewModel
    let shared: SharedShoppingViewModel
    var showsMicrophone = true

    var body: some View {
        Group {
            if showsMicrophone && viewModel.activity == .idle {
                Button("Find store by voice", systemImage: "mic") {
                    shared.startStoreDictation()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(ShoppingIconButtonStyle())
                .disabled(!shared.canQueryStore)
            }
            if shared.isStoreQueryVisible {
                TextField("Store query", text: $viewModel.text, axis: .vertical)
                    .disabled(viewModel.activity != .idle)
                    .submitLabel(.search)
                    .onSubmit {
                        Task {
                            await shared.searchStoreQuery()
                        }
                    }
                if viewModel.activity == .recording {
                    Label("Listening…", systemImage: "mic.fill")
                    Button("Finish dictation", systemImage: "stop.circle") {
                        Task {
                            await shared.finishStoreDictation()
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                } else if viewModel.activity != .idle {
                    ProgressView(viewModel.activity == .preparing ? "Preparing microphone…" : "Stopping dictation…")
                } else {
                    Button("Find store", systemImage: "magnifyingglass") {
                        Task {
                            await shared.searchStoreQuery()
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(!shared.canQueryStore || !viewModel.canSearch)
                }
                Button("Cancel", role: .cancel) {
                    shared.closeStoreQuery()
                }
                .buttonStyle(ShoppingActionButtonStyle())
                if let message = viewModel.message {
                    Text(message)
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityFocused($messageIsFocused)
                }
                ForEach(viewModel.matches) { store in
                    Button {
                        Task {
                            await shared.chooseQueriedStore(store)
                        }
                    } label: {
                        Text("Show list for \(store.name)")
                    }
                    .disabled(!shared.canQueryStore || viewModel.activity != .idle)
                }
            }
        }
        .onChange(of: viewModel.message) { _, message in
            messageIsFocused = message != nil
        }
    }
}

#Preview("Inline store query", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var shared
    Form {
        Section("Supermarket") {
            StoreQueryView(viewModel: shared.storeQuery, shared: shared)
        }
    }
    .task {
        shared.openStoreQuery()
        shared.storeQuery.text = "Unknown store"
        await shared.searchStoreQuery()
    }
}
