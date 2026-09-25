import AuthenticationServices
import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast)) @MainActor
struct SharedShoppingViewModelTests {
    @Test("Root alerts wait until the presented sheet finishes dismissing")
    func noticesWaitForSheetDismissal() throws {
        let model = try makeModel(api: SharedFlowAPI(), credentials: MemorySharedCredentialStore())
        #expect(model.canPresentRootNotice)
        model.isReviewPresented = true
        #expect(!model.canPresentRootNotice)
        model.isReviewPresented = false
        #expect(!model.canPresentRootNotice)
        model.reviewPresentationDidDismiss()
        #expect(model.canPresentRootNotice)

        model.isInvitationsPresented = true
        model.isInvitationsPresented = false
        #expect(!model.canPresentRootNotice)
        model.invitationsPresentationDidDismiss()
        #expect(model.canPresentRootNotice)

        model.draft.beginAddingItem()
        #expect(!model.canPresentRootNotice)
        model.draft.cancelEditor()
        #expect(!model.canPresentRootNotice)
        model.draft.editorPresentationDidDismiss()
        #expect(model.canPresentRootNotice)
    }

    @Test("A reopened uncertain batch retries its original intent and consumes only confirmed draft rows")
    func persistedRetry() async throws {
        let first = ShoppingDraftItem(name: "Leche sin lactosa", quantity: "2 litros", store: "Día")
        let later = ShoppingDraftItem(name: "Pan", quantity: "", store: "Día")
        let api = SharedFlowAPI()
        let session = api.session
        let group = try #require(session.user.group)
        let request = AddItemsRequest(
            operationId: UUID(),
            items: [SharedNewItem(name: first.name, quantity: first.quantity, store: .newName(first.store))]
        )
        let original = PendingSharedOperation.addItems(
            userID: session.user.id,
            groupID: group.id,
            request: request,
            sourceDraft: ShoppingDraftSnapshot(items: [first])
        )
        let credentials = MemorySharedCredentialStore(session: session, operation: original)
        let model = try makeModel(api: api, credentials: credentials, items: [first, later])
        await model.load()
        await model.retryPendingOperation()
        #expect(model.pendingOperation == original)
        #expect(model.draft.items == [first, later])
        let failureNotice = try #require(model.presentedNotice)
        model.dismissPresentedNotice(failureNotice)
        #expect(model.notice == nil)
        #expect(model.pendingOperation == original)
        #expect(await credentials.loadOperation() == original)
        #expect(model.draft.items == [first, later])
        await model.retryPendingOperation()
        #expect(await api.sentBatches == [request, request])
        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.draft.items == [later])
    }

    @Test("An uncertain operation from a different account cannot be replayed")
    func anotherAccountCannotRetry() async throws {
        let api = SharedFlowAPI()
        let session = api.session
        let operation = PendingSharedOperation.createGroup(
            userID: UUID(),
            request: CreateGroupRequest(operationId: UUID(), name: "Casa")
        )
        let credentials = MemorySharedCredentialStore(session: session, operation: operation)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        await model.retryPendingOperation()
        #expect(await api.createdGroups == 0)
        #expect(model.pendingOperation == operation)
        #expect(!model.canMutate)
    }

    @Test("A mismatched Apple state never sends credentials and preserves the pending invitation")
    func wrongState() async throws {
        let api = SharedFlowAPI()
        let invitation = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
        let credentials = MemorySharedCredentialStore(invitation: invitation)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        await model.prepareAppleLogin()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(request)
        await model.completeAppleLogin(
            token: "token",
            code: "code",
            returnedState: "wrong",
            displayName: nil
        )
        #expect(await api.loginRequests == 0)
        #expect(await credentials.loadInvitation() == invitation)
        #expect(model.session == nil)
    }

    @Test("Opening a trusted link before login persists it without accepting a group")
    func invitationBeforeLogin() async throws {
        let api = SharedFlowAPI()
        let credentials = MemorySharedCredentialStore()
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        let id = UUID()
        let url = try #require(URL(string: "https://links.test/invite/\(id.uuidString.lowercased())#token=\(String(repeating: "A", count: 43))"))
        await model.receiveInvitation(url)
        #expect(await credentials.loadInvitation()?.id == id)
        #expect(await api.acceptedInvitations == 0)
        #expect(model.group == nil)
    }

    @Test("A link received during startup is persisted before loading completes", .timeLimit(.minutes(1)))
    func invitationDuringStartup() async throws {
        let gate = SharedFlowGate()
        let api = SharedFlowAPI(currentUserGate: gate)
        let credentials = ObservedSharedCredentials(session: api.session)
        let model = try makeModel(api: api, credentials: credentials)
        let loading = Task {
            await model.load()
        }
        await gate.waitUntilReached()
        let invitation = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
        await model.receiveInvitation(invitationURL(invitation))
        let receivedBeforeLoad = await credentials.loadIncomingInvitation()
        await gate.open()
        await loading.value
        try #require(receivedBeforeLoad == invitation)
        await credentials.waitForSavedInvitation(invitation.id)
        #expect(await credentials.loadInvitation() == invitation)
        #expect(model.hasLoaded)
        #expect(await api.acceptedInvitations == 0)
    }

    @Test("A link received while Apple's sheet is active survives login", .timeLimit(.minutes(1)))
    func invitationDuringAppleLogin() async throws {
        let api = SharedFlowAPI()
        let credentials = ObservedSharedCredentials()
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        await model.prepareAppleLogin()
        let appleRequest = ASAuthorizationAppleIDProvider().createRequest()
        model.configureAppleRequest(appleRequest)
        let invitation = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
        await model.receiveInvitation(invitationURL(invitation))
        let receivedDuringApple = await credentials.loadIncomingInvitation()
        await model.completeAppleLogin(
            token: "native-fixture", code: "single-use-fixture", returnedState: appleRequest.state, displayName: nil
        )
        try #require(receivedDuringApple == invitation)
        await credentials.waitForSavedInvitation(invitation.id)
        #expect(await credentials.loadInvitation() == invitation)
        #expect(await api.loginRequests == 1)
        #expect(await api.acceptedInvitations == 0)
    }

    @Test("A failed acceptance retains its original link and a newly received link separately", .timeLimit(.minutes(1)))
    func incomingDoesNotReplaceUncertainAcceptance() async throws {
        let gate = SharedFlowGate()
        let api = SharedFlowAPI(acceptanceGate: gate, acceptanceError: .transport)
        let original = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
        let incoming = PendingInvitation(id: UUID(), token: String(repeating: "E", count: 43))
        let credentials = MemorySharedCredentialStore(session: api.session, invitation: original)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        let acceptance = Task {
            await model.acceptInvitation()
        }
        await gate.waitUntilReached()
        await model.receiveInvitation(invitationURL(incoming))
        await gate.open()
        await acceptance.value
        #expect(await credentials.loadInvitation() == original)
        #expect(await credentials.loadIncomingInvitation() == incoming)
        #expect(model.pendingInvitation == original)
        #expect(await api.acceptedInvitations == 1)
    }

    @Test("Promoting a link cannot erase a newer link received during its Keychain save", .timeLimit(.minutes(1)))
    func newerIncomingSurvivesPromotion() async throws {
        let gate = SharedFlowGate()
        let api = SharedFlowAPI()
        let credentials = ObservedSharedCredentials(invitationSaveGate: gate)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        let original = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
        let incoming = PendingInvitation(id: UUID(), token: String(repeating: "E", count: 43))
        let receiving = Task {
            await model.receiveInvitation(invitationURL(original))
        }
        await gate.waitUntilReached()
        await model.receiveInvitation(invitationURL(incoming))
        await gate.open()
        await receiving.value
        #expect(await credentials.loadInvitation() == original)
        #expect(await credentials.loadIncomingInvitation() == incoming)
    }

    @Test("Unknown error bodies retain the original batch intent", arguments: ["invalid_response", "unknown_gateway_error"])
    func unknownRejectionKeepsRetryEnvelope(_ code: String) async throws {
        let error = SharedAPIError.server(
            status: 409,
            code: code,
            requestID: nil,
            retryAfter: nil
        )
        let api = SharedFlowAPI(firstBatchError: error)
        let session = api.session
        let group = try #require(session.user.group)
        let request = AddItemsRequest(
            operationId: UUID(),
            items: [SharedNewItem(name: "Pan", quantity: nil, store: .newName("Día"))]
        )
        let operation = PendingSharedOperation.addItems(
            userID: session.user.id, groupID: group.id, request: request, sourceDraft: ShoppingDraftSnapshot()
        )
        let credentials = MemorySharedCredentialStore(session: session, operation: operation)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        await model.retryPendingOperation()
        try #require(model.pendingOperation == operation)
        #expect(await credentials.loadOperation() == operation)
        await model.retryPendingOperation()
        #expect(await api.sentBatches == [request, request])
        #expect(await credentials.loadOperation() == nil)
    }

    @Test("An unrecognized preview rejection preserves the saved invitation", arguments: [404, 410])
    func unknownPreviewKeepsInvitation(_ status: Int) async throws {
        let error = SharedAPIError.server(
            status: status,
            code: "invalid_response",
            requestID: nil,
            retryAfter: nil
        )
        let api = SharedFlowAPI(previewError: error)
        let invitation = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
        let credentials = MemorySharedCredentialStore(session: api.session, invitation: invitation)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        #expect(await credentials.loadInvitation() == invitation)
        #expect(model.pendingInvitation == invitation)
    }

    private func invitationURL(_ invitation: PendingInvitation) -> URL {
        URL(string: "https://links.test/invite/\(invitation.id.uuidString.lowercased())#token=\(invitation.token)")!
    }

    private func makeModel(
        api: SharedFlowAPI,
        credentials: any SharedCredentialStoring,
        items: [ShoppingDraftItem] = []
    ) throws -> SharedShoppingViewModel {
        SharedShoppingViewModel(
            api: api,
            configuration: try SharedAPIConfiguration(
                baseURL: "https://api.test",
                invitationOrigin: "https://links.test"
            ),
            credentials: credentials,
            draft: ShoppingDraftViewModel(
                interpreter: UnavailableDraftInterpreter(),
                speech: UnavailableSpeechCapture(),
                persistence: MemoryDraftPersistence(),
                initialDraft: ShoppingDraftSnapshot(items: items)
            )
        )
    }
}

