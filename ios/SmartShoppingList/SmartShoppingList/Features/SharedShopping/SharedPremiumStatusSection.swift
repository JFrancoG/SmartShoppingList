import SwiftUI

struct SharedPremiumStatusSection: View {
    @ScaledMetric(relativeTo: .body) private var statusSpacing = 16.0
    @ScaledMetric(relativeTo: .body) private var deadlineSpacing = 4.0
    let viewModel: SharedShoppingViewModel

    var body: some View {
        Section {
            VStack(spacing: statusSpacing) {
                if viewModel.membershipAccess?.premiumActive == true {
                    Label("Premium active", systemImage: "checkmark.seal.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.success)
                        .accessibilityAddTraits(.isHeader)
                    if viewModel.premium.status?.state == .inGracePeriod,
                       let graceEnd = viewModel.premium.status?.gracePeriodExpiresAt {
                        VStack(spacing: deadlineSpacing) {
                            Text("Payment grace ends").font(.subheadline)
                            Text(graceEnd, format: .dateTime.day().month().year()).font(.headline)
                        }
                        .accessibilityElement(children: .combine)
                    } else if let expiry = viewModel.premium.status?.expiresAt {
                        VStack(spacing: deadlineSpacing) {
                            Text("Current period ends").font(.subheadline)
                            Text(expiry, format: .dateTime.day().month().year()).font(.headline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if viewModel.premium.status?.state == .inGracePeriod {
                        Text("Premium remains active while Apple retries your payment. Check your payment method in subscription settings.")
                    } else if viewModel.premium.status?.autoRenewEnabled == false {
                        Text("Renewal is cancelled. Premium remains active until the current period ends.")
                    }
                } else {
                    Label("Free plan", systemImage: "person.crop.circle")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                if viewModel.premium.isBusy {
                    ProgressView("Checking subscription…")
                }
            }
            .foregroundStyle(.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(viewModel.membershipAccess?.premiumActive == true ? Color.successSoft : Color.surface)
    }
}

#Preview("Premium status · ES", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPremiumStatusSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Premium status · EN AX5", traits: .sharedShopping(.premiumActive)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPremiumStatusSection(viewModel: viewModel)
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}
