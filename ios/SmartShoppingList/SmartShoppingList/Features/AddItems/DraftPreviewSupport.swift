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
    case availableModel
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

    #if DEBUG
    static func aiValidationViewModel(emptyInterpretation: Bool) -> ShoppingDraftViewModel {
        ShoppingDraftViewModel(
            interpreter: ValidationDraftInterpreter(emptyInterpretation: emptyInterpretation),
            speech: ValidationSpeechCapture(),
            persistence: MemoryDraftPersistence(),
            initialDraft: ShoppingDraftSnapshot()
        )
    }
    #endif

    static func viewModel(snapshot: ShoppingDraftSnapshot, state: DraftPreviewState) -> ShoppingDraftViewModel {
        var draft = snapshot
        switch state {
        case .content, .availableModel:
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
            interpreter: PreviewDraftInterpreter(availability: state == .availableModel ? .available : .deviceNotEligible),
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
    let availability: DraftInterpretationAvailability

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        guard availability == .available else { throw DraftInterpretationError.unavailable }
        return [
            SuggestedProduct(name: "Bread", quantity: nil, store: "Mercadona"),
            SuggestedProduct(name: "Beer", quantity: "2", store: "Mercadona")
        ]
    }
}

private struct PreviewSpeechCapture: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }

    func finish() async throws {}
    func cancel() async {}
}

#if DEBUG
@MainActor
private struct ValidationDraftInterpreter: DraftInterpreting {
    let emptyInterpretation: Bool
    var availability: DraftInterpretationAvailability { .available }

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        if emptyInterpretation { throw DraftInterpretationError.noProducts }
        return [SuggestedProduct(name: "Yogurts", quantity: "6", store: "Aldi")]
    }
}

private actor ValidationSpeechCapture: SpeechCapturing {
    private var continuation: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation?

    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        continuation?.finish()
        let stream = AsyncThrowingStream<SpeechCaptureEvent, any Error>.makeStream()
        continuation = stream.continuation
        stream.continuation.yield(.recording(localeIdentifier: "en-US"))
        stream.continuation.yield(.transcript("Add 6 Yogurts to Aldi"))
        return stream.stream
    }

    func finish() async throws {
        continuation?.finish()
        continuation = nil
    }

    func cancel() async {
        continuation?.finish()
        continuation = nil
    }
}
#endif