private actor SharedFlowAPI: SharedShoppingAPI {
    let session: SharedSession
    private(set) var sentBatches: [AddItemsRequest] = []
    private(set) var createdGroups = 0
    private(set) var loginRequests = 0
    private(set) var acceptedInvitations = 0
    let currentUserGate: SharedFlowGate?
    private(set) var sentItemChanges: [SharedItemChangeRequest] = []
    private var itemChangeResult: SharedItem?
    private var changeError: SharedAPIError? = .transport
    private var changeRefreshFails = false

    func configureItemChange(error: SharedAPIError?, refreshFails: Bool = false) {
        changeError = error
        changeRefreshFails = refreshFails
    }

    func changeItem(_ request: SharedItemChangeRequest, item: SharedItem, token: String) async throws -> SharedItem {
        sentItemChanges.append(request)
        if case .server = changeError {
            changeFirstPurchaseItem()
            throw try #require(changeError)
        }
        if let itemChangeResult {
            return itemChangeResult
        }
        let replacement = request.replacement
        let store: UUID
        if case .existing(let id) = replacement?.store {
            store = id
        } else {
            store = item.storeId
        }
        let result = SharedItem(
            id: item.id,
            groupId: item.groupId,
            storeId: store,
            name: replacement?.name ?? item.name,
            quantity: replacement == nil ? item.quantity : replacement?.quantity,
            status: replacement == nil ? "cancelled" : "pending",
            version: item.version + 1,
            createdBy: item.createdBy,
            createdAt: item.createdAt,
            purchasedBy: nil,
            purchasedAt: nil
        )
        purchaseItems.removeAll { $0.id == item.id }
        if result.status == "pending" {
            purchaseItems.append(result)
        }
        itemChangeResult = result
        // Simulate loss AFTER committing the change. Retry returns the original receipt.
        if let changeError {
            throw changeError
        }
        return result
    }

    private(set) var sentPurchases: [FinalizePurchaseRequest] = []
    private(set) var purchaseItems: [SharedItem] = []
    var purchaseError: SharedAPIError? = .transport
    private var failRefreshAfterPurchase = false
    private var pendingItemsGate: SharedFlowGate?
    private var pendingItemsError: SharedAPIError?
    private var emptyPendingItems = false
    private var failCurrentUser = false

    func configurePendingItems(gate: SharedFlowGate? = nil, error: SharedAPIError? = nil, empty: Bool = false) {
        pendingItemsGate = gate
        pendingItemsError = error
        emptyPendingItems = empty
    }

    func setCurrentUserFailure(_ fails: Bool) {
        failCurrentUser = fails
    }

    func allowPurchaseButFailRefresh() {
        purchaseError = nil
        failRefreshAfterPurchase = true
    }

    func preparePurchaseItems() throws -> [SharedItem] {
        let groupID = try #require(session.user.group).id
        let firstStore = UUID()
        let secondStore = UUID()
        purchaseItems = (0..<6).map { index in
            SharedItem(
                id: UUID(),
                groupId: groupID,
                storeId: index < 5 ? firstStore : secondStore,
                name: "Producto \(index)",
                quantity: nil,
                status: "pending",
                version: 1,
                createdBy: session.user.id,
                createdAt: .distantPast,
                purchasedBy: nil,
                purchasedAt: nil
            )
        }
        return purchaseItems
    }

    func rejectPurchaseWithConflict() {
        changeFirstPurchaseItem()
        purchaseError = .server(
            status: 409,
            code: "item_conflict",
            requestID: UUID(),
            retryAfter: nil
        )
    }

    func changeFirstPurchaseItem() {
        guard let item = purchaseItems.first else { return }
        purchaseItems[0] = SharedItem(
            id: item.id,
            groupId: item.groupId,
            storeId: item.storeId,
            name: "Editado por otra persona",
            quantity: item.quantity,
            status: "pending",
            version: 2,
            createdBy: item.createdBy,
            createdAt: item.createdAt,
            purchasedBy: nil,
            purchasedAt: nil
        )
    }

    func finalizePurchase(
        _ request: FinalizePurchaseRequest,
        groupID: UUID,
        token: String
    ) async throws -> PurchaseResult {
        sentPurchases.append(request)
        if sentPurchases.count == 1, let purchaseError {
            throw purchaseError
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let ids = Set(request.items.map(\.id))
        let bought = purchaseItems.filter { ids.contains($0.id) }.map { item in
            SharedItem(
                id: item.id,
                groupId: item.groupId,
                storeId: item.storeId,
                name: item.name,
                quantity: item.quantity,
                status: "purchased",
                version: item.version + 1,
                createdBy: item.createdBy,
                createdAt: item.createdAt,
                purchasedBy: session.user.id,
                purchasedAt: date
            )
        }
        purchaseItems.removeAll { ids.contains($0.id) }
        return PurchaseResult(items: bought, confirmedAt: date)
    }

    let acceptanceGate: SharedFlowGate?
    let acceptanceError: SharedAPIError?
    let firstBatchError: SharedAPIError
    let previewError: SharedAPIError

    init(
        currentUserGate: SharedFlowGate? = nil,
        acceptanceGate: SharedFlowGate? = nil,
        acceptanceError: SharedAPIError? = nil,
        firstBatchError: SharedAPIError = .transport,
        previewError: SharedAPIError = .transport
    ) {
        self.currentUserGate = currentUserGate
        self.acceptanceGate = acceptanceGate
        self.acceptanceError = acceptanceError
        self.firstBatchError = firstBatchError
        self.previewError = previewError
        let userID = UUID()
        let group = SharedGroup(
            id: UUID(),
            name: "Casa",
            creatorUserId: userID,
            createdAt: .distantPast
        )
        session = SharedSession(
            accessToken: String(repeating: "A", count: 43),
            tokenType: "Bearer",
            expiresAt: .distantFuture,
            user: SharedUser(id: userID, displayName: nil, group: group)
        )
    }

    func createChallenge() async throws -> SharedChallenge {
        SharedChallenge(id: UUID(), nonce: String(repeating: "A", count: 43), expiresAt: .distantFuture)
    }

    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession {
        loginRequests += 1
        return session
    }

    func currentUser(token: String) async throws -> SharedUser {
        await currentUserGate?.pause()
        if failCurrentUser || (changeRefreshFails && !sentItemChanges.isEmpty) || (failRefreshAfterPurchase && !sentPurchases.isEmpty) {
            throw SharedAPIError.transport
        }
        return session.user
    }
    func logout(token: String) async throws {}

    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        createdGroups += 1
        return try #require(session.user.group)
    }

    func stores(groupID: UUID, token: String) async throws -> [SharedStore] {
        Set(purchaseItems.map(\.storeId)).map { SharedStore(id: $0, groupId: groupID, name: "Tienda") }
    }
    func createInvitation(groupID: UUID, token: String) async throws -> CreatedInvitation {
        throw SharedAPIError.transport
    }
    func invitations(groupID: UUID, token: String) async throws -> [SharedInvitation] { [] }
    func revokeInvitation(groupID: UUID, invitationID: UUID, token: String) async throws {}
    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview {
        throw previewError
    }
    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup {
        acceptedInvitations += 1
        await acceptanceGate?.pause()
        if let acceptanceError {
            throw acceptanceError
        }
        return try #require(session.user.group)
    }

    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        sentBatches.append(request)
        if sentBatches.count == 1 {
            throw firstBatchError
        }
        return request.items.map {
            SharedItem(
                id: UUID(), groupId: groupID, storeId: UUID(), name: $0.name, quantity: $0.quantity,
                status: "pending", version: 1, createdBy: session.user.id, createdAt: .distantPast,
                purchasedBy: nil, purchasedAt: nil
            )
        }
    }

    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem] {
        let result = emptyPendingItems ? [] : purchaseItems.filter { $0.storeId == storeID }
        let error = pendingItemsError
        await pendingItemsGate?.pause()
        if let error {
            throw error
        }
        return result
    }
}

