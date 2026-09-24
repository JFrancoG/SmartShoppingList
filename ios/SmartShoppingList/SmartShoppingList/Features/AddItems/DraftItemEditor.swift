import SwiftUI

struct DraftItemEditor: View {
    @Bindable var viewModel: ShoppingDraftViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Product", text: $viewModel.editorItem.name, axis: .vertical)
                        .accessibilityHint("Include any variants you need, such as lactose-free.")
                    TextField("Quantity", text: $viewModel.editorItem.quantity, axis: .vertical)
                        .accessibilityLabel("Quantity, optional")
                    TextField("Store", text: $viewModel.editorItem.store, axis: .vertical)
                } footer: {
                    Text("Name: up to 160 characters. Quantity and store: up to 80. Quantity is optional.")
                }
            }
            .navigationTitle("Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditor()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        viewModel.saveEditor()
                    }
                }
            }
        }
        .modifier(ShoppingNoticeModifier(
            notice: viewModel.presentedEditorNotice,
            dismiss: viewModel.dismissPresentedNotice
        ))
    }
}

#Preview(traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
}

#Preview("Falta la tienda", traits: .shoppingDraft(.missingStore)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
}

#Preview("Producto nuevo", traits: .shoppingDraft(.empty)) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    DraftItemEditor(viewModel: viewModel)
}
