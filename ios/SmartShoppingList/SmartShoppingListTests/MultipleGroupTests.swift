import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
@MainActor
struct MultipleGroupTests {
    @Test(arguments: ["purchase", "restore", "verification"])
    func `Explicit premium action failures use the native notice while background status remains inline`(
        action: String
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let status = SharedSubscriptionStatus(
            appAccountToken: fixture.session.user.id,
            isConfigured: true,
            productIDs: ["premium.monthly", "premium.annual"],
            state: .free,
            expiresAt: nil,
            gracePeriodExpiresAt: nil,
            autoRenewEnabled: nil,
            verifiedAt: nil
        )
        await api.configureSubscription(status)
        let verification = PendingSubscriptionVerification(
            userID: fixture.session.user.id,
            transactionID: "908",
            request: VerifySharedSubscriptionRequest(signedTransaction: "saved.original.transaction")
        )
        if action == "verification" {
            await api.rejectSubscriptionVerification(.transport)
        }
        let credentials = MemorySharedCredentialStore(
            session: fixture.session,
            subscriptionVerification: action == "verification" ? verification : nil
        )
        let store = MembershipNoTransactionsStore(withCatalogue: true)
        let model = fixture.model(api: api, credentials: credentials, subscriptionStore: store)
        await model.load()
        await model.loadPremium()
        #expect(model.presentedNotice == nil)
        switch action {
        case "purchase":
            await model.purchasePremium(productID: "premium.monthly")
            #expect(await store.purchases == 1)
        case "restore":
            await model.restorePremium()
            #expect(await store.restorations == 1)
        default:
            try #require(model.premium.notice != nil)
            await model.loadPremium(reportsActionErrors: true)
            #expect(await credentials.loadSubscriptionVerification() == verification)
            #expect(await api.subscriptionRequests.count == 2)
        }
        #expect(model.presentedNotice != nil)
        #expect(model.premium.notice == nil)
        #expect(await store.finished.isEmpty)
        #expect(model.pendingOperation == nil)
        #expect(model.membershipAccess?.premiumActive != true)
    }

    @Test
    func `A subscription status read refreshes account rights even without transactions on this Apple device`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.configureFreeGroup(fixture.first.id)
        let status = SharedSubscriptionStatus(
            appAccountToken: UUID(),
            isConfigured: true,
            productIDs: ["premium.monthly", "premium.annual"],
            state: .subscribed,
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            gracePeriodExpiresAt: nil,
            autoRenewEnabled: true,
            verifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        await api.configureSubscription(status, reconcilesPremium: true)
        let store = MembershipNoTransactionsStore()
        let model = fixture.model(api: api, subscriptionStore: store)
        await model.load()
        await model.selectGroup(id: fixture.second.id)
        try #require(model.hasRestrictedGroup)
        try #require(!model.canCreateGroup)
        await model.loadPremium()
        #expect(model.premium.status?.state == .subscribed)
        #expect(model.membershipAccess?.premiumActive == true)
        #expect(model.canCreateGroup)
        #expect(model.canPerformShopping)
        #expect(model.group?.id == fixture.second.id)
        #expect(model.draft.items == fixture.draft.items)
        #expect(await api.subscriptionRequests.isEmpty)
        #expect(await store.finished.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `An Apple update received during a group or store read is verified after that action finishes`(
        readsStore: Bool
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let accountToken = UUID()
        let status = SharedSubscriptionStatus(
            appAccountToken: accountToken,
            isConfigured: true,
            productIDs: ["premium.monthly"],
            state: .free,
            expiresAt: nil,
            gracePeriodExpiresAt: nil,
            autoRenewEnabled: nil,
            verifiedAt: nil
        )
        await api.configureSubscription(status)
        let deliveryGate = MembershipGate()
        let consumedGate = MembershipGate()
        let transaction = SharedStoreTransaction(
            id: "908",
            appAccountToken: accountToken,
            productID: "premium.monthly",
            signedTransaction: "apple.update.during.refresh"
        )
        let store = MembershipSubscriptionStore(
            transaction: transaction,
            deliveryGate: deliveryGate,
            consumedGate: consumedGate
        )
        let model = fixture.model(api: api, subscriptionStore: store)
        await model.load()
        await deliveryGate.waitUntilReached()
        await model.loadPremium()
        await model.selectGroup(id: fixture.first.id)
        model.selectedStoreID = fixture.firstStore.id
        let refreshGate = MembershipGate()
        if readsStore {
            await api.delayNextItems(refreshGate)
        } else {
            await api.delayNextUserLookup(refreshGate)
        }
        let refresh = Task {
            if readsStore {
                await model.loadSelectedStore()
            } else {
                await model.refresh()
            }
        }
        await refreshGate.waitUntilReached()
        try #require(model.isBusy)
        await deliveryGate.open()
        // Requesting the next stream element proves the previous update reached the busy ViewModel.
        await consumedGate.waitUntilReached()
        #expect(await api.subscriptionRequests.isEmpty)
        #expect(await store.finished.isEmpty)
        await refreshGate.open()
        await refresh.value
        #expect(await api.subscriptionRequests.map(\.signedTransaction) == ["apple.update.during.refresh"])
        #expect(await store.finished == ["908"])
        #expect(model.premium.pendingVerification == nil)
        #expect(!model.isBusy)
        await consumedGate.open()
    }

