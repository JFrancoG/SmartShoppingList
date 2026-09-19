import SwiftUI

struct DraftPreviewContainer<Content: View>: View {
    @State private var viewModel: ShoppingDraftViewModel
    private let content: (ShoppingDraftViewModel) -> Content

    var body: some View {
        content(viewModel)
    }
}

extension DraftPreviewContainer {
    init(
        snapshot: ShoppingDraftSnapshot,
        state: DraftPreviewState,
        content: @escaping (ShoppingDraftViewModel) -> Content
    ) {
        _viewModel = State(initialValue: DraftPreviewSupport.viewModel(snapshot: snapshot, state: state))
        self.content = content
    }
}

#Preview(traits: .shoppingDraft) {
    DraftPreviewContainer(snapshot: DraftPreviewSupport.snapshot, state: .content) { viewModel in
        AddItemsView(viewModel: viewModel)
    }
}