private struct UnavailableDraftInterpreter: DraftInterpreting {
    var availability: DraftInterpretationAvailability { .unavailable }
    func interpret(_ text: String) async throws -> [SuggestedProduct] { throw SharedAPIError.transport }
}

private struct UnavailableSpeechCapture: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> { throw SharedAPIError.transport }
    func finish() async throws {}
    func cancel() async {}
}

/// A deterministic observation point; tests release it explicitly instead of sleeping or polling.
private actor SharedFlowGate {
    private var reached = false
    private var opened = false
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var resumptions: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        reached = true
        arrivals.forEach {
            $0.resume()
        }
        arrivals = []
        guard !opened else { return }
        await withCheckedContinuation {
            resumptions.append($0)
        }
    }

    func waitUntilReached() async {
        guard !reached else { return }
        await withCheckedContinuation {
            arrivals.append($0)
        }
    }

    func open() {
        opened = true
        resumptions.forEach {
            $0.resume()
        }
        resumptions = []
    }
}

/// Runs the production in-memory credential store, with an observable save boundary for startup and promotion races.
private actor ObservedSharedCredentials: SharedCredentialStoring {
    let base: MemorySharedCredentialStore
    let invitationSaveGate: SharedFlowGate?
    private var savedInvitations: Set<UUID> = []
    private var saveObservers: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    init(session: SharedSession? = nil, invitationSaveGate: SharedFlowGate? = nil) {
        base = MemorySharedCredentialStore(session: session)
        self.invitationSaveGate = invitationSaveGate
    }

    func loadSession() async -> SharedSession? {
        await base.loadSession()
    }
    func saveSession(_ session: SharedSession?) async {
        await base.saveSession(session)
    }
    func loadInvitation() async -> PendingInvitation? {
        await base.loadInvitation()
    }
    func loadIncomingInvitation() async -> PendingInvitation? {
        await base.loadIncomingInvitation()
    }
    func saveIncomingInvitation(_ invitation: PendingInvitation) async {
        await base.saveIncomingInvitation(invitation)
    }
    func clearIncomingInvitation(matching invitation: PendingInvitation) async -> Bool {
        await base.clearIncomingInvitation(matching: invitation)
    }
    func loadOperation() async -> PendingSharedOperation? {
        await base.loadOperation()
    }
    func saveOperation(_ operation: PendingSharedOperation?) async {
        await base.saveOperation(operation)
    }

    func saveInvitation(_ invitation: PendingInvitation?) async {
        await invitationSaveGate?.pause()
        await base.saveInvitation(invitation)
        guard let invitation else { return }
        savedInvitations.insert(invitation.id)
        saveObservers.removeValue(forKey: invitation.id)?.forEach {
            $0.resume()
        }
    }

    func waitForSavedInvitation(_ id: UUID) async {
        guard !savedInvitations.contains(id) else { return }
        await withCheckedContinuation {
            saveObservers[id, default: []].append($0)
        }
    }
}

