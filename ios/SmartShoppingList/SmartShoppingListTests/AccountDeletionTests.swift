import AuthenticationServices
import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
@MainActor
struct AccountDeletionTests {
    @Test
    func `Lost deletion acknowledgement is recovered after relaunch without submitting again`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        await api.loseAcceptanceResponse()
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)

        await model.confirm(session: fixture.session)

        #expect(model.blocksAccountUse)
        #expect(model.acceptedUserID == nil)
        let receipt = try #require(await credentials.loadAccountDeletion())
        #expect(receipt.submitted)
        #expect(await api.hadDurableReceiptBeforeAcceptance)
        let relaunched = fixture.model(api: api, credentials: credentials)
        await relaunched.restore()
        await relaunched.checkStatus()
        #expect(relaunched.acceptedUserID == fixture.session.user.id)
        #expect(relaunched.pending?.receipt == receipt.receipt)
        #expect(await api.deletionRequests == 1)
    }

    @Test
    func `Cancellation cannot unlock an account when acceptance won the race`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        await api.setStatus(.accepted)

        await model.cancel()

        #expect(model.acceptedUserID == fixture.session.user.id)
        #expect(model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() != nil)
        #expect(!model.canDismissResult)
    }

    @Test
    func `Prepared cancellation clears its receipt only after server confirmation`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        await api.failCancellation()
        await model.cancel()
        #expect(model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() != nil)
        await api.allowCancellation()

        await model.cancel()

        #expect(!model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() == nil)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `Cancellation tombstone unlocks a receipt whose preparation never reached the server`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        await api.losePreparation()
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        #expect(model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() != nil)

        await model.cancel()

        #expect(!model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() == nil)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `Unrelated operation status cannot authorize local data deletion`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        await api.useWrongOperationID()
        await model.checkStatus()
        #expect(model.acceptedUserID == nil)
        #expect(model.blocksAccountUse)
        #expect(model.notice != nil)
    }

    @Test
    func `Completed result stays durable until local data is cleared`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        await api.setStatus(.completed)
        await model.checkStatus()
        await model.dismissResult()
        #expect(model.blocksAccountUse)
        try await model.markLocalDataCleared()
        #expect(!model.blocksAccountUse)
        #expect(model.canDismissResult)
        #expect(await model.dismissResult())
        #expect(!model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() == nil)
    }

    @Test
    func `Unreadable deletion receipt blocks account use and is never overwritten`() async {
        let fixture = DeletionFixture()
        let credentials = UnreadableDeletionCredentials()
        let api = DeletionAPI(credentials: MemorySharedCredentialStore())
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        #expect(model.blocksAccountUse)
        #expect(model.storageFailed)
        #expect(await model.dismissResult() == false)
        #expect(await credentials.writes == 0)
        #expect(await api.challengeRequests == 0)
    }

    @Test
    func `Failed receipt persistence prevents preparation or deletion requests`() async {
        let fixture = DeletionFixture()
        let api = DeletionAPI(credentials: MemorySharedCredentialStore())
        let model = fixture.model(api: api, credentials: FailingDeletionWrites())
        await model.prepare(session: fixture.session)
        #expect(await api.challengeRequests == 0)
        #expect(await api.deletionRequests == 0)
        #expect(model.notice != nil)
    }

    @Test
    func `A completed result remains available when removing it from Keychain fails`() async {
        let fixture = DeletionFixture()
        let receipt = SharedDeletionReceipt(operationId: UUID(), statusSecret: "test-receipt")
        let saved = PendingAccountDeletion(
            userID: fixture.session.user.id,
            receipt: receipt,
            revision: "revision",
            submitted: true,
            lastStatus: SharedDeletionStatus(operationId: receipt.operationId, status: .completed),
            localDataCleared: true
        )
        let credentials = FailingDeletionWrites(saved: saved)
        let api = DeletionAPI(credentials: MemorySharedCredentialStore())
        let model = fixture.model(api: api, credentials: credentials)
        await model.restore()

        #expect(await model.dismissResult() == false)
        #expect(model.pending == saved)
        #expect(model.canDismissResult)
        #expect(model.notice != nil)
    }

    @Test
    func `A saved server cancellation can prepare a new operation without reusing its tombstone`() async throws {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .cancelled)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: .cancelled)
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        let replacement = try #require(await credentials.loadAccountDeletion())
        #expect(replacement.receipt.operationId != saved.receipt.operationId)
        #expect(replacement.receipt.statusSecret != saved.receipt.statusSecret)
        #expect(model.pending == replacement)
        #expect(model.canAuthorize)
        #expect(model.canCancelPreparation)
        #expect(!model.hasAuthorization)
        #expect(await api.deletionRequests == 0)
        #expect(try await api.deletionStatus(saved.receipt).status == .cancelled)
    }

    @Test
    func `A stale preparation recovers after conflict only when its cancellation is confirmed`() async throws {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .prepared)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: .cancelled)
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        let replacement = try #require(await credentials.loadAccountDeletion())
        #expect(replacement.receipt.operationId != saved.receipt.operationId)
        #expect(model.pending == replacement)
        #expect(model.canAuthorize)
        #expect(await api.statusRequests == 1)
        #expect(await api.challengeRequests == 2)
        #expect(await api.deletionRequests == 0)
        try fixture.authorize(model)
        #expect(model.hasAuthorization)
    }

    @Test
    func `A second preparation conflict stops after the single confirmed replacement`() async throws {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .prepared)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: .cancelled)
        await api.rejectChallenges()
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        let replacement = try #require(await credentials.loadAccountDeletion())
        #expect(replacement.receipt.operationId != saved.receipt.operationId)
        #expect(model.pending == replacement)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(model.canRefreshPreparation)
        #expect(model.notice != nil)
        #expect(await api.statusRequests == 1)
        #expect(await api.challengeRequests == 2)
        #expect(await api.deletionRequests == 0)
    }

    @Test(arguments: [false, true])
    func `An unconfirmed cancellation cannot replace the original operation`(unrelatedStatus: Bool) async throws {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .prepared)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: .cancelled)
        if unrelatedStatus {
            await api.useWrongOperationID()
        } else {
            await api.failStatus()
        }
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        #expect(await credentials.loadAccountDeletion() == saved)
        #expect(model.pending?.receipt == saved.receipt)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(model.notice != nil)
        #expect(await api.challengeRequests == 1)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `Acceptance discovered after a preparation conflict keeps the accepted operation`() async throws {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .prepared)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: .accepted)
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        #expect(model.pending?.receipt == saved.receipt)
        #expect(model.acceptedUserID == fixture.session.user.id)
        #expect(await credentials.loadAccountDeletion()?.lastStatus?.status == .accepted)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(await api.challengeRequests == 1)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `A preparation conflict is not cancellation when the status remains prepared`() async throws {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .prepared)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: .prepared)
        await api.rejectChallenges()
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        #expect(await credentials.loadAccountDeletion() == saved)
        #expect(model.pending?.receipt == saved.receipt)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(model.notice != nil)
        #expect(await api.statusRequests == 1)
        #expect(await api.challengeRequests == 1)
        #expect(await api.deletionRequests == 0)
    }

    @Test(arguments: [
        SharedDeletionStatus.State.prepared,
        .accepted,
        .purging,
        .dataDeleted,
        .completed
    ])
    func `Reopening a submitted operation never starts a replacement`(status: SharedDeletionStatus.State) async {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: status, submitted: true)
        let credentials = MemorySharedCredentialStore()
        await credentials.saveAccountDeletion(saved)
        let api = DeletionAPI(credentials: credentials)
        await api.seedOperation(saved.receipt.operationId, status: status)
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session, forceRefresh: true)

        #expect(model.pending?.receipt == saved.receipt)
        #expect(await credentials.loadAccountDeletion()?.submitted == true)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(await api.challengeRequests == 0)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `Failed persistence keeps a cancelled receipt instead of issuing an unrecorded replacement`() async {
        let fixture = DeletionFixture()
        let saved = fixture.savedRequest(status: .cancelled)
        let credentials = FailingDeletionWrites(saved: saved)
        let api = DeletionAPI(credentials: MemorySharedCredentialStore())
        await api.seedOperation(saved.receipt.operationId, status: .cancelled)
        let model = fixture.model(api: api, credentials: credentials)

        await model.prepare(session: fixture.session)

        #expect(await credentials.loadAccountDeletion() == saved)
        #expect(model.pending?.receipt == saved.receipt)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(model.notice != nil)
        #expect(await api.challengeRequests == 0)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `Reentering a prepared deletion preserves a verified Apple identity`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)
        let receipt = try #require(await credentials.loadAccountDeletion())

        await model.prepare(session: fixture.session)

        #expect(model.hasAuthorization)
        #expect(await api.challengeRequests == 1)
        #expect(await credentials.loadAccountDeletion() == receipt)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 1)
        #expect(model.acceptedUserID == fixture.session.user.id)
    }

    @Test
    func `Reentering after identity expiry explains renewal and requires a fresh Apple verification`() async throws {
        let fixture = DeletionFixture()
        let clock = DeletionClock()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        await api.setChallengeExpiry(clock.date.addingTimeInterval(300))
        let model = fixture.model(api: api, credentials: credentials, now: { clock.date })
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)
        let receipt = try #require(await credentials.loadAccountDeletion())
        clock.date = clock.date.addingTimeInterval(271)
        await api.setChallengeExpiry(clock.date.addingTimeInterval(300))

        await model.prepare(session: fixture.session)

        #expect(!model.hasAuthorization)
        #expect(model.canAuthorize)
        #expect(!model.requiresIdentityRefresh)
        #expect(await credentials.loadAccountDeletion() == receipt)
        #expect(await api.challengeRequests == 2)
        var notice = try #require(model.notice)
        notice.locale = Locale(identifier: "en")
        #expect(String(localized: notice) == "Your previous identity check expired. The details have been refreshed. Verify your identity with Apple again to continue.")
        await model.prepare(session: fixture.session)
        #expect(model.notice != nil)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 0)

        try fixture.authorize(model)

        #expect(model.notice == nil)
        #expect(model.hasAuthorization)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `A failed forced refresh cannot authorize with the previous identity challenge`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)
        let receipt = try #require(await credentials.loadAccountDeletion())
        await api.losePreparation()

        await model.prepare(session: fixture.session, forceRefresh: true)

        #expect(!model.canAuthorize)
        #expect(!model.hasAuthorization)
        #expect(model.canRefreshPreparation)
        #expect(model.notice != nil)
        #expect(await credentials.loadAccountDeletion() == receipt)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 0)
        await api.allowPreparation()

        await model.prepare(session: fixture.session)

        #expect(model.canAuthorize)
        #expect(!model.hasAuthorization)
        #expect(await credentials.loadAccountDeletion() == receipt)
        #expect(await api.challengeRequests == 3)
        #expect(await api.deletionRequests == 0)
    }

    @Test
    func `Reentering while Apple is open preserves the identity request being completed`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(request)
        let state = try #require(request.state)

        await model.prepare(session: fixture.session)
        await model.prepare(session: fixture.session, forceRefresh: true)
        await model.cancel()
        #expect(model.phase == .verifyingIdentity)
        #expect(!model.canCancelRequest)
        model.acceptAuthorization(token: "fresh-apple-token", code: "fresh-code", state: state)
        await model.confirm(session: fixture.session)

        #expect(await api.challengeRequests == 1)
        #expect(await api.deletionRequests == 1)
        #expect(model.acceptedUserID == fixture.session.user.id)
    }

    @Test
    func `An expired Apple response cannot delete and refreshing preserves the original operation`() async throws {
        let fixture = DeletionFixture()
        let clock = DeletionClock()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        await api.setChallengeExpiry(clock.date.addingTimeInterval(300))
        let model = fixture.model(api: api, credentials: credentials, now: { clock.date })
        await model.prepare(session: fixture.session)
        let receipt = try #require(await credentials.loadAccountDeletion())
        let request = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(request)
        let state = try #require(request.state)
        clock.date = clock.date.addingTimeInterval(271)

        model.acceptAuthorization(token: "expired-apple-token", code: "expired-code", state: state)
        await model.confirm(session: fixture.session)

        #expect(!model.hasAuthorization)
        #expect(model.requiresIdentityRefresh)
        #expect(model.phase == .review)
        var expiryNotice = try #require(model.notice)
        expiryNotice.locale = Locale(identifier: "en")
        #expect(String(localized: expiryNotice) == "This identity check has expired. Refresh the deletion details and try again.")
        #expect(await api.deletionRequests == 0)
        #expect(await credentials.loadAccountDeletion() == receipt)
        await api.setChallengeExpiry(clock.date.addingTimeInterval(300))
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 1)
        #expect(model.pending?.receipt == receipt.receipt)
    }

    @Test
    func `Identity expiring before confirmation reports recovery instead of silently ignoring deletion`() async throws {
        let fixture = DeletionFixture()
        let clock = DeletionClock()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        await api.setChallengeExpiry(clock.date.addingTimeInterval(300))
        let model = fixture.model(api: api, credentials: credentials, now: { clock.date })
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)
        clock.date = clock.date.addingTimeInterval(271)

        await model.confirm(session: fixture.session)

        #expect(!model.hasAuthorization)
        #expect(model.requiresIdentityRefresh)
        #expect(model.canRefreshPreparation)
        #expect(model.canCancelPreparation)
        #expect(await api.deletionRequests == 0)
        #expect(await credentials.loadAccountDeletion()?.submitted == false)
        var expiryNotice = try #require(model.notice)
        expiryNotice.locale = Locale(identifier: "en")
        #expect(String(localized: expiryNotice) == "This identity check has expired. Refresh the deletion details and try again.")

        await api.setChallengeExpiry(clock.date.addingTimeInterval(300))
        await model.prepare(session: fixture.session, forceRefresh: true)
        try fixture.authorize(model)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 1)
    }

    @Test
    func `Prepared status after an uncertain submission cannot enable another deletion attempt`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        await api.loseRequestBeforeAcceptance()
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        try fixture.authorize(model)
        await model.confirm(session: fixture.session)
        let sent = try #require(await credentials.loadAccountDeletion())
        try #require(sent.submitted)

        await model.checkStatus()

        #expect(model.pending?.submitted == true)
        #expect(await credentials.loadAccountDeletion()?.submitted == true)
        #expect(model.blocksAccountUse)
        #expect(!model.canAuthorize)
        #expect(model.phase == .submitted)
        #expect(!model.canCancelPreparation)
        #expect(model.canCancelRequest)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(request)
        model.acceptAuthorization(token: "second-token", code: "second-code", state: request.state)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 1)
        #expect(model.pending?.receipt == sent.receipt)

        await model.cancel()
        #expect(!model.blocksAccountUse)
        #expect(await credentials.loadAccountDeletion() == nil)
        #expect(await api.deletionRequests == 1)
    }

    @Test
    func `Apple cancellation keeps the account until a fresh verification is explicitly confirmed`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(request)
        model.receiveAppleAuthorization(.failure(CancellationError()))
        await model.confirm(session: fixture.session)
        #expect(!model.hasAuthorization)
        #expect(model.acceptedUserID == nil)
        #expect(await api.deletionRequests == 0)
        #expect(model.canCancelPreparation)
        #expect(model.canAuthorize)
        #expect(model.phase == .review)
        try fixture.authorize(model)
        await model.confirm(session: fixture.session)
        #expect(await api.deletionRequests == 1)
    }
}

