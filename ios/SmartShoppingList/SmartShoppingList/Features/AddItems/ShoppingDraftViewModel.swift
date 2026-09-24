import Foundation
import Observation

enum DraftActivity {
    case idle
    case interpreting
    case preparingSpeech
    case recording
    case finishingSpeech
}

@Observable @MainActor
final class ShoppingDraftViewModel {
    var text: String {
        didSet {
            guard hasLoaded, text != oldValue else { return }
            cancelInterpretation()
            preparedItems = nil
            queuePersistence()
        }
    }
    private(set) var items: [ShoppingDraftItem]
    private(set) var preparedItems: [PreparedDraftItem]?
    private(set) var activity = DraftActivity.idle
    private(set) var availability: DraftInterpretationAvailability
    private(set) var notice: LocalizedStringResource?
    private(set) var persistenceNotice: LocalizedStringResource?
    private(set) var hasLoaded: Bool
    var editorItem = ShoppingDraftItem()
    var isEditorPresented = false
    private(set) var editorError: LocalizedStringResource?

    @ObservationIgnored private let interpreter: any DraftInterpreting
    @ObservationIgnored private let speech: any SpeechCapturing
    @ObservationIgnored private let persistence: any DraftPersisting
    @ObservationIgnored private var interpretedText: String?
    @ObservationIgnored private var interpretationID: UUID?
    @ObservationIgnored private var interpretationTask: Task<Void, Never>?
    @ObservationIgnored private var captureID: UUID?
    @ObservationIgnored private var textBeforeDictation: String?
    @ObservationIgnored private var finishingID: UUID?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSnapshot: ShoppingDraftSnapshot?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var storageBlocked = false

    init(
        interpreter: any DraftInterpreting,
        speech: any SpeechCapturing,
        persistence: any DraftPersisting,
        initialDraft: ShoppingDraftSnapshot? = nil
    ) {
        self.interpreter = interpreter
        self.speech = speech
        self.persistence = persistence
        text = initialDraft?.text ?? ""
        items = initialDraft?.items ?? []
        interpretedText = initialDraft?.interpretedText
        hasLoaded = initialDraft != nil
        availability = interpreter.availability
    }

