import SwiftUI

struct SharedPremiumRestoreSection: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        if viewModel.premium.status?.isConfigured == true {
            Section {
                Button {
                    Task {
                        await viewModel.restorePremium()
                    }
                } label: {
                    Text("Restore purchases")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(ShoppingActionButtonStyle(
                    widthFraction: 1,
                    minimumHeight: 48,
                    isProminent: false,
                    usesCapsule: true
                ))
                .disabled(viewModel.isBusy || !viewModel.premium.canRestore)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

#Preview("Restore purchases · ES", traits: .sharedShopping(.premiumFree)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPremiumRestoreSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}
