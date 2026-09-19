import SwiftUI

struct DraftItemEditor: View {
    @Bindable var viewModel: ShoppingDraftViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Producto", text: $viewModel.editorItem.name, axis: .vertical)
                        .accessibilityHint("Incluye las variantes que necesitas, por ejemplo sin lactosa.")
                    TextField("Cantidad, opcional", text: $viewModel.editorItem.quantity, axis: .vertical)
                    TextField("Tienda", text: $viewModel.editorItem.store, axis: .vertical)
                } footer: {
                    Text("Nombre: hasta 160 caracteres. Cantidad y tienda: hasta 80. La cantidad es opcional.")
                }

                if let error = viewModel.editorError {
                    Section {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .navigationTitle("Producto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        viewModel.cancelEditor()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        viewModel.saveEditor()
                    }
                }
            }
        }
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