    @Test
    func `A lost free group selection is retried with its exact identity without changing the active shopping group`(
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.configureFreeGroup(fixture.first.id, loseNextSelectionResponse: true)
        var session = fixture.session
        session.activeGroupID = fixture.first.id
        let credentials = MemorySharedCredentialStore(session: session)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        await model.selectFreeGroup(id: fixture.second.id)
        let pending = try #require(model.pendingOperation)
        #expect(model.group?.id == fixture.first.id)
        #expect(await credentials.loadOperation() == pending)
        #expect(model.draft.items == fixture.draft.items)

        let reopened = fixture.model(api: api, credentials: credentials)
        await reopened.load()
        try #require(reopened.hasRestrictedGroup)
        #expect(!reopened.canSelectFreeGroup)
        await reopened.retryPendingOperation()

        #expect(reopened.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(reopened.membershipAccess?.freeGroupId == fixture.second.id)
        #expect(reopened.group?.id == fixture.first.id)
        #expect(reopened.draft.items == fixture.draft.items)
        let requests = await api.freeGroupRequests
        #expect(requests.count == 2)
        #expect(requests[0] == requests[1])
        #expect(requests[0].operationId == pending.operationID)
        #expect(requests[0].groupId == fixture.second.id)
    }

    @Test
    func `A restricted additional group keeps consultation and cancellation but cannot create ordinary shopping intents`(
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.configureFreeGroup(fixture.second.id)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        model.selectedStoreID = fixture.firstStore.id
        await model.loadSelectedStore()
        let item = try #require(model.items.first)
        #expect(model.hasRestrictedGroup)
        #expect(model.canCancelItem(item))
        #expect(!model.canChangeItem(item))
        #expect(!model.canTogglePurchaseItem(item))
        #expect(!model.canFinalizePurchase)
        await model.addDraftItems()
        await model.prepareReview()
        await model.finalizePurchase()
        model.beginEditingItem(item)
        #expect(model.pendingOperation == nil)
        #expect(model.editingItem == nil)
        #expect(model.reviewedItems.isEmpty)
        #expect(await api.additionGroups.isEmpty)
        #expect(model.items == [item])
        #expect(model.draft.items == fixture.draft.items)

        await model.cancelItem(item)
        #expect(await api.cancelledItems == [item.id])
        #expect(model.pendingOperation == nil)
        #expect(model.items.isEmpty)
        #expect(model.hasRestrictedGroup)
    }

