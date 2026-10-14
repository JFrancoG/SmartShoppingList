import StoreKit
import SwiftUI

struct SharedPremiumView: View {
    @Environment(\.usesPreparedShoppingPreview) private var usesPreparedShoppingPreview
    let viewModel: SharedShoppingViewModel
    @State private var showsSubscriptionManagement = false
    var referenceDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Form {
                SharedPremiumStatusSection(viewModel: viewModel)
                SharedPremiumGroupNotice(viewModel: viewModel, date: referenceDate ?? context.date)

                if viewModel.membershipAccess?.premiumActive == true {
                    SharedPremiumManagementSection(
                        viewModel: viewModel,
                        showsSubscriptionManagement: $showsSubscriptionManagement
                    )
                }

                SharedPremiumBenefitsSection()

                SharedPremiumOptionsSection(viewModel: viewModel)

                if viewModel.membershipAccess?.premiumActive != true {
                    SharedPremiumManagementSection(
                        viewModel: viewModel,
                        showsSubscriptionManagement: $showsSubscriptionManagement
                    )
                }

                SharedPremiumRestoreSection(viewModel: viewModel)
            }
            .modifier(ShoppingFormStyle())
        }
        .navigationTitle("Premium")
        .manageSubscriptionsSheet(isPresented: $showsSubscriptionManagement)
        .task {
            // The preview trait already prepared a snapshot; do not recapture a transient reload state.
            guard !usesPreparedShoppingPreview else { return }
            await viewModel.loadPremium()
        }
        .refreshable {
            await viewModel.loadPremium(reportsActionErrors: true)
        }
    }
}

#Preview("Premium free · ES", traits: .sharedShopping(.premiumFree)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedPremiumView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Premium · EN AX5", traits: .sharedShopping(.premiumRestricted)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedPremiumView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Premium active · illustrative · ES", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedPremiumView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Payment grace · illustrative · EN AX5", traits: .sharedShopping(.premiumGrace)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedPremiumView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Purchase verification · illustrative · ES AX5", traits: .sharedShopping(.premiumVerification)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedPremiumView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "es"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Premium active · EN AX5", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedPremiumView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
