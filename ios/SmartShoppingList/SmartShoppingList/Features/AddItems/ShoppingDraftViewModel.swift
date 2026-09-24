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
        case .available: "Puedes interpretar el texto y revisar los productos antes de añadirlos al grupo."
        case .deviceNotEligible: "Este dispositivo no admite Apple Intelligence. Puedes añadir los productos a mano."
        case .intelligenceDisabled: "Activa Apple Intelligence en Ajustes para interpretar texto. La entrada manual sigue disponible."
        case .modelNotReady: "El modelo aún no está listo. Puedes continuar a mano y volver a comprobarlo después."
        case .unsupportedLanguage: "La interpretación en español no está disponible. Puedes continuar a mano."
        case .unavailable: "La interpretación no está disponible ahora. Puedes continuar a mano."
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
            persistenceNotice = "No se ha podido recuperar el borrador guardado. Lo conservamos sin modificar. Los cambios de esta sesión no se guardarán al cerrar la app."
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
                    editorError = "El borrador admite hasta 50 productos."
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
                    persistenceNotice = "No se ha podido guardar el borrador en este dispositivo. Conserva la app abierta; volveremos a intentarlo con el siguiente cambio."
                }
            }
            saveTask = nil
        }
    }

    private static func validationMessage(_ error: DraftValidationError) -> LocalizedStringResource {
        switch error {
        case .emptyBatch: return "Añade al menos un producto para revisar el borrador."
        case .tooManyItems: return "El borrador admite hasta 50 productos."
        case .invalidField(_, let field, let reason):
            switch (field, reason) {
            case (.name, .required): return "Escribe el nombre del producto."
            case (.store, .required): return "Indica la tienda de cada producto antes de revisar el borrador."
            case (.name, .tooLong): return "Acorta el nombre del producto: admite hasta 160 caracteres Unicode."
            case (.quantity, .tooLong): return "Acorta la cantidad: admite hasta 80 caracteres Unicode."
            case (.store, .tooLong): return "Acorta la tienda: admite hasta 80 caracteres Unicode."
            case (_, .invalidCharacters): return "El campo contiene caracteres de control que no se admiten."
            case (.quantity, .required): return "Revisa la cantidad del producto."
            }
        }
    }

    private static func interpretationMessage(_ error: any Error) -> LocalizedStringResource {
        switch error as? DraftInterpretationError {
        case .inputTooLong: "El texto es demasiado largo. Interpreta una lista más corta; tu texto se conserva."
        case .tooManyProducts: "La propuesta superaría los 50 productos. No se ha añadido ninguno; divide el texto y revisa el borrador."
        case .noProducts: "No se han encontrado productos. Puedes reformular el texto o añadirlos a mano."
        case .refused: "No se ha podido interpretar este texto. Puedes añadir los productos a mano."
        case .unavailable: "El modelo de Apple Intelligence no está disponible en este momento. El borrador se conserva; puedes reintentar más tarde o continuar a mano."
        case .failed, .none: "No se ha podido interpretar el texto. El borrador se conserva; puedes reintentar o continuar a mano."
        }
    }

    private static func speechMessage(_ error: any Error) -> LocalizedStringResource {
        switch error as? SpeechCaptureError {
        case .permissionDenied: "El micrófono no tiene permiso. Puedes permitirlo en Ajustes o escribir los productos a mano."
        case .unavailable, .unsupportedLocale: "La transcripción en español no está disponible en este dispositivo. Puedes escribir el texto o añadir los productos a mano."
        case .microphoneUnavailable: "No hay un micrófono disponible. Puedes continuar a mano."
        default: "La grabación se ha interrumpido. El texto reconocido se conserva; puedes continuar a mano o volver a dictar."
        }
    }
}
