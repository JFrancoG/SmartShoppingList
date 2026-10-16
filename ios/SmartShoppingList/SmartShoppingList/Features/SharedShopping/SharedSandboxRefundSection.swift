#if DEBUG
import StoreKit
import SwiftUI

struct SharedSandboxRefundSection: View {
    let viewModel: SharedShoppingViewModel
    @State private var request: SandboxRefundRequest?
    @State private var showsRefund = false
    @State private var preparation: Task<Void, Never>?

    var body: some View {
        Section {
            Button {
                preparation = Task {
                    let prepared = await viewModel.prepareSandboxRefund()
                    guard !Task.isCancelled, let prepared else { return }
                    request = prepared
                    showsRefund = true
                }
            } label: {
                Text("Request test refund")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, usesCapsule: true))
            .disabled(viewModel.isBusy || !viewModel.premium.canRestore || showsRefund)
        } header: {
            Text("Sandbox testing")
        } footer: {
            Text("Opens Apple's refund sheet for this account's active test purchase.")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .refundRequestSheet(for: request?.transactionID ?? 0, isPresented: $showsRefund) { result in
            guard let request else { return }
            let outcome: SandboxRefundOutcome
            switch result {
            case .success(.success): outcome = .submitted
            case .success(.userCancelled): outcome = .cancelled
            case .failure(.duplicateRequest): outcome = .duplicate
            default: outcome = .failed
            }
            Task {
                await viewModel.completeSandboxRefund(outcome, userID: request.userID)
            }
        }
        .onChange(of: viewModel.session?.accessToken) {
            preparation?.cancel()
            showsRefund = false
            request = nil
        }
        .onDisappear {
            preparation?.cancel()
        }
    }
}

#Preview("Sandbox refund · ES", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedSandboxRefundSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}
#endif
