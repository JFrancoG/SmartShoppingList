import Foundation
import Testing
@testable import SmartShoppingList

@MainActor
@Suite(.tags(.fast))
struct ShoppingDraftViewModelTests {
    @Test
    func `A human correction discards an interpretation that finishes later`() async throws {
        let original = item(1, name: "leche", quantity: "1 litro", store: "Mercadona")
        let interpreter = ControlledDraftInterpreter()
        let model = makeModel(interpreter: interpreter, items: [original])
        model.text = "leche y pan en Mercadona"

        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        model.beginEditingItem(original)
        model.editorItem.name = "leche sin lactosa"
        model.editorItem.quantity = "3 briks"
        model.editorItem.store = "Día Norte"
        model.saveEditor()
        try interpreter.succeed([SuggestedProduct(name: "pan", quantity: nil, store: "Mercadona")])
        await task.value
        model.reviewDraft()

        let prepared = try #require(model.preparedItems)
        #expect(prepared.map(\.id) == [identifier(1)])
        #expect(prepared.map(\.name) == ["leche sin lactosa"])
        #expect(prepared.map(\.quantity) == ["3 briks"])
        #expect(prepared.map(\.store) == ["Día Norte"])
    }

    @Test
    func `A successful interpretation appends to previously corrected products`() async throws {
        let corrected = item(1, name: "leche sin lactosa", quantity: "3 briks", store: "Día Norte")
        let interpreter = ControlledDraftInterpreter()
        let persistence = ViewModelDraftPersistence()
        let model = makeModel(interpreter: interpreter, persistence: persistence, items: [corrected])
        model.text = "pan integral y dos manzanas en Mercadona"

        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([
            SuggestedProduct(name: "pan integral", quantity: nil, store: "Mercadona"),
            SuggestedProduct(name: "manzanas", quantity: "dos", store: "Mercadona")
        ])
        await task.value
        model.reviewDraft()
        await model.flushPersistence()

        let prepared = try #require(model.preparedItems)
        #expect(prepared.map(\.name) == ["leche sin lactosa", "pan integral", "manzanas"])
        #expect(prepared.map(\.quantity) == ["3 briks", nil, "dos"])
        #expect(prepared.map(\.store) == ["Día Norte", "Mercadona", "Mercadona"])
        #expect(prepared.first?.id == identifier(1))
        let saved = try #require(await persistence.load())
        #expect(saved.items.map(\.name) == ["leche sin lactosa", "pan integral", "manzanas"])
    }

    @Test
    func `An interpretation failure preserves both the draft and the original text`() async throws {
        let existing = item(1)
        let interpreter = ControlledDraftInterpreter()
        let persistence = ViewModelDraftPersistence()
        let model = makeModel(interpreter: interpreter, persistence: persistence, items: [existing])
        model.text = "añade peras y café del supermercado que te dije"

        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.fail(.failed)
        await task.value
        await model.flushPersistence()

        #expect(model.items == [existing])
        #expect(model.text == "añade peras y café del supermercado que te dije")
        let saved = try #require(await persistence.load())
        #expect(saved.items == [existing])
        #expect(saved.text == "añade peras y café del supermercado que te dije")
    }

    @Test
    func `An ineligible device still supports manual correction and complete review`() async throws {
        let interpreter = ControlledDraftInterpreter(availability: .deviceNotEligible)
        let model = makeModel(interpreter: interpreter)
        model.text = "café en Mercadona"
        await model.interpretText().value

        model.beginAddingItem()
        model.editorItem.name = "café molido"
        model.editorItem.quantity = "250 g"
        model.editorItem.store = "Mercadona"
        model.saveEditor()
        let added = try #require(model.items.first)
        model.beginEditingItem(added)
        model.editorItem.quantity = ""
        model.editorItem.store = "Día Centro"
        model.saveEditor()
        model.reviewDraft()

        let prepared = try #require(model.preparedItems)
        #expect(prepared.map(\.name) == ["café molido"])
        #expect(prepared.map(\.quantity) == [nil])
        #expect(prepared.map(\.store) == ["Día Centro"])
    }

