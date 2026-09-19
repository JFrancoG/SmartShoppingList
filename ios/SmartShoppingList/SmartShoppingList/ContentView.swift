import SwiftUI

struct ContentView: View {
    let viewModel: ShoppingDraftViewModel

    var body: some View {
        AddItemsView(viewModel: viewModel)
    }
}

#Preview(traits: .shoppingDraft) {
    @Previewable @Environment(ShoppingDraftViewModel.self) var viewModel
    ContentView(viewModel: viewModel)
}