extension SharedShoppingViewModelTests {
    @Test
    func `purchase checks are reversible and isolated per store without sending a mutation`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(items[0])
        model.togglePurchaseItem(items[1])
        #expect(model.purchaseSelection.map(\.id) == [items[0].id, items[1].id])
        model.togglePurchaseItem(items[1])
        model.selectedStoreID = items[5].storeId
        await model.loadSelectedStore()
        #expect(model.purchaseSelection.isEmpty)
        model.togglePurchaseItem(items[5])
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        #expect(model.purchaseSelection.map(\.id) == [items[0].id])
        #expect(await api.sentPurchases.isEmpty)
    }

    @Test
    func `an uncertain purchase survives reopening and retries exactly the original selection`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let credentials = MemorySharedCredentialStore(session: api.session)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        for item in items.prefix(3) {
            model.togglePurchaseItem(item)
        }
        await model.finalizePurchase()
        let original = try #require(model.pendingOperation)
        #expect(!model.canFinalizePurchase)
        #expect(model.purchaseSelection.count == 3)
        let reopened = try makeModel(api: api, credentials: credentials)
        await reopened.load()
        #expect(reopened.pendingOperation == original)
        #expect(reopened.purchaseSelection.count == 3)
        await reopened.retryPendingOperation()
        let requests = await api.sentPurchases
        try #require(requests.count == 2)
        #expect(requests[0] == requests[1])
        #expect(Set(requests[0].items.map(\.id)) == Set(items.prefix(3).map(\.id)))
        #expect(reopened.pendingOperation == nil)
        #expect(reopened.purchaseSelection.isEmpty)
        #expect(Set(reopened.items.map(\.id)) == Set(items[3...4].map(\.id)))
        #expect(await credentials.loadOperation() == nil)
    }

    @Test
    func `refresh never silently adopts a newer selected product version`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(items[0])
        await api.changeFirstPurchaseItem()
        await model.refresh()
        #expect(model.purchaseSelection.first?.version == 1)
        #expect(model.purchaseSelectionNeedsReview)
        #expect(!model.canFinalizePurchase)
        await model.finalizePurchase()
        #expect(await api.sentPurchases.isEmpty)
    }
}


