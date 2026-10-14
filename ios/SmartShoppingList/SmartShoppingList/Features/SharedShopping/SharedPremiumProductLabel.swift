import SwiftUI

struct SharedPremiumProductLabel: View {
    @ScaledMetric(relativeTo: .headline) private var inlineSpacing = 12.0
    @ScaledMetric(relativeTo: .subheadline) private var stackedSpacing = 4.0
    let product: SharedSubscriptionProduct

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: inlineSpacing) {
                Text(product.displayName).font(.headline)
                Text(product.displayPrice).font(.subheadline)
            }
            .fixedSize(horizontal: true, vertical: true)
            VStack(spacing: stackedSpacing) {
                Text(product.displayName).font(.headline)
                Text(product.displayPrice).font(.subheadline)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(product.displayName)
        .accessibilityValue(
            product.period == .monthly
                ? Text("\(product.displayPrice) per month")
                : Text("\(product.displayPrice) per year")
        )
    }
}

#Preview("Product labels · ES", traits: .sharedShopping(.premiumFree)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    VStack(spacing: 16) {
        ForEach(viewModel.premium.products) { product in
            Button {} label: {
                SharedPremiumProductLabel(product: product)
            }
        }
    }
    .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, minimumHeight: 48))
    .padding()
    .background(.canvas)
    .environment(\.locale, Locale(identifier: "es"))
}
