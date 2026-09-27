import Foundation
import Observation
import Testing
@testable import SmartShoppingList

@MainActor
@Suite(.tags(.fast))
struct DraftIntentTests {
    @Test(arguments: [false, true])
    func `An intent preserves existing work and accepts equal products with different request identities`(
        coldStart: Bool
    ) async throws {
        let existing = ShoppingDraftItem(name: "pan corregido", quantity: "2 barras", store: "Día Norte")
        let draft = ShoppingDraftSnapshot(text: "  acordarme también del café\n", items: [existing])
        let persistence = IntentDraftPersistence(snapshot: draft)
        let model = intentModel(persistence: persistence, draft: coldStart ? nil : draft)
        let first = ShoppingDraftItem(name: "  leche  entera ", quantity: " 2 briks ", store: " Aldi ")
        let second = ShoppingDraftItem(name: "leche entera", quantity: "2 briks", store: "Aldi")

        try await model.addItemFromIntent(first)
        try await model.addItemFromIntent(second)

        #expect(model.items.first == existing)
        #expect(model.items.map(\.id) == [existing.id, first.id, second.id])
        #expect(model.items.map(\.name) == ["pan corregido", "leche entera", "leche entera"])
        #expect(model.items.map(\.quantity) == ["2 barras", "2 briks", "2 briks"])
        #expect(model.items.map(\.store) == ["Día Norte", "Aldi", "Aldi"])
        #expect(model.text == "  acordarme también del café\n")
        #expect(model.showsDraftReview)
        #expect(!model.isReceivingIntent)
        let saved = try #require(await persistence.load())
        #expect(saved.items == model.items)
        #expect(saved.text == "  acordarme también del café\n")
        #expect(saved.intentRequestIDs == [first.id, second.id])
    }

    @Test(.timeLimit(.minutes(1)))
    func `An intent joins an unfinished UI load and rejects a concurrent addition`() async throws {
        let existing = ShoppingDraftItem(name: "café", quantity: "", store: "Lidl")
        let draft = ShoppingDraftSnapshot(text: "lista pendiente", items: [existing])
        let persistence = IntentDraftPersistence(snapshot: draft, suspendsLoad: true)
        let model = intentModel(persistence: persistence)
        let uiLoad = Task { await model.load() }
        await persistence.waitForLoad()
        let request = ShoppingDraftItem(name: "leche", quantity: "1 litro", store: "Aldi")
        let addition = Task { try await model.addItemFromIntent(request) }
        for await receiving in Observations({ model.isReceivingIntent }) {
            if receiving {
                break
            }
        }

        await #expect(throws: DraftIntentError.busy) {
            try await model.addItemFromIntent(ShoppingDraftItem(name: "arroz", store: "Día"))
        }
        #expect(model.items.isEmpty)
        #expect(!model.canAddItem)
        await persistence.finishLoading()
        await uiLoad.value
        #expect(try await addition.value)

