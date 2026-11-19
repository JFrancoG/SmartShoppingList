import DeviceCheck
import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
@MainActor
struct SubscriptionRecoveryTests {
    @Test
    func `Foreground loading never claims a purchase owned by a deleted account`() async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        let api = RecoveryAPI(credentials: credentials)
        let attester = RecoveryAttester()
        let model = fixture.model(api: api, store: RecoveryStore(), credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        #expect(await api.challengeCount == 0)
        #expect(attester.keyCount == 0)
        #expect(model.status?.state == .free)
    }

    @Test
    func `Lost recovery reply replays the exact durable proof after relaunch without another attestation`() async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        let api = RecoveryAPI(credentials: credentials)
        let store = RecoveryStore()
        let attester = RecoveryAttester()
        let model = fixture.model(api: api, store: store, credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        await api.loseNextReply()
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        let saved = try #require(await credentials.loadSubscriptionRecovery())
        #expect(saved.request != nil)
        #expect(await api.proofWasSavedBeforeSending)
        #expect(await store.finished.isEmpty)
        #expect(attester.hashes == [try #require(Data(base64Encoded: RecoveryFixture.expectedHash))])
        let relaunched = fixture.model(api: api, store: store, credentials: credentials, attester: attester)
        _ = await relaunched.load(session: fixture.session, isCurrentSession: { _ in true })
        #expect(await api.requests.count == 1)

        _ = await relaunched.restore(session: fixture.session, isCurrentSession: { _ in true })

        let sent = await api.requests
        #expect(sent.count == 2)
        #expect(sent[0] == sent[1])
        #expect(sent[1] == saved.request)
        #expect(attester.keyCount == 1)
        #expect(attester.hashes.count == 1)
        #expect(await credentials.loadSubscriptionRecovery() == nil)
        #expect(await store.finished == ["recovery-transaction"])
        #expect(relaunched.status?.state == .subscribed)
    }

    @Test
    func `A server hash that changes the proof binding is never sent to Apple`() async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        let api = RecoveryAPI(credentials: credentials)
        await api.corruptChallengeHash()
        let attester = RecoveryAttester()
        let model = fixture.model(api: api, store: RecoveryStore(), credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        #expect(attester.hashes.isEmpty)
        #expect(await api.requests.isEmpty)
        #expect(model.status?.state == .free)
    }

