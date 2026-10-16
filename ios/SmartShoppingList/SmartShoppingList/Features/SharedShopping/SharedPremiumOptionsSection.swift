import SwiftUI

struct SharedPremiumOptionsSection: View {
    let viewModel: SharedShoppingViewModel

    var body: some View {
        Section {
            if let message = viewModel.premium.notice {
                Text(message)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.premium.status?.isConfigured == true {
                ForEach(viewModel.premium.products) { product in
                    Button {
                        Task {
                            await viewModel.purchasePremium(productID: product.id)
                        }
                    } label: {
                        SharedPremiumProductLabel(product: product)
                    }
                    .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, usesCapsule: true))
                    .disabled(viewModel.isBusy || !viewModel.premium.canPurchase)
                }
                Text("Payment is charged to your Apple Account. The subscription renews automatically unless you cancel in Apple's subscription settings.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !viewModel.premium.isBusy {
                Text("Purchases will be available once premium is ready.")
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            if viewModel.membershipAccess?.premiumActive == true {
                Text("Change plan")
            } else {
                Text("Subscription options")
            }
        }
        .listRowBackground(Color.surface)
    }
}

#Preview("Subscription options · ES", traits: .sharedShopping(.premiumFree)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPremiumOptionsSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Subscription options · EN AX5", traits: .sharedShopping(.premiumFree)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPremiumOptionsSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