private struct DeletionFixture {
    let session = SharedSession(
        accessToken: "deletion-test-session", tokenType: "Bearer", expiresAt: .distantFuture,
        user: SharedUser(id: UUID(), displayName: "Test member", group: nil)
    )

    func savedRequest(status: SharedDeletionStatus.State, submitted: Bool = false) -> PendingAccountDeletion {
        let receipt = SharedDeletionReceipt(operationId: UUID(), statusSecret: "saved-deletion-receipt")
        return PendingAccountDeletion(
            userID: session.user.id,
            receipt: receipt,
            revision: "revision-1",
            submitted: submitted,
            lastStatus: SharedDeletionStatus(operationId: receipt.operationId, status: status)
        )
    }

    @MainActor
    func model(
        api: DeletionAPI,
        credentials: any SharedDeletionCredentialStoring,
        now: @escaping @MainActor () -> Date = { Date() }
    ) -> SharedAccountDeletionViewModel {
        SharedAccountDeletionViewModel(api: api, credentials: credentials, now: now)
    }

    @MainActor
    func authorize(_ model: SharedAccountDeletionViewModel) throws {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(request)
        let state: String = try #require(request.state)
        model.acceptAuthorization(token: "fresh-apple-token", code: "fresh-code", state: state)
        #expect(model.hasAuthorization)
    }
}

