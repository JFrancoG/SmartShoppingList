import SwiftUI

struct SharedPremiumGroupNotice: View {
    let viewModel: SharedShoppingViewModel
    var date = Date()

    var body: some View {
        if case let .multiple(_, false, transitionEnd, _, _) = viewModel.freeGroupPresentation(at: date) {
            Section {
                if let transitionEnd {
                    Text("You can shop in your existing groups until \(transitionEnd, format: .dateTime.day().month(.wide).year().hour().minute()). Then only in your free group.")
                } else {
                    Text("Your free plan lets you shop in one group. Review which group you want to use.")
                }
                NavigationLink {
                    SharedFreeGroupView(viewModel: viewModel)
                } label: {
                    Text("Review free group")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 48)
                }

            }
            .fixedSize(horizontal: false, vertical: true)
            .listRowBackground(Color.surface)
        }
    }
}

#Preview("Group notice · ES", traits: .sharedShopping(.premiumTransition)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    Form {
        SharedPremiumGroupNotice(viewModel: viewModel, date: Date(timeIntervalSince1970: 1_791_590_400))
    }
    .modifier(ShoppingFormStyle())
    .environment(\.locale, Locale(identifier: "es"))
}