    @Test
    func `Changing only the active group cannot bypass an account free group cooldown`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.configureFreeGroup(fixture.first.id, permitsChange: false)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.second.id)
        await model.selectFreeGroup(id: fixture.second.id)
        #expect(model.group?.id == fixture.second.id)
        #expect(model.membershipAccess?.freeGroupId == fixture.first.id)
        #expect(model.hasRestrictedGroup)
        #expect(await api.freeGroupRequests.isEmpty)
        #expect(model.pendingOperation == nil)
    }

    @Test
    func `Several memberships require a choice and reopening restores the local choice instead of the legacy group`(
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()

        #expect(model.groups.count == 2)
        #expect(model.group == nil)
        #expect(model.session?.user.group?.id == fixture.first.id)
        await model.selectGroup(id: fixture.second.id)
        #expect(model.group?.id == fixture.second.id)
        #expect(model.stores.map(\.groupId) == [fixture.second.id])
        #expect(model.draft.items == fixture.draft.items)

        let reopened = fixture.model(api: api, credentials: credentials)
        await reopened.load()
        #expect(reopened.group?.id == fixture.second.id)
        #expect(reopened.session?.user.group?.id == fixture.first.id)
        #expect(reopened.groupNeedsIdentifier(fixture.first))
    }

    @Test
    func `Losing the selected membership never silently chooses the only remaining group`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        var session = fixture.session
        session.activeGroupID = fixture.first.id
        let credentials = MemorySharedCredentialStore(session: session)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        await api.setMemberships([fixture.second])

        await model.refresh()
        await model.refresh()
        #expect(model.group == nil)
        #expect(model.stores.isEmpty)
        #expect(model.session?.activeGroupID == fixture.first.id)
        #expect(model.draft.items == fixture.draft.items)
        await model.selectGroup(id: fixture.second.id)
        #expect(model.group?.id == fixture.second.id)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `A previous group item response or error cannot replace the visible group`(fails: Bool) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        let gate = MembershipGate()
        await api.delayNextItems(gate, fails: fails)
        model.selectedStoreID = fixture.firstStore.id
        let oldLoad = Task {
            await model.loadSelectedStore()
        }
        await gate.waitUntilReached()
        try #require(model.canSelectGroup)

        await model.selectGroup(id: fixture.second.id)
        model.selectedStoreID = fixture.secondStore.id
        await model.loadSelectedStore()
        let visible = model.items
        try #require(visible.map(\.name) == ["Pan del viaje"])
        await gate.open()
        await oldLoad.value

        #expect(model.group?.id == fixture.second.id)
        #expect(model.items == visible)
        #expect(model.storeItemsState == .loaded)
        #expect(model.notice == nil)
        #expect(model.canMutate)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Returning to the same group still rejects its earlier generation`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        let gate = MembershipGate()
        await api.delayNextItems(gate)
        model.selectedStoreID = fixture.firstStore.id
        let oldLoad = Task {
            await model.loadSelectedStore()
        }
        await gate.waitUntilReached()
        await model.selectGroup(id: fixture.second.id)
        await api.removeFirstGroupItems()
        await model.selectGroup(id: fixture.first.id)
        model.selectedStoreID = fixture.firstStore.id
        await model.loadSelectedStore()
        try #require(model.items.isEmpty)
        await gate.open()
        await oldLoad.value

        #expect(model.group?.id == fixture.first.id)
        #expect(model.items.isEmpty)
        #expect(model.storeItemsState == .loaded)
    }

    @Test
    func `Pending recovery keeps its original group while the local active group stays unchanged`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let operation = PendingSharedOperation.addItems(
            userID: fixture.session.user.id,
            groupID: fixture.first.id,
            request: AddItemsRequest(
                operationId: UUID(),
                items: [SharedNewItem(name: "Leche", quantity: nil, store: .existing(fixture.firstStore.id))]
            ),
            sourceDraft: fixture.draft
        )
        var session = fixture.session
        session.activeGroupID = fixture.second.id
        let credentials = MemorySharedCredentialStore(session: session, operation: operation)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        #expect(model.group?.id == fixture.second.id)
        #expect(model.pendingOperation == operation)
        #expect(!model.canSelectGroup)
        #expect(model.draft.items == fixture.draft.items)

        await model.retryPendingOperation()
        #expect(await api.additionGroups == [fixture.first.id])
        #expect(await api.additionOperations == [operation.operationID])
        #expect(model.group?.id == fixture.second.id)
        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.draft.items.isEmpty)
    }

    @Test
    func `A group change preserves the draft but invalidates a prepared submission and shopping selection`(
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        model.selectedStoreID = fixture.firstStore.id
        await model.loadSelectedStore()
        model.togglePurchaseItem(try #require(model.items.first))
        await model.prepareReview()
        await model.selectGroup(id: fixture.second.id)
        #expect(model.group?.id == fixture.first.id)
        model.isReviewPresented = false
        model.reviewPresentationDidDismiss()

        await model.selectGroup(id: fixture.second.id)
        await model.confirmReviewedBatch()
        #expect(await api.additionGroups.isEmpty)
        #expect(model.group?.id == fixture.second.id)
        #expect(model.reviewedItems.isEmpty)
        #expect(model.storeChoices.isEmpty)
        #expect(model.purchaseSelection.isEmpty)
        #expect(model.selectedStoreID == nil)
        #expect(model.draft.items == fixture.draft.items)
    }

    @Test
    func `An unfinished manual editor keeps its input and prevents changing its destination`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        model.draft.beginAddingItem()
        model.draft.editorItem.name = "Texto sin guardar"

        await model.selectGroup(id: fixture.second.id)
        #expect(model.group?.id == fixture.first.id)
        #expect(model.draft.editorItem.name == "Texto sin guardar")
        #expect(!model.canSelectGroup)
    }

    @Test(arguments: [false, true])
    func `Shortcuts only submit directly when the verified account has exactly one group`(multiple: Bool) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        if !multiple {
            await api.setMemberships([fixture.first])
        }
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        let input = ShoppingDraftItem(name: "Café", store: "Aldi")

        let result = try await model.addShoppingItemFromIntent(input)

        if multiple {
            #expect(result == .savedToDraft)
            #expect(await api.additionGroups.isEmpty)
            #expect(model.draft.items.contains(input))
            #expect(model.pendingOperation == nil)
        } else {
            #expect(result == .added(storeName: "Aldi"))
            #expect(await api.additionGroups == [fixture.first.id])
            #expect(!model.draft.items.contains(input))
        }
        let original = try #require(fixture.draft.items.first)
        #expect(model.draft.items.contains(original))
    }

    @Test
    func `Unknown membership verification keeps shortcut input local even with a saved active group`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.setMemberships([fixture.first])
        let model = fixture.model(api: api)
        await model.load()
        await api.failMembershipLookup()
        let input = ShoppingDraftItem(name: "Café", store: "Aldi")

        #expect(try await model.addShoppingItemFromIntent(input) == .savedToDraft)
        #expect(await api.additionGroups.isEmpty)
        #expect(model.draft.items.contains(input))
        #expect(!model.canMutate)
    }

    @Test(arguments: [false, true])
    func `Explicit creation and joining add memberships without replacing the existing ones`(
        joining: Bool
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let credentials = MemorySharedCredentialStore(
            session: fixture.session,
            invitation: joining ? fixture.invitation : nil
        )
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        await model.selectGroup(id: fixture.second.id)
        if joining {
            await model.acceptInvitation()
        } else {
            model.groupName = "Trabajo"
            await model.createGroup()
        }

        #expect(Set(model.groups.map(\.id)) == Set([fixture.first.id, fixture.second.id, fixture.third.id]))
        #expect(model.group?.id == fixture.third.id)
        #expect(model.session?.user.group?.id == fixture.first.id)
        #expect(model.draft.items == fixture.draft.items)
        #expect(model.pendingOperation == nil)
    }

    @Test
    func `Replaying an old create receipt cannot retarget an existing active selection`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.setCreationReceipt(fixture.first)
        var session = fixture.session
        session.activeGroupID = fixture.second.id
        let pending = PendingSharedOperation.createGroup(
            userID: session.user.id,
            request: CreateGroupRequest(operationId: UUID(), name: "Casa")
        )
        let credentials = MemorySharedCredentialStore(session: session, operation: pending)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()

        await model.retryPendingOperation()
        #expect(model.group?.id == fixture.second.id)
        #expect(model.groups.count == 2)
        #expect(model.pendingOperation == nil)
        #expect(model.draft.items == fixture.draft.items)
    }

    @Test
    func `A confirmed group quota rejection unlocks the draft and leaves current memberships intact`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.rejectCreationAtLimit()
        let credentials = MemorySharedCredentialStore(session: fixture.session)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        await model.selectGroup(id: fixture.second.id)
        model.groupName = "Trabajo"

        await model.createGroup()
        #expect(model.pendingOperation == nil)
        #expect(await credentials.loadOperation() == nil)
        #expect(model.group?.id == fixture.second.id)
        #expect(model.groups.count == 2)
        #expect(model.draft.items == fixture.draft.items)
        #expect(model.canMutate)
        var message = try #require(model.notice)
        message.locale = Locale(identifier: "es")
        #expect(
            String(localized: message)
                == "Tu cuenta ha alcanzado su límite de grupos. Se conservan tus grupos actuales y el borrador."
        )
    }

    @Test
    func `Missing account capabilities never authorize creation or joining`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.omitCapabilities()
        let credentials = MemorySharedCredentialStore(session: fixture.session, invitation: fixture.invitation)
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        model.groupName = "Trabajo"

        await model.createGroup()
        await model.acceptInvitation()
        #expect(!model.canCreateGroup)
        #expect(!model.canAcceptInvitation)
        #expect(await api.membershipMutations == 0)
        #expect(!model.groupsAreVerified)
        #expect(model.pendingInvitation == fixture.invitation)
    }
}

