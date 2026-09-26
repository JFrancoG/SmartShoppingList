import Foundation
import Testing
@testable import SmartShoppingList

@MainActor
@Suite(.tags(.fast))
struct ShoppingDraftViewModelTests {
    @Test(arguments: [(DraftField.name, 60), (.quantity, 80), (.store, 40)])
    func `An overlong editor field stays intact with an inline error until corrected`(
        field: DraftField,
        limit: Int
    ) throws {
        let model = makeModel(interpreter: ControlledDraftInterpreter())
        model.beginAddingItem()
        model.editorItem.name = "Bread"
        model.editorItem.quantity = "2"
        model.editorItem.store = "Aldi"
        let accepted = String(repeating: "a", count: limit)
        switch field {
        case .name: model.editorItem.name = accepted + "a"
        case .quantity: model.editorItem.quantity = accepted + "a"
        case .store: model.editorItem.store = accepted + "a"
        }
        let entered = model.editorItem
        #expect(model.editorHasLengthIssue)
        var message = try #require(model.editorLengthMessage(for: field))
        message.locale = Locale(identifier: "es")
        let expectedMessage = switch field {
        case .name: "Nombre del producto: máximo 60 caracteres."
        case .quantity: "Cantidad: máximo 80 caracteres."
        case .store: "Nombre de la tienda: máximo 40 caracteres."
        }
        #expect(String(localized: message) == expectedMessage)

        #expect(model.saveEditor() == nil)

        #expect(model.editorItem == entered)
        #expect(model.items.isEmpty)
        #expect(model.presentedEditorNotice == nil)
        switch field {
        case .name: model.editorItem.name = accepted
        case .quantity: model.editorItem.quantity = accepted
        case .store: model.editorItem.store = accepted
        }
        #expect(!model.editorHasLengthIssue)
        #expect(model.editorLengthMessage(for: field) == nil)
        let corrected = model.editorItem

        model.saveEditor()

        #expect(model.items == [corrected])
        #expect(!model.isEditorPresented)
    }

    @Test
    func `Restoring an older long draft preserves it for correction instead of truncating it`() async throws {
        let legacy = item(1, name: String(repeating: "n", count: 160), store: String(repeating: "s", count: 80))
        let persistence = ViewModelDraftPersistence()
        await persistence.save(ShoppingDraftSnapshot(items: [legacy]))
        let model = ShoppingDraftViewModel(
            interpreter: ControlledDraftInterpreter(),
            speech: ViewModelUnavailableSpeech(),
            persistence: persistence
        )

        await model.load()
        model.beginEditingItem(legacy)

        #expect(model.editorItem == legacy)
        #expect(model.editorLengthMessage(for: .name) != nil)
        #expect(model.editorLengthMessage(for: .store) != nil)
        #expect(model.showsRecoveryControls)
        #expect(model.showsDraftReview)
        #expect(model.saveEditor() == nil)
        model.cancelEditor()
        await model.flushPersistence()
        #expect(model.items == [legacy])
        #expect(await persistence.load()?.items == [legacy])
    }

