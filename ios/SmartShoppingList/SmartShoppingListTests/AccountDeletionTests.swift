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
        #expect(model.canDismissResult)
        await model.dismissResult()
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
    func `Apple cancellation keeps the account and never sends deletion`() async throws {
        let fixture = DeletionFixture()
        let credentials = MemorySharedCredentialStore()
        let api = DeletionAPI(credentials: credentials)
        let model = fixture.model(api: api, credentials: credentials)
        await model.prepare(session: fixture.session)
        model.receiveAppleAuthorization(.failure(CancellationError()))
        await model.confirm(session: fixture.session)
        #expect(!model.hasAuthorization)
        #expect(model.acceptedUserID == nil)
        #expect(await api.deletionRequests == 0)
    }
}

private struct DeletionFixture {
    let session = SharedSession(
        accessToken: "deletion-test-session", tokenType: "Bearer", expiresAt: .distantFuture,
        user: SharedUser(id: UUID(), displayName: "Test member", group: nil)
    )

    @MainActor
    func model(api: DeletionAPI, credentials: any SharedDeletionCredentialStoring) -> SharedAccountDeletionViewModel {
        SharedAccountDeletionViewModel(api: api, credentials: credentials)
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

private actor DeletionAPI: SharedAccountDeletionAPI {
    let credentials: MemorySharedCredentialStore
    private var operationID: UUID?
    private var state = SharedDeletionStatus.State.prepared
    private var losesPreparation = false
    private var losesResponse = false
    private var cancellationFails = false
    private var wrongOperationID = false
    private(set) var deletionRequests = 0
    private(set) var challengeRequests = 0
    private(set) var hadDurableReceiptBeforeAcceptance = false

    init(credentials: MemorySharedCredentialStore) { self.credentials = credentials }
    func losePreparation() { losesPreparation = true }
    func loseAcceptanceResponse() { losesResponse = true }
    func setStatus(_ state: SharedDeletionStatus.State) { self.state = state }
    func failCancellation() { cancellationFails = true }
    func allowCancellation() { cancellationFails = false }
    func useWrongOperationID() { wrongOperationID = true }

    func deletionPreview(token: String) -> SharedDeletionPreview {
        SharedDeletionPreview(revision: "revision-1", groups: [], ownContentCount: 2, legacyContentCount: 1)
    }

    func deletionChallenge(_ request: SharedDeletionPreparation, token: String) throws -> SharedChallenge {
        challengeRequests += 1
        if losesPreparation {
            throw URLError(.networkConnectionLost)
        }
        operationID = request.operationId
        return SharedChallenge(id: UUID(), nonce: "nonce", expiresAt: Date().addingTimeInterval(300))
    }

    func deleteAccount(_ request: SharedDeletionRequest, token: String) async throws -> SharedDeletionStatus {
        deletionRequests += 1
        let saved = await credentials.loadAccountDeletion()
        hadDurableReceiptBeforeAcceptance = saved?.receipt.operationId == request.operationId && saved?.submitted == true
        state = .accepted
        if losesResponse {
            throw URLError(.networkConnectionLost)
        }
        return SharedDeletionStatus(operationId: request.operationId, status: state)
    }

    func deletionStatus(_ receipt: SharedDeletionReceipt) -> SharedDeletionStatus {
        SharedDeletionStatus(operationId: wrongOperationID ? UUID() : receipt.operationId, status: state)
    }

    func cancelDeletion(_ receipt: SharedDeletionReceipt) throws -> SharedDeletionStatus {
        if cancellationFails {
            throw URLError(.notConnectedToInternet)
        }
        if state == .prepared {
            state = .cancelled
        }
        return SharedDeletionStatus(operationId: receipt.operationId, status: state)
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
    func loadAccountDeletion() -> PendingAccountDeletion? { nil }
    func saveAccountDeletion(_ deletion: PendingAccountDeletion?) throws { throw SharedCredentialError.unavailable(status: -1) }
}