@Suite(.tags(.integration))
@MainActor
struct MultipleGroupKeychainTests {
    @Test
    func `A new model restores the selected group from Keychain while retaining the legacy projection`() async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let service = "MultipleGroupKeychainTests.\(UUID())"
        let credentials = SharedKeychainStore(service: service)
        do {
            // Historical payload: neither activeGroupID nor account capabilities existed yet.
            let legacyPayload = Data("""
            {"accessToken":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","tokenType":"Bearer",
            "expiresAt":900000000,"user":{"id":"\(fixture.session.user.id)","displayName":"Alex",
            "group":{"id":"\(fixture.first.id)","name":"Casa","creatorUserId":"\(fixture.session.user.id)",
            "createdAt":800000000}}}
            """.utf8)
            let legacySession = try JSONDecoder().decode(SharedSession.self, from: legacyPayload)
            try await credentials.saveSession(legacySession)
            let model = fixture.model(api: api, credentials: SharedKeychainStore(service: service))
            await model.load()
            #expect(model.group == nil)
            #expect(model.session?.accessToken == fixture.session.accessToken)
            await model.selectGroup(id: fixture.second.id)
            let reopened = fixture.model(api: api, credentials: SharedKeychainStore(service: service))
            await reopened.load()

            #expect(reopened.group?.id == fixture.second.id)
            #expect(reopened.stores.map(\.id) == [fixture.secondStore.id])
            #expect(reopened.session?.user.group?.id == fixture.first.id)
            try await credentials.saveSession(nil)
        } catch {
            try? await credentials.saveSession(nil)
            throw error
        }
    }
}

private struct MembershipFixture {
    let configuration: SharedAPIConfiguration
    let session: SharedSession
    let first: SharedGroup
    let second: SharedGroup
    let third: SharedGroup
    let firstStore: SharedStore
    let secondStore: SharedStore
    let draft = ShoppingDraftSnapshot(items: [ShoppingDraftItem(name: "Leche", store: "Aldi")])
    let invitation = PendingInvitation(id: UUID(), token: String(repeating: "A", count: 43))
}

