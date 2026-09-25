import Foundation
import Observation

enum StoreQueryActivity {
    case idle
    case preparing
    case recording
    case stopping
}

@Observable @MainActor
final class StoreQueryViewModel {
    var text = "" {
        didSet {
            matches = []
            message = nil
        }
    }
    private(set) var activity = StoreQueryActivity.idle
    private(set) var matches: [SharedStore] = []
    private(set) var message: LocalizedStringResource?
    @ObservationIgnored private let speech: any SpeechCapturing
    @ObservationIgnored private var stores: [SharedStore] = []
    @ObservationIgnored private var captureID: UUID?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var originalText = ""
    @ObservationIgnored private var receivedTranscript = false

    init(speech: any SpeechCapturing) {
        self.speech = speech
    }

    var canSearch: Bool { activity == .idle && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func prepare(stores: [SharedStore]) {
        guard activity == .idle else { return }
        self.stores = stores
        text = ""
    }

    func clear() {
        stopDictation()
        stores = []
        text = ""
    }

    func search() {
        guard canSearch else { return }
        matches = StoreQueryMatcher.matches(text, stores: stores)
        if matches.isEmpty {
            message = "I couldn’t find that store in your group. Try again, correct the text or use the Store selector."
        } else if matches.count > 1 {
            message = "More than one store matches. Choose the one you want."
        } else {
            message = nil
        }
    }

    @discardableResult
    func startDictation() -> Task<Void, Never> {
        guard activity == .idle else { return Task {} }
        let id = UUID()
        captureID = id
        originalText = text
        receivedTranscript = false
        matches = []
        message = nil
        activity = .preparing
        let task = Task {
            do {
                let events = try await speech.start()
                for try await event in events {
                    guard captureID == id, !Task.isCancelled else { return }
                    switch event {
                    case .preparing: break
                    case .recording:
                        if activity == .preparing {
                            activity = .recording
                        }
                    case .transcript(let transcript):
                        receivedTranscript = !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        text = transcript
                    }
                }
            } catch {
                guard captureID == id, !Task.isCancelled else { return }
                message = Self.speechMessage(error)
            }
            guard captureID == id, activity != .stopping else { return }
            captureID = nil
            captureTask = nil
            activity = .idle
        }
        captureTask = task
        return task
    }

    @discardableResult
    func finishDictation() -> Task<Void, Never> {
        guard activity == .recording, let id = captureID else { return Task {} }
        let capture = captureTask
        activity = .stopping
        return Task {
            do {
                try await speech.finish()
            } catch {
                guard captureID == id else { return }
                message = Self.speechMessage(error)
            }
            await capture?.value
            guard captureID == id else { return }
            captureID = nil
            captureTask = nil
            activity = .idle
            if message == nil {
                if receivedTranscript && canSearch {
                    search()
                } else {
                    message = "No speech was recognized. Try again or type a store name."
                }
            }
        }
    }

    @discardableResult
    func stopDictation(restoreText: Bool = false) -> Task<Void, Never> {
        guard captureID != nil else { return Task {} }
        captureID = nil
        let capture = captureTask
        captureTask = nil
        capture?.cancel()
        if restoreText {
            text = originalText
        }
        activity = .stopping
        return Task {
            await speech.cancel()
            await capture?.value
            activity = .idle
        }
    }

    private static func speechMessage(_ error: any Error) -> LocalizedStringResource {
        switch error as? SpeechCaptureError {
        case .permissionDenied: "Microphone access is not allowed. Enable it in Settings or use the Store selector."
        case .unavailable, .unsupportedLocale: "Transcription is unavailable on this device or in this language. Type a store name or use the Store selector."
        case .microphoneUnavailable: "No microphone is available. Type a store name or use the Store selector."
        default: "Recording was interrupted. Correct the recognized text, try again or use the Store selector."
        }
    }
}
