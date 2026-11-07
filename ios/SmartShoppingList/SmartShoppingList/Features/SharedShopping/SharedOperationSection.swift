import SwiftUI

struct SharedOperationSection: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        if viewModel.pendingOperation != nil || viewModel.isBusy || viewModel.readFailure != nil {
            Section("Group status") {
                if viewModel.isBusy {
                    ProgressView("Loading group…")
                }
                if let message = viewModel.readFailure {
                    Text(message)
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(!viewModel.hasLoaded || viewModel.isBusy || !viewModel.isConfigured)
                }
                if viewModel.pendingOperation != nil {
                    Text("A submission is awaiting confirmation. Its data is kept so you can retry without duplicating it.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Retry submission", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.retryPendingOperation()
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle())
                    .disabled(!viewModel.canRetryOperation)
                    .accessibilityHint("Retries the same submission that is awaiting confirmation.")
                    if !viewModel.canRetryOperation && !viewModel.isBusy {
                        Text("To recover the submission, sign in with the same Apple Account that started it.")
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
            .listRowBackground(Color.surface)
        }
    }
}

#Preview("Pending submission", traits: .sharedShopping(.pending)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedOperationSection(viewModel: viewModel)
    }
}
