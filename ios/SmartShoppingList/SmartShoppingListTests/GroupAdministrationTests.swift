import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
@MainActor
struct GroupAdministrationTests {
    @Test
    func `Proposing administration preserves an existing purchase selection in the same group`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials)
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await model.load()
        let item = try #require(fixture.items.first)
        model.selectedStoreID = item.storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(item)
        try #require(model.purchaseSelection == [item])
        await model.loadGroupManagement()
        model.selectedSuccessorID = GroupAdministrationAPI.successorID

        await model.proposeGroupTransfer()

        #expect(model.pendingOperation == nil)
        #expect(model.selectedStoreID == item.storeId)
        #expect(model.purchaseSelection == [item])
        #expect(model.canFinalizePurchase)
    }

    @Test
    func `A lost transfer response is persisted before sending and replays without restoring an old administrator`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials)
        await api.configure(lossAfterCommit: true)
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await model.load()
        await model.loadGroupManagement()
        model.selectedSuccessorID = GroupAdministrationAPI.successorID

        await model.proposeGroupTransfer()

        let pending = try #require(await credentials.loadOperation())
        #expect(await api.savedBeforeSending)
        #expect(!model.canMutate)
        #expect(model.draft.items == fixture.draft.items)
        var changedGroup = fixture.group
        changedGroup.administratorUserId = GroupAdministrationAPI.successorID
        await api.replaceCurrentGroup(changedGroup)

        let reopened = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await reopened.load()
        await reopened.retryPendingOperation()

        #expect(await api.operationIDs == [pending.operationID, pending.operationID])
        #expect(reopened.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(reopened.group?.administratorUserId == GroupAdministrationAPI.successorID)
        #expect(reopened.group?.creatorUserId == fixture.session.user.id)
        #expect(!reopened.canManageInvitations)
        #expect(reopened.draft.items == fixture.draft.items)
    }

    @Test(arguments: [false, true])
    func `A historical departure receipt cannot remove a later membership`(rejoinedSameGroup: Bool) async throws {
        let fixture = try SharedPreviewFixture.sample()
        var currentGroup = fixture.group
        if !rejoinedSameGroup {
            currentGroup = SharedGroup(
                id: UUID(),
                name: "Viaje",
                creatorUserId: GroupAdministrationAPI.successorID,
                createdAt: fixture.group.createdAt,
                administratorUserId: GroupAdministrationAPI.successorID
            )
        }
        var currentSession = fixture.session
        currentSession.user.group = currentGroup
        let operation = PendingSharedOperation.leaveGroup(
            userID: fixture.session.user.id,
            groupID: fixture.group.id,
            request: LeaveGroupRequest(operationId: UUID(), confirmClosure: false)
        )
        let credentials = MemorySharedCredentialStore(session: currentSession, operation: operation)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials)
        await api.replaceCurrentGroup(currentGroup)
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await model.load()

        await model.retryPendingOperation()

        #expect(model.pendingOperation == nil)
        #expect(model.group?.id == currentGroup.id)
        #expect(await credentials.loadSession()?.user.group?.id == currentGroup.id)
        #expect(model.draft.items == fixture.draft.items)
        #expect(await api.operationIDs == [operation.operationID])
    }

    @Test
    func `A confirmed transfer remains recoverable until current access can be refreshed`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials)
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await model.load()
        await model.loadGroupManagement()
        model.selectedSuccessorID = GroupAdministrationAPI.successorID
        await api.configure(failRefreshAfterCommit: true)

        await model.proposeGroupTransfer()

        let pending = try #require(model.pendingOperation)
        #expect(await credentials.loadOperation() == pending)
        #expect(!model.canManageInvitations)
        #expect(!model.canMutate)
        #expect(model.draft.items == fixture.draft.items)
        await api.configure()
        await model.retryPendingOperation()
        #expect(model.pendingOperation == nil)
        #expect(await api.operationIDs == [pending.operationID, pending.operationID])
    }

    @Test
    func `A confirmed proposal conflict unlocks the unchanged draft for review`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials)
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await model.load()
        await model.loadGroupManagement()
        model.selectedSuccessorID = GroupAdministrationAPI.successorID
        await api.configure(rejection: .server(
            status: 409,
            code: "transfer_pending",
            requestID: nil,
            retryAfter: nil
        ))

        await model.proposeGroupTransfer()

        #expect(await api.savedBeforeSending)
        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.canMutate)
        #expect(model.groupManagementState == .failed)
        #expect(model.draft.items == fixture.draft.items)
    }

    @Test
    func `A legacy session never inherits administration from its historical creator`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let legacy = Data("""
        {"accessToken":"SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSQ","tokenType":"Bearer",
        "expiresAt":900000000,"user":{"id":"\(fixture.session.user.id)","displayName":null,
        "group":{"id":"\(fixture.group.id)","name":"Casa","creatorUserId":"\(fixture.session.user.id)",
        "createdAt":800000000}}}
        """.utf8)
        let session = try JSONDecoder().decode(SharedSession.self, from: legacy)
        let credentials = MemorySharedCredentialStore(session: session)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials)
        await api.replaceCurrentGroup(session.user.group)
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)

        await model.load()
        await model.openInvitations()

        #expect(model.group?.id == fixture.group.id)
        #expect(!model.isAdministrator)
        #expect(!model.canManageInvitations)
        #expect(!model.isInvitationsPresented)
        #expect(model.draft.items == fixture.draft.items)
    }

    @Test(arguments: [SharedGroupTransferAction.accept, .reject, .withdraw])
    func `Resolving a transfer records the original action and applies only current permissions`(
        _ action: SharedGroupTransferAction
    ) async throws {
        let fixture = try SharedPreviewFixture.sample()
        var session = fixture.session
        if action != .withdraw {
            session.user = SharedUser(id: GroupAdministrationAPI.successorID, displayName: nil, group: fixture.group)
        }
        let credentials = MemorySharedCredentialStore(session: session)
        let api = GroupAdministrationAPI(fixture: fixture, credentials: credentials, actorID: session.user.id)
        await api.preparePendingTransfer()
        let model = try makeModel(api: api, credentials: credentials, draft: fixture.draft)
        await model.load()
        await model.loadGroupManagement()

        await model.resolveGroupTransfer(action)

        #expect(await api.savedBeforeSending)
        #expect(await api.resolvedActions == [action])
        #expect(model.pendingOperation == nil)
        #expect(model.canManageInvitations == (action != .reject))
        #expect(model.group?.creatorUserId == fixture.group.creatorUserId)
    }

    private func makeModel(
        api: GroupAdministrationAPI,
        credentials: MemorySharedCredentialStore,
        draft: ShoppingDraftSnapshot
    ) throws -> SharedShoppingViewModel {
        SharedShoppingViewModel(
            api: api,
            configuration: try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test"),
            credentials: credentials,
            draft: DraftPreviewSupport.viewModel(snapshot: draft, state: .content),
            storeQuery: StoreQueryViewModel(speech: GroupAdministrationSpeech())
        )
    }
}