    @Test
    func `A cancelled result cannot replace a newer interpretation`() async throws {
        let existing = item(1)
        let interpreter = ControlledDraftInterpreter()
        let model = makeModel(interpreter: interpreter, items: [existing])
        model.text = "arroz en Mercadona"
        let firstTask = model.interpretText()
        await interpreter.waitForCalls(1)

        model.cancelInterpretation()
        model.text = "peras en Día"
        let secondTask = model.interpretText()
        await interpreter.waitForCalls(2)
        try interpreter.succeed([SuggestedProduct(name: "arroz", quantity: nil, store: "Mercadona")], call: 1)
        await firstTask.value
        try interpreter.succeed([SuggestedProduct(name: "peras", quantity: "2", store: "Día")], call: 2)
        await secondTask.value
        model.reviewDraft()

        let prepared = try #require(model.preparedItems)
        #expect(prepared.map(\.name) == ["pan integral", "peras"])
        #expect(prepared.map(\.quantity) == ["1 barra", "2"])
        #expect(prepared.map(\.store) == ["Mercadona", "Día"])
    }

    @Test
    func `An interpretation exceeding fifty total products is rejected atomically`() async throws {
        let existing = (1...49).map { item(UInt8($0)) }
        let interpreter = ControlledDraftInterpreter()
        let model = makeModel(interpreter: interpreter, items: existing)
        model.text = "dos productos más: arroz y peras en Día"

        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([
            SuggestedProduct(name: "arroz", quantity: nil, store: "Día"),
            SuggestedProduct(name: "peras", quantity: nil, store: "Día")
        ])
        await task.value

        #expect(model.items == existing)
        #expect(model.text == "dos productos más: arroz y peras en Día")
        #expect(model.notice != nil)
    }

    private func makeModel(
        interpreter: ControlledDraftInterpreter,
        persistence: ViewModelDraftPersistence = ViewModelDraftPersistence(),
        items: [ShoppingDraftItem] = []
    ) -> ShoppingDraftViewModel {
        ShoppingDraftViewModel(
            interpreter: interpreter,
            speech: ViewModelUnavailableSpeech(),
            persistence: persistence,
            initialDraft: ShoppingDraftSnapshot(items: items)
        )
    }

    private func item(
        _ number: UInt8,
        name: String = "pan integral",
        quantity: String = "1 barra",
        store: String = "Mercadona"
    ) -> ShoppingDraftItem {
        ShoppingDraftItem(
            id: identifier(number),
            name: name,
            quantity: quantity,
            store: store
        )
    }

    private func identifier(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }
}

@MainActor
private final class ControlledDraftInterpreter: DraftInterpreting {
    let availability: DraftInterpretationAvailability
    private var callCount = 0
    private var responses: [Int: CheckedContinuation<[SuggestedProduct], any Error>] = [:]
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(availability: DraftInterpretationAvailability = .available) {
        self.availability = availability
    }

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        guard availability == .available else { throw DraftInterpretationError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            callCount += 1
            responses[callCount] = continuation
            let readyWaiters = startWaiters.filter { $0.count <= callCount }
            startWaiters.removeAll { $0.count <= callCount }
            for waiter in readyWaiters {
                waiter.continuation.resume()
            }
        }
    }

    func waitForCalls(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count: count, continuation: continuation))
        }
    }

    func succeed(_ products: [SuggestedProduct], call: Int = 1) throws {
        let pending = responses.removeValue(forKey: call)
        let response = try #require(pending)
        response.resume(returning: products)
    }

    func fail(_ error: DraftInterpretationError, call: Int = 1) throws {
        let pending = responses.removeValue(forKey: call)
        let response = try #require(pending)
        response.resume(throwing: error)
    }
}

private actor ViewModelDraftPersistence: DraftPersisting {
    private var snapshot: ShoppingDraftSnapshot?

    func load() -> ShoppingDraftSnapshot? { snapshot }

    func save(_ draft: ShoppingDraftSnapshot) {
        snapshot = draft
    }
}

private actor ViewModelUnavailableSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }

    func finish() async throws {}
    func cancel() async {}
}