private extension MembershipFixture {
    init() throws {
        configuration = try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test")
        let userID = UUID()
        first = SharedGroup(
            id: UUID(),
            name: "Casa",
            creatorUserId: userID,
            createdAt: .distantPast
        )
        second = SharedGroup(
            id: UUID(),
            name: "Casa",
            creatorUserId: userID,
            createdAt: .distantPast
        )
        third = SharedGroup(
            id: UUID(),
            name: "Trabajo",
            creatorUserId: userID,
            createdAt: .distantPast
        )
        firstStore = SharedStore(id: UUID(), groupId: first.id, name: "Aldi")
        secondStore = SharedStore(id: UUID(), groupId: second.id, name: "Aldi")
        session = SharedSession(
            accessToken: String(repeating: "A", count: 43),
            tokenType: "Bearer",
            expiresAt: .distantFuture,
            user: SharedUser(id: userID, displayName: "Alex", group: first)
        )
    }

    @MainActor
    func model(
        api: MembershipAPI,
        credentials: (any SharedCredentialStoring)? = nil,
        subscriptionStore: (any SharedSubscriptionStore)? = nil
    ) -> SharedShoppingViewModel {
        SharedShoppingViewModel(
            api: api,
            configuration: configuration,
            credentials: credentials ?? MemorySharedCredentialStore(session: session),
            draft: DraftPreviewSupport.viewModel(snapshot: draft, state: .content),
            storeQuery: StoreQueryViewModel(speech: MembershipSpeech()),
            subscriptionStore: subscriptionStore
        )
    }
}

