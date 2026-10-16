import SwiftUI

struct SharedEmptyStoreArchiveSection: View {
    let viewModel: SharedShoppingViewModel
    @State private var storeToArchive: SharedStore?
    @State private var confirmsArchive = false

    var body: some View {
        if let store = viewModel.selectedEmptyStore {
            Section {
                Button("Archive store") {
                    storeToArchive = store
                    confirmsArchive = true
                }
                .buttonStyle(ShoppingActionButtonStyle(usesCapsule: true))
                .disabled(!viewModel.canMutate)
                .accessibilityLabel(Text("Archive store: \(store.name)"))
            } footer: {
                Text("An archived store keeps its identity and history. Restore it before adding products to it again.")
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .shoppingAlert(Text("Archive store?"), isPresented: $confirmsArchive, presenting: storeToArchive) { selected in
                ShoppingAlertActions(primaryTitle: Text("Archive")) {
                    Task {
                        await viewModel.archiveEmptyStoreFromShopping(selected)
                    }
                } cancel: {}
            } message: { selected in
                Text("Archive \(selected.name)? It will stop appearing in shopping lists and will keep its history.")
            }
        }
    }
}

#Preview("Empty store archive · ES", traits: .sharedShopping(.emptyStore)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedEmptyStoreArchiveSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}