        #expect(await persistence.loadCount == 1)
        #expect(model.items == [existing, request])
        #expect(model.text == "lista pendiente")
        #expect(!model.isReceivingIntent)
        #expect(await persistence.load()?.items == [existing, request])
    }

    @Test(arguments: InvalidIntentInput.allCases)
    func `Invalid shortcut input leaves the current and saved draft unchanged`(input: InvalidIntentInput) async throws {
        let existing = ShoppingDraftItem(name: "pan", store: "Aldi")
        let draft = ShoppingDraftSnapshot(text: "leche pendiente", items: [existing])
        let persistence = IntentDraftPersistence(snapshot: draft)
        let model = intentModel(persistence: persistence, draft: draft)

        await #expect(throws: DraftValidationError.self) {
            try await model.addItemFromIntent(input.item)
        }

        #expect(model.items == [existing])
        #expect(model.text == "leche pendiente")
        #expect(!model.isReceivingIntent)
        #expect(await persistence.load() == draft)
    }

    @Test(arguments: [49, 50])
    func `The fiftieth product accepts exact field limits and a fifty first product changes nothing`(
        existingCount: Int
    ) async throws {
        let rows = (0..<existingCount).map { ShoppingDraftItem(name: "producto \($0)", store: "Aldi") }
        let draft = ShoppingDraftSnapshot(text: "texto pendiente", items: rows)
        let persistence = IntentDraftPersistence(snapshot: draft)
        let model = intentModel(persistence: persistence, draft: draft)
        let request = ShoppingDraftItem(
            name: String(repeating: "n", count: 60),
            quantity: String(repeating: "q", count: 80),
            store: String(repeating: "s", count: 40)
        )

        if existingCount == 49 {
            try await model.addItemFromIntent(request)
            #expect(model.items == rows + [request])
            #expect(await persistence.load()?.items == rows + [request])
        } else {
            await #expect(throws: DraftValidationError.tooManyItems) {
                try await model.addItemFromIntent(request)
            }
            #expect(model.items == rows)
            #expect(await persistence.load() == draft)
        }
        #expect(model.text == "texto pendiente")
    }

    @Test(.timeLimit(.minutes(1)), arguments: OccupiedIntentDraft.allCases)
    func `A shortcut cannot interrupt an editor interpretation or pending proposal`(
        occupied: OccupiedIntentDraft
    ) async throws {
        let existing = ShoppingDraftItem(name: "pan", store: "Aldi")
        let persistence = IntentDraftPersistence()
        let interpreter = IntentDraftInterpreter()
        let model = intentModel(
            persistence: persistence,
            draft: ShoppingDraftSnapshot(text: "leche en Lidl", items: [existing]),
            interpreter: interpreter
        )
        var interpretation: Task<Void, Never>?
        switch occupied {
        case .editor, .dismissingEditor:
            model.beginEditingItem(existing)
            model.editorItem.name = "corrección sin guardar"
            if occupied == .dismissingEditor {
                model.cancelEditor()
            }
        case .interpreting, .proposal:
            interpretation = model.interpretText()
            await interpreter.waitForCall()
            if occupied == .proposal {
                interpreter.finish()
                await interpretation?.value
            }
        }
        await model.flushPersistence()
        let previousItems = model.items
        let previousEditor = model.editorItem
        let previousProposal = model.interpretationProposal
        let previousStored = await persistence.load()

        await #expect(throws: DraftIntentError.busy) {
            try await model.addItemFromIntent(ShoppingDraftItem(name: "arroz", store: "Día"))
        }

        #expect(model.items == previousItems)
        #expect(model.editorItem == previousEditor)
        #expect(model.interpretationProposal == previousProposal)
        #expect(model.text == "leche en Lidl")
        #expect(await persistence.load() == previousStored)
        if occupied == .interpreting {
            interpreter.finish()
            await interpretation?.value
        }
    }

    @Test
    func `A failed save keeps a visible row and retrying its request persists it only once`() async throws {
        let existing = ShoppingDraftItem(name: "pan", store: "Aldi")
        let draft = ShoppingDraftSnapshot(text: "añadir leche", items: [existing])
        let persistence = IntentDraftPersistence(snapshot: draft, failsSaving: true)
        let model = intentModel(persistence: persistence, draft: draft)
        let request = ShoppingDraftItem(name: "leche", quantity: "2", store: "Lidl")

        await #expect(throws: DraftIntentError.saveFailed) {
            try await model.addItemFromIntent(request)
        }

        #expect(model.items == [existing, request])
        #expect(model.persistenceNotice != nil)
        #expect(!model.isReceivingIntent)
        #expect(await persistence.load() == draft)
        await persistence.allowSaving()
        try await model.addItemFromIntent(request)

        #expect(model.items == [existing, request])
        #expect(model.persistenceNotice == nil)
        let saved = try #require(await persistence.load())
        #expect(saved.items == [existing, request])
        #expect(saved.text == "añadir leche")
        #expect(saved.intentRequestIDs == [request.id])
    }

    @Test(.timeLimit(.minutes(1)))
    func `An intent waits behind an earlier UI save until the latest corrected draft is persisted`() async throws {
        let existing = ShoppingDraftItem(name: "pan", quantity: "1", store: "Aldi")
        let persistence = IntentQueuedPersistence()
        let model = intentModel(persistence: persistence, draft: ShoppingDraftSnapshot(items: [existing]))
        model.beginEditingItem(existing)
        model.editorItem.name = "pan integral"
        model.editorItem.quantity = "3 barras"
        let corrected = try #require(model.saveEditor())
        model.editorPresentationDidDismiss()
        await persistence.waitForSave(1)
        model.text = "también falta fruta"
        let request = ShoppingDraftItem(name: "leche", quantity: "2", store: "Lidl")
        var returned = false
        let addition = Task {
            let added = try await model.addItemFromIntent(request)
            returned = true
            return added
        }
        for await receiving in Observations({ model.isReceivingIntent }) {
            if receiving {
                break
            }
        }

        #expect(!returned)
        #expect(await persistence.load() == nil)
        await persistence.finishSave(1)
        await persistence.waitForSave(2)

        #expect(!returned)
        #expect(model.isReceivingIntent)
        #expect(await persistence.load()?.items == [corrected])
        await persistence.finishSave(2)
        #expect(try await addition.value)

        let saved = try #require(await persistence.load())
        #expect(saved.items == [corrected, request])
        #expect(saved.text == "también falta fruta")
        #expect(model.items == [corrected, request])
        #expect(!model.isReceivingIntent)
    }
}