    @Test
    func `Dismissing an editor error preserves fields and allows another invalid attempt`() throws {
        let model = makeModel(interpreter: ControlledDraftInterpreter(), items: [item(1)])
        model.beginAddingItem()
        model.editorItem.name = "Bread"
        model.editorItem.store = ""
        model.saveEditor()
        let snapshot = ShoppingNotice(source: .editor, message: try #require(model.editorError))
        let fields = model.editorItem
        model.dismissPresentedNotice(snapshot)
        #expect(model.editorError == nil)
        #expect(model.isEditorPresented)
        #expect(model.editorItem == fields)
        #expect(model.items == [item(1)])
        model.saveEditor()
        #expect(model.editorError != nil)
        model.editorItem.store = "Aldi"
        model.saveEditor()
        #expect(model.items.map(\.name).contains("Bread"))
        #expect(!model.isEditorPresented)
    }

    @Test
    func `Dismissing an old editor alert does not clear a newer validation error`() throws {
        let model = makeModel(interpreter: ControlledDraftInterpreter(), items: [])
        model.beginAddingItem()
        model.saveEditor()
        let old = ShoppingNotice(source: .editor, message: try #require(model.editorError))
        model.editorItem.name = "Bread"
        model.saveEditor()
        let current = ShoppingNotice(source: .editor, message: try #require(model.editorError))
        #expect(old != current)
        model.dismissPresentedNotice(old)
        #expect(model.editorError == current.message)
        model.dismissPresentedNotice(current)
        #expect(model.editorError == nil)
        #expect(model.editorItem.name == "Bread")
        #expect(model.items.isEmpty)
    }

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
        #expect(model.interpretationProposal == nil)
        #expect(model.showsRecoveryControls)
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
        let proposal = try #require(model.interpretationProposal)
        #expect(proposal.snapshot.items.map(\.name) == ["pan integral", "manzanas"])
        #expect(!proposal.snapshot.items.contains { $0.id == corrected.id })
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

    @Test(arguments: [DraftInterpretationError.failed, .noProducts, .refused])
    func `An interpretation failure preserves both the draft and the original text`(
        error: DraftInterpretationError
    ) async throws {
        let existing = item(1)
        let interpreter = ControlledDraftInterpreter()
        let persistence = ViewModelDraftPersistence()
        let model = makeModel(interpreter: interpreter, persistence: persistence, items: [existing])
        model.text = "añade peras y café del supermercado que te dije"

        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.fail(error)
        await task.value
        await model.flushPersistence()

        #expect(model.items == [existing])
        #expect(model.text == "añade peras y café del supermercado que te dije")
        #expect(model.notice != nil)
        #expect(model.interpretationProposal == nil)
        #expect(model.showsRecoveryControls)
        #expect(model.showsShoppingText)
        #expect(model.showsManualEntry)
        let saved = try #require(await persistence.load())
        #expect(saved.items == [existing])
        #expect(saved.text == "añade peras y café del supermercado que te dije")
        let restored = ShoppingDraftViewModel(
            interpreter: ControlledDraftInterpreter(),
            speech: ViewModelUnavailableSpeech(),
            persistence: persistence
        )
        await restored.load()
        #expect(restored.items == [existing])
        #expect(restored.showsShoppingText)
        #expect(restored.showsDraftReview)
        #expect(restored.interpretationProposal == nil)
    }

    @Test
    func `Model loss during interpretation explains recovery and allows retry`() async throws {
        let existing = item(1)
        let interpreter = ControlledDraftInterpreter()
        let model = makeModel(interpreter: interpreter, items: [existing])
        model.text = "dos peras en Día"

        let firstAttempt = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.fail(.unavailable)
        await firstAttempt.value

        var notice = try #require(model.notice)
        notice.locale = Locale(identifier: "es")
        #expect(String(localized: notice).contains("modelo de Apple Intelligence no está disponible"))
        #expect(model.items == [existing])
        #expect(model.text == "dos peras en Día")
        #expect(model.canInterpret)

        let retry = model.interpretText()
        await interpreter.waitForCalls(2)
        try interpreter.succeed([SuggestedProduct(name: "peras", quantity: "dos", store: "Día")], call: 2)
        await retry.value

        #expect(model.items.map(\.name) == ["pan integral", "peras"])
        #expect(model.notice == nil)
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

    @Test(.timeLimit(.minutes(1)))
    func `A confirmed interpretation clears its completed text across relaunch`() async throws {
        let interpreter = ControlledDraftInterpreter()
        let persistence = ViewModelDraftPersistence()
        let model = makeModel(interpreter: interpreter, persistence: persistence)
        #expect(!model.showsShoppingText)
        #expect(!model.showsManualEntry)
        model.text = "pan en Aldi"
        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([SuggestedProduct(name: "pan", quantity: nil, store: "Aldi")])
        await task.value
        let proposal = try #require(model.interpretationProposal)
        #expect(!model.showsDraftReview)
        #expect(!model.isEditorPresented)

        let submitted = try #require(model.takeInterpretationProposal(id: proposal.id))

        #expect(model.takeInterpretationProposal(id: proposal.id) == nil)
        #expect(model.items == submitted.items)
        #expect(model.showsDraftReview)
        #expect(await model.consumeConfirmedItems(submitted.items))
        await model.flushPersistence()
        #expect(model.items.isEmpty)
        #expect(!model.showsRecoveryControls)
        #expect(!model.showsShoppingText)
        #expect(!model.showsManualEntry)
        let saved = try #require(await persistence.load())
        #expect(saved.items.isEmpty)
        #expect(saved.text.isEmpty)
        #expect(saved.interpretedText == nil)
        let reopened = ShoppingDraftViewModel(
            interpreter: ControlledDraftInterpreter(),
            speech: ViewModelUnavailableSpeech(),
            persistence: persistence
        )
        await reopened.load()
        #expect(reopened.text.isEmpty)
        #expect(!reopened.showsShoppingText)
        #expect(!reopened.showsManualEntry)
        #expect(!reopened.canInterpret)
        reopened.revealRecoveryControls()
        #expect(reopened.shoppingText.isEmpty)
    }

    @Test(arguments: [(false, false), (true, false), (false, true)])
    func `Loading older completed text clears it but preserves unfinished work`(
        hasPendingRows: Bool,
        hasNewText: Bool
    ) async throws {
        let persistence = ViewModelDraftPersistence()
        let rows = hasPendingRows ? [item(1, name: "pan", store: "Aldi")] : []
        let source = hasNewText ? "leche en Lidl" : "pan en Aldi"
        await persistence.save(ShoppingDraftSnapshot(text: source, items: rows, interpretedText: "pan en Aldi"))
        let model = ShoppingDraftViewModel(
            interpreter: ControlledDraftInterpreter(),
            speech: ViewModelUnavailableSpeech(),
            persistence: persistence
        )

        await model.load()
        await model.flushPersistence()
        model.revealRecoveryControls()

        let expectedText = hasPendingRows || hasNewText ? source : ""
        #expect(model.shoppingText == expectedText)
        #expect(model.items == rows)
        let saved = try #require(await persistence.load())
        #expect(saved.text == expectedText)
        #expect(saved.items == rows)
        #expect(saved.interpretedText == (hasPendingRows || hasNewText ? "pan en Aldi" : nil))
    }

    @Test(arguments: [false, true], [false, true])
    func `Consuming a confirmed batch preserves remaining rows and newer text`(
        hasRemainingRows: Bool,
        hasNewText: Bool
    ) async throws {
        let persistence = ViewModelDraftPersistence()
        let confirmed = item(1, name: "pan", store: "Aldi")
        let remaining = hasRemainingRows ? [item(2, name: "arroz", store: "Lidl")] : []
        let source = hasNewText ? "peras en Mercadona" : "pan en Aldi"
        let model = ShoppingDraftViewModel(
            interpreter: ControlledDraftInterpreter(),
            speech: ViewModelUnavailableSpeech(),
            persistence: persistence,
            initialDraft: ShoppingDraftSnapshot(text: source, items: [confirmed] + remaining, interpretedText: "pan en Aldi")
        )

        #expect(await model.consumeConfirmedItems([confirmed]))

        let expectedText = hasRemainingRows || hasNewText ? source : ""
        #expect(model.items == remaining)
        #expect(model.text == expectedText)
        let saved = try #require(await persistence.load())
        #expect(saved.items == remaining)
        #expect(saved.text == expectedText)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Editing an interpretation exposes its retained rows and rejects the old confirmation`() async throws {
        let interpreter = ControlledDraftInterpreter()
        let model = makeModel(interpreter: interpreter)
        model.text = "pan en Aldi"
        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([SuggestedProduct(name: "pan", quantity: nil, store: "Aldi")])
        await task.value
        let proposal = try #require(model.interpretationProposal)

        model.editInterpretationProposal(id: proposal.id)

        #expect(model.takeInterpretationProposal(id: proposal.id) == nil)
        #expect(model.items == proposal.snapshot.items)
        #expect(model.text == "pan en Aldi")
        #expect(model.showsShoppingText)
        #expect(model.showsManualEntry)
        #expect(model.showsDraftReview)
        #expect(!model.isEditorPresented)
        model.beginEditingItem(try #require(model.items.first))
        model.editorItem.name = "pan integral"
        model.saveEditor()
        #expect(model.items.map(\.name) == ["pan integral"])
        #expect(model.interpretationProposal == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `A text correction invalidates only the previous interpretation proposal`() async throws {
        let interpreter = ControlledDraftInterpreter()
        let model = makeModel(interpreter: interpreter)
        model.text = "pan en Aldi"
        let firstTask = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([SuggestedProduct(name: "pan", quantity: nil, store: "Aldi")])
        await firstTask.value
        let first = try #require(model.interpretationProposal)

        model.text = "peras en Día"

        #expect(model.takeInterpretationProposal(id: first.id) == nil)
        let secondTask = model.interpretText()
        await interpreter.waitForCalls(2)
        try interpreter.succeed([SuggestedProduct(name: "peras", quantity: "2", store: "Día")], call: 2)
        await secondTask.value
        let second = try #require(model.interpretationProposal)
        model.editInterpretationProposal(id: first.id)
        #expect(model.interpretationProposal == second)
        #expect(model.takeInterpretationProposal(id: first.id) == nil)
        #expect(model.takeInterpretationProposal(id: second.id)?.items.map(\.name) == ["peras"])
        #expect(model.items.map(\.name) == ["peras"])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `Reinterpreting a correction replaces only untouched suggestions after a successful result`(
        manuallyEdited: Bool
    ) async throws {
        let interpreter = ControlledDraftInterpreter()
        let previous = item(1, name: "Coffee", store: "Aldi")
        let persistence = ViewModelDraftPersistence()
        let model = makeModel(interpreter: interpreter, persistence: persistence, items: [previous])
        model.text = "6 yogures en Aldi"
        let first = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([SuggestedProduct(name: "yogures", quantity: "6", store: "Aldi")])
        await first.value
        let proposal = try #require(model.interpretationProposal)
        model.editInterpretationProposal(id: proposal.id)
        if manuallyEdited {
            model.beginEditingItem(try #require(model.items.last))
            model.editorItem.quantity = "5"
            model.saveEditor()
        }
        let beforeCorrection = model.items
        model.text = "7 yogures en Aldi"
        let failed = model.interpretText()
        await interpreter.waitForCalls(2)
        try interpreter.fail(.failed, call: 2)
        await failed.value
        #expect(model.items == beforeCorrection)
        #expect(model.interpretationProposal == nil)

        let corrected = model.interpretText()
        await interpreter.waitForCalls(3)
        try interpreter.succeed([SuggestedProduct(name: "yogures", quantity: "7", store: "Aldi")], call: 3)
        await corrected.value
        await model.flushPersistence()
        let current = try #require(model.interpretationProposal)
        #expect(current.snapshot.items.map(\.quantity) == ["7"])
        #expect(model.items.first == previous)
        #expect(model.items.dropFirst().map(\.quantity) == (manuallyEdited ? ["5", "7"] : ["7"]))
        #expect(await persistence.load()?.items == model.items)
        #expect(model.takeInterpretationProposal(id: proposal.id) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `An incomplete interpretation persists editable products without offering confirmation or appending twice`() async throws {
        let interpreter = ControlledDraftInterpreter()
        let persistence = ViewModelDraftPersistence()
        let model = makeModel(interpreter: interpreter, persistence: persistence)
        model.text = "dos panes"
        let task = model.interpretText()
        await interpreter.waitForCalls(1)
        try interpreter.succeed([SuggestedProduct(name: "panes", quantity: "dos", store: nil)])
        await task.value
        await model.flushPersistence()

        #expect(model.interpretationProposal == nil)
        #expect(model.notice != nil)
        #expect(model.showsRecoveryControls)
        #expect(model.showsDraftReview)
        #expect(model.items.map(\.name) == ["panes"])
        #expect(model.items.map(\.store) == [""])
        await model.interpretText().value
        #expect(model.items.count == 1)
        let saved = try #require(await persistence.load())
        #expect(saved.items == model.items)
        #expect(saved.text == "dos panes")
        model.beginEditingItem(try #require(model.items.first))
        model.editorItem.store = "Aldi"
        model.saveEditor()
        model.reviewDraft()
        #expect(model.preparedItems?.map(\.store) == ["Aldi"])
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