private actor MembershipAPI: SharedShoppingAPI {
    private let fixture: MembershipFixture
    private var memberships: [SharedGroup]
    private var providesCapabilities = true
    private var membershipCountOverride: Int?
    private var lookupFails = false
    private var creationFails = false
    private var creationReceipt: SharedGroup?
    private var nextItemsGate: MembershipGate?
    private var delayedItemsError: SharedAPIError?
    private var firstGroupHasItems = true
    private var nextUserGate: MembershipGate?
    private var subscriptionStatus: SharedSubscriptionStatus?
    private var subscriptionVerificationError: SharedAPIError?
    private var premiumOnSubscriptionRead = false
    private var hasReadSubscription = false
    private(set) var subscriptionRequests: [VerifySharedSubscriptionRequest] = []
    private var freeGroupID: UUID?
    private var permitsFreeGroupChange = true
    private var loseNextFreeGroupResponse = false
    private var selectionReceipts: [UUID: SharedAccountCapabilities] = [:]
    private(set) var freeGroupRequests: [SelectFreeGroupRequest] = []
    private(set) var cancelledItems: [UUID] = []
    private(set) var userLookups = 0
    private(set) var additionGroups: [UUID] = []
    private(set) var additionOperations: [UUID] = []
    private(set) var membershipMutations = 0

    init(fixture: MembershipFixture) {
        self.fixture = fixture
        memberships = [fixture.first, fixture.second]
    }

    func rejectSubscriptionVerification(_ error: SharedAPIError) {
        subscriptionVerificationError = error
    }

    func configureSubscription(_ status: SharedSubscriptionStatus, reconcilesPremium: Bool = false) {
        subscriptionStatus = status
        premiumOnSubscriptionRead = reconcilesPremium
    }

    func subscription(token: String) async throws -> SharedSubscriptionStatus {
        hasReadSubscription = true
        return try #require(subscriptionStatus)
    }

    func verifySubscription(
        _ request: VerifySharedSubscriptionRequest,
        token: String
    ) async throws -> SharedSubscriptionAcknowledgement {
        subscriptionRequests.append(request)
        if let subscriptionVerificationError {
            throw subscriptionVerificationError
        }
        return SharedSubscriptionAcknowledgement(
            subscription: try #require(subscriptionStatus),
            acknowledgedTransactionId: "908"
        )
    }

    func configureFreeGroup(_ groupID: UUID, loseNextSelectionResponse: Bool = false, permitsChange: Bool = true) {
        freeGroupID = groupID
        loseNextFreeGroupResponse = loseNextSelectionResponse
        permitsFreeGroupChange = permitsChange
    }

    func selectFreeGroup(_ request: SelectFreeGroupRequest, token: String) async throws -> SharedAccountCapabilities {
        freeGroupRequests.append(request)
        if let receipt = selectionReceipts[request.operationId] {
            return receipt
        }
        freeGroupID = request.groupId
        permitsFreeGroupChange = false
        let result = try #require(await currentUser(token: token).accountCapabilities)
        selectionReceipts[request.operationId] = result
        if loseNextFreeGroupResponse {
            loseNextFreeGroupResponse = false
            throw SharedAPIError.transport
        }
        return result
    }

    func delayNextUserLookup(_ gate: MembershipGate) {
        nextUserGate = gate
    }

    func setMemberships(_ groups: [SharedGroup]) {
        memberships = groups
    }

    func overrideMembershipCount(_ count: Int) {
        membershipCountOverride = count
    }

    func delayAuthenticationFailure(_ gate: MembershipGate) {
        nextItemsGate = gate
        delayedItemsError = .server(
            status: 401,
            code: "invalid_session",
            requestID: nil,
            retryAfter: nil
        )
    }

    func omitCapabilities() {
        providesCapabilities = false
    }

    func failMembershipLookup() {
        lookupFails = true
    }

    func rejectCreationAtLimit() {
        creationFails = true
    }

    func setCreationReceipt(_ group: SharedGroup) {
        creationReceipt = group
    }

    func delayNextItems(_ gate: MembershipGate, fails: Bool = false) {
        nextItemsGate = gate
        delayedItemsError = fails ? .transport : nil
    }

    func removeFirstGroupItems() {
        firstGroupHasItems = false
    }

    func currentUser(token: String) async throws -> SharedUser {
        userLookups += 1
        let gate = nextUserGate
        nextUserGate = nil
        await gate?.pause()
        var user = fixture.session.user
        if providesCapabilities {
            let premiumActive = premiumOnSubscriptionRead && hasReadSubscription
            let maximum = freeGroupID == nil ? 3 : (premiumActive ? 5 : 1)
            user.accountCapabilities = try SharedAccountCapabilities(
                membershipCount: membershipCountOverride ?? memberships.count,
                canCreateGroup: memberships.count < maximum,
                canJoinGroup: memberships.count < maximum,
                limits: SharedAccountLimits(groupsPerAccount: SharedResourceLimit(maximum: maximum, enforced: true)),
                membershipAccess: freeGroupID.map { id in
                    SharedMembershipAccess(
                        premiumActive: premiumActive,
                        premiumExpiresAt: Date(timeIntervalSince1970: 1_800_000_000),
                        transitionEndsAt: Date(timeIntervalSince1970: 1_800_604_800),
                        freeGroupId: id,
                        freeGroupChangeAvailableAt: permitsFreeGroupChange
                            ? nil : Date(timeIntervalSince1970: 1_902_592_000),
                        canChangeFreeGroup: permitsFreeGroupChange
                    )
                }
            )
        }
        return user
    }

    func groups(token: String) async throws -> [SharedGroup] {
        guard !lookupFails else { throw SharedAPIError.transport }
        return memberships.map { original in
            guard let freeGroupID else { return original }
            var group = original
            group.capabilities = SharedGroupAccess(
                canUseShopping: (premiumOnSubscriptionRead && hasReadSubscription) || group.id == freeGroupID,
                isFreeGroup: group.id == freeGroupID
            )
            return group
        }
    }

    func stores(groupID: UUID, token: String) async throws -> [SharedStore] {
        try [fixture.firstStore, fixture.secondStore].filter { $0.groupId == groupID }.map { original in
            var store = original
            store.state = try SharedStoreState(
                archivedAt: nil,
                pendingItemCount: 1,
                capabilities: SharedStoreCapabilities(canAddItems: true, canArchive: false, canRestore: false)
            )
            return store
        }
    }

    private var archivedGate: MembershipGate?
    private var archivedFails = false

    func delayArchivedStores(_ gate: MembershipGate, fails: Bool) {
        archivedGate = gate
        archivedFails = fails
    }

    func archivedStores(groupID: UUID, token: String) async throws -> [SharedStore] {
        let gate = archivedGate
        let fails = archivedFails
        archivedGate = nil
        archivedFails = false
        await gate?.pause()
        if fails {
            throw SharedAPIError.server(
                status: 401,
                code: "invalid_session",
                requestID: nil,
                retryAfter: nil
            )
        }
        return []
    }
    func groupCapacity(groupID: UUID, token: String) async throws -> SharedGroupCapacity {
        let count = [fixture.firstStore, fixture.secondStore].filter { $0.groupId == groupID }.count
        return try SharedGroupCapacity(
            groupId: groupID,
            capacityOwnerUserId: fixture.session.user.id,
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
        let snapshot = groupID == fixture.first.id && !firstGroupHasItems
            ? []
            : [item(groupID: groupID, storeID: storeID)]
        let gate = nextItemsGate
        let error = delayedItemsError
        nextItemsGate = nil
        delayedItemsError = nil
        await gate?.pause()
        if let error {
            throw error
        }
        return snapshot
    }

    private func item(groupID: UUID, storeID: UUID) -> SharedItem {
        SharedItem(
            id: storeID,
            groupId: groupID,
            storeId: storeID,
            name: groupID == fixture.first.id ? "Leche de casa" : "Pan del viaje",
            quantity: nil,
            status: "pending",
            version: 1,
            createdBy: fixture.session.user.id,
            createdAt: .distantPast,
            purchasedBy: nil,
            purchasedAt: nil
        )
    }

    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        additionGroups.append(groupID)
        additionOperations.append(request.operationId)
        let storeID = groupID == fixture.first.id ? fixture.firstStore.id : fixture.secondStore.id
        return [item(groupID: groupID, storeID: storeID)]
    }

    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        membershipMutations += 1
        if creationFails {
            throw SharedAPIError.server(
                status: 409,
                code: "group_limit_reached",
                requestID: nil,
                retryAfter: nil
            )
        }
        if let creationReceipt {
            return creationReceipt
        }
        memberships.append(fixture.third)
        creationReceipt = fixture.third
        return fixture.third
    }

    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview {
        InvitationPreview(group: fixture.third, expiresAt: .distantFuture, alreadyAccepted: false)
    }

    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup {
        membershipMutations += 1
        memberships.append(fixture.third)
        return fixture.third
    }

    func createChallenge() async throws -> SharedChallenge { throw SharedAPIError.configuration }
    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession {
        throw SharedAPIError.configuration
    }
    func logout(token: String) async throws {}
    func groupMembers(groupID: UUID, token: String) async throws -> [SharedGroupMember] {
        throw SharedAPIError.configuration
    }
    func groupAdministration(groupID: UUID, token: String) async throws -> SharedGroupAdministration {
        throw SharedAPIError.configuration
    }
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
    func finalizePurchase(
        _ request: FinalizePurchaseRequest,
        groupID: UUID,
        token: String
    ) async throws -> PurchaseResult {
        throw SharedAPIError.configuration
    }
    func changeItem(_ request: SharedItemChangeRequest, item: SharedItem, token: String) async throws -> SharedItem {
        guard request.replacement == nil else { throw SharedAPIError.configuration }
        cancelledItems.append(item.id)
        firstGroupHasItems = false
        return SharedItem(
            id: item.id,
            groupId: item.groupId,
            storeId: item.storeId,
            name: item.name,
            quantity: item.quantity,
            status: "cancelled",
            version: item.version + 1,
            createdBy: item.createdBy,
            createdAt: item.createdAt,
            purchasedBy: nil,
            purchasedAt: nil
        )
    }
}

