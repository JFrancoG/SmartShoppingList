import Foundation
import Testing
@testable import SmartShoppingList

@MainActor
@Suite
struct AppBootstrapTests {
    @Test(.tags(.fast))
    func `Concurrent startup callers wait for evidence and share one composed context`() async throws {
        let gate = BootstrapEvidenceGate()
        let secondStarted = BootstrapTestSignal()
        var compositions = 0
        let bootstrap = AppBootstrap(resolve: {
            try await AppEnvironmentResolver(read: gate.read).resolve()
        }) { environment in
            compositions += 1
            return try makeShopping(environment: environment)
        }
        let first = Task { try await bootstrap.context() }
        await gate.waitUntilRead()
        let second = Task {
            secondStarted.signal()
            return try await bootstrap.context()
        }
        await secondStarted.wait()

        #expect(bootstrap.state == .resolving)
        #expect(bootstrap.shopping == nil)
        #expect(bootstrap.environment == nil)
        #expect(compositions == 0)
        #expect(gate.readCount == 1)

        gate.release(.sandbox)
        let firstContext = try await first.value
        let secondContext = try await second.value
        let reopened = try await bootstrap.context()

        #expect(firstContext === secondContext)
        #expect(reopened === firstContext)
        #expect(bootstrap.shopping === firstContext)
        #expect(compositions == 1)
        #expect(gate.readCount == 1)
    }

    @Test(.tags(.fast), arguments: [
        (BootstrapEvidenceFailure.unavailable, AppBootstrapError.unavailable),
        (.unverified, .unverified),
        (.unsupported, .unsupportedEnvironment),
        (.cancelled, .cancelled)
    ])
    func `Failed evidence opens no context until an explicit successful retry`(
        failure: BootstrapEvidenceFailure,
        expected: AppBootstrapError
    ) async throws {
        let control = BootstrapRecoveryControl()
        let resolver = AppEnvironmentResolver {
            control.reads += 1
            if control.shouldRecover {
                return .production
            }
            return try failure.read()
        }
        let bootstrap = AppBootstrap(resolve: resolver.resolve) { environment in
            control.compositions += 1
            return try makeShopping(environment: environment)
        }

        await #expect(throws: expected) {
            try await bootstrap.context()
        }
        #expect(bootstrap.state == .recovery(expected))
        #expect(bootstrap.shopping == nil)
        #expect(bootstrap.environment == nil)
        #expect(control.compositions == 0)

        control.shouldRecover = true
        await bootstrap.prepare()
        #expect(control.reads == 1)
        #expect(control.compositions == 0)

