import SwiftUI

struct SharedPreviewContainer<Content: View>: View {
    @State private var viewModel: SharedShoppingViewModel
    private let fixture: SharedPreviewFixture
    private let state: SharedPreviewState
    private let content: (SharedShoppingViewModel) -> Content

    var body: some View {
        content(viewModel)
            .task {
                // Debug previews arrive ready; this also keeps the helper valid in Release builds.
                if !viewModel.hasLoaded {
                    await SharedPreviewSupport.prepare(viewModel, fixture: fixture, state: state)
                }
            }
    }
}

extension SharedPreviewContainer {
    init(
        context: SharedPreviewContext,
        state: SharedPreviewState,
        content: @escaping (SharedShoppingViewModel) -> Content
    ) {
        _viewModel = State(initialValue: SharedPreviewSupport.viewModel(
            fixture: context.fixture,
            state: state,
            presentation: context.presentations[state]
        ))
        self.fixture = context.fixture
        self.state = state
        self.content = content
    }
}

#Preview("Contenedor independiente", traits: .sharedShopping) {
    @Previewable @Environment(SharedShoppingViewModel.self) var viewModel
    SharedGroupView(viewModel: viewModel)
}
