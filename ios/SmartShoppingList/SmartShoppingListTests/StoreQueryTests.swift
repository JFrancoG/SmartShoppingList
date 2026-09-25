import Foundation
import Observation
import Testing
@testable import SmartShoppingList

@MainActor
@Suite(.tags(.fast))
struct StoreQueryTests {
    private let groupID = UUID()

    @Test(arguments: ["Dame la lista de Mercadona", "Show me the list for MERCADONA!", "Mercadona"])
    func `Queries return real stores in either language`(query: String) {
        let stores = makeStores(["Mercadona", "Aldi"])
        let result = StoreQueryMatcher.matches(query, stores: stores)
        #expect(result.map(\.id) == [stores[0].id])
    }

    @Test(arguments: ["Dame la lista de Día", "Show me the list for dia", "DÍA"])
    func `Ambiguous branches remain separate choices`(query: String) {
        let stores = makeStores(["Día Norte", "Día Sur", "Diamante"])
        #expect(StoreQueryMatcher.matches(query, stores: stores).map(\.id) == [stores[0].id, stores[1].id])
    }

    @Test(arguments: ["", "  ", "Dame la lista de Walmart", "aldino", "mediodía"])
    func `Unknown empty and substring queries do not invent a match`(query: String) {
        #expect(StoreQueryMatcher.matches(query, stores: makeStores(["Aldi", "Día"])).isEmpty)
    }

    @Test
    func `Mentioning two stores keeps both choices`() {
        let stores = makeStores(["Aldi", "Lidl", "Mercadona"])
        #expect(StoreQueryMatcher.matches("Aldi or Lidl", stores: stores).map(\.id) == [stores[0].id, stores[1].id])
    }

    @Test
    func `Editing a query invalidates earlier choices`() {
        let model = StoreQueryViewModel(speech: StoreQuerySpeech())
        model.prepare(stores: makeStores(["Aldi", "Lidl"]))
        model.text = "Aldi"
        model.search()
        #expect(model.matches.map(\.name) == ["Aldi"])
        model.text = "Unknown"
        #expect(model.matches.isEmpty)
        #expect(model.message == nil)
        model.search()
        #expect(model.matches.isEmpty)
        #expect(model.message == "I couldn’t find that store in your group. Try again, correct the text or use the Store selector.")
    }

    @Test(.timeLimit(.minutes(1)))
    func `Finishing resolves the final transcript and cancellation restores prior text`() async {
        let speech = StoreQuerySpeech()
        let model = StoreQueryViewModel(speech: speech)
        model.prepare(stores: makeStores(["Aldi", "Lidl"]))
        model.text = "Aldi"
        let capture = model.startDictation()
        await waitForRecording(model)
        await speech.setFinalText("Show me the list for Lidl")
        await model.finishDictation().value
        await capture.value
        #expect(model.text == "Show me the list for Lidl")
        #expect(model.matches.map(\.name) == ["Lidl"])
        let next = model.startDictation()
        await waitForRecording(model)
        await speech.transcribe("Aldi")
        await waitForText("Aldi", model: model)
        await model.stopDictation(restoreText: true).value
        await next.value
        #expect(model.text == "Show me the list for Lidl")
        #expect(model.activity == .idle)
        #expect(model.matches.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Leaving capture preserves text without selecting a store`() async {
        let speech = StoreQuerySpeech()
        let model = StoreQueryViewModel(speech: speech)
        model.prepare(stores: makeStores(["Aldi"]))
        let capture = model.startDictation()
        await waitForRecording(model)
        await speech.transcribe("Aldi")
        await waitForText("Aldi", model: model)
        await model.stopDictation().value
        await capture.value
        #expect(model.text == "Aldi")
        #expect(model.matches.isEmpty)
        #expect(model.activity == .idle)
        #expect(await speech.cancelCount == 1)
    }

    @Test(arguments: [SpeechCaptureError.permissionDenied, .unsupportedLocale, .unavailable])
    func `Speech failures preserve typed queries and manual search`(error: SpeechCaptureError) async {
        let model = StoreQueryViewModel(speech: StoreQuerySpeech(error: error))
        model.prepare(stores: makeStores(["Aldi"]))
        model.text = "Aldi"
        await model.startDictation().value
        #expect(model.message != nil)
        #expect(model.text == "Aldi")
        #expect(model.canSearch)
        model.search()
        #expect(model.matches.map(\.name) == ["Aldi"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Silent dictation does not search the previous typed query`() async {
        let model = StoreQueryViewModel(speech: StoreQuerySpeech())
        model.prepare(stores: makeStores(["Aldi"]))
        model.text = "Aldi"
        let capture = model.startDictation()
        await waitForRecording(model)
        await model.finishDictation().value
        await capture.value
        #expect(model.matches.isEmpty)
        #expect(model.text == "Aldi")
        #expect(model.message == "No speech was recognized. Try again or type a store name.")
    }

    @Test(.timeLimit(.minutes(1)))
    func `A late finish after closing cannot change the next store query`() async throws {
        let speech = ControlledDraftSpeech()
        let model = StoreQueryViewModel(speech: speech)
        model.prepare(stores: makeStores(["Aldi", "Lidl"]))
        let first = model.startDictation()
        await waitForRecording(model)
        try await speech.transcribe("Aldi", capture: 1)
        await waitForText("Aldi", model: model)
        let finish = model.finishDictation()
        await speech.waitForFinishCalls(1)
        await model.stopDictation().value
        await first.value
        model.prepare(stores: makeStores(["Lidl"]))
        let next = model.startDictation()
        await waitForRecording(model)
        try await speech.transcribe("Lidl", capture: 2)
        await waitForText("Lidl", model: model)
        try await speech.completeFinish(call: 1, error: .failed)
        await finish.value
        #expect(model.text == "Lidl")
        #expect(model.activity == .recording)
        #expect(model.message == nil)
        #expect(model.matches.isEmpty)
        await model.stopDictation().value
        await next.value
    }

    private func makeStores(_ names: [String]) -> [SharedStore] {
        names.map { SharedStore(id: UUID(), groupId: groupID, name: $0) }
    }

    private func waitForRecording(_ model: StoreQueryViewModel) async {
        for await activity in Observations({ model.activity }) {
            if activity == .recording {
                return
            }
        }
    }

    private func waitForText(_ expected: String, model: StoreQueryViewModel) async {
        for await text in Observations({ model.text }) {
            if text == expected {
                return
            }
        }
    }
}

private actor StoreQuerySpeech: SpeechCapturing {
    private let error: SpeechCaptureError?
    private var continuation: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation?
    private var finalText: String?
    private(set) var cancelCount = 0

    init(error: SpeechCaptureError? = nil) {
        self.error = error
    }

    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        if let error {
            throw error
        }
        let stream = AsyncThrowingStream<SpeechCaptureEvent, any Error>.makeStream()
        continuation = stream.continuation
        continuation?.yield(.recording(localeIdentifier: "en-US"))
        return stream.stream
    }

    func setFinalText(_ text: String) {
        finalText = text
    }

    func transcribe(_ text: String) {
        continuation?.yield(.transcript(text))
    }

    func finish() async throws {
        if let finalText {
            continuation?.yield(.transcript(finalText))
        }
        continuation?.finish()
        continuation = nil
    }

    func cancel() async {
        cancelCount += 1
        continuation?.finish()
        continuation = nil
    }
}
