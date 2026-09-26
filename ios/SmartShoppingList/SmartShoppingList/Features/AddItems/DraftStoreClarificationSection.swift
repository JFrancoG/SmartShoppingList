import SwiftUI

struct DraftStoreClarificationSection: View {
    @Bindable var viewModel: SharedShoppingViewModel
    var storeName: String? = nil

    var body: some View {
        if viewModel.hasStoreClarifications(for: storeName) {
            Section {
                ForEach($viewModel.storeChoices) { $choice in
                    if viewModel.needsStoreClarification(choice, storeName: storeName) {
                        Picker("Store for “\(choice.id)”", selection: $choice.selection) {
                            Text("Select an option").tag("")
                            ForEach(viewModel.storeCandidates(for: choice.id)) { store in
                                Text(store.name).tag(store.id.uuidString)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(viewModel.isBusy)
                    }
                }
            } header: {
                Text("Choose the matching store")
            } footer: {
                Text("More than one store matches this name. Choose which one you mean.")
            }
            .listRowBackground(Color.surface)
        }
    }

}

#Preview("Store clarification", traits: .sharedShopping(.review)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        DraftStoreClarificationSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .onAppear {
        viewModel.seedStoreClarificationPreview()
    }
}