        await bootstrap.retry()
        #expect(bootstrap.state == .ready)
        #expect(bootstrap.shopping != nil)
        #expect(control.compositions == 1)
        #expect(control.reads == 2)
    }

    @Test(.tags(.fast))
    func `Cancelling one waiting caller preserves the context needed by another caller`() async throws {
        let gate = BootstrapEvidenceGate()
        let secondStarted = BootstrapTestSignal()
        var compositions = 0
        let bootstrap = AppBootstrap(resolve: {
            try await AppEnvironmentResolver(read: gate.read).resolve()
        }) { environment in
            compositions += 1
            return try makeShopping(environment: environment)
        }
        let cancelled = Task { try await bootstrap.context() }
        await gate.waitUntilRead()
        let remaining = Task {
            secondStarted.signal()
            return try await bootstrap.context()
        }
        await secondStarted.wait()
        cancelled.cancel()
        #expect(compositions == 0)

        gate.release(.production)
        await #expect(throws: CancellationError.self) {
            try await cancelled.value
        }
        let context = try await remaining.value

        #expect(bootstrap.state == .ready)
        #expect(bootstrap.shopping === context)
        #expect(compositions == 1)
        #expect(gate.readCount == 1)
    }

    @Test(.tags(.fast))
    func `An abandoned resolution cannot compose or replace the context created by retry`() async throws {
        let gate = BootstrapEvidenceGate()
        var reads = 0
        var composedEnvironments: [AppEnvironment] = []
        let bootstrap = AppBootstrap(resolve: {
            reads += 1
            if reads == 1 {
                return try await AppEnvironmentResolver(read: gate.read).resolve()
            }
            return .production
        }) { environment in
            composedEnvironments.append(environment)
            return try makeShopping(environment: environment)
        }
        let abandoned = Task { await bootstrap.prepare() }
        await gate.waitUntilRead()

        bootstrap.cancelPreparation()
        #expect(bootstrap.state == .recovery(.cancelled))
        #expect(composedEnvironments.isEmpty)

        await bootstrap.retry()
        let recovered = try #require(bootstrap.shopping)
        #expect(bootstrap.state == .ready)
        #expect(composedEnvironments == [.production])

        // The first reader deliberately returns despite cancellation, as an external API may do.
        gate.release(.sandbox)
        await abandoned.value

        #expect(bootstrap.state == .ready)
        #expect(bootstrap.environment == .production)
        #expect(bootstrap.shopping === recovered)
        #expect(composedEnvironments == [.production])
        #expect(reads == 2)
    }

    @Test(.tags(.integration))
    func `Changing distribution reopens separate drafts without importing the legacy production file`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AppBootstrapTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appending(path: "SmartShoppingList/draft-v1.json")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = Data("""
        {"text":"Real shopping draft","items":[
          {"id":"00000000-0000-0000-0000-000000000010","name":"Real bread","quantity":"2","store":"Real store"}
        ]}
        """.utf8)
        try legacy.write(to: legacyURL)
        let compose: @MainActor (AppEnvironment) throws -> SharedShoppingViewModel = { environment in
            let storage = SharedAppStorage(configuration: try environment.configuration, supportDirectory: directory)
            return try makeShopping(environment: environment, persistence: FileDraftPersistence(fileURL: storage.draftFileURL))
        }
        let sandbox = AppBootstrap(resolve: { .sandbox }, makeShopping: compose)
        let sandboxContext = try await sandbox.context()
        await sandboxContext.draft.load()
        #expect(sandboxContext.draft.text.isEmpty)
        #expect(sandboxContext.draft.items.isEmpty)
        let entry = ShoppingDraftItem(
            id: identifier(32),
            name: "Test milk",
            quantity: "3 cartons",
            store: "Test store"
        )

        #expect(try await sandboxContext.addDraftItemFromIntent(entry))
        #expect(try Data(contentsOf: legacyURL) == legacy)

        let production = AppBootstrap(resolve: { .production }, makeShopping: compose)
        let productionContext = try await production.context()
        await productionContext.draft.load()
        #expect(productionContext.draft.text == "Real shopping draft")
        #expect(productionContext.draft.items.map(\.name) == ["Real bread"])
        #expect(productionContext.draft.items.map(\.quantity) == ["2"])
        #expect(productionContext.draft.items.map(\.store) == ["Real store"])

        let reopened = AppBootstrap(resolve: { .sandbox }, makeShopping: compose)
        let reopenedContext = try await reopened.context()
        await reopenedContext.draft.load()
        #expect(reopenedContext.draft.items.map(\.id) == [identifier(32)])
        #expect(reopenedContext.draft.items.map(\.name) == ["Test milk"])
        #expect(reopenedContext.draft.items.map(\.quantity) == ["3 cartons"])
        #expect(reopenedContext.draft.items.map(\.store) == ["Test store"])
        #expect(try Data(contentsOf: legacyURL) == legacy)
    }

    @Test(.tags(.fast))
    func `A startup invitation is saved only after its context is resolved and then survives loading`() async throws {
        let gate = BootstrapEvidenceGate()
        let credentials = MemorySharedCredentialStore()
        var compositions = 0
        let bootstrap = AppBootstrap(resolve: {
            try await AppEnvironmentResolver(read: gate.read).resolve()
        }) { environment in
            compositions += 1
            return try makeShopping(environment: environment, credentials: credentials)
        }
        let url = try invitationURL(origin: "https://smartshoppinglistsandbox-sandbox.up.railway.app")
        let receiving = Task { await bootstrap.receiveInvitation(url) }
        await gate.waitUntilRead()

        #expect(await credentials.loadIncomingInvitation() == nil)
        #expect(await credentials.loadInvitation() == nil)
        #expect(compositions == 0)

        gate.release(.sandbox)
        await receiving.value
        let pending = PendingInvitation(id: identifier(1), token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        #expect(await credentials.loadIncomingInvitation() == pending)
        #expect(await credentials.loadInvitation() == nil)

        let context = try #require(bootstrap.shopping)
        await context.load()
        #expect(context.pendingInvitation == pending)
        #expect(await credentials.loadInvitation() == pending)
        #expect(await credentials.loadIncomingInvitation() == nil)
        #expect(bootstrap.invitationNotice == nil)
        #expect(compositions == 1)
    }

    @Test(.tags(.fast), arguments: [
        (AppEnvironment.sandbox, "https://smartshoppinglist-production.up.railway.app"),
        (.production, "https://smartshoppinglistsandbox-sandbox.up.railway.app")
    ])
    func `An invitation from the opposite context preserves saved work and explains the mismatch`(
        environment: AppEnvironment,
        invitationOrigin: String
    ) async throws {
        let saved = PendingInvitation(id: identifier(2), token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let credentials = MemorySharedCredentialStore(invitation: saved)
        let bootstrap = AppBootstrap(resolve: { environment }) { selected in
            try makeShopping(environment: selected, credentials: credentials)
        }

        await bootstrap.receiveInvitation(try invitationURL(origin: invitationOrigin))
        let context = try #require(bootstrap.shopping)
        await context.load()

        #expect(context.pendingInvitation == saved)
        #expect(await credentials.loadInvitation() == saved)
        #expect(await credentials.loadIncomingInvitation() == nil)
        #expect(bootstrap.invitationNotice != nil)
        #expect(bootstrap.environment == environment)
    }

    private func makeShopping(
        environment: AppEnvironment,
        persistence: any DraftPersisting = MemoryDraftPersistence(),
        credentials: any SharedCredentialStoring = MemorySharedCredentialStore()
    ) throws -> SharedShoppingViewModel {
        SharedShoppingViewModel(
            api: nil,
            configuration: try environment.configuration,
            credentials: credentials,
            draft: ShoppingDraftViewModel(
                interpreter: BootstrapUnavailableInterpreter(),
                speech: BootstrapUnavailableSpeech(),
                persistence: persistence
            ),
            storeQuery: StoreQueryViewModel(speech: BootstrapUnavailableSpeech())
        )
    }

    private func invitationURL(origin: String) throws -> URL {
        let path = "/invite/00000000-0000-0000-0000-000000000001"
        return try #require(URL(string: origin + path + "#token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"))
    }

    private func identifier(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }
}

enum BootstrapEvidenceFailure: Sendable {
    case unavailable
    case unverified
    case unsupported
    case cancelled

    func read() throws -> AppDistributionEvidence {
        switch self {
        case .unavailable: throw URLError(.notConnectedToInternet)
        case .unverified: return .unverified
        case .unsupported: return .unsupported
        case .cancelled: throw CancellationError()
        }
    }
}

@MainActor
private final class BootstrapRecoveryControl {
    var shouldRecover = false
    var reads = 0
    var compositions = 0
}

@MainActor
private final class BootstrapEvidenceGate {
    private(set) var readCount = 0
    private var readers: [CheckedContinuation<AppDistributionEvidence, Never>] = []
    private var releasedEvidence: AppDistributionEvidence?
    private let started = BootstrapTestSignal()

    func read() async -> AppDistributionEvidence {
        readCount += 1
        if let releasedEvidence {
            return releasedEvidence
        }
        return await withCheckedContinuation { continuation in
            readers.append(continuation)
            started.signal()
        }
    }

    func waitUntilRead() async {
        await started.wait()
    }

    func release(_ evidence: AppDistributionEvidence) {
        releasedEvidence = evidence
        readers.forEach { $0.resume(returning: evidence) }
        readers = []
    }
}

@MainActor
private final class BootstrapTestSignal {
    private var isSignalled = false
    private var observers: [CheckedContinuation<Void, Never>] = []

    func signal() {
        isSignalled = true
        observers.forEach { $0.resume() }
        observers = []
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { observers.append($0) }
    }
}

private struct BootstrapUnavailableInterpreter: DraftInterpreting {
    var availability: DraftInterpretationAvailability { .unavailable }
    func interpret(_ text: String) async throws -> [SuggestedProduct] { throw DraftInterpretationError.unavailable }
}

private struct BootstrapUnavailableSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> { throw SpeechCaptureError.unavailable }
    func finish() async throws {}
    func cancel() async {}
}
