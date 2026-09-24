import DeveloperToolsSupport
import SwiftUI

struct DraftPreviewModifier: PreviewModifier {
    let state: DraftPreviewState

    static func makeSharedContext() async throws -> ShoppingDraftSnapshot {
        DraftPreviewSupport.snapshot
    }

    func body(content: Content, context: ShoppingDraftSnapshot) -> some View {
        DraftPreviewContainer(snapshot: context, state: state) { viewModel in
            content
                .environment(viewModel)
        }
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var shoppingDraft: Self { shoppingDraft(.content) }

    static func shoppingDraft(_ state: DraftPreviewState) -> Self {
        .modifier(DraftPreviewModifier(state: state))
    }
}

enum DraftPreviewState {
    case content
    case empty
    case missingStore
}

@MainActor
enum DraftPreviewSupport {
    static let items = [
        ShoppingDraftItem(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            name: "Jabón",
            quantity: "",
            store: "Mercadona"
        ),
        ShoppingDraftItem(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
            name: "Cerveza sin alcohol",
            quantity: "6 latas",
            store: "Mercadona"
        ),
        ShoppingDraftItem(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3)),
            name: "Yogures sin lactosa",
            quantity: "4 unidades",
            store: "Mercadona"
        )
    ]

    static var snapshot: ShoppingDraftSnapshot {
        ShoppingDraftSnapshot(text: "Comprar jabón, cerveza y yogures en Mercadona", items: items)
    }

    static func viewModel(snapshot: ShoppingDraftSnapshot, state: DraftPreviewState) -> ShoppingDraftViewModel {
        var draft = snapshot
        switch state {
        case .content:
            break
        case .empty:
            draft = ShoppingDraftSnapshot()
        case .missingStore:
            draft.items = draft.items.prefix(1).map { item in
                var incomplete = item
                incomplete.store = ""
                return incomplete
            }
        }
        let viewModel = ShoppingDraftViewModel(
            interpreter: PreviewDraftInterpreter(),
            speech: PreviewSpeechCapture(),
            persistence: MemoryDraftPersistence(),
            initialDraft: draft
        )
        if let item = draft.items.last {
            viewModel.editorItem = item
        }
        if state == .missingStore {
            viewModel.saveEditor()
            viewModel.reviewDraft()
        }
        return viewModel
    }
}

@MainActor
private struct PreviewDraftInterpreter: DraftInterpreting {
    var availability: DraftInterpretationAvailability { .deviceNotEligible }

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        throw DraftInterpretationError.unavailable
    }
}

private struct PreviewSpeechCapture: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }

    func finish() async throws {}
    func cancel() async {}
}
