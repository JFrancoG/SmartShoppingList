import SwiftUI

struct SharedPremiumBenefitsSection: View {
    var body: some View {
        Section {
            Label("Join or create up to 5 groups", systemImage: "person.2")
            Label("Up to 10 stores per group", systemImage: "storefront")
            Label("Up to 100 products per store", systemImage: "cart")
        } header: {
            Text("Premium includes")
        } footer: {
            Text("Store and product limits apply to groups you administer. Only active stores and products pending purchase count.")
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
