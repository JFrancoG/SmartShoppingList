import SwiftUI

struct SharedPremiumBenefitsSection: View {
    @ScaledMetric(relativeTo: .footnote) private var footerSpacing = 8.0
    var body: some View {
        Section {
            Label("Join or create up to 5 groups", systemImage: "person.2")
            Label("Up to 10 stores per group", systemImage: "storefront")
            Label("Up to 100 products per store", systemImage: "cart")
        } header: {
            Text("Premium includes")
        } footer: {
            VStack(alignment: .leading, spacing: footerSpacing) {
                Text("Store and product limits apply to groups you administer. Only active stores and products pending purchase count.")
                Text("Free plan: 1 group · 3 active stores · 20 pending products per store.")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .listRowBackground(Color.surface)
    }
}

#Preview("Premium benefits · ES", traits: .sharedShopping(.premiumFree)) {
    Form {
        SharedPremiumBenefitsSection()
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Premium benefits · EN AX5", traits: .sharedShopping(.premiumFree)) {
    Form {
        SharedPremiumBenefitsSection()
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
