import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
@MainActor
struct StoreQuotaTests {
    @Test(arguments: [false, true])
    func `The management refresh action can reverify a cached session after a temporary lookup failure`(
        failsOnInitialLoad: Bool
    ) async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        let model = makeModel(fixture, api: api, credentials: credentials)
        if failsOnInitialLoad {
            await api.failNextUserLookup()
        }
        await model.load()
        if !failsOnInitialLoad {
            await api.failNextUserLookup()
            await model.loadStoreManagement()
        }
        try #require(!model.groupsAreVerified)
        #expect(!model.canMutate)
        if failsOnInitialLoad {
            #expect(!model.sessionIsVerified)
        }

        await model.loadStoreManagement()

        #expect(model.sessionIsVerified)
        #expect(model.groupsAreVerified)
        #expect(model.storeManagementState == .loaded)
        #expect(model.canChangeStoreState(try #require(model.stores.last), action: .archive))
    }

    @Test
    func `Management refresh adopts a changed administrator and revokes the former owner's actions`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await model.loadStoreManagement()
        let emptyStore = try #require(model.stores.last)
        try #require(model.canChangeStoreState(emptyStore, action: .archive))
        let successorID = UUID()
        await api.changeAdministrator(to: successorID)

        await model.loadStoreManagement()

        #expect(model.storeManagementState == .loaded)
        #expect(model.groupCapacity?.capacityOwnerUserId == successorID)
        #expect(model.group?.administratorUserId == successorID)
        #expect(!model.canChangeStoreState(try #require(model.stores.last), action: .archive))
        #expect(model.storeActionMessage(emptyStore, action: .archive) != nil)
        #expect(model.draft.items == fixture.draft.items)
    }

    @Test(arguments: [SharedStoreAction.archive, .restore])
    func `A lost store response survives reopening and its historical receipt never overwrites current state`(
        action: SharedStoreAction
    ) async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        await api.setEmptyStoreArchived(action == .restore)
        await api.loseNextStoreResponse()
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await model.loadStoreManagement()
        let store = try #require(action == .archive ? model.stores.last : model.archivedStores.first)

        await model.changeStoreState(store, action: action)

        let pending = try #require(await credentials.loadOperation())
        #expect(await api.savedBeforeSending)
        #expect(!model.canMutate)
        guard case .changeStoreState(let userID, let groupID, let storeID, let savedAction, _) = pending else {
            Issue.record("Store recovery lost its route")
            return
        }
        #expect(userID == fixture.session.user.id)
        #expect(groupID == fixture.group.id)
        #expect(storeID == store.id)
        #expect(savedAction == action)
        // Another member changes the live state after the original commit; the old receipt remains immutable.
        await api.setEmptyStoreArchived(action == .restore)
        let reopened = makeModel(fixture, api: api, credentials: credentials)
        await reopened.load()
        await reopened.retryPendingOperation()

        #expect(await api.storeOperationIDs == [pending.operationID, pending.operationID])
        #expect(reopened.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(reopened.stores.contains { $0.id == store.id } == (action == .archive))
        #expect(reopened.archivedStores.contains { $0.id == store.id } == (action == .restore))
        #expect(reopened.draft.items == fixture.draft.items)
    }

    @Test(arguments: [SharedStoreAction.archive, .restore])
    func `A refused store action can be explicitly confirmed again with a fresh operation after refreshing`(
        action: SharedStoreAction
    ) async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        await api.setEmptyStoreArchived(action == .restore)
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await model.loadStoreManagement()
        await api.rejectNextStoreChange(code: action == .archive ? "store_not_empty" : "store_limit_reached")
        let original = try #require(action == .archive ? model.stores.last : model.archivedStores.first)

        await model.changeStoreState(original, action: action)

        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.notice != nil)
        #expect(model.draft.items == fixture.draft.items)
        let refusedID = try #require(await api.storeOperationIDs.first)
        let refreshed = try #require(action == .archive ? model.stores.last : model.archivedStores.first)
        await model.changeStoreState(refreshed, action: action)
        let ids = await api.storeOperationIDs
        #expect(ids.count == 2)
        #expect(ids.last != refusedID)
        #expect(model.pendingOperation == nil)
    }

    @Test
    func `A confirmed store action remains recoverable until fresh access and capacity are available`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await model.loadStoreManagement()
        await api.failRefreshAfterStoreCommit()

        await model.changeStoreState(try #require(model.stores.last), action: .archive)

        let pending = try #require(model.pendingOperation)
        #expect(await credentials.loadOperation() == pending)
        #expect(!model.canMutate)
        await api.allowRefresh()
        await model.retryPendingOperation()
        #expect(await api.storeOperationIDs == [pending.operationID, pending.operationID])
        #expect(model.pendingOperation == nil)
        #expect(model.archivedStores.count == 1)
    }

    @Test(arguments: ["store_limit_reached", "pending_item_limit_reached", "store_archived"])
    func `A definitive addition refusal keeps the draft and a later confirmation creates a new intention`(
        code: String
    ) async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await api.rejectNextAddition(code: code)

        await model.addDraftItems()

        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.draft.items == fixture.draft.items)
        #expect(model.notice != nil)
        let refused = try #require(await api.additionOperationIDs.first)
        await model.addDraftItems()
        let ids = await api.additionOperationIDs
        #expect(ids.count == 2)
        #expect(ids.last != refused)
        #expect(model.draft.items.isEmpty)
    }

    @Test
    func `Full stores block growth while name corrections and cancellation remain available`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        await api.fillStores()
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await model.addDraftItems()
        #expect(await api.additionOperationIDs.isEmpty)
        #expect(model.draft.items == fixture.draft.items)
        model.selectedStoreID = fixture.stores[0].id
        await model.loadSelectedStore()
        let item = try #require(model.items.first)
        model.togglePurchaseItem(item)
        #expect(model.canFinalizePurchase)
        model.beginEditingItem(item)
        model.editName = "Leche corregida"
        #expect(model.canSaveItemEdit)
        model.editStoreID = fixture.stores[1].id
        #expect(!model.canSaveItemEdit)
        #expect(model.editValidationMessage != nil)
        model.editStoreID = item.storeId
        await model.saveItemEdit()
        #expect(await api.changedNames == ["Leche corregida"])
        let corrected = try #require(model.items.first)
        await model.cancelItem(corrected)
        #expect(await api.cancelledItemIDs == [item.id])
    }

    @Test
    func `A rejected move preserves the correction and a corrected destination uses a new intention`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        model.selectedStoreID = fixture.stores[0].id
        await model.loadSelectedStore()
        let item = try #require(model.items.first)
        model.beginEditingItem(item)
        model.editName = "Leche sin lactosa corregida"
        model.editStoreID = fixture.stores[1].id
        await api.rejectNextItemChange()

        await model.saveItemEdit()

        #expect(model.editName == "Leche sin lactosa corregida")
        #expect(model.editStoreID == fixture.stores[1].id)
        #expect(model.pendingOperation == nil)
        #expect(!model.editNeedsReview)
        let refused = try #require(await api.changeOperationIDs.first)
        model.editStoreID = item.storeId
        await model.saveItemEdit()
        let ids = await api.changeOperationIDs
        #expect(ids.count == 2)
        #expect(ids.last != refused)
        #expect(model.items.first?.name == "Leche sin lactosa corregida")
    }

    @Test
    func `Unverified legacy store data cannot authorize growth or store administration`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        await api.returnLegacyStores()
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        await model.loadStoreManagement()
        #expect(model.storeManagementState == .failed)
        #expect(!model.canChangeStoreState(try #require(model.stores.last), action: .archive))
        await model.addDraftItems()
        #expect(await api.additionOperationIDs.isEmpty)
        #expect(model.draft.items == fixture.draft.items)
    }

    @Test
    func `Siri keeps a full store addition in the draft for review`() async throws {
        let fixture = try SharedPreviewFixture.sample()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let api = StoreQuotaAPI(fixture: fixture, credentials: credentials)
        await api.fillStores()
        let model = makeModel(fixture, api: api, credentials: credentials)
        await model.load()
        let entry = ShoppingDraftItem(name: "Arroz", quantity: "", store: fixture.stores[0].name)

        let outcome = try await model.addShoppingItemFromIntent(entry)

        #expect(outcome == .savedToDraft)
        #expect(model.draft.items.contains { $0.name == "Arroz" })
        #expect(await api.additionOperationIDs.isEmpty)
    }

    private func makeModel(
        _ fixture: SharedPreviewFixture,
        api: StoreQuotaAPI,
        credentials: MemorySharedCredentialStore
    ) -> SharedShoppingViewModel {
        SharedShoppingViewModel(
            api: api,
            configuration: fixture.configuration,
            credentials: credentials,
            draft: DraftPreviewSupport.viewModel(snapshot: fixture.draft, state: .content),
            storeQuery: StoreQueryViewModel(speech: StoreQuotaSpeech())
        )
    }
}

