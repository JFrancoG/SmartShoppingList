import SwiftUI

struct SharedPurchaseSection: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        Section {
            if viewModel.items.isEmpty && !viewModel.isBusy {
                Text("Sin productos cargados. Actualiza para consultar esta tienda.")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.items) { item in
                Button {
                    viewModel.togglePurchaseItem(item)
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: viewModel.isPurchaseSelected(item) ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(item.name)
                                .font(.headline)
                            if let quantity = item.quantity {
                                Text(quantity)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canTogglePurchaseItem(item))
                .accessibilityValue(viewModel.isPurchaseSelected(item) ? Text("Seleccionado") : Text("Sin seleccionar"))
                .accessibilityHint("Cambia la selección local. La compra se guarda al pulsar Finalizar compra.")
            }
        } header: {
            Text("Pendientes · \(viewModel.selectedStoreName)")
        } footer: {
            Text("Marca los productos que vas a comprar. Los demás seguirán pendientes.")
        }

        Section {
            Text("Seleccionados: \(viewModel.purchaseSelection.count) de 50 como máximo")
            if viewModel.purchaseSelectionNeedsReview {
                Label("Hay productos seleccionados que han cambiado o ya no están pendientes.", systemImage: "exclamationmark.triangle")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Desmarcar los productos que han cambiado") {
                    viewModel.discardChangedPurchaseSelections()
                }
                .disabled(!viewModel.canMutate)
            }
            Button {
                Task {
                    await viewModel.finalizePurchase()
                }
            } label: {
                Label {
                    Text(viewModel.purchaseActionTitle)
                } icon: {
                    Image(systemName: "cart.badge.checkmark")
                }
            }
            .disabled(!viewModel.canFinalizePurchase)
            .accessibilityHint("Confirma únicamente los productos seleccionados de esta tienda para todo el grupo.")
        } header: {
            Text("Confirmar compra")
        } footer: {
            Text("Cambiar de tienda o salir de esta pantalla no confirma la compra. Actualiza para consultar cambios del grupo.")
        }
    }
}

#Preview("Selección de compra", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPurchaseSection(viewModel: viewModel)
    }
}