@MainActor
private final class DeletionClock {
    var date = Date(timeIntervalSince1970: 2_000_000_000)
}

private actor DeletionAPI: SharedAccountDeletionAPI {
    let credentials: MemorySharedCredentialStore
    private var operationID: UUID?
    private var operationStates: [UUID: SharedDeletionStatus.State] = [:]
    private var state = SharedDeletionStatus.State.prepared
    private var losesPreparation = false
    private var losesResponse = false
    private var losesRequest = false
    private var challengeExpiry: Date?
    private var cancellationFails = false
    private var wrongOperationID = false
    private var statusFails = false
    private var rejectsChallenges = false
    private(set) var deletionRequests = 0
    private(set) var challengeRequests = 0
    private(set) var statusRequests = 0
    private(set) var hadDurableReceiptBeforeAcceptance = false

    init(credentials: MemorySharedCredentialStore) { self.credentials = credentials }
    func losePreparation() { losesPreparation = true }
    func allowPreparation() { losesPreparation = false }
    func loseAcceptanceResponse() { losesResponse = true }
    func loseRequestBeforeAcceptance() { losesRequest = true }
    func setChallengeExpiry(_ expiry: Date) { challengeExpiry = expiry }
    func setStatus(_ state: SharedDeletionStatus.State) {
        self.state = state
        if let operationID {
            operationStates[operationID] = state
        }
    }
    func seedOperation(_ id: UUID, status: SharedDeletionStatus.State) { operationStates[id] = status }
    func failCancellation() { cancellationFails = true }
    func allowCancellation() { cancellationFails = false }
    func useWrongOperationID() { wrongOperationID = true }
    func failStatus() { statusFails = true }
    func rejectChallenges() { rejectsChallenges = true }

    func deletionPreview(token: String) -> SharedDeletionPreview {
        SharedDeletionPreview(revision: "revision-1", groups: [], ownContentCount: 2, legacyContentCount: 1)
    }

    func deletionChallenge(_ request: SharedDeletionPreparation, token: String) throws -> SharedChallenge {
        challengeRequests += 1
        if losesPreparation {
            throw URLError(.networkConnectionLost)
        }
        if rejectsChallenges || operationStates[request.operationId].map({ $0 != .prepared }) == true {
            throw SharedAPIError.server(status: 409, code: "deletion_in_progress", requestID: nil, retryAfter: nil)
        }
        operationID = request.operationId
        state = .prepared
        operationStates[request.operationId] = .prepared
        return SharedChallenge(id: UUID(), nonce: "nonce", expiresAt: challengeExpiry ?? Date().addingTimeInterval(300))
    }

    func deleteAccount(_ request: SharedDeletionRequest, token: String) async throws -> SharedDeletionStatus {
        deletionRequests += 1
        let saved = await credentials.loadAccountDeletion()
        hadDurableReceiptBeforeAcceptance = saved?.receipt.operationId == request.operationId && saved?.submitted == true
        if losesRequest {
            throw URLError(.networkConnectionLost)
        }
        state = .accepted
        operationStates[request.operationId] = .accepted
        if losesResponse {
            throw URLError(.networkConnectionLost)
        }
        return SharedDeletionStatus(operationId: request.operationId, status: state)
    }

    func deletionStatus(_ receipt: SharedDeletionReceipt) throws -> SharedDeletionStatus {
        statusRequests += 1
        if statusFails {
            throw URLError(.notConnectedToInternet)
        }
        return SharedDeletionStatus(
            operationId: wrongOperationID ? UUID() : receipt.operationId,
            status: operationStates[receipt.operationId] ?? state
        )
    }

    func cancelDeletion(_ receipt: SharedDeletionReceipt) throws -> SharedDeletionStatus {
        if cancellationFails {
            throw URLError(.notConnectedToInternet)
        }
        let current = operationStates[receipt.operationId] ?? state
        let result: SharedDeletionStatus.State = current == .prepared ? .cancelled : current
        operationStates[receipt.operationId] = result
        if operationID == receipt.operationId {
            state = result
        }
        return SharedDeletionStatus(operationId: receipt.operationId, status: result)
    }

    func deletionSessionStatus(token: String) -> Bool { false }
    func claimAdministration(_ request: ResolveGroupTransferRequest, groupID: UUID, token: String) throws -> SharedGroup {
        throw SharedAPIError.invalidResponse
    }
}

private actor UnreadableDeletionCredentials: SharedDeletionCredentialStoring {
    private(set) var writes = 0
    func loadAccountDeletion() throws -> PendingAccountDeletion? { throw SharedCredentialError.corruptData }
    func saveAccountDeletion(_ deletion: PendingAccountDeletion?) { writes += 1 }
}

private actor FailingDeletionWrites: SharedDeletionCredentialStoring {
    let saved: PendingAccountDeletion?
    init(saved: PendingAccountDeletion? = nil) { self.saved = saved }
    func loadAccountDeletion() -> PendingAccountDeletion? { saved }
    func saveAccountDeletion(_ deletion: PendingAccountDeletion?) throws { throw SharedCredentialError.unavailable(status: -1) }
}
