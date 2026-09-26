import AVFoundation
import Foundation
import Speech

protocol SpeechCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error>
    func finish() async throws
    func cancel() async
}

enum SpeechCaptureEvent {
    case preparing
    case recording(localeIdentifier: String)
    case transcript(String)
}

enum SpeechCaptureError: Error {
    case unavailable
    case unsupportedLocale
    case permissionDenied
    case microphoneUnavailable
    case failed
}

private enum CaptureTranscriber {
    case speech(SpeechTranscriber)
    case dictation(DictationTranscriber)

    var module: any SpeechModule {
        switch self {
        case .speech(let transcriber): transcriber
        case .dictation(let transcriber): transcriber
        }
    }
}

actor SpeechCaptureService: SpeechCapturing {
    private let localeIdentifier: String
    private var captureID: UUID?
    private var provider: CaptureInputSequenceProvider?
    private var analyzer: SpeechAnalyzer?
    private var captureTask: Task<Void, Never>?
    private var interruptionTasks: [Task<Void, Never>] = []
    private var continuation: AsyncThrowingStream<SpeechCaptureEvent, any Error>.Continuation?
    private var isRecording = false
    private var isFinishing = false
    private var isStopping = false

    init(localeIdentifier: String) {
        self.localeIdentifier = localeIdentifier
    }

    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        try Task.checkCancellation()
        guard captureID == nil, !isStopping else { throw SpeechCaptureError.failed }

        let id = UUID()
        let stream = AsyncThrowingStream<SpeechCaptureEvent, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        captureID = id
        isFinishing = false
        continuation = stream.continuation
        stream.continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination {
                Task {
                    await self?.cancel(captureID: id)
                }
            }
        }
        stream.continuation.yield(.preparing)
        captureTask = Task {
            await runCapture(id: id)
        }
        return stream.stream
    }

    func finish() async throws {
        guard let id = captureID else { return }
        guard !isFinishing else { return }
        guard isRecording, let analyzer, let captureTask else {
            await cancel()
            return
        }

        isFinishing = true
        stopCaptureInput()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            await captureTask.value
        } catch {
            await cancel(captureID: id)
            if error is CancellationError {
                throw CancellationError()
            }
            throw SpeechCaptureError.failed
        }
    }

    func cancel() async {
        guard captureID != nil else { return }
        isStopping = true
        captureID = nil
        let task = captureTask
        let currentAnalyzer = analyzer
        captureTask = nil
        analyzer = nil
        task?.cancel()
        stopCaptureInput()
        continuation?.finish()
        continuation = nil
        await currentAnalyzer?.cancelAndFinishNow()
        await task?.value
        deactivateAudioSession()
        isFinishing = false
        isStopping = false
    }

    private func runCapture(id: UUID) async {
        do {
            let transcriber = try await prepareCapture(id: id)
            switch transcriber {
            case .speech(let module):
                try await consumeResults(module, id: id) { String($0.text.characters) }
            case .dictation(let module):
                try await consumeResults(module, id: id) { String($0.text.characters) }
            }
            try checkCapture(id)
            guard isFinishing else { throw SpeechCaptureError.failed }
            await completeCapture(id: id, error: nil)
        } catch is CancellationError {
            await completeCapture(id: id, error: nil)
        } catch {
            await completeCapture(id: id, error: error as? SpeechCaptureError ?? .failed)
        }
    }

    private func consumeResults<Module: SpeechModule>(
        _ module: Module,
        id: UUID,
        text: @Sendable (Module.Result) -> String
    ) async throws {
        var finalizedText = ""
        for try await result in module.results {
            try checkCapture(id)
            let recognizedText = text(result)
            if result.isFinal {
                finalizedText += recognizedText
                continuation?.yield(.transcript(finalizedText))
            } else {
                continuation?.yield(.transcript(finalizedText + recognizedText))
            }
        }
    }

    private func selectTranscriber(id: UUID) async throws -> (CaptureTranscriber, Locale) {
        try checkCapture(id)
        let requestedLocale = Locale(identifier: localeIdentifier)
        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            try checkCapture(id)
            return (.speech(SpeechTranscriber(locale: locale, preset: .progressiveTranscription)), locale)
        }
        try checkCapture(id)
        // The dictation module keeps recognition on-device on hardware or locales without SpeechTranscriber.
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SpeechCaptureError.unsupportedLocale
        }
        try checkCapture(id)
        return (.dictation(DictationTranscriber(locale: locale, preset: .progressiveLongDictation)), locale)
    }

    private func prepareCapture(id: UUID) async throws -> CaptureTranscriber {
        let (transcriber, locale) = try await selectTranscriber(id: id)
        let module = transcriber.module
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw SpeechCaptureError.permissionDenied }
        try checkCapture(id)

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try checkCapture(id)
            try await request.downloadAndInstall()
        }
        try checkCapture(id)
        let captureProvider = try await makeCaptureProvider(transcriber: module)
        try checkCapture(id)
        provider = captureProvider
        let speechAnalyzer = SpeechAnalyzer(modules: [module])
        analyzer = speechAnalyzer
        try await speechAnalyzer.start(inputSequence: captureProvider.analyzerInputs)
        try checkCapture(id)
        observeInterruptions(id: id, session: captureProvider.captureSession)
        captureProvider.captureSession.startRunning()
        guard captureProvider.captureSession.isRunning else { throw SpeechCaptureError.failed }
        isRecording = true
        continuation?.yield(.recording(localeIdentifier: locale.identifier))
        return transcriber
    }

    private func makeCaptureProvider(transcriber: any SpeechModule) async throws -> CaptureInputSequenceProvider {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw SpeechCaptureError.microphoneUnavailable
        }
        guard ProcessInfo.processInfo.isiOSAppOnMac else {
            return try await CaptureInputSequenceProvider.providerWithSession(
                from: microphone,
                compatibleWith: [transcriber]
            )
        }

        // On macOS 27.2 beta, the convenience factory calls setAudioSettings:, unavailable to iOS apps on Mac.
        // The explicit initializer converts native capture samples to the analyzer's supported format.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechCaptureError.unavailable
        }
        try Task.checkCancellation()
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: microphone)
        let captureProvider = try CaptureInputSequenceProvider(session: session, analyzerFormat: format, priority: nil)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { throw SpeechCaptureError.microphoneUnavailable }
        session.addInput(input)
        let output = captureProvider.captureAudioDataOutput
        guard session.canAddOutput(output) else { throw SpeechCaptureError.failed }
        session.addOutput(output)
        return captureProvider
    }

    private func checkCapture(_ id: UUID) throws {
        try Task.checkCancellation()
        guard captureID == id, !isStopping else { throw CancellationError() }
    }

    private func cancel(captureID id: UUID) async {
        guard captureID == id else { return }
        await cancel()
    }

    private func completeCapture(id: UUID, error: SpeechCaptureError?) async {
        guard captureID == id else { return }
        isStopping = true
        captureID = nil
        let currentAnalyzer = analyzer
        let currentTask = captureTask
        analyzer = nil
        captureTask = nil
        stopCaptureInput()
        if let error {
            currentTask?.cancel()
            continuation?.finish(throwing: error)
            await currentAnalyzer?.cancelAndFinishNow()
        } else {
            continuation?.finish()
        }
        continuation = nil
        deactivateAudioSession()
        isFinishing = false
        isStopping = false
    }

    private func stopCaptureInput() {
        interruptionTasks.forEach {
            $0.cancel()
        }
        interruptionTasks.removeAll()
        provider?.captureSession.stopRunning()
        // Stopping alone does not terminate analyzerInputs. Releasing the provider also releases its audio output.
        provider = nil
        isRecording = false
    }

    private func observeInterruptions(id: UUID, session: AVCaptureSession) {
        let sessionID = ObjectIdentifier(session)
        let names = [
            AVCaptureSession.wasInterruptedNotification,
            AVCaptureSession.runtimeErrorNotification,
            AVCaptureSession.didStopRunningNotification
        ]
        interruptionTasks = names.map { name in
            // Map notifications to a Sendable identity before they cross an isolation boundary.
            let events = NotificationCenter.default.notifications(named: name).compactMap { notification in
                notification.object.map { ObjectIdentifier($0 as AnyObject) }
            }
            return Task {
                for await sourceID in events {
                    guard !Task.isCancelled, captureID == id else { return }
                    if sourceID == sessionID, !isFinishing {
                        await completeCapture(id: id, error: .failed)
                        return
                    }
                }
            }
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