extension SharedShoppingViewModelTests {
    @Test
    func `a terminal purchase conflict preserves unchanged checks and requires explicit review`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let credentials = MemorySharedCredentialStore(session: api.session)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(items[0])
        model.togglePurchaseItem(items[1])
        await api.rejectPurchaseWithConflict()

        await model.finalizePurchase()

        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.purchaseSelection.map(\.id) == [items[0].id, items[1].id])
        #expect(model.purchaseSelectionNeedsReview)
        #expect(!model.canFinalizePurchase)
        #expect(model.notice != nil)
        model.discardChangedPurchaseSelections()
        #expect(model.purchaseSelection.map(\.id) == [items[1].id])
        #expect(model.canFinalizePurchase)
        await model.finalizePurchase()
        let requests = await api.sentPurchases
        try #require(requests.count == 2)
        #expect(requests[0].operationId != requests[1].operationId)
        #expect(requests[1].items.map(\.id) == [items[1].id])
        #expect(model.items.contains { $0.id == items[0].id && $0.version == 2 })
    }
}


extension SharedShoppingViewModelTests {
    @Test
    func `a confirmed purchase does not reappear when refreshing the list fails`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(items[0])
        await api.allowPurchaseButFailRefresh()

        await model.finalizePurchase()

        #expect(model.pendingOperation == nil)
        #expect(!model.items.contains { $0.id == items[0].id })
        #expect(model.items.count == 4)
        #expect(!model.canTogglePurchaseItem(items[1]))
        #expect(!model.canFinalizePurchase)
        var notice = try #require(model.notice)
        notice.locale = Locale(identifier: "es")
        #expect(String(localized: notice) == "La compra se ha confirmado, pero no se ha podido actualizar la lista. Actualiza antes de continuar.")
    }
}


