import StoreKit
import SwiftUI

struct SharedPremiumView: View {
    let viewModel: SharedShoppingViewModel
    @State private var showsSubscriptionManagement = false

    var body: some View {
        Form {
            Section {
                if viewModel.membershipAccess?.premiumActive == true {
                    Label("Premium active", systemImage: "checkmark.seal")
                    if viewModel.premium.status?.state == .inGracePeriod,
                       let graceEnd = viewModel.premium.status?.gracePeriodExpiresAt {
                        LabeledContent("Payment grace ends") {
                            Text(graceEnd, format: .dateTime.day().month().year())
                        }
                    } else if let expiry = viewModel.premium.status?.expiresAt {
                        LabeledContent("Current period ends") {
                            Text(expiry, format: .dateTime.day().month().year())
                        }
                    }
                    if viewModel.premium.status?.state == .inGracePeriod {
                        Text("Premium remains active while Apple retries your payment. Check your payment method in subscription settings.")
                    } else if viewModel.premium.status?.autoRenewEnabled == false {
                        Text("Renewal is cancelled. Premium remains active until the current period ends.")
                    }
                } else {
                    Label("Free plan", systemImage: "person.crop.circle")
                }
                Text("One personal premium subscription includes up to 5 groups. Groups you administer share limits of 10 active stores and 100 pending products per store.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Without premium: one group, 3 active stores and 20 pending products per store. Group store and product limits follow the current administrator's plan.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Color.surface)

            SharedFreeGroupSection(viewModel: viewModel)

            Section {
                if viewModel.premium.isBusy {
                    ProgressView("Checking subscription…")
                }
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
                            VStack(alignment: .leading) {
                                Text(product.displayName).font(.headline)
                                if product.period == .monthly {
                                    Text("\(product.displayPrice) per month")
                                } else {
                                    Text("\(product.displayPrice) per year")
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .disabled(viewModel.isBusy || !viewModel.premium.canPurchase)
                    }
                    if viewModel.premium.pendingVerification != nil {
                        Button("Retry purchase verification", systemImage: "arrow.clockwise") {
                            Task {
                                await viewModel.loadPremium(reportsActionErrors: true)
                            }
                        }
                        .disabled(viewModel.isBusy)
                    }
                    Button("Restore purchases", systemImage: "arrow.clockwise") {
                        Task {
                            await viewModel.restorePremium()
                        }
                    }
                    .disabled(viewModel.isBusy || !viewModel.premium.canRestore)
                    Button("Manage Apple subscription", systemImage: "creditcard") {
                        showsSubscriptionManagement = true
                    }
                    .disabled(viewModel.isBusy)
                    Text("Payment is charged to your Apple Account. The subscription renews automatically unless you cancel in Apple's subscription settings.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !viewModel.premium.isBusy {
                    Text("Purchases will be available once premium is ready.")
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(Color.surface)
        }
        .modifier(ShoppingFormStyle())
        .navigationTitle("Premium")
        .manageSubscriptionsSheet(isPresented: $showsSubscriptionManagement)
        .task {
            await viewModel.loadPremium()
        }
        .refreshable {
            await viewModel.loadPremium(reportsActionErrors: true)
        }
    }
}

#Preview("Premium · ES", traits: .sharedShopping(.premiumTransition)) {
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
