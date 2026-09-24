import SwiftUI

struct SharedOperationSection: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        if viewModel.notice != nil || viewModel.pendingOperation != nil || viewModel.isBusy {
            Section("Estado del grupo") {
                if viewModel.isBusy {
                    ProgressView("Consultando el grupo…")
                }
                if let notice = viewModel.notice {
                    Text(notice)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cerrar aviso") {
                        viewModel.dismissNotice()
                    }
                }
                if viewModel.pendingOperation != nil {
                    Text("Hay un envío pendiente de confirmación. Conservamos sus datos para reintentarlo sin duplicarlo.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Reintentar envío", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.retryPendingOperation()
                        }
                    }
                    .disabled(!viewModel.canRetryOperation)
                    .accessibilityHint("Repite el mismo envío que quedó pendiente de confirmar.")
                    if !viewModel.canRetryOperation && !viewModel.isBusy {
                        Text("Para recuperar el envío, accede con la misma cuenta de Apple que lo inició.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#Preview("Envío pendiente", traits: .sharedShopping(.pending)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedOperationSection(viewModel: viewModel)
    }
}