private actor MembershipGate {
    private var reached = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func pause() async {
        reached = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilReached() async {
        guard !reached else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private struct MembershipSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }
    func finish() async throws {}
    func cancel() async {}
}

extension MultipleGroupTests {
    @Test
    func `A count mismatch cannot turn a partial membership snapshot into a direct shortcut destination`(
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        await api.setMemberships([fixture.first])
        await api.overrideMembershipCount(2)
        let model = fixture.model(api: api)
        let input = ShoppingDraftItem(name: "Café", store: "Aldi")

        #expect(try await model.addShoppingItemFromIntent(input) == .savedToDraft)
        #expect(!model.groupsAreVerified)
        #expect(!model.canMutate)
        #expect(await api.additionGroups.isEmpty)
        #expect(model.draft.items.contains(input))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `An old authentication error cannot replace the session during a selection save`(
        savingFails: Bool
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        var session = fixture.session
        session.activeGroupID = fixture.first.id
        let saveGate = MembershipGate()
        let credentials = MembershipCredentialStore(
            session: session,
            targetID: fixture.second.id,
            gate: saveGate,
            fails: savingFails
        )
        let model = fixture.model(api: api, credentials: credentials)
        await model.load()
        let readGate = MembershipGate()
        await api.delayAuthenticationFailure(readGate)
        model.selectedStoreID = fixture.firstStore.id
        let loading = Task {
            await model.loadSelectedStore()
        }
        await readGate.waitUntilReached()
        let switching = Task {
            await model.selectGroup(id: fixture.second.id)
        }
        await saveGate.waitUntilReached()
        await readGate.open()
        await loading.value
        #expect(model.sessionIsVerified)
        await saveGate.open()
        await switching.value

        #expect(model.sessionIsVerified)
        #expect(model.group?.id == (savingFails ? fixture.first.id : fixture.second.id))
        #expect(try await credentials.loadSession()?.activeGroupID == model.group?.id)
        #expect(model.draft.items == fixture.draft.items)
    }
}

private actor MembershipCredentialStore: SharedCredentialStoring {
    private let store: MemorySharedCredentialStore
    private let targetID: UUID
    private let gate: MembershipGate
    private let fails: Bool

    init(
        session: SharedSession,
        targetID: UUID,
        gate: MembershipGate,
        fails: Bool
    ) {
        store = MemorySharedCredentialStore(session: session)
        self.targetID = targetID
        self.gate = gate
        self.fails = fails
    }

    func loadSession() async throws -> SharedSession? {
        await store.loadSession()
    }
    func saveSession(_ session: SharedSession?) async throws {
        if session?.activeGroupID == targetID {
            await gate.pause()
            if fails {
                throw SharedCredentialError.unavailable(status: -1)
            }
        }
        await store.saveSession(session)
    }
    func loadInvitation() async throws -> PendingInvitation? {
        await store.loadInvitation()
    }
    func saveInvitation(_ invitation: PendingInvitation?) async throws {
        await store.saveInvitation(invitation)
    }
    func loadIncomingInvitation() async throws -> PendingInvitation? {
        await store.loadIncomingInvitation()
    }
    func saveIncomingInvitation(_ invitation: PendingInvitation) async throws {
        await store.saveIncomingInvitation(invitation)
    }
    func clearIncomingInvitation(matching invitation: PendingInvitation) async throws -> Bool {
        await store.clearIncomingInvitation(matching: invitation)
    }
    func loadOperation() async throws -> PendingSharedOperation? {
        await store.loadOperation()
    }
    func saveOperation(_ operation: PendingSharedOperation?) async throws {
        await store.saveOperation(operation)
    }
}


extension MultipleGroupTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `Late store management results cannot replace another group's capacity or invalidate its session`(
        fails: Bool
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        let gate = MembershipGate()
        await api.delayArchivedStores(gate, fails: fails)
        let management = Task {
            await model.loadStoreManagement()
        }
        await gate.waitUntilReached()
        try #require(model.canSelectGroup)
        await model.selectGroup(id: fixture.second.id)
        await model.loadStoreManagement()
        try #require(model.storeManagementState == .loaded)

        await gate.open()
        await management.value

        #expect(model.group?.id == fixture.second.id)
        #expect(model.groupCapacity?.groupId == fixture.second.id)
        #expect(model.stores.map(\.id) == [fixture.secondStore.id])
        #expect(model.storeManagementState == .loaded)
        #expect(model.sessionIsVerified)
        #expect(model.notice == nil)
    }
}


