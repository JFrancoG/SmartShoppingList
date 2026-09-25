import SwiftUI

struct AppRootView: View {
    let viewModel: ShoppingDraftViewModel
    var shared: SharedShoppingViewModel? = nil

    var body: some View {
        if let shared {
            SharedRootView(viewModel: shared)
        } else {
            AddItemsView(viewModel: viewModel)
        }
    }
}

#Preview(traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    AppRootView(viewModel: viewModel)
}