    @Test
    func `A definitive expired proof rejection allows a fresh explicit recovery attempt`() async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        let api = RecoveryAPI(credentials: credentials)
        let store = RecoveryStore()
        let attester = RecoveryAttester()
        let model = fixture.model(api: api, store: store, credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        await api.rejectNextProof()
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        #expect(await credentials.loadSubscriptionRecovery() == nil)
        #expect(await store.finished.isEmpty)
        #expect(attester.keyCount == 1)

        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })

        #expect(attester.keyCount == 2)
        #expect(await api.challengeCount == 2)
        #expect(model.status?.state == .subscribed)
    }

    @Test(arguments: [DCError.Code.invalidKey, .serverUnavailable])
    func `App Attest retries only a temporary failure with its original key and hash`(_ failure: DCError.Code) async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        let api = RecoveryAPI(credentials: credentials)
        let attester = RecoveryAttester()
        attester.nextFailure = failure
        let model = fixture.model(api: api, store: RecoveryStore(), credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        #expect(await api.requests.isEmpty)
        #expect((await credentials.loadSubscriptionRecovery() != nil) == (failure == .serverUnavailable))

        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })

        #expect(attester.keyCount == (failure == .serverUnavailable ? 1 : 2))
        #expect(attester.hashes.count == 2)
        #expect(attester.hashes.first == attester.hashes.last)
        #expect(model.status?.state == .subscribed)
    }

    @Test
    func `Failed proof persistence retains the returned attestation and saves it before delivery`() async throws {
        let fixture = RecoveryFixture()
        let credentials = FailingProofCredentials()
        let api = RecoveryAPI(credentials: credentials)
        let attester = RecoveryAttester()
        let store = RecoveryStore()
        let model = fixture.model(api: api, store: store, credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        #expect(model.pendingRecovery?.request != nil)
        #expect(await credentials.loadSubscriptionRecovery()?.request == nil)
        #expect(await api.requests.isEmpty)

        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })

        #expect(attester.keyCount == 1)
        #expect(attester.hashes.count == 1)
        #expect(await api.proofWasSavedBeforeSending)
        #expect(await store.finished == ["recovery-transaction"])
    }

    @Test
    func `An expired unsubmitted challenge replaces its key before the next attestation`() async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        await credentials.saveSubscriptionRecovery(PendingSubscriptionRecovery(
            userID: fixture.session.user.id, transactionID: "recovery-transaction", environment: .sandbox,
            keyID: "expired-key", signedTransaction: "verified-local-jws",
            challenge: SharedRecoveryChallenge(
                id: UUID(), nonce: "old-nonce", expiresAt: .distantPast, clientDataHash: "old-hash",
                appAccountToken: fixture.session.user.id, environment: "Sandbox"
            )
        ))
        let api = RecoveryAPI(credentials: credentials)
        let attester = RecoveryAttester()
        let model = fixture.model(api: api, store: RecoveryStore(), credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        #expect(attester.keyCount == 1)
        #expect(await api.requests.first?.keyId == "device-key")
        #expect(model.status?.state == .subscribed)
    }

    @Test
    func `A different account cannot send a saved Premium recovery proof`() async throws {
        let fixture = RecoveryFixture()
        let credentials = MemorySharedCredentialStore()
        await credentials.saveSubscriptionRecovery(PendingSubscriptionRecovery(
            userID: UUID(), transactionID: "other", environment: .sandbox,
            keyID: "other-key", signedTransaction: "other-jws"
        ))
        let api = RecoveryAPI(credentials: credentials)
        let attester = RecoveryAttester()
        let model = fixture.model(api: api, store: RecoveryStore(), credentials: credentials, attester: attester)
        _ = await model.load(session: fixture.session, isCurrentSession: { _ in true })
        _ = await model.restore(session: fixture.session, isCurrentSession: { _ in true })
        #expect(await api.challengeCount == 0)
        #expect(await api.requests.isEmpty)
        #expect(attester.keyCount == 0)
        #expect(await credentials.loadSubscriptionRecovery() != nil)
    }

    @Test
    func `Recovery rejects a proof for another store environment before attesting`() throws {
        let fixture = RecoveryFixture()
        #expect(throws: SharedAPIError.invalidResponse) {
            try fixture.challenge.verifiedHash(
                userID: fixture.session.user.id, keyID: "device-key", transaction: "verified-local-jws", storeEnvironment: .production
            )
        }
    }
}

private struct RecoveryFixture {
    static let expectedHash = "AYjdbVSs2m12auXbUvIwSHmIyQ2gRqfsDNGd1YGXxws="
    static let userID = UUID(uuid: (0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x42, 0x22, 0x82, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22))
    let session = SharedSession(
        accessToken: "recovery-session", tokenType: "Bearer", expiresAt: .distantFuture,
        user: SharedUser(id: userID, displayName: "New account", group: nil)
    )
    var challenge: SharedRecoveryChallenge {
        SharedRecoveryChallenge(
            id: UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x41, 0x11, 0x81, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11)),
            nonce: "challenge-nonce", expiresAt: .distantFuture, clientDataHash: Self.expectedHash,
            appAccountToken: Self.userID, environment: "Sandbox"
        )
    }

    func status(_ state: SharedSubscriptionState) -> SharedSubscriptionStatus {
        SharedSubscriptionStatus(
            appAccountToken: Self.userID, isConfigured: true, productIDs: ["monthly", "annual"], state: state,
            expiresAt: state == .subscribed ? .distantFuture : nil, gracePeriodExpiresAt: nil,
            autoRenewEnabled: true, verifiedAt: Date()
        )
    }

    @MainActor
    func model(
        api: RecoveryAPI, store: RecoveryStore, credentials: any SharedSubscriptionCredentialStoring, attester: RecoveryAttester
    ) -> SharedPremiumViewModel {
        SharedPremiumViewModel(api: api, store: store, credentials: credentials, recoveryAttester: attester)
    }
}