private actor GroupAdministrationAPI: SharedShoppingAPI {
    static let successorID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 2))
    private let fixture: SharedPreviewFixture
    private let credentials: MemorySharedCredentialStore
    private var user: SharedUser
    private var transfer: SharedGroupTransfer?
    private var receipt: SharedGroupTransferResult?
    private var lossAfterCommit = false
    private var failRefreshAfterCommit = false
    private var rejection: SharedAPIError?
    private(set) var savedBeforeSending = false
    private(set) var operationIDs: [UUID] = []
    private(set) var resolvedActions: [SharedGroupTransferAction] = []

    init(fixture: SharedPreviewFixture, credentials: MemorySharedCredentialStore, actorID: UUID? = nil) {
        self.fixture = fixture
        self.credentials = credentials
        user = SharedUser(id: actorID ?? fixture.session.user.id, displayName: nil, group: fixture.group)
    }

    func configure(
        lossAfterCommit: Bool = false,
        failRefreshAfterCommit: Bool = false,
        rejection: SharedAPIError? = nil
    ) {
        self.lossAfterCommit = lossAfterCommit
        self.failRefreshAfterCommit = failRefreshAfterCommit
        self.rejection = rejection
    }

    func replaceCurrentGroup(_ group: SharedGroup?) {
        user.group = group
    }

    func preparePendingTransfer() {
        transfer = SharedGroupTransfer(
            id: UUID(),
            groupId: fixture.group.id,
            proposerUserId: fixture.session.user.id,
            recipientUserId: Self.successorID,
            status: .pending,
            createdAt: fixture.group.createdAt,
            expiresAt: fixture.group.createdAt.addingTimeInterval(604_800),
            resolvedAt: nil
        )
    }

    func groups(token: String) async throws -> [SharedGroup] {
        user.group.map { [$0] } ?? []
    }

    func currentUser(token: String) async throws -> SharedUser {
        if failRefreshAfterCommit, receipt != nil {
            throw SharedAPIError.transport
        }
        var current = user
        current.accountCapabilities = try SharedAccountCapabilities(
            membershipCount: user.group == nil ? 0 : 1,
            canCreateGroup: user.group == nil,
            canJoinGroup: user.group == nil,
            limits: SharedAccountLimits(groupsPerAccount: SharedResourceLimit(maximum: 1, enforced: true))
        )
        return current
    }

    func groupMembers(groupID: UUID, token: String) async throws -> [SharedGroupMember] {
        [
            SharedGroupMember(id: fixture.session.user.id, displayName: nil),
            SharedGroupMember(id: Self.successorID, displayName: nil)
        ]
    }

    func groupAdministration(groupID: UUID, token: String) async throws -> SharedGroupAdministration {
        let group = try #require(user.group)
        let administrator = group.administratorUserId == user.id
        let recipient = transfer?.recipientUserId == user.id
        return SharedGroupAdministration(
            group: group,
            memberCount: 2,
            pendingTransfer: transfer,
            capabilities: SharedGroupCapabilities(
                canManageInvitations: administrator,
                canProposeTransfer: administrator && transfer == nil,
                canAcceptTransfer: recipient,
                canRejectTransfer: recipient,
                canWithdrawTransfer: administrator && transfer != nil,
                canLeave: !administrator,
                requiresClosureConfirmation: false,
                capacityOwnerUserId: group.administratorUserId ?? fixture.session.user.id,
                limits: SharedGroupLimits(
                    groupsPerAccount: SharedResourceLimit(maximum: 1, enforced: true),
                    storesPerGroup: SharedResourceLimit(maximum: nil, enforced: false),
                    pendingItemsPerStore: SharedResourceLimit(maximum: nil, enforced: false)
                )
            )
        )
    }

    func proposeTransfer(
        _ request: ProposeGroupTransferRequest,
        groupID: UUID,
        token: String
    ) async throws -> SharedGroupTransferResult {
        await recordSubmission(request.operationId)
        if let rejection {
            throw rejection
        }
        if let receipt {
            return receipt
        }
        preparePendingTransfer()
        let result = SharedGroupTransferResult(group: fixture.group, transfer: try #require(transfer))
        receipt = result
        if lossAfterCommit {
            throw SharedAPIError.transport
        }
        return result
    }

    func resolveTransfer(
        _ request: ResolveGroupTransferRequest,
        groupID: UUID,
        transferID: UUID,
        action: SharedGroupTransferAction,
        token: String
    ) async throws -> SharedGroupTransferResult {
        await recordSubmission(request.operationId)
        resolvedActions.append(action)
        let original = try #require(transfer)
        var group = fixture.group
        if action == .accept {
            group.administratorUserId = Self.successorID
        }
        let status: SharedGroupTransferStatus = switch action {
        case .accept: .accepted
        case .reject: .rejected
        case .withdraw: .withdrawn
        }
        let result = SharedGroupTransferResult(
            group: group,
            transfer: SharedGroupTransfer(
                id: original.id,
                groupId: groupID,
                proposerUserId: original.proposerUserId,
                recipientUserId: original.recipientUserId,
                status: status,
                createdAt: original.createdAt,
                expiresAt: original.expiresAt,
                resolvedAt: original.createdAt.addingTimeInterval(60)
            )
        )
        user.group = group
        transfer = nil
        receipt = result
        return result
    }

    func leaveGroup(_ request: LeaveGroupRequest, groupID: UUID, token: String) async throws -> SharedGroupDeparture {
        await recordSubmission(request.operationId)
        return SharedGroupDeparture(
            userId: user.id,
            groupId: groupID,
            leftAt: fixture.group.createdAt,
            groupClosed: false
        )
    }

    private func recordSubmission(_ id: UUID) async {
        operationIDs.append(id)
        savedBeforeSending = await credentials.loadOperation()?.operationID == id
    }

    func stores(groupID: UUID, token: String) async throws -> [SharedStore] {
        fixture.stores.filter { $0.groupId == groupID }
    }
    func archivedStores(groupID: UUID, token: String) async throws -> [SharedStore] { [] }
    func groupCapacity(groupID: UUID, token: String) async throws -> SharedGroupCapacity {
        let count = fixture.stores.filter { $0.groupId == groupID }.count
        return try SharedGroupCapacity(
            groupId: groupID,
            capacityOwnerUserId: user.group?.administratorUserId ?? fixture.session.user.id,
            activeStoreCount: count,
            limits: SharedStoreLimits(
                storesPerGroup: SharedResourceLimit(maximum: 3, enforced: true),
                pendingItemsPerStore: SharedResourceLimit(maximum: 20, enforced: true)
            ),
            canCreateStore: count < 3
        )
    }
    func changeStoreState(
        _ request: ChangeStoreStateRequest,
        groupID: UUID,
        storeID: UUID,
        action: SharedStoreAction,
        token: String
    ) async throws -> SharedStore {
        throw SharedAPIError.configuration
    }
    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem] {
        fixture.items.filter { $0.groupId == groupID && $0.storeId == storeID }
    }
    func createChallenge() async throws -> SharedChallenge { throw SharedAPIError.configuration }
    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession { throw SharedAPIError.configuration }
    func logout(token: String) async throws {}
    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func createInvitation(groupID: UUID, token: String) async throws -> CreatedInvitation {
        throw SharedAPIError.configuration
    }
    func invitations(groupID: UUID, token: String) async throws -> [SharedInvitation] { [] }
    func revokeInvitation(groupID: UUID, invitationID: UUID, token: String) async throws {}
    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview {
        throw SharedAPIError.configuration
    }
    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        throw SharedAPIError.configuration
    }
    func finalizePurchase(
        _ request: FinalizePurchaseRequest,
        groupID: UUID,
        token: String
    ) async throws -> PurchaseResult {
        throw SharedAPIError.configuration
    }
    func changeItem(_ request: SharedItemChangeRequest, item: SharedItem, token: String) async throws -> SharedItem {
        throw SharedAPIError.configuration
    }
}

private struct GroupAdministrationSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SharedAPIError.configuration
    }
    func finish() async throws {}
    func cancel() async {}
}
