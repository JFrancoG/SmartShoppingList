import Foundation
import Observation
import Testing
@testable import SmartShoppingList

@MainActor
@Suite(.tags(.fast))
struct ShoppingDraftSpeechTests {
    @Test(.timeLimit(.minutes(1)))
    func `A late finish from a cancelled capture cannot alter the next dictation`() async throws {
        let speech = ControlledDraftSpeech()
        let model = makeModel(speech: speech)
        let firstCapture = model.startDictation()
        await waitForActivity(.recording, in: model)
        let firstFinish = model.finishDictation()
        await speech.waitForFinishCalls(1)

        await model.cancelDictation().value
        await firstCapture.value
        let secondCapture = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe("peras en Día", capture: 2)
        await waitForText("peras en Día", in: model)

        try await speech.completeFinish(call: 1, error: .failed)
        await firstFinish.value

        #expect(model.activity == .recording)
        #expect(model.notice == nil)
        #expect(model.text == "peras en Día")
        try await speech.transcribe("peras y arroz en Día", capture: 2)
        await waitForText("peras y arroz en Día", in: model)
        #expect(model.activity == .recording)

        await model.cancelDictation().value
        await secondCapture.value
    }

    @Test
    func `Denied microphone permission preserves the text and corrected draft`() async throws {
        let speech = ControlledDraftSpeech(startError: .permissionDenied)
        let corrected = ShoppingDraftItem(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            name: "leche sin lactosa",
            quantity: "3 briks",
            store: "Día Norte"
        )
        let model = makeModel(
            speech: speech,
            draft: ShoppingDraftSnapshot(text: "añadir también café molido", items: [corrected])
        )

        await model.startDictation().value
        model.reviewDraft()

        #expect(model.activity == .idle)
        #expect(model.text == "añadir también café molido")
        let prepared = try #require(model.preparedItems)
        #expect(prepared.map(\.id) == [corrected.id])
        #expect(prepared.map(\.name) == ["leche sin lactosa"])
        #expect(prepared.map(\.quantity) == ["3 briks"])
        #expect(prepared.map(\.store) == ["Día Norte"])
    }

    private func makeModel(
        speech: ControlledDraftSpeech,
        draft: ShoppingDraftSnapshot = ShoppingDraftSnapshot()
    ) -> ShoppingDraftViewModel {
        ShoppingDraftViewModel(
            interpreter: SpeechTestUnavailableInterpreter(),
            speech: speech,
            persistence: MemoryDraftPersistence(),
            initialDraft: draft
        )
    }

    private func waitForActivity(_ activity: DraftActivity, in model: ShoppingDraftViewModel) async {
        for await current in Observations({ model.activity }) {
            if current == activity {
                return
            }
        }
    }

    private func waitForText(_ text: String, in model: ShoppingDraftViewModel) async {
        for await current in Observations({ model.text }) {
            if current == text {
                return
            }
        }
    }


}

private actor ControlledDraftSpeech: SpeechCapturing {
    private let startError: SpeechCaptureError?
    private var captureCount = 0
    private var finishCount = 0
    private var streams: [Int: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation] = [:]
    private var finishes: [Int: (capture: Int, response: CheckedContinuation<Void, any Error>)] = [:]
    private var finishWaiters: [(count: Int, response: CheckedContinuation<Void, Never>)] = []

    init(startError: SpeechCaptureError? = nil) {
        self.startError = startError
    }

    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        if let startError {
            throw startError
        }
        captureCount += 1
        let stream = AsyncThrowingStream<SpeechCaptureEvent, any Error>.makeStream()
        streams[captureCount] = stream.continuation
        stream.continuation.yield(.recording(localeIdentifier: "es-ES"))
        return stream.stream
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { response in
            finishCount += 1
            finishes[finishCount] = (captureCount, response)
            let readyWaiters = finishWaiters.filter { $0.count <= finishCount }
            finishWaiters.removeAll { $0.count <= finishCount }
            for waiter in readyWaiters {
                waiter.response.resume()
            }
        }
    }

    func cancel() async {
        streams.removeValue(forKey: captureCount)?.finish()
    }

    func waitForFinishCalls(_ count: Int) async {
        guard finishCount < count else { return }
        await withCheckedContinuation { response in
            finishWaiters.append((count, response))
        }
    }

    func transcribe(_ text: String, capture: Int) throws {
        let stream = try #require(streams[capture])
        stream.yield(.transcript(text))
    }

    func completeFinish(call: Int, error: SpeechCaptureError? = nil) throws {
        let pending = finishes.removeValue(forKey: call)
        let finish = try #require(pending)
        if let error {
            finish.response.resume(throwing: error)
        } else {
            streams.removeValue(forKey: finish.capture)?.finish()
            finish.response.resume()
        }
    }
}

@MainActor
private struct SpeechTestUnavailableInterpreter: DraftInterpreting {
    var availability: DraftInterpretationAvailability { .deviceNotEligible }

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        throw DraftInterpretationError.unavailable
    }
}