private actor StoreQuotaAPI: SharedShoppingAPI {
    let fixture: SharedPreviewFixture
    let credentials: MemorySharedCredentialStore
    private var group: SharedGroup
    private var storedItems: [SharedItem]
    private var emptyStoreArchived = false
    private var fullStores = false
    private var legacyStores = false
    private var loseStoreResponse = false
    private var refreshFailsAfterCommit = false
    private var receipt: SharedStore?
    private var additionError: String?
    private var itemChangeError = false
    private var storeError: String?
    private var userLookupFails = false
    private(set) var savedBeforeSending = false
    private(set) var storeOperationIDs: [UUID] = []
    private(set) var additionOperationIDs: [UUID] = []
    private(set) var changeOperationIDs: [UUID] = []
    private(set) var changedNames: [String] = []
    private(set) var cancelledItemIDs: [UUID] = []

    init(fixture: SharedPreviewFixture, credentials: MemorySharedCredentialStore) {
        self.fixture = fixture
        self.credentials = credentials
        group = fixture.group
        storedItems = fixture.items
    }

    func failNextUserLookup() {
        userLookupFails = true
    }
    func changeAdministrator(to id: UUID) {
        group.administratorUserId = id
    }
    func setEmptyStoreArchived(_ archived: Bool) {
        emptyStoreArchived = archived
    }
    func loseNextStoreResponse() {
        loseStoreResponse = true
    }
    func failRefreshAfterStoreCommit() {
        refreshFailsAfterCommit = true
    }
    func allowRefresh() {
        refreshFailsAfterCommit = false
    }
    func fillStores() {
        fullStores = true
    }
    func returnLegacyStores() {
        legacyStores = true
    }
    func rejectNextAddition(code: String) {
        additionError = code
    }
    func rejectNextStoreChange(code: String) {
        storeError = code
    }
    func rejectNextItemChange() {
        itemChangeError = true
    }

    func currentUser(token: String) async throws -> SharedUser {
        if userLookupFails {
            userLookupFails = false
            throw SharedAPIError.transport
        }
        if refreshFailsAfterCommit, receipt != nil {
            throw SharedAPIError.transport
        }
        return SharedUser(
            id: fixture.session.user.id,
            displayName: "Alex",
            group: group,
            accountCapabilities: try SharedAccountCapabilities(
                membershipCount: 1,
                canCreateGroup: false,
                canJoinGroup: false,
                limits: SharedAccountLimits(groupsPerAccount: SharedResourceLimit(maximum: 1, enforced: true))
            )
        )
    }
    func groups(token: String) async throws -> [SharedGroup] { [group] }
    func groupAdministration(groupID: UUID, token: String) async throws -> SharedGroupAdministration {
        let administrator = group.administratorUserId == fixture.session.user.id
        return SharedGroupAdministration(
            group: group,
            memberCount: 2,
            pendingTransfer: nil,
            capabilities: SharedGroupCapabilities(
                canManageInvitations: administrator,
                canProposeTransfer: administrator,
                canAcceptTransfer: false,
                canRejectTransfer: false,
                canWithdrawTransfer: false,
                canLeave: !administrator,
                requiresClosureConfirmation: false,
                capacityOwnerUserId: try #require(group.administratorUserId),
                limits: SharedGroupLimits(
                    groupsPerAccount: SharedResourceLimit(maximum: 1, enforced: true),
                    storesPerGroup: SharedResourceLimit(maximum: 3, enforced: true),
                    pendingItemsPerStore: SharedResourceLimit(maximum: 20, enforced: true)
                )
            )
        )
    }
    func groupCapacity(groupID: UUID, token: String) async throws -> SharedGroupCapacity {
        try SharedGroupCapacity(
            groupId: groupID,
            capacityOwnerUserId: try #require(group.administratorUserId),
            activeStoreCount: emptyStoreArchived ? 1 : 2,
            limits: SharedStoreLimits(
                storesPerGroup: SharedResourceLimit(maximum: 3, enforced: true),
                pendingItemsPerStore: SharedResourceLimit(maximum: 20, enforced: true)
            ),
            canCreateStore: true
        )
    }
    private func store(_ original: SharedStore, archived: Bool = false) throws -> SharedStore {
        var store = original
        if legacyStores {
            store.state = nil
            return store
        }
        let count = archived ? 0 : fullStores ? 20 : storedItems.filter { $0.storeId == store.id }.count
        let administrator = group.administratorUserId == fixture.session.user.id
        store.state = try SharedStoreState(
            archivedAt: archived ? fixture.group.createdAt : nil,
            pendingItemCount: count,
            capabilities: SharedStoreCapabilities(
                canAddItems: !archived && count < 20,
                canArchive: !archived && count == 0 && administrator,
                canRestore: archived && administrator
            )
        )
        return store
    }
    func stores(groupID: UUID, token: String) async throws -> [SharedStore] {
        try fixture.stores.filter { !emptyStoreArchived || $0.id != fixture.stores[1].id }.map { try store($0) }
    }
    func archivedStores(groupID: UUID, token: String) async throws -> [SharedStore] {
        guard emptyStoreArchived else { return [] }
        return [try store(fixture.stores[1], archived: true)]
    }
    func changeStoreState(
        _ request: ChangeStoreStateRequest,
        groupID: UUID,
        storeID: UUID,
        action: SharedStoreAction,
        token: String
    ) async throws -> SharedStore {
        storeOperationIDs.append(request.operationId)
        savedBeforeSending = await credentials.loadOperation()?.operationID == request.operationId
        if let receipt {
            return receipt
        }
        if let code = storeError {
            storeError = nil
            throw SharedAPIError.server(
                status: 409,
                code: code,
                requestID: UUID(),
                retryAfter: nil
            )
        }
        emptyStoreArchived = action == .archive
        let committed = try store(fixture.stores[1], archived: emptyStoreArchived)
        receipt = committed
        if loseStoreResponse {
            throw SharedAPIError.transport
        }
        return committed
    }
    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        additionOperationIDs.append(request.operationId)
        if let code = additionError {
            additionError = nil
            throw SharedAPIError.server(
                status: 409,
                code: code,
                requestID: UUID(),
                retryAfter: nil
            )
        }
        return fixture.items
    }
    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem] {
        storedItems.filter { $0.storeId == storeID }
    }
    func changeItem(_ request: SharedItemChangeRequest, item: SharedItem, token: String) async throws -> SharedItem {
        changeOperationIDs.append(request.operationId)
        if itemChangeError {
            itemChangeError = false
            throw SharedAPIError.server(
                status: 409,
                code: "pending_item_limit_reached",
                requestID: UUID(),
                retryAfter: nil
            )
        }
        let replacement = request.replacement
        let updated = SharedItem(
            id: item.id,
            groupId: item.groupId,
            storeId: item.storeId,
            name: replacement?.name ?? item.name,
            quantity: replacement?.quantity,
            status: replacement == nil ? "cancelled" : "pending",
            version: item.version + 1,
            createdBy: item.createdBy,
            createdAt: item.createdAt,
            purchasedBy: nil,
            purchasedAt: nil
        )
        storedItems.removeAll { $0.id == item.id }
        if replacement == nil {
            cancelledItemIDs.append(item.id)
        } else {
            changedNames.append(updated.name)
            storedItems.insert(updated, at: 0)
        }
        return updated
    }
    func createChallenge() async throws -> SharedChallenge { throw SharedAPIError.configuration }
    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession {
        throw SharedAPIError.configuration
    }
    func logout(token: String) async throws {}
    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func groupMembers(groupID: UUID, token: String) async throws -> [SharedGroupMember] { [] }
    func proposeTransfer(
        _ request: ProposeGroupTransferRequest,
        groupID: UUID,
        token: String
    ) async throws -> SharedGroupTransferResult {
        throw SharedAPIError.configuration
    }
    func resolveTransfer(
        _ request: ResolveGroupTransferRequest,
        groupID: UUID,
        transferID: UUID,
        action: SharedGroupTransferAction,
        token: String
    ) async throws -> SharedGroupTransferResult {
        throw SharedAPIError.configuration
    }
    func leaveGroup(_ request: LeaveGroupRequest, groupID: UUID, token: String) async throws -> SharedGroupDeparture {
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
    func finalizePurchase(
        _ request: FinalizePurchaseRequest,
        groupID: UUID,
        token: String
    ) async throws -> PurchaseResult {
        throw SharedAPIError.configuration
    }
}

private struct StoreQuotaSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }
    func finish() async throws {}
    func cancel() async {}
}