extension SharedShoppingViewModelTests {
    @Test
    func `an empty store is confirmed only after its response arrives`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        #expect(model.storeItemsState == .notLoaded)
        let gate = SharedFlowGate()
        await api.configurePendingItems(gate: gate, empty: true)
        async let loading: Void = model.loadSelectedStore()
        await gate.waitUntilReached()
        #expect(model.storeItemsState == .loading)
        #expect(!model.canFinalizePurchase)
        await gate.open()
        await loading
        #expect(model.storeItemsState == .loaded)
        #expect(model.items.isEmpty)
    }

    @Test
    func `dismissing a load error cannot turn it into a confirmed empty store`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        await api.configurePendingItems(error: .transport)
        await model.loadSelectedStore()
        model.dismissNotice()
        #expect(model.storeItemsState == .failed)
        #expect(model.items.isEmpty)
        await api.configurePendingItems(empty: true)
        await model.refresh()
        #expect(model.storeItemsState == .loaded)
        #expect(model.items.isEmpty)
    }

    @Test(arguments: [true, false])
    func `a failed refresh preserves checks but blocks purchases until verified`(beforeItems: Bool) async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(items[0])
        await api.setCurrentUserFailure(beforeItems)
        await api.configurePendingItems(error: beforeItems ? nil : .transport)
        await model.refresh()
        #expect(model.storeItemsState == .failed)
        #expect(model.items.map(\.id) == items.prefix(5).map(\.id))
        #expect(model.purchaseSelection.map(\.id) == [items[0].id])
        #expect(!model.canTogglePurchaseItem(items[0]))
        #expect(!model.canFinalizePurchase)
        await model.finalizePurchase()
        #expect(await api.sentPurchases.isEmpty)
        await api.setCurrentUserFailure(false)
        await api.configurePendingItems()
        await model.refresh()
        #expect(model.storeItemsState == .loaded)
        #expect(model.canFinalizePurchase)
    }

    @Test
    func `switching stores clears old rows and ignores their delayed response`() async throws {
        let api = SharedFlowAPI()
        let items = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = items[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(items[0])
        let gate = SharedFlowGate()
        await api.configurePendingItems(gate: gate)
        async let refreshing: Void = model.refresh()
        await gate.waitUntilReached()
        model.selectedStoreID = items[5].storeId
        #expect(model.items.isEmpty)
        #expect(model.storeItemsState == .notLoaded)
        await gate.open()
        await refreshing
        #expect(model.items.isEmpty)
        #expect(model.storeItemsState == .notLoaded)
        await api.configurePendingItems()
        await model.loadSelectedStore()
        #expect(model.items.map(\.id) == [items[5].id])
        #expect(model.storeItemsState == .loaded)
        model.selectedStoreID = items[0].storeId
        #expect(model.purchaseSelection.map(\.id) == [items[0].id])
    }
}


