import SwiftUI

struct SharedReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SharedShoppingViewModel

    var body: some View {
        NavigationStack {
            Form {
                SharedOperationSection(viewModel: viewModel)
                Section {
                    ForEach(viewModel.reviewedItems) { item in
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .font(.headline)
                            if let quantity = item.quantity {
                                Text(quantity)
                            }
                            Text("Tienda indicada: \(item.store)")
                                .foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Productos revisados · \(viewModel.reviewedItems.count)")
                } footer: {
                    Text("Para corregir productos o cantidades, vuelve al borrador antes de confirmar.")
                }
                Section {
                    ForEach($viewModel.storeChoices) { $choice in
                        Picker("Tienda para «\(choice.id)»", selection: $choice.selection) {
                            Text("Selecciona una opción").tag("")
                            Text("Confirmar el nombre «\(choice.id)»").tag("new")
                            ForEach(viewModel.stores) { store in
                                Text(store.name).tag(store.id.uuidString)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .disabled(viewModel.isBusy)
                        .accessibilityHint("Elige una tienda del grupo o confirma el nombre que has revisado.")
                    }
                } header: {
                    Text("Confirma las tiendas")
                } footer: {
                    Text("Confirma una opción para cada nombre. Si ese nombre ya existe en el grupo, se usará la misma tienda.")
                }
                Section {
                    Button("Confirmar incorporación al grupo", systemImage: "plus.circle") {
                        Task {
                            await viewModel.confirmReviewedBatch()
                        }
                    }
                    .disabled(!viewModel.canConfirmReview)
                    .accessibilityHint("Añade todos los productos revisados al grupo con las tiendas elegidas.")
                } footer: {
                    Text("Los productos se compartirán únicamente al confirmar este envío.")
                }
            }
            .navigationTitle("Revisar envío")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Volver", role: .cancel) {
                        dismiss()
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .interactiveDismissDisabled(viewModel.isBusy)
        }
    }
}

#Preview("Elegir tiendas", traits: .sharedShopping(.review)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedReviewView(viewModel: viewModel)
}

#Preview("Revisión con texto grande", traits: .sharedShopping(.review)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedReviewView(viewModel: viewModel)
        .environment(\.dynamicTypeSize, .accessibility5)
}