    var canInterpret: Bool {
        hasLoaded && activity == .idle && availability == .available && text != interpretedText
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canAddItem: Bool { hasLoaded && items.count < 50 }

    var availabilityMessage: LocalizedStringResource {
        switch availability {
        case .available: "You can interpret the text and review the products before adding them to the group."
        case .deviceNotEligible: "This device does not support Apple Intelligence. You can add products manually."
        case .intelligenceDisabled: "Turn on Apple Intelligence in Settings to interpret text. You can still add products manually."
        case .modelNotReady: "The model is not ready yet. You can continue manually and check again later."
        case .unsupportedLanguage: "Interpretation is unavailable in the selected language. You can continue manually."
        case .unavailable: "Interpretation is currently unavailable. You can continue manually."
        }
    }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            if let snapshot = try await persistence.load() {
                text = snapshot.text
                items = snapshot.items
                interpretedText = snapshot.interpretedText
            }
        } catch {
            storageBlocked = true
            persistenceNotice = "The saved draft could not be restored. It is kept unchanged. Changes in this session will not be saved when you close the app."
        }
    }

    func refreshAvailability() {
        availability = interpreter.availability
    }

    func beginAddingItem() {
        guard canAddItem else { return }
        stopForEditing()
        editorItem = ShoppingDraftItem()
        editorError = nil
        isEditorPresented = true
    }

    func beginEditingItem(_ item: ShoppingDraftItem) {
        guard hasLoaded, items.contains(where: { $0.id == item.id }) else { return }
        stopForEditing()
        editorItem = item
        editorError = nil
        isEditorPresented = true
    }

    func saveEditor() {
        do {
            let validated = try PreparedDraftItem(validating: editorItem)
            let saved = ShoppingDraftItem(
                id: validated.id,
                name: validated.name,
                quantity: validated.quantity ?? "",
                store: validated.store
            )
            cancelInterpretation()
            if let index = items.firstIndex(where: { $0.id == saved.id }) {
                items[index] = saved
            } else {
                guard items.count < 50 else {
                    editorError = "The draft can contain up to 50 products."
                    return
                }
                items.append(saved)
            }
            preparedItems = nil
            editorError = nil
            isEditorPresented = false
            queuePersistence()
        } catch {
            editorError = Self.validationMessage(error)
        }
    }

    func cancelEditor() {
        isEditorPresented = false
    }

    func removeItem(id: UUID) {
        cancelInterpretation()
        items.removeAll { $0.id == id }
        preparedItems = nil
        queuePersistence()
    }

    func reviewDraft() {
        cancelInterpretation()
        do {
            preparedItems = try ShoppingDraftRules.prepare(items)
            notice = nil
        } catch {
            preparedItems = nil
            notice = Self.validationMessage(error)
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func setActive(_ active: Bool) {
        if active {
            refreshAvailability()
        } else {
            cancelInterpretation()
            stopDictation(discardTranscript: false)
            Task {
                await flushPersistence()
            }
        }
    }

    func cancelInterpretation() {
        interpretationID = nil
        interpretationTask?.cancel()
        interpretationTask = nil
        if activity == .interpreting {
            activity = .idle
        }
    }

    @discardableResult
    func interpretText() -> Task<Void, Never> {
        refreshAvailability()
        guard canInterpret else { return Task {} }
        let id = UUID()
        let input = text
        interpretationID = id
        activity = .interpreting
        notice = nil
        let task = Task {
            do {
                let suggestions = try await interpreter.interpret(input)
                guard interpretationID == id, !Task.isCancelled else { return }
                guard !suggestions.isEmpty else { throw DraftInterpretationError.noProducts }
                guard items.count + suggestions.count <= 50 else { throw DraftInterpretationError.tooManyProducts }
                items.append(contentsOf: suggestions.map {
                    ShoppingDraftItem(name: $0.name, quantity: $0.quantity ?? "", store: $0.store ?? "")
                })
                interpretedText = input
                preparedItems = nil
                queuePersistence()
            } catch {
                guard interpretationID == id, !Task.isCancelled else { return }
                notice = Self.interpretationMessage(error)
                refreshAvailability()
            }
            guard interpretationID == id else { return }
            interpretationID = nil
            interpretationTask = nil
            activity = .idle
        }
        interpretationTask = task
        return task
    }

    @discardableResult
    func startDictation() -> Task<Void, Never> {
        guard hasLoaded, activity == .idle else { return Task {} }
        let id = UUID()
        let prefix = text == interpretedText ? "" : text.trimmingCharacters(in: .whitespacesAndNewlines)
        captureID = id
        textBeforeDictation = text
        activity = .preparingSpeech
        notice = nil
        let task = Task {
            do {
                let stream = try await speech.start()
                for try await event in stream {
                    guard captureID == id, !Task.isCancelled else { return }
                    switch event {
                    case .preparing: break
                    case .recording:
                        activity = .recording
                    case .transcript(let transcript):
                        text = prefix.isEmpty ? transcript : prefix + "\n" + transcript
                    }
                }
            } catch {
                guard captureID == id, !Task.isCancelled else { return }
                notice = Self.speechMessage(error)
            }
            guard captureID == id else { return }
            captureID = nil
            captureTask = nil
            if activity != .finishingSpeech {
                textBeforeDictation = nil
                activity = .idle
            }
        }
        captureTask = task
        return task
    }

    @discardableResult
    func finishDictation() -> Task<Void, Never> {
        guard activity == .recording, let id = captureID else { return Task {} }
        let task = captureTask
        finishingID = id
        activity = .finishingSpeech
        return Task {
            do {
                try await speech.finish()
            } catch {
                guard finishingID == id else { return }
                notice = Self.speechMessage(error)
            }
            await task?.value
            guard finishingID == id else { return }
            finishingID = nil
            textBeforeDictation = nil
            activity = .idle
        }
    }

    @discardableResult
    func cancelDictation() -> Task<Void, Never> {
        stopDictation(discardTranscript: true)
    }

    @discardableResult
    private func stopDictation(discardTranscript: Bool) -> Task<Void, Never> {
        guard captureID != nil || finishingID != nil else { return Task {} }
        captureID = nil
        finishingID = nil
        if discardTranscript, let textBeforeDictation {
            text = textBeforeDictation
        }
        textBeforeDictation = nil
        let task = captureTask
        captureTask = nil
        task?.cancel()
        activity = .finishingSpeech
        return Task {
            await speech.cancel()
            await task?.value
            activity = .idle
        }
    }

    func flushPersistence() async {
        await saveTask?.value
    }

    /// Remove only unchanged rows acknowledged by the server before clearing its retry envelope.
    func consumeConfirmedItems(_ confirmed: [ShoppingDraftItem]) async -> Bool {
        await load()
        await flushPersistence()
        guard !storageBlocked else { return false }
        let originals = Dictionary(confirmed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cancelInterpretation()
        items.removeAll { originals[$0.id] == $0 }
        preparedItems = nil
        queuePersistence()
        await flushPersistence()
        return persistenceNotice == nil
    }

    private func stopForEditing() {
        cancelInterpretation()
        stopDictation(discardTranscript: false)
        notice = nil
    }

    private func queuePersistence() {
        guard hasLoaded, !storageBlocked else { return }
        pendingSnapshot = ShoppingDraftSnapshot(text: text, items: items, interpretedText: interpretedText)
        guard saveTask == nil else { return }
        saveTask = Task {
            while let snapshot = pendingSnapshot {
                pendingSnapshot = nil
                do {
                    try await persistence.save(snapshot)
                    persistenceNotice = nil
                } catch {
                    persistenceNotice = "The draft could not be saved on this device. Keep the app open; we will retry with your next change."
                }
            }
            saveTask = nil
        }
    }

    private static func validationMessage(_ error: DraftValidationError) -> LocalizedStringResource {
        switch error {
        case .emptyBatch: return "Add at least one product to review the draft."
        case .tooManyItems: return "The draft can contain up to 50 products."
        case .invalidField(_, let field, let reason):
            switch (field, reason) {
            case (.name, .required): return "Enter the product name."
            case (.store, .required): return "Specify a store for each product before reviewing the draft."
            case (.name, .tooLong): return "Shorten the product name: up to 160 Unicode characters."
            case (.quantity, .tooLong): return "Shorten the quantity: up to 80 Unicode characters."
            case (.store, .tooLong): return "Shorten the store name: up to 80 Unicode characters."
            case (_, .invalidCharacters): return "This field contains unsupported control characters."
            case (.quantity, .required): return "Review the product quantity."
            }
        }
    }

    private static func interpretationMessage(_ error: any Error) -> LocalizedStringResource {
        switch error as? DraftInterpretationError {
        case .inputTooLong: "The text is too long. Interpret a shorter list; your text is kept."
        case .tooManyProducts: "The result would exceed 50 products. None were added; split the text and review the draft."
        case .noProducts: "No products were found. You can rephrase the text or add them manually."
        case .refused: "This text could not be interpreted. You can add products manually."
        case .unavailable: "The Apple Intelligence model is currently unavailable. Your draft is kept; you can retry later or continue manually."
        case .failed, .none: "The text could not be interpreted. Your draft is kept; you can retry or continue manually."
        }
    }

    private static func speechMessage(_ error: any Error) -> LocalizedStringResource {
        switch error as? SpeechCaptureError {
        case .permissionDenied: "Microphone access is not allowed. You can allow it in Settings or enter products manually."
        case .unavailable: "Transcription is unavailable on this device. You can type the text or add products manually."
        case .unsupportedLocale: "Transcription is unavailable in the selected language on this device. You can type the text or add products manually."
        case .microphoneUnavailable: "No microphone is available. You can continue manually."
        default: "Recording was interrupted. The recognized text is kept; you can continue manually or dictate again."
        }
    }
}