@MainActor
@Suite(.tags(.integration))
struct DraftIntentPersistenceTests {
    @Test(arguments: [false, true])
    func `A legacy draft retains request identity across relaunch even after confirmed consumption`(
        consumed: Bool
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DraftIntentTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "draft.json")
        try Data(#"{"text":"","items":[]}"#.utf8).write(to: fileURL)
        let model = intentModel(persistence: FileDraftPersistence(fileURL: fileURL))
        let request = ShoppingDraftItem(name: "leche", store: "Lidl")
        try await model.addItemFromIntent(request)
        if consumed {
            #expect(await model.consumeConfirmedItems([request]))
        }

        let restored = intentModel(persistence: FileDraftPersistence(fileURL: fileURL))
        try await restored.addItemFromIntent(request)

        let expected = consumed ? [] : [request]
        #expect(restored.items == expected)
        let disk = try #require(try await FileDraftPersistence(fileURL: fileURL).load())
        #expect(disk.items == expected)
        #expect(disk.intentRequestIDs == [request.id])
    }

    @Test
    func `An unreadable draft rejects the shortcut and preserves the original file`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DraftIntentTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appending(path: "draft.json")
        let original = Data(#"{"text":"compra anterior","items":["#.utf8)
        try original.write(to: fileURL)
        let model = intentModel(persistence: FileDraftPersistence(fileURL: fileURL))

        await #expect(throws: DraftIntentError.storageUnavailable) {
            try await model.addItemFromIntent(ShoppingDraftItem(name: "leche", store: "Lidl"))
        }

        #expect(model.items.isEmpty)
        #expect(!model.isReceivingIntent)
        #expect(model.persistenceNotice != nil)
        #expect(try Data(contentsOf: fileURL) == original)
    }
}

enum InvalidIntentInput: CaseIterable {
    case missingName, missingStore, longName, longQuantity, longStore, controlCharacter

    var item: ShoppingDraftItem {
        var item = ShoppingDraftItem(name: "leche", quantity: "2", store: "Aldi")
        switch self {
        case .missingName: item.name = " \n "
        case .missingStore: item.store = " \t "
        case .longName: item.name = String(repeating: "n", count: 61)
        case .longQuantity: item.quantity = String(repeating: "q", count: 81)
        case .longStore: item.store = String(repeating: "s", count: 41)
        case .controlCharacter: item.name = "leche\u{0000}"
        }
        return item
    }
}

