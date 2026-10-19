#if DEBUG
import StoreKit
import SwiftUI

struct SharedSandboxRefundSection: View {
    let viewModel: SharedShoppingViewModel
    @State private var request: SandboxRefundRequest?
    @State private var preparation: Task<Void, Never>?

    var body: some View {
        Section {
            Button {
                guard preparation == nil, request == nil else { return }
                preparation = Task {
                    defer { preparation = nil }
                    let prepared = await viewModel.prepareSandboxRefund()
                    guard !Task.isCancelled, let prepared else { return }
                    request = prepared
                }
            } label: {
                Text("Request test refund")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, usesCapsule: true))
            .disabled(viewModel.isBusy || !viewModel.premium.canRestore || preparation != nil || request != nil)
        } header: {
            Text("Sandbox testing")
        } footer: {
            Text("Opens Apple's refund sheet for this account's active test purchase.")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .background {
            if let request {
                SandboxRefundPresentation(request: request) { result in
                    guard self.request?.id == request.id else { return }
                    self.request = nil
                    Task {
                        await viewModel.completeSandboxRefund(result, request: request)
                    }
                }
                .id(request.id)
            }
        }
        .onChange(of: viewModel.session?.accessToken) {
            preparation?.cancel()
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
