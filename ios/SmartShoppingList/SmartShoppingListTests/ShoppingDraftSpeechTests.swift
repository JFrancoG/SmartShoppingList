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
        try await speech.transcribe("texto descartado", capture: 1)
        await waitForText("texto descartado", in: model)
        let firstFinish = model.finishDictation()
        await speech.waitForFinishCalls(1)

        await model.cancelDictation().value
        await firstCapture.value
        try #require(model.text.isEmpty)
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

    @Test(.timeLimit(.minutes(1)), arguments: ["", "  café molido\n", "pan en Aldi"], [false, true])
    func `Cancelling dictation restores and persists the exact previous text`(
        original: String,
        replacingText: Bool
    ) async throws {
        let speech = ControlledDraftSpeech()
        let persistence = MemoryDraftPersistence()
        let item = ShoppingDraftItem(name: "arroz", quantity: "1 paquete", store: "Mercadona")
        let draft = ShoppingDraftSnapshot(text: original, items: [item], interpretedText: original)
        let model = ShoppingDraftViewModel(
            interpreter: SpeechTestUnavailableInterpreter(),
            speech: speech,
            persistence: persistence,
            initialDraft: draft
        )
        let capture = model.startDictation(replacingText: replacingText)
        #expect(model.shoppingText == (replacingText ? "" : original))
        #expect(model.text == original)
        await waitForActivity(.recording, in: model)
        #expect(model.shoppingText == (replacingText ? "" : original))
        try await speech.transcribe("leche en Lidl", capture: 1)
        await waitForText("leche en Lidl", in: model)
        #expect(model.shoppingText == "leche en Lidl")
        await model.flushPersistence()

        await model.cancelDictation().value
        await capture.value
        await model.flushPersistence()

        #expect(model.text == original)
        #expect(model.shoppingText == original)
        #expect(model.activity == .idle)
        #expect(model.items == [item])
        let saved = try #require(try await persistence.load())
        #expect(saved.text == original)
        #expect(saved.items == [item])
        #expect(saved.interpretedText == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Finishing keeps the transcript and the next cancellation restores it`() async throws {
        let speech = ControlledDraftSpeech()
        let model = makeModel(speech: speech, draft: ShoppingDraftSnapshot(text: "pan"))
        let first = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe("leche", capture: 1)
        await waitForText("pan\nleche", in: model)
        let finish = model.finishDictation()
        await speech.waitForFinishCalls(1)
        try await speech.completeFinish(call: 1)
        await finish.value
        await first.value
        #expect(model.text == "pan\nleche")
        #expect(model.activity == .idle)

        let second = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe("arroz", capture: 2)
        await waitForText("pan\nleche\narroz", in: model)
        await model.cancelDictation().value
        await second.value
        #expect(model.text == "pan\nleche")
    }

    @Test(.timeLimit(.minutes(1)))
    func `Backgrounding stops dictation without discarding the captured text`() async throws {
        let speech = ControlledDraftSpeech()
        let model = makeModel(speech: speech)
        let capture = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe("pan en Aldi", capture: 1)
        await waitForText("pan en Aldi", in: model)

        model.setActive(false)
        await capture.value
        await waitForActivity(.idle, in: model)
        #expect(model.text == "pan en Aldi")
    }

    @Test(arguments: [
        (SpeechCaptureError.permissionDenied, "Microphone access is not allowed. You can allow it in Settings or enter products manually."),
        (.unavailable, "Transcription is unavailable on this device. You can type the text or add products manually."),
        (.unsupportedLocale, "Transcription is unavailable in the selected language on this device. You can type the text or add products manually.")
    ])
    func `Capture failures explain the recovery and preserve manual draft review`(
        error: SpeechCaptureError, expectedMessage: String
    ) async throws {
        let speech = ControlledDraftSpeech(startError: error)
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
        var notice = try #require(model.notice)
        notice.locale = Locale(identifier: "en")
        #expect(String(localized: notice) == expectedMessage)
        model.reviewDraft()

        #expect(model.activity == .idle)
        #expect(model.text == "añadir también café molido")
        let prepared = try #require(model.preparedItems)
        #expect(prepared.map(\.id) == [corrected.id])
        #expect(prepared.map(\.name) == ["leche sin lactosa"])
        #expect(prepared.map(\.quantity) == ["3 briks"])
        #expect(prepared.map(\.store) == ["Día Norte"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Finishing recognized speech automatically appends an editable summary exactly once`() async throws {
        let speech = ControlledDraftSpeech()
        let interpreter = RecordingDraftInterpreter()
        let original = ShoppingDraftItem(name: "Coffee", store: "Aldi")
        let model = ShoppingDraftViewModel(
            interpreter: interpreter,
            speech: speech,
            persistence: MemoryDraftPersistence(),
            initialDraft: ShoppingDraftSnapshot(items: [original])
        )
        let capture = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe("bread and beer at Mercadona", capture: 1)
        let finishing = model.finishDictation()
        await speech.waitForFinishCalls(1)
        try await speech.completeFinish(call: 1)
        await finishing.value
        await capture.value

        #expect(interpreter.inputs == ["bread and beer at Mercadona"])
        #expect(model.items.map(\.name) == ["Coffee", "Bread", "Beer"])
        #expect(model.items.first == original)
        #expect(model.activity == .idle)
        let proposal = try #require(model.interpretationProposal)
        #expect(proposal.snapshot.items.map(\.name) == ["Bread", "Beer"])
        await model.finishDictation().value
        #expect(interpreter.inputs.count == 1)
        #expect(model.items.count == 3)
        #expect(model.interpretationProposal == proposal)
        let nextCapture = model.startDictation()
        await waitForActivity(.recording, in: model)
        #expect(model.takeInterpretationProposal(id: proposal.id) == nil)
        await model.cancelDictation().value
        await nextCapture.value
        #expect(model.items.map(\.name) == ["Coffee", "Bread", "Beer"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Replacing a failed dictation interprets only the new phrase and permits a new confirmed intent`() async throws {
        let speech = ControlledDraftSpeech()
        let interpreter = RecordingDraftInterpreter(firstError: .noProducts)
        let persistence = MemoryDraftPersistence()
        let model = ShoppingDraftViewModel(
            interpreter: interpreter,
            speech: speech,
            persistence: persistence,
            initialDraft: ShoppingDraftSnapshot()
        )
        let phrases = ["what is the weather", "bread and beer at Mercadona", "bread and beer at Mercadona"]
        for (index, phrase) in phrases.enumerated() {
            let capture = model.startDictation(replacingText: true)
            await waitForActivity(.recording, in: model)
            try await speech.transcribe(phrase, capture: index + 1)
            await waitForText(phrase, in: model)
            let finish = model.finishDictation()
            await speech.waitForFinishCalls(index + 1)
            try await speech.completeFinish(call: index + 1)
            await finish.value
            await capture.value
            if index == 0 {
                #expect(model.notice != nil)
                #expect(model.showsShoppingText)
                #expect(model.showsManualEntry)
                #expect(model.items.isEmpty)
                #expect(model.interpretationProposal == nil)
                model.dismissNotice()
            } else {
                let proposal = try #require(model.interpretationProposal)
                #expect(proposal.snapshot.text == "bread and beer at Mercadona")
                #expect(model.items.map(\.name) == ["Bread", "Beer"])
                if index == 1 {
                    let submitted = try #require(model.takeInterpretationProposal(id: proposal.id))
                    #expect(await model.consumeConfirmedItems(submitted.items))
                    #expect(!model.showsRecoveryControls)
                }
            }
        }
        await model.flushPersistence()
        #expect(interpreter.inputs == phrases)
        #expect(model.items.count == 2)
        #expect(model.notice == nil)
        let saved = try #require(try await persistence.load())
        #expect(saved.text == "bread and beer at Mercadona")
        #expect(saved.items.map(\.name) == ["Bread", "Beer"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `A microphone failure from clean entry exposes text and manual recovery`() async throws {
        let model = ShoppingDraftViewModel(
            interpreter: RecordingDraftInterpreter(),
            speech: ControlledDraftSpeech(startError: .permissionDenied),
            persistence: MemoryDraftPersistence(),
            initialDraft: ShoppingDraftSnapshot()
        )
        #expect(!model.showsManualEntry)

        await model.startDictation(replacingText: true).value

        #expect(model.notice != nil)
        #expect(model.showsShoppingText)
        #expect(model.showsManualEntry)
        model.dismissNotice()
        model.text = "bread and beer at Mercadona"
        await model.interpretText().value
        #expect(model.interpretationProposal?.snapshot.items.map(\.name) == ["Bread", "Beer"])
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["", "   "])
    func `Silent capture never interprets earlier typed text`(transcript: String) async throws {
        let speech = ControlledDraftSpeech()
        let interpreter = RecordingDraftInterpreter()
        let model = ShoppingDraftViewModel(
            interpreter: interpreter,
            speech: speech,
            persistence: MemoryDraftPersistence(),
            initialDraft: ShoppingDraftSnapshot(text: "old unsent shopping text")
        )
        let capture = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe(transcript, capture: 1)
        let finishing = model.finishDictation()
        await speech.waitForFinishCalls(1)
        try await speech.completeFinish(call: 1)
        await finishing.value
        await capture.value

        #expect(interpreter.inputs.isEmpty)
        #expect(model.items.isEmpty)
        #expect(model.text.hasPrefix("old unsent shopping text"))
        #expect(model.notice != nil)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `A finish completing after cancellation or leaving Add never starts interpretation`(background: Bool) async throws {
        let speech = ControlledDraftSpeech()
        let interpreter = RecordingDraftInterpreter()
        let model = ShoppingDraftViewModel(
            interpreter: interpreter,
            speech: speech,
            persistence: MemoryDraftPersistence(),
            initialDraft: ShoppingDraftSnapshot()
        )
        let capture = model.startDictation()
        await waitForActivity(.recording, in: model)
        try await speech.transcribe("bread and beer at Mercadona", capture: 1)
        await waitForText("bread and beer at Mercadona", in: model)
        let finishing = model.finishDictation()
        await speech.waitForFinishCalls(1)
        if background {
            model.setActive(false)
        } else {
            await model.cancelDictation().value
        }
        await capture.value
        try await speech.completeFinish(call: 1)
        await finishing.value

        #expect(interpreter.inputs.isEmpty)
        #expect(model.items.isEmpty)
        #expect(model.text == (background ? "bread and beer at Mercadona" : ""))
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

actor ControlledDraftSpeech: SpeechCapturing {
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

@MainActor
private final class RecordingDraftInterpreter: DraftInterpreting {
    let availability = DraftInterpretationAvailability.available
    private(set) var inputs: [String] = []
    private let firstError: DraftInterpretationError?

    init(firstError: DraftInterpretationError? = nil) {
        self.firstError = firstError
    }

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        inputs.append(text)
        if inputs.count == 1, let firstError {
            throw firstError
        }
        return [
            SuggestedProduct(name: "Bread", quantity: nil, store: "Mercadona"),
            SuggestedProduct(name: "Beer", quantity: "2", store: "Mercadona")
        ]
    }
}
