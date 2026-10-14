import SwiftUI

struct SharedPremiumManagementSection: View {
    let viewModel: SharedShoppingViewModel
    @Binding var showsSubscriptionManagement: Bool

    var body: some View {
        if viewModel.premium.status?.isConfigured == true {
            Section {
                if viewModel.membershipAccess?.premiumActive == true {
                    Button("Manage Apple subscription", systemImage: "creditcard") {
                        showsSubscriptionManagement = true
                    }
                    .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, minimumHeight: 48, usesCapsule: true))
                    .disabled(viewModel.isBusy)
                }
                if viewModel.premium.pendingVerification != nil {
                    Button("Retry purchase verification", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.loadPremium(reportsActionErrors: true)
                        }
                    }
                    .buttonStyle(ShoppingActionButtonStyle(widthFraction: 1, minimumHeight: 48, usesCapsule: true))
                    .disabled(viewModel.isBusy)
                }
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
            } header: {
                if viewModel.membershipAccess?.premiumActive == true {
                    Text("Subscription management")
                }
            }
            .listRowBackground(Color.surface)
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