enum OccupiedIntentDraft: CaseIterable {
    case editor, dismissingEditor, interpreting, proposal
}

@MainActor
private func intentModel(
    persistence: any DraftPersisting,
    draft: ShoppingDraftSnapshot? = nil,
    interpreter: IntentDraftInterpreter = IntentDraftInterpreter()
) -> ShoppingDraftViewModel {
    ShoppingDraftViewModel(
        interpreter: interpreter,
        speech: IntentUnavailableSpeech(),
        persistence: persistence,
        initialDraft: draft
    )
}

private actor IntentDraftPersistence: DraftPersisting {
    private var snapshot: ShoppingDraftSnapshot?
    private var suspendsLoad: Bool
    private var failsSaving: Bool
    private(set) var loadCount = 0
    private var pendingLoads: [CheckedContinuation<ShoppingDraftSnapshot?, Never>] = []
    private var loadWaiter: CheckedContinuation<Void, Never>?

    init(snapshot: ShoppingDraftSnapshot? = nil, suspendsLoad: Bool = false, failsSaving: Bool = false) {
        self.snapshot = snapshot
        self.suspendsLoad = suspendsLoad
        self.failsSaving = failsSaving
    }

    func load() async -> ShoppingDraftSnapshot? {
        loadCount += 1
        guard suspendsLoad else { return snapshot }
        return await withCheckedContinuation { response in
            pendingLoads.append(response)
            loadWaiter?.resume()
            loadWaiter = nil
        }
    }

    func save(_ draft: ShoppingDraftSnapshot) throws {
        guard !failsSaving else { throw DraftPersistenceError.writeFailed }
        snapshot = draft
    }

    func waitForLoad() async {
        guard pendingLoads.isEmpty else { return }
        await withCheckedContinuation { loadWaiter = $0 }
    }

    func finishLoading() {
        suspendsLoad = false
        for pending in pendingLoads {
            pending.resume(returning: snapshot)
        }
        pendingLoads = []
    }

    func allowSaving() {
        failsSaving = false
    }
}

@MainActor
private final class IntentDraftInterpreter: DraftInterpreting {
    let availability = DraftInterpretationAvailability.available
    private var response: CheckedContinuation<[SuggestedProduct], Never>?
    private var callWaiter: CheckedContinuation<Void, Never>?

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        await withCheckedContinuation { response in
            self.response = response
            callWaiter?.resume()
            callWaiter = nil
        }
    }

    func waitForCall() async {
        guard response == nil else { return }
        await withCheckedContinuation { callWaiter = $0 }
    }

    func finish() {
        response?.resume(returning: [SuggestedProduct(name: "leche", quantity: nil, store: "Lidl")])
        response = nil
    }
}

private actor IntentUnavailableSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }

    func finish() async throws {}
    func cancel() async {}
}

private actor IntentQueuedPersistence: DraftPersisting {
    private var snapshot: ShoppingDraftSnapshot?
    private var saveCount = 0
    private var saves: [Int: CheckedContinuation<Void, Never>] = [:]
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]

    func load() -> ShoppingDraftSnapshot? { snapshot }

    func save(_ draft: ShoppingDraftSnapshot) async {
        saveCount += 1
        let call = saveCount
        await withCheckedContinuation { response in
            saves[call] = response
            arrivals.removeValue(forKey: call)?.resume()
        }
        snapshot = draft
    }

    func waitForSave(_ call: Int) async {
        guard saves[call] == nil else { return }
        await withCheckedContinuation { arrivals[call] = $0 }
    }

    func finishSave(_ call: Int) {
        saves.removeValue(forKey: call)?.resume()
    }
}