extension SharedShoppingViewModelTests {
    @Test("A lost item-change response survives reopening and retries the same committed intent", arguments: [false, true])
    func itemChangeLostResponse(cancelling: Bool) async throws {
        let api = SharedFlowAPI()
        let products = try await api.preparePurchaseItems()
        let item = products[0]
        let credentials = MemorySharedCredentialStore(session: api.session)
        let model = try makeModel(api: api, credentials: credentials)
        await model.load()
        model.selectedStoreID = item.storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(item)
        if cancelling {
            await model.cancelItem(item)
        } else {
            model.beginEditingItem(item)
            model.editName = "Pan integral"
            model.editQuantity = "2 barras"
            await model.saveItemEdit()
        }
        let original = try #require(await credentials.loadOperation())
        #expect(!model.canFinalizePurchase)
        #expect(!model.canMutate)
        let reopened = try makeModel(api: api, credentials: credentials)
        await reopened.load()
        #expect(reopened.pendingOperation == original)
        if !cancelling {
            #expect(reopened.editName == "Pan integral")
            #expect(reopened.editQuantity == "2 barras")
        }
        await reopened.retryPendingOperation()
        let requests = await api.sentItemChanges
        #expect(requests.count == 2)
        #expect(requests.first == requests.last)
        #expect(await credentials.loadOperation() == nil)
        let row = reopened.items.first { $0.id == item.id }
        if cancelling {
            #expect(row == nil)
        } else {
            #expect(row?.name == "Pan integral")
            #expect(row?.version == 2)
        }
        await model.refresh()
        #expect(model.purchaseSelectionNeedsReview)
        #expect(model.purchaseSelection.first?.version == 1)
    }

