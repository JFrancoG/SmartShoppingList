import SwiftUI

struct SharedPremiumManagementSection: View {
    let viewModel: SharedShoppingViewModel
    @Binding var showsSubscriptionManagement: Bool

    var body: some View {
        if viewModel.premium.status?.isConfigured == true,
           viewModel.membershipAccess?.premiumActive == true || viewModel.premium.pendingVerification != nil {
            Section {
                if viewModel.membershipAccess?.premiumActive == true {
                    Button("Manage subscription", systemImage: "creditcard") {
                        showsSubscriptionManagement = true
                    }
                    .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, usesCapsule: true))
                    .disabled(viewModel.isBusy)
                }
                if viewModel.premium.pendingVerification != nil {
                    Button("Retry purchase verification", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.loadPremium(reportsActionErrors: true)
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, usesCapsule: true))
                    .disabled(viewModel.isBusy)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

#Preview("Subscription management · ES", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    @Previewable @State var showsManagement = false
    Form {
        SharedPremiumManagementSection(viewModel: viewModel, showsSubscriptionManagement: $showsManagement)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Subscription management · EN AX5", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    @Previewable @State var showsManagement = false
    Form {
        SharedPremiumManagementSection(viewModel: viewModel, showsSubscriptionManagement: $showsManagement)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