extension MultipleGroupTests {
    @Test(.timeLimit(.minutes(1)))
    func `Store management serializes access verification before allowing another refresh or group choice`(
    ) async throws {
        let fixture = try MembershipFixture()
        let api = MembershipAPI(fixture: fixture)
        let model = fixture.model(api: api)
        await model.load()
        await model.selectGroup(id: fixture.first.id)
        let gate = MembershipGate()
        await api.delayNextUserLookup(gate)
        let firstRefresh = Task {
            await model.loadStoreManagement()
        }
        await gate.waitUntilReached()
        let lookups = await api.userLookups
        #expect(model.isBusy)
        #expect(!model.canSelectGroup)
        await model.loadStoreManagement()
        await model.selectGroup(id: fixture.second.id)
        #expect(await api.userLookups == lookups)
        #expect(model.group?.id == fixture.first.id)

        await gate.open()
        await firstRefresh.value
        await model.selectGroup(id: fixture.second.id)
        await model.loadStoreManagement()

        #expect(model.group?.id == fixture.second.id)
        #expect(model.groupCapacity?.groupId == fixture.second.id)
        #expect(model.storeManagementState == .loaded)
    }
}

private actor MembershipSubscriptionStore: SharedSubscriptionStore {
    private let transaction: SharedStoreTransaction
    private let deliveryGate: MembershipGate
    private let consumedGate: MembershipGate
    private var hasDelivered = false
    private(set) var finished: [String] = []

    init(transaction: SharedStoreTransaction, deliveryGate: MembershipGate, consumedGate: MembershipGate) {
        self.transaction = transaction
        self.deliveryGate = deliveryGate
        self.consumedGate = consumedGate
    }

    func products(ids: [String]) async throws -> [SharedSubscriptionProduct] { [] }
    func purchase(id: String, appAccountToken: UUID) async throws -> SharedSubscriptionPurchaseResult {
        throw SharedSubscriptionStoreError.unavailable
    }
    func restore() async throws {}
    func transactions() async throws -> [SharedStoreTransaction] { [] }
    func updates() async -> AsyncStream<SharedStoreTransaction> {
        AsyncStream(unfolding: {
            await self.nextUpdate()
        })
    }
    func finish(transactionID: String) async {
        finished.append(transactionID)
    }

    private func nextUpdate() async -> SharedStoreTransaction? {
        if !hasDelivered {
            hasDelivered = true
            await deliveryGate.pause()
            return transaction
        }
        await consumedGate.pause()
        return nil
    }
}

private actor MembershipNoTransactionsStore: SharedSubscriptionStore {
    private let withCatalogue: Bool
    private(set) var finished: [String] = []
    private(set) var purchases = 0
    private(set) var restorations = 0

    init(withCatalogue: Bool = false) {
        self.withCatalogue = withCatalogue
    }

    func products(ids: [String]) async throws -> [SharedSubscriptionProduct] {
        guard withCatalogue else { throw SharedSubscriptionStoreError.unavailable }
        return [
            SharedSubscriptionProduct(
                id: "premium.monthly",
                displayName: "Example monthly",
                displayPrice: "Example price",
                period: .monthly,
                subscriptionGroupID: "910"
            ),
            SharedSubscriptionProduct(
                id: "premium.annual",
                displayName: "Example annual",
                displayPrice: "Example price",
                period: .annual,
                subscriptionGroupID: "910"
            )
        ]
    }
    func purchase(id: String, appAccountToken: UUID) async throws -> SharedSubscriptionPurchaseResult {
        purchases += 1
        throw SharedSubscriptionStoreError.unavailable
    }
    func restore() async throws {
        restorations += 1
        throw SharedSubscriptionStoreError.unavailable
    }
    func transactions() async throws -> [SharedStoreTransaction] { [] }
    func updates() async -> AsyncStream<SharedStoreTransaction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func finish(transactionID: String) async {
        finished.append(transactionID)
    }
}