    @Test("Editing conflicts retain the proposal and require explicit review before a new intent")
    func itemEditConflict() async throws {
        let api = SharedFlowAPI()
        let products = try await api.preparePurchaseItems()
        await api.configureItemChange(error: .server(status: 409, code: "item_conflict", requestID: UUID(), retryAfter: nil))
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = products[0].storeId
        await model.loadSelectedStore()
        model.beginEditingItem(products[0])
        model.editName = "Mi propuesta"
        await model.saveItemEdit()
        #expect(model.editName == "Mi propuesta")
        #expect(model.editNeedsReview)
        #expect(!model.canSaveItemEdit)
        #expect(model.pendingOperation == nil)
        let first = try #require(await api.sentItemChanges.first)
        model.reviewLatestItem()
        #expect(model.canSaveItemEdit)
        await api.configureItemChange(error: nil)
        await model.saveItemEdit()
        let last = try #require(await api.sentItemChanges.last)
        #expect(last.operationId != first.operationId)
        #expect(last.expectedVersion == 2)
    }

    @Test("A confirmed item change with failed refresh blocks stale purchase selections")
    func itemChangeRefreshFailure() async throws {
        let api = SharedFlowAPI()
        let products = try await api.preparePurchaseItems()
        await api.configureItemChange(error: nil, refreshFails: true)
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = products[0].storeId
        await model.loadSelectedStore()
        model.togglePurchaseItem(products[0])
        await model.cancelItem(products[0])
        #expect(model.pendingOperation == nil)
        #expect(model.storeItemsState == .failed)
        #expect(!model.canFinalizePurchase)
        #expect(!model.items.contains(products[0]))
        #expect(model.purchaseSelection == [products[0]])
    }
}


extension SharedShoppingViewModelTests {
    @Test("Invalid visible fields block edits while an abandoned new-store field does not")
    func editValidationUsesVisibleFields() async throws {
        let api = SharedFlowAPI()
        let products = try await api.preparePurchaseItems()
        let model = try makeModel(api: api, credentials: MemorySharedCredentialStore(session: api.session))
        await model.load()
        model.selectedStoreID = products[0].storeId
        await model.loadSelectedStore()
        model.beginEditingItem(products[0])
        model.editName = ""
        #expect(!model.canSaveItemEdit)
        #expect(model.editValidationMessage != nil)
        model.editName = String(repeating: "\u{0344}", count: 81)
        #expect(!model.canSaveItemEdit)
        #expect(model.editValidationMessage != nil)
        model.editName = "Pan"
        model.editStoreID = nil
        model.editNewStore = "\u{0001}"
        #expect(!model.canSaveItemEdit)
        model.editStoreID = products[0].storeId
        #expect(model.editValidationMessage == nil)
        #expect(model.canSaveItemEdit)
        await api.configureItemChange(error: nil)
        await model.saveItemEdit()
        #expect(model.items.first { $0.id == products[0].id }?.name == "Pan")
    }
}