private actor RecoveryAPI: SharedSubscriptionAPI, SharedSubscriptionRecoveryAPI {
    let credentials: any SharedSubscriptionRecoveryStoring
    private var rejectsProof = false
    private var losesReply = false
    private var corruptsHash = false
    private(set) var challengeCount = 0
    private(set) var requests: [SharedRecoveryRequest] = []
    private(set) var proofWasSavedBeforeSending = false
    init(credentials: any SharedSubscriptionRecoveryStoring) { self.credentials = credentials }
    func loseNextReply() { losesReply = true }
    func rejectNextProof() { rejectsProof = true }
    func corruptChallengeHash() { corruptsHash = true }
    func subscription(token: String) -> SharedSubscriptionStatus { RecoveryFixture().status(.free) }
    func verifySubscription(_ request: VerifySharedSubscriptionRequest, token: String) throws -> SharedSubscriptionAcknowledgement {
        throw SharedAPIError.invalidResponse
    }
    func subscriptionRecoveryChallenge(_ request: SharedRecoveryChallengeRequest, token: String) -> SharedRecoveryChallenge {
        challengeCount += 1
        let result = RecoveryFixture().challenge
        return SharedRecoveryChallenge(
            id: result.id, nonce: result.nonce, expiresAt: result.expiresAt,
            clientDataHash: corruptsHash ? Data(repeating: 0, count: 32).base64EncodedString() : result.clientDataHash,
            appAccountToken: result.appAccountToken, environment: result.environment
        )
    }
    func recoverSubscription(_ request: SharedRecoveryRequest, token: String) async throws -> SharedSubscriptionAcknowledgement {
        requests.append(request)
        if rejectsProof {
            rejectsProof = false
            throw SharedAPIError.server(status: 403, code: "invalid_subscription_recovery", requestID: nil, retryAfter: nil)
        }
        proofWasSavedBeforeSending = try await credentials.loadSubscriptionRecovery()?.request == request
        if losesReply {
            losesReply = false
            throw URLError(.networkConnectionLost)
        }
        return SharedSubscriptionAcknowledgement(
            subscription: RecoveryFixture().status(.subscribed), acknowledgedTransactionId: "recovery-transaction"
        )
    }
}

@MainActor
private final class RecoveryAttester: SharedRecoveryAttesting {
    private(set) var keyCount = 0
    private(set) var hashes: [Data] = []
    var nextFailure: DCError.Code?
    func generateKey() -> String {
        keyCount += 1
        return "device-key"
    }
    func attest(keyID: String, hash: Data) throws -> Data {
        hashes.append(hash)
        if let nextFailure {
            self.nextFailure = nil
            throw NSError(domain: DCError.errorDomain, code: nextFailure.rawValue)
        }
        return Data("apple-proof".utf8)
    }
}

private actor RecoveryStore: SharedSubscriptionStore {
    nonisolated let expectedEnvironment = SharedStoreEnvironment.sandbox
    private(set) var finished: [String] = []
    private(set) var restores = 0
    func products(ids: [String]) -> [SharedSubscriptionProduct] {
        [
            SharedSubscriptionProduct(id: "monthly", displayName: "Monthly", displayPrice: "1 €", period: .monthly, subscriptionGroupID: "1"),
            SharedSubscriptionProduct(id: "annual", displayName: "Annual", displayPrice: "10 €", period: .annual, subscriptionGroupID: "1")
        ]
    }
    func purchase(id: String, appAccountToken: UUID) -> SharedSubscriptionPurchaseResult { .cancelled }
    func restore() { restores += 1 }
    func transactions() -> [SharedStoreTransaction] { [transaction] }
    func recoveryTransactions() -> [SharedStoreTransaction] { restores > 0 ? [transaction] : [] }
    func updates() -> AsyncStream<SharedStoreTransaction> { AsyncStream { $0.finish() } }
    func finish(transactionID: String) { finished.append(transactionID) }
    private var transaction: SharedStoreTransaction {
        SharedStoreTransaction(
            id: "recovery-transaction", appAccountToken: UUID(), productID: "monthly",
            signedTransaction: "verified-local-jws", environment: .sandbox
        )
    }
}


private actor FailingProofCredentials: SharedSubscriptionCredentialStoring, SharedSubscriptionRecoveryStoring {
    private var recovery: PendingSubscriptionRecovery?
    private var rejectsNextProof = true
    func loadSubscriptionVerification() -> PendingSubscriptionVerification? { nil }
    func saveSubscriptionVerification(_ verification: PendingSubscriptionVerification?) {}
    func loadSubscriptionRecovery() -> PendingSubscriptionRecovery? { recovery }
    func saveSubscriptionRecovery(_ recovery: PendingSubscriptionRecovery?) throws {
        if rejectsNextProof, recovery?.request != nil {
            rejectsNextProof = false
            throw SharedCredentialError.unavailable(status: -1)
        }
        self.recovery = recovery
    }
}
