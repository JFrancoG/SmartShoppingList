import SwiftUI

struct SharedFreeGroupView: View {
    @Environment(\.usesPreparedShoppingPreview) private var usesPreparedShoppingPreview
    let viewModel: SharedShoppingViewModel
    var referenceDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Form {
                SharedOperationSection(viewModel: viewModel)
                SharedFreeGroupSection(viewModel: viewModel, date: referenceDate ?? context.date)
            }
            .modifier(ShoppingFormStyle())
        }
        .navigationTitle("Free group")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !usesPreparedShoppingPreview else { return }
            await viewModel.load()
            await viewModel.refresh()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

#Preview("Free group · transition ES", traits: .sharedShopping(.premiumTransition)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedFreeGroupView(viewModel: viewModel, referenceDate: Date(timeIntervalSince1970: 1_791_590_400))
    }
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Free group · restricted EN AX5", traits: .sharedShopping(.premiumRestricted)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedFreeGroupView(viewModel: viewModel, referenceDate: Date(timeIntervalSince1970: 1_791_590_400))
    }
    .environment(\.locale, Locale(identifier: "en"))
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Free group · empty ES", traits: .sharedShopping(.premiumNoGroups)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedFreeGroupView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "es"))
}

#Preview("Free group · single ES", traits: .sharedShopping(.premiumSingleGroup)) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    NavigationStack {
        SharedFreeGroupView(viewModel: viewModel)
    }
    .environment(\.locale, Locale(identifier: "es"))
}
