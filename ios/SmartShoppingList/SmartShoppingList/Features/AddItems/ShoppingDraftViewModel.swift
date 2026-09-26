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
            if captureID == nil && finishingID == nil {
                showsRecoveryControls = true
            }
            preparedItems = nil
            queuePersistence()
        }
    }
    private(set) var items: [ShoppingDraftItem]
    private(set) var preparedItems: [PreparedDraftItem]?
    private(set) var interpretationProposal: DraftInterpretationProposal?
    private(set) var showsRecoveryControls: Bool
    private(set) var activity = DraftActivity.idle
    private(set) var availability: DraftInterpretationAvailability
    private(set) var notice: LocalizedStringResource?
    private(set) var persistenceNotice: LocalizedStringResource?
    private(set) var hasLoaded: Bool
    var editorItem = ShoppingDraftItem()
    private(set) var isAddingItem = false
    var isEditorPresented = false {
        didSet {
            if isEditorPresented {
                isEditorPresentationActive = true
            }
        }
    }
    private(set) var isEditorPresentationActive = false
    private(set) var editorError: LocalizedStringResource?

    @ObservationIgnored private let interpreter: any DraftInterpreting
    @ObservationIgnored private let speech: any SpeechCapturing
    @ObservationIgnored private let persistence: any DraftPersisting
    @ObservationIgnored private var interpretedText: String?
    @ObservationIgnored private var revisableInterpretedItems: [ShoppingDraftItem] = []
    @ObservationIgnored private var interpretationID: UUID?
    @ObservationIgnored private var interpretationTask: Task<Void, Never>?
    @ObservationIgnored private var captureID: UUID?
    @ObservationIgnored private var textBeforeDictation: String?
    private var currentTranscript: String?
    @ObservationIgnored private var replacesDictatedText = false
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
        showsRecoveryControls = !(initialDraft?.items.isEmpty ?? true)
            || (initialDraft?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && initialDraft?.text != initialDraft?.interpretedText)
        hasLoaded = initialDraft != nil
        availability = interpreter.availability
    }

    var canInterpret: Bool {
        hasLoaded && activity == .idle && availability == .available && text != interpretedText
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canAddItem: Bool { hasLoaded && items.count < 50 }

    var showsShoppingText: Bool {
        showsRecoveryControls || activity == .preparingSpeech || activity == .recording || activity == .finishingSpeech
    }

    var shoppingText: String {
        get {
            if replacesDictatedText,
               activity == .preparingSpeech || activity == .recording || activity == .finishingSpeech {
                return currentTranscript ?? ""
            }
            return text
        }
        set { text = newValue }
    }

    var showsManualEntry: Bool { availability != .available || showsRecoveryControls }
    var showsDraftReview: Bool { !items.isEmpty && interpretationProposal == nil }

    func revealRecoveryControls() {
        showsRecoveryControls = true
    }

    func takeInterpretationProposal(id: UUID) -> ShoppingDraftSnapshot? {
        guard let proposal = interpretationProposal, proposal.id == id else { return nil }
        interpretationProposal = nil
        revisableInterpretedItems = []
        showsRecoveryControls = true
        return proposal.snapshot
    }

    func editInterpretationProposal(id: UUID) {
        guard interpretationProposal?.id == id else { return }
        interpretationProposal = nil
        showsRecoveryControls = true
    }

    var editorHasLengthIssue: Bool {
        editorLengthMessage(for: .name) != nil || editorLengthMessage(for: .quantity) != nil
            || editorLengthMessage(for: .store) != nil
    }

    func editorLengthMessage(for field: DraftField) -> LocalizedStringResource? {
        let value = switch field {
        case .name: editorItem.name
        case .quantity: editorItem.quantity
        case .store: editorItem.store
        }
        return ShoppingDraftRules.exceedsLength(value, field: field) ? ShoppingDraftRules.lengthMessage(for: field) : nil
    }

    var availabilityMessage: LocalizedStringResource {
        switch availability {
        case .available: "You can interpret the text and review the products before adding them to the group."
        case .deviceNotEligible: "This device does not support Apple Intelligence."
        case .intelligenceDisabled: "Apple Intelligence is turned off. You can turn it on in device Settings."
        case .modelNotReady: "The Apple Intelligence model is not ready yet."
        case .unsupportedLanguage: "Apple Intelligence does not support the app’s current language."
        case .unavailable: "Apple Intelligence is currently unavailable on this device."
        }
    }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        var clearedCompletedText = false
        defer {
            isLoading = false
            hasLoaded = true
            if clearedCompletedText {
                queuePersistence()
            }
        }
        do {
            if let snapshot = try await persistence.load() {
                text = snapshot.text
                items = snapshot.items
                interpretedText = snapshot.interpretedText
                clearedCompletedText = clearCompletedText()
                showsRecoveryControls = !items.isEmpty || hasUninterpretedText
            }
        } catch {
            storageBlocked = true
            showsRecoveryControls = true
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
        isAddingItem = true
        editorError = nil
        isEditorPresented = true
    }

    func beginEditingItem(_ item: ShoppingDraftItem) {
        guard hasLoaded, items.contains(where: { $0.id == item.id }) else { return }
        stopForEditing()
        editorItem = item
        isAddingItem = false
        editorError = nil
        isEditorPresented = true
    }

    @discardableResult
    func saveEditor(closeEditor: Bool = true) -> ShoppingDraftItem? {
        guard !editorHasLengthIssue else {
            editorError = nil
            return nil
        }
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
                    return nil
                }
                items.append(saved)
            }
            preparedItems = nil
            editorError = nil
            if closeEditor {
                isEditorPresented = false
            }
            queuePersistence()
            return saved
        } catch {
            editorError = Self.validationMessage(error)
            return nil
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

    var presentedNotice: ShoppingNotice? {
        if let notice {
            return ShoppingNotice(source: .draft, message: notice)
        }
        if let persistenceNotice {
            return ShoppingNotice(source: .storage, message: persistenceNotice)
        }
        return nil
    }

    var presentedEditorNotice: ShoppingNotice? {
        editorError.map { ShoppingNotice(source: .editor, message: $0) }
    }

    func editorPresentationDidDismiss() {
        isEditorPresentationActive = false
    }

    func dismissPresentedNotice(_ snapshot: ShoppingNotice) {
        switch snapshot.source {
        case .draft where notice == snapshot.message:
            notice = nil
        case .editor where editorError == snapshot.message:
            editorError = nil
        default:
            break
        }
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
        if activity == .interpreting || interpretationProposal != nil {
            showsRecoveryControls = true
        }
        interpretationProposal = nil
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
        interpretationProposal = nil
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
                let originals = Dictionary(
                    revisableInterpretedItems.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                let retained = items.filter { originals[$0.id] != $0 }
                guard retained.count + suggestions.count <= 50 else { throw DraftInterpretationError.tooManyProducts }
                let additions = suggestions.map {
                    ShoppingDraftItem(name: $0.name, quantity: $0.quantity ?? "", store: $0.store ?? "")
                }
                items = retained + additions
                revisableInterpretedItems = additions
                interpretedText = input
                preparedItems = nil
                queuePersistence()
                do {
                    _ = try ShoppingDraftRules.prepare(additions)
                    interpretationProposal = DraftInterpretationProposal(
                        snapshot: ShoppingDraftSnapshot(text: input, items: additions, interpretedText: input)
                    )
                } catch let error as DraftValidationError {
                    showsRecoveryControls = true
                    notice = Self.validationMessage(error)
                }
            } catch {
                guard interpretationID == id, !Task.isCancelled else { return }
                showsRecoveryControls = true
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
    func startDictation(replacingText: Bool = false) -> Task<Void, Never> {
        guard hasLoaded, activity == .idle else { return Task {} }
        cancelInterpretation()
        if !replacingText {
            revisableInterpretedItems = []
        }
        let id = UUID()
        let prefix = replacingText || text == interpretedText ? "" : text.trimmingCharacters(in: .whitespacesAndNewlines)
        captureID = id
        textBeforeDictation = text
        currentTranscript = nil
        replacesDictatedText = replacingText
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
                        currentTranscript = transcript
                        text = prefix.isEmpty ? transcript : prefix + "\n" + transcript
                    }
                }
            } catch {
                guard captureID == id, !Task.isCancelled else { return }
                showsRecoveryControls = true
                notice = Self.speechMessage(error)
            }
            guard captureID == id else { return }
            captureID = nil
            captureTask = nil
            if activity != .finishingSpeech {
                showsRecoveryControls = true
                textBeforeDictation = nil
                replacesDictatedText = false
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
                showsRecoveryControls = true
                notice = Self.speechMessage(error)
            }
            await task?.value
            guard finishingID == id else { return }
            finishingID = nil
            textBeforeDictation = nil
            let hasTranscript = currentTranscript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let replacingText = replacesDictatedText
            currentTranscript = nil
            replacesDictatedText = false
            activity = .idle
            guard notice == nil else { return }
            guard hasTranscript else {
                showsRecoveryControls = true
                notice = "No speech was recognized. Try again or add products manually."
                return
            }
            if replacingText {
                interpretedText = nil
                queuePersistence()
            }
            await interpretText().value
            if interpretationProposal == nil && hasUninterpretedText {
                showsRecoveryControls = true
            }
        }
    }

    @discardableResult
    func cancelDictation() -> Task<Void, Never> {
        stopDictation(discardTranscript: true)
    }

    @discardableResult
    private func stopDictation(discardTranscript: Bool) -> Task<Void, Never> {
        guard captureID != nil || finishingID != nil else { return Task {} }
        showsRecoveryControls = true
        captureID = nil
        finishingID = nil
        if discardTranscript, let textBeforeDictation {
            text = textBeforeDictation
        }
        textBeforeDictation = nil
        currentTranscript = nil
        replacesDictatedText = false
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
        revisableInterpretedItems = []
        items.removeAll { originals[$0.id] == $0 }
        preparedItems = nil
        clearCompletedText()
        queuePersistence()
        await flushPersistence()
        let saved = persistenceNotice == nil
        if saved && items.isEmpty && !hasUninterpretedText {
            showsRecoveryControls = false
        }
        return saved
    }

    @discardableResult
    private func clearCompletedText() -> Bool {
        guard items.isEmpty, text == interpretedText else { return false }
        interpretedText = nil
        text = ""
        return true
    }

    private func stopForEditing() {
        cancelInterpretation()
        showsRecoveryControls = true
        stopDictation(discardTranscript: false)
        notice = nil
    }

    private var hasUninterpretedText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != interpretedText
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
            case (_, .tooLong): return ShoppingDraftRules.lengthMessage(for: field)
            case (_, .invalidCharacters): return "This field contains unsupported control characters."
            case (.quantity, .required): return "Review the product quantity."
            }
        }
    }

    private static func interpretationMessage(_ error: any Error) -> LocalizedStringResource {
        switch error as? DraftInterpretationError {
        case .inputTooLong: "The text is too long. Interpret a shorter list; your text is kept."
        case .tooManyProducts: "The result would exceed 50 products. None were added; split the text and review the draft."
        case .noProducts: "No products were found. Edit the text, dictate again, or add products manually."
        case .refused: "This text could not be interpreted. Edit the text, dictate again, or add products manually."
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
