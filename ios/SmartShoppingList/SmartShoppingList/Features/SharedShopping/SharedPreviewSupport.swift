import DeveloperToolsSupport
import SwiftUI

struct SharedPreviewModifier: PreviewModifier {
    let state: SharedPreviewState

    static func makeSharedContext() async throws -> SharedPreviewContext {
        let fixture = try SharedPreviewFixture.sample()
        var presentations: [SharedPreviewState: SharedPreviewPresentation] = [:]
        for state in SharedPreviewState.allCases {
            let model = SharedPreviewSupport.viewModel(fixture: fixture, state: state)
            await SharedPreviewSupport.prepare(model, fixture: fixture, state: state)
            presentations[state] = SharedPreviewPresentation(model: model, fixture: fixture, state: state)
        }
        return SharedPreviewContext(fixture: fixture, presentations: presentations)
    }

    func body(content: Content, context: SharedPreviewContext) -> some View {
        SharedPreviewContainer(context: context, state: state) { viewModel in
            content
                .environment(viewModel)
        }
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var sharedShopping: Self { sharedShopping(.group) }

    static func sharedShopping(_ state: SharedPreviewState) -> Self {
        .modifier(SharedPreviewModifier(state: state))
    }
}

enum SharedPreviewState: CaseIterable, Hashable {
    case group
    case multipleGroups
    case premiumTransition
    case premiumRestricted
    case premiumActive
    case premiumGrace
    case premiumVerification
    case signedOut
    case signInUnavailable
    case invitation
    case review
    case invitations
    case pending
    case unconfigured
    case storeManagement
    case groupManagementOwner
    case groupTransferRecipient
}

/// Cached by Xcode: values only. Each preview creates its own mutable ViewModel and fake services.
struct SharedPreviewContext {
    let fixture: SharedPreviewFixture
    let presentations: [SharedPreviewState: SharedPreviewPresentation]
}

struct SharedPreviewPresentation {
    let session: SharedSession?
    let groups: [SharedGroup]
    let groupsAreVerified: Bool
    let administration: SharedGroupAdministration?
    let groupMembers: [SharedGroupMember]
    let groupManagementState: GroupManagementLoadState
    let selectedSuccessorID: UUID?
    let pendingInvitation: PendingInvitation?
    let invitationPreview: InvitationPreview?
    let pendingOperation: PendingSharedOperation?
    let stores: [SharedStore]
    let archivedStores: [SharedStore]
    let groupCapacity: SharedGroupCapacity?
    let storeManagementState: GroupManagementLoadState
    let items: [SharedItem]
    let invitations: [SharedInvitation]
    let shareURL: URL?
    let sessionIsVerified: Bool
    let notice: LocalizedStringResource?
    let reviewedItems: [PreparedDraftItem]
    let storeChoices: [DraftStoreChoice]
    let selectedStoreID: UUID?
    let purchaseSelection: [SharedItem]
    let isReviewPresented: Bool
    let isInvitationsPresented: Bool
    let reviewSnapshot: ShoppingDraftSnapshot?
    let subscriptionStatus: SharedSubscriptionStatus?
    let subscriptionProducts: [SharedSubscriptionProduct]
    let subscriptionVerification: PendingSubscriptionVerification?
    let subscriptionNotice: LocalizedStringResource?
}

extension SharedPreviewPresentation {
    @MainActor
    init(model: SharedShoppingViewModel, fixture: SharedPreviewFixture, state: SharedPreviewState) {
        session = model.session
        groups = model.groups
        groupsAreVerified = model.groupsAreVerified
        administration = model.administration
        groupMembers = model.groupMembers
        groupManagementState = model.groupManagementState
        selectedSuccessorID = model.selectedSuccessorID
        pendingInvitation = model.pendingInvitation
        invitationPreview = model.invitationPreview
        pendingOperation = model.pendingOperation
        stores = model.stores
        archivedStores = model.archivedStores
        groupCapacity = model.groupCapacity
        storeManagementState = model.storeManagementState
        items = model.items
        invitations = model.invitations
        shareURL = model.shareURL
        sessionIsVerified = model.sessionIsVerified
        notice = model.notice
        reviewedItems = model.reviewedItems
        storeChoices = model.storeChoices
        selectedStoreID = model.selectedStoreID
        purchaseSelection = model.purchaseSelection
        isReviewPresented = model.isReviewPresented
        isInvitationsPresented = model.isInvitationsPresented
        reviewSnapshot = state == .review ? fixture.draft : nil
        subscriptionStatus = model.premium.status
        subscriptionProducts = model.premium.products
        subscriptionVerification = model.premium.pendingVerification
        subscriptionNotice = model.premium.notice
    }
}

/// Only these immutable values are shared between previews; each container creates its own models and services.
struct SharedPreviewFixture {
    let configuration: SharedAPIConfiguration
    let session: SharedSession
    let group: SharedGroup
    let stores: [SharedStore]
    let archivedStores: [SharedStore]
    let items: [SharedItem]
    let draft: ShoppingDraftSnapshot
    let invitation: SharedInvitation
    let pendingInvitation: PendingInvitation
    let createdInvitation: CreatedInvitation

    static func sample() throws -> SharedPreviewFixture {
        let configuration = try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test")
        let userID = identifier(1)
        let groupID = identifier(16)
        let date = Date(timeIntervalSince1970: 1_789_812_000)
        let group = SharedGroup(
            id: groupID,
            name: "Casa",
            creatorUserId: userID,
            createdAt: date,
            administratorUserId: userID
        )
        let session = SharedSession(
            accessToken: "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSQ",
            tokenType: "Bearer",
            expiresAt: date.addingTimeInterval(30 * 86_400),
            user: SharedUser(id: userID, displayName: "Alex", group: group)
        )
        let stores = [
            SharedStore(
                id: identifier(32),
                groupId: groupID,
                name: "Mercadona Centro",
                state: try SharedStoreState(
                    archivedAt: nil,
                    pendingItemCount: 2,
                    capabilities: SharedStoreCapabilities(canAddItems: true, canArchive: false, canRestore: false)
                )
            ),
            SharedStore(
                id: identifier(33),
                groupId: groupID,
                name: "Día Norte",
                state: try SharedStoreState(
                    archivedAt: nil,
                    pendingItemCount: 0,
                    capabilities: SharedStoreCapabilities(canAddItems: true, canArchive: true, canRestore: false)
                )
            )
        ]
        let archivedStores = [SharedStore(
            id: identifier(34),
            groupId: groupID,
            name: "Tienda del barrio anterior",
            state: try SharedStoreState(
                archivedAt: date,
                pendingItemCount: 0,
                capabilities: SharedStoreCapabilities(canAddItems: false, canArchive: false, canRestore: true)
            )
        )]
        let draft = ShoppingDraftSnapshot(
            text: "Leche sin lactosa y pan integral en Mercadona Centro",
            items: [
                ShoppingDraftItem(
                    id: identifier(48),
                    name: "Leche sin lactosa",
                    quantity: "2 briks",
                    store: "Mercadona Centro"
                ),
                ShoppingDraftItem(
                    id: identifier(49),
                    name: "Pan integral de semillas",
                    quantity: "",
                    store: "Mercadona Centro"
                )
            ]
        )
        let items = draft.items.map { entry in
            SharedItem(
                id: entry.id,
                groupId: groupID,
                storeId: identifier(32),
                name: entry.name,
                quantity: entry.quantity.isEmpty ? nil : entry.quantity,
                status: "pending",
                version: 1,
                createdBy: userID,
                createdAt: date,
                purchasedBy: nil,
                purchasedAt: nil
            )
        }
        let invitation = SharedInvitation(
            id: identifier(64),
            groupId: groupID,
            createdAt: date,
            expiresAt: date.addingTimeInterval(86_400),
            revokedAt: nil,
            acceptedAt: nil,
            acceptedBy: nil
        )
        let pendingInvitation = PendingInvitation(
            id: invitation.id,
            token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
        let endpoint = configuration.invitationOrigin.appending(path: "invite/\(invitation.id.uuidString.lowercased())")
        guard var link = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SharedAPIError.configuration
        }
        link.fragment = "token=\(pendingInvitation.token)"
        guard let invitationURL = link.url else { throw SharedAPIError.configuration }
        return SharedPreviewFixture(
            configuration: configuration,
            session: session,
            group: group,
            stores: stores,
            archivedStores: archivedStores,
            items: items,
            draft: draft,
            invitation: invitation,
            pendingInvitation: pendingInvitation,
            createdInvitation: CreatedInvitation(invitation: invitation, url: invitationURL)
        )
    }

    private static func identifier(_ suffix: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, suffix))
    }
}

@MainActor
enum SharedPreviewSupport {
    #if DEBUG
    static func aiValidationViewModel(emptyInterpretation: Bool) throws -> SharedShoppingViewModel {
        let fixture = try SharedPreviewFixture.sample()
        let api = PreviewSharedShoppingAPI(fixture: fixture, user: fixture.session.user)
        api.permitsAdditions = true
        return SharedShoppingViewModel(
            api: api,
            configuration: fixture.configuration,
            credentials: MemorySharedCredentialStore(session: fixture.session),
            draft: DraftPreviewSupport.aiValidationViewModel(emptyInterpretation: emptyInterpretation),
            storeQuery: StoreQueryViewModel(speech: PreviewStoreQuerySpeech())
        )
    }
    #endif

    static func viewModel(
        fixture: SharedPreviewFixture,
        state: SharedPreviewState,
        presentation: SharedPreviewPresentation? = nil
    ) -> SharedShoppingViewModel {
        let draft = DraftPreviewSupport.viewModel(snapshot: fixture.draft, state: .content)
        var session = fixture.session
        if state == .invitation {
            session.user.group = nil
        } else if state == .groupTransferRecipient {
            session.user = SharedUser(
                id: PreviewSharedShoppingAPI.successorID,
                displayName: "Alex",
                group: fixture.group
            )
        }
        let pending: PendingSharedOperation? = state == .pending ? .addItems(
            userID: session.user.id,
            groupID: fixture.group.id,
            request: AddItemsRequest(
                operationId: fixture.invitation.id,
                items: fixture.draft.items.map { item in
                    SharedNewItem(
                        name: item.name,
                        quantity: item.quantity.isEmpty ? nil : item.quantity,
                        store: .existing(fixture.stores[0].id)
                    )
                }
            ),
            sourceDraft: fixture.draft
        ) : nil
        let isPremiumPreview = [.premiumActive, .premiumGrace, .premiumVerification].contains(state)
        if state == .multipleGroups || state == .premiumTransition || state == .premiumRestricted || isPremiumPreview {
            session.activeGroupID = fixture.group.id
        }
        let credentials = MemorySharedCredentialStore(
            session: state == .signedOut || state == .signInUnavailable || state == .unconfigured ? nil : session,
            invitation: state == .invitation || state == .signedOut ? fixture.pendingInvitation : nil,
            operation: pending,
            subscriptionVerification: state == .premiumVerification ? PendingSubscriptionVerification(
                userID: session.user.id,
                transactionID: "1001",
                request: VerifySharedSubscriptionRequest(signedTransaction: "preview-verification-only")
            ) : nil
        )
        let managementScenario: GroupManagementPreviewScenario = switch state {
        case .groupManagementOwner: .owner
        case .groupTransferRecipient: .recipient
        default: .solo
        }
        let api = state == .unconfigured ? nil : PreviewSharedShoppingAPI(
            fixture: fixture,
            user: session.user,
            signInUnavailable: state == .signInUnavailable,
            managementScenario: managementScenario
        )
        if state == .multipleGroups || state == .premiumTransition || state == .premiumRestricted || isPremiumPreview {
            api?.premiumScenario = state == .multipleGroups ? nil : state
            api?.additionalGroups = [SharedGroup(
                id: fixture.invitation.id,
                name: state == .multipleGroups ? fixture.group.name : "Familia",
                creatorUserId: session.user.id,
                createdAt: fixture.group.createdAt
            )]
        }
        let configuration = state == .unconfigured ? nil : fixture.configuration
        let subscriptionStore: (any SharedSubscriptionStore)? = isPremiumPreview ? PreviewPremiumStore() : nil
        #if DEBUG
        if let presentation {
            return SharedShoppingViewModel(
                preview: presentation,
                api: api,
                configuration: configuration,
                credentials: credentials,
                draft: draft,
                storeQuery: StoreQueryViewModel(speech: PreviewStoreQuerySpeech()),
                subscriptionStore: subscriptionStore
            )
        }
        #endif
        return SharedShoppingViewModel(
            api: api,
            configuration: configuration,
            credentials: credentials,
            draft: draft,
            storeQuery: StoreQueryViewModel(speech: PreviewStoreQuerySpeech()),
            subscriptionStore: subscriptionStore
        )
    }

    static func prepare(
        _ model: SharedShoppingViewModel,
        fixture: SharedPreviewFixture,
        state: SharedPreviewState
    ) async {
        await model.load()
        if [.premiumActive, .premiumGrace, .premiumVerification].contains(state) {
            await model.loadPremium()
        }
        switch state {
        case .group, .multipleGroups, .premiumTransition, .premiumRestricted,
             .premiumActive, .premiumGrace, .premiumVerification:
            model.selectedStoreID = fixture.stores.first?.id
            await model.loadSelectedStore()
            if let first = model.items.first {
                model.togglePurchaseItem(first)
            }
        case .review:
            await model.prepareReview()
        case .invitations:
            await model.openInvitations()
            await model.createInvitation()
        case .storeManagement:
            await model.loadStoreManagement()
        case .groupManagementOwner, .groupTransferRecipient:
            await model.loadGroupManagement()
            model.selectedSuccessorID = PreviewSharedShoppingAPI.successorID
        case .signedOut, .signInUnavailable, .invitation, .pending, .unconfigured:
            break
        }
    }
}

@MainActor
private final class PreviewSharedShoppingAPI: SharedShoppingAPI {
    nonisolated static let successorID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 2))
    let fixture: SharedPreviewFixture
    let user: SharedUser
    let signInUnavailable: Bool
    var additionalGroups: [SharedGroup] = []
    var premiumScenario: SharedPreviewState? = nil
    private var premiumIsActive: Bool { premiumScenario == .premiumActive || premiumScenario == .premiumGrace }
    private let managementScenario: GroupManagementPreviewScenario
    private var storedStores: [SharedStore]
    private var storedArchivedStores: [SharedStore]
    private var storeReceipts: [UUID: PreviewStoreReceipt] = [:]
    private var storedItems: [SharedItem]
    #if DEBUG
    var permitsAdditions = false
    private var additions: [UUID: [SharedItem]] = [:]
    #endif

    init(
        fixture: SharedPreviewFixture,
        user: SharedUser,
        signInUnavailable: Bool = false,
        managementScenario: GroupManagementPreviewScenario = .solo
    ) {
        self.fixture = fixture
        self.user = user
        self.signInUnavailable = signInUnavailable
        self.managementScenario = managementScenario
        storedStores = fixture.stores
        storedArchivedStores = fixture.archivedStores
        storedItems = fixture.items
    }

    // Preview data never requires a remote request.
    func createChallenge() async throws -> SharedChallenge {
        guard !signInUnavailable else { throw SharedAPIError.transport }
        return SharedChallenge(id: UUID(), nonce: String(repeating: "A", count: 43), expiresAt: Date().addingTimeInterval(300))
    }
    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession { throw SharedAPIError.configuration }
    @MainActor
    func currentUser(token: String) async throws -> SharedUser {
        var result = user
        let count = (user.group == nil ? 0 : 1) + additionalGroups.count
        let maximum = premiumIsActive ? 5 : (premiumScenario != nil || additionalGroups.isEmpty ? 1 : 3)
        let permitsGrowth = premiumIsActive || premiumScenario == nil
        result.accountCapabilities = try SharedAccountCapabilities(
            membershipCount: count,
            canCreateGroup: permitsGrowth && count < maximum,
            canJoinGroup: permitsGrowth && count < maximum,
            limits: SharedAccountLimits(groupsPerAccount: SharedResourceLimit(maximum: maximum, enforced: true)),
            membershipAccess: premiumScenario.map { scenario in
                let premiumExpiry: Date
                let transitionEnd: Date?
                if premiumIsActive {
                    let expiryTimestamp = scenario == .premiumGrace ? 1_792_800_000.0 : 1_792_972_800.0
                    premiumExpiry = Date(timeIntervalSince1970: expiryTimestamp)
                    transitionEnd = nil
                } else if scenario == .premiumTransition {
                    premiumExpiry = Date(timeIntervalSince1970: 1_791_417_600)
                    transitionEnd = Date(timeIntervalSince1970: 1_792_022_400)
                } else {
                    premiumExpiry = fixture.group.createdAt
                    transitionEnd = fixture.group.createdAt.addingTimeInterval(7 * 86_400)
                }
                return SharedMembershipAccess(
                    premiumActive: premiumIsActive,
                    premiumExpiresAt: premiumExpiry,
                    transitionEndsAt: transitionEnd,
                    freeGroupId: additionalGroups.first?.id,
                    freeGroupChangeAvailableAt: scenario == .premiumRestricted
                        ? Date(timeIntervalSince1970: 1_792_022_400) : nil,
                    canChangeFreeGroup: scenario != .premiumRestricted
                )
            }
        )
        return result
    }
    @MainActor
    func groups(token: String) async throws -> [SharedGroup] {
        ((user.group.map { [$0] } ?? []) + additionalGroups).map(projectedGroup)
    }
    private func projectedGroup(_ original: SharedGroup) -> SharedGroup {
        guard let premiumScenario else { return original }
        var group = original
        group.capabilities = SharedGroupAccess(
            canUseShopping: premiumIsActive || premiumScenario == .premiumTransition
                || group.id == additionalGroups.first?.id,
            isFreeGroup: group.id == additionalGroups.first?.id
        )
        return group
    }

    @MainActor
    func subscription(token: String) async throws -> SharedSubscriptionStatus {
        guard let scenario = premiumScenario,
              [.premiumActive, .premiumGrace, .premiumVerification].contains(scenario) else {
            throw SharedAPIError.configuration
        }
        let inGrace = premiumScenario == .premiumGrace
        return SharedSubscriptionStatus(
            appAccountToken: user.id,
            isConfigured: true,
            productIDs: ["preview.premium.monthly", "preview.premium.annual"],
            state: inGrace ? .inGracePeriod : premiumIsActive ? .subscribed : .free,
            expiresAt: premiumIsActive ? Date(timeIntervalSince1970: inGrace ? 1_791_417_600 : 1_792_972_800) : nil,
            gracePeriodExpiresAt: inGrace ? Date(timeIntervalSince1970: 1_792_800_000) : nil,
            autoRenewEnabled: premiumIsActive ? true : nil,
            verifiedAt: premiumIsActive ? Date(timeIntervalSince1970: 1_791_504_000) : nil
        )
    }

    func verifySubscription(
        _ request: VerifySharedSubscriptionRequest,
        token: String
    ) async throws -> SharedSubscriptionAcknowledgement {
        throw SharedAPIError.server(status: 503, code: "subscription_unavailable", requestID: nil, retryAfter: nil)
    }

    func logout(token: String) async throws {}
    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func groupMembers(groupID: UUID, token: String) async throws -> [SharedGroupMember] {
        guard managementScenario != .solo else {
            return [SharedGroupMember(id: user.id, displayName: user.displayName)]
        }
        return [
            SharedGroupMember(id: fixture.session.user.id, displayName: "Alex"),
            SharedGroupMember(id: Self.successorID, displayName: "Alex"),
            SharedGroupMember(id: fixture.invitation.id, displayName: nil)
        ]
    }
    @MainActor
    func groupAdministration(groupID: UUID, token: String) async throws -> SharedGroupAdministration {
        let isRecipient = managementScenario == .recipient
        let transfer = isRecipient ? SharedGroupTransfer(
            id: fixture.invitation.id,
            groupId: fixture.group.id,
            proposerUserId: fixture.session.user.id,
            recipientUserId: Self.successorID,
            status: .pending,
            createdAt: fixture.group.createdAt,
            expiresAt: fixture.group.createdAt.addingTimeInterval(604_800),
            resolvedAt: nil
        ) : nil
        return SharedGroupAdministration(
            group: projectedGroup(fixture.group),
            memberCount: managementScenario == .solo ? 1 : 3,
            pendingTransfer: transfer,
            capabilities: SharedGroupCapabilities(
                canManageInvitations: !isRecipient,
                canProposeTransfer: managementScenario == .owner,
                canAcceptTransfer: isRecipient,
                canRejectTransfer: isRecipient,
                canWithdrawTransfer: false,
                canLeave: managementScenario != .owner,
                requiresClosureConfirmation: managementScenario == .solo,
                capacityOwnerUserId: fixture.session.user.id,
                limits: SharedGroupLimits(
                    groupsPerAccount: SharedResourceLimit(maximum: 1, enforced: true),
                    storesPerGroup: SharedResourceLimit(maximum: 3, enforced: true),
                    pendingItemsPerStore: SharedResourceLimit(maximum: 20, enforced: true)
                )
            )
        )
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
    @MainActor
    func stores(groupID: UUID, token: String) async throws -> [SharedStore] {
        try storedStores.filter { $0.groupId == groupID }.map { try currentStore($0, archivedAt: nil) }
    }
    @MainActor
    func archivedStores(groupID: UUID, token: String) async throws -> [SharedStore] {
        try storedArchivedStores.filter { $0.groupId == groupID }.map {
            try currentStore($0, archivedAt: $0.archivedAt)
        }
    }

    private func currentStore(_ original: SharedStore, archivedAt: Date?) throws -> SharedStore {
        var store = original
        let count = storedItems.filter { $0.storeId == store.id && $0.status == "pending" }.count
        let isAdministrator = user.id == fixture.group.administratorUserId
        store.state = try SharedStoreState(
            archivedAt: archivedAt,
            pendingItemCount: count,
            capabilities: SharedStoreCapabilities(
                canAddItems: archivedAt == nil && count < 20,
                canArchive: archivedAt == nil && count == 0 && isAdministrator,
                canRestore: archivedAt != nil && storedStores.count < 3 && isAdministrator
            )
        )
        return store
    }
    @MainActor
    func groupCapacity(groupID: UUID, token: String) async throws -> SharedGroupCapacity {
        let count = storedStores.filter { $0.groupId == groupID }.count
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
    @MainActor
    func changeStoreState(
        _ request: ChangeStoreStateRequest,
        groupID: UUID,
        storeID: UUID,
        action: SharedStoreAction,
        token: String
    ) async throws -> SharedStore {
        if let receipt = storeReceipts[request.operationId] {
            guard receipt.store.id == storeID, receipt.store.groupId == groupID, receipt.action == action else {
                throw SharedAPIError.invalidResponse
            }
            return receipt.store
        }
        guard groupID == fixture.group.id, user.id == fixture.group.administratorUserId,
              let store = (storedStores + storedArchivedStores).first(where: { $0.id == storeID }) else {
            throw SharedAPIError.configuration
        }
        let current = try currentStore(store, archivedAt: store.archivedAt)
        let updated: SharedStore
        if action == .archive, current.archivedAt == nil {
            guard current.capabilities?.canArchive == true else { throw SharedAPIError.configuration }
            updated = try currentStore(current, archivedAt: Date.now)
            storedStores.removeAll { $0.id == storeID }
            storedArchivedStores.append(updated)
        } else if action == .restore, current.archivedAt != nil {
            guard current.capabilities?.canRestore == true else { throw SharedAPIError.configuration }
            updated = try currentStore(current, archivedAt: nil)
            storedArchivedStores.removeAll { $0.id == storeID }
            storedStores.append(updated)
        } else {
            updated = current
        }
        storeReceipts[request.operationId] = PreviewStoreReceipt(action: action, store: updated)
        return updated
    }
    func createInvitation(groupID: UUID, token: String) async throws -> CreatedInvitation {
        fixture.createdInvitation
    }
    func invitations(groupID: UUID, token: String) async throws -> [SharedInvitation] { [fixture.invitation] }
    func revokeInvitation(groupID: UUID, invitationID: UUID, token: String) async throws {
        throw SharedAPIError.configuration
    }
    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview {
        InvitationPreview(group: fixture.group, expiresAt: fixture.invitation.expiresAt, alreadyAccepted: false)
    }
    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup {
        throw SharedAPIError.configuration
    }
    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        #if DEBUG
        return try await MainActor.run {
            guard permitsAdditions, groupID == fixture.group.id else { throw SharedAPIError.transport }
            if let result = additions[request.operationId] { return result }
            let result = try request.items.map { entry in
                let storeID: UUID
                switch entry.store {
                case .existing(let id):
                    guard storedStores.contains(where: { $0.id == id }) else { throw SharedAPIError.invalidResponse }
                    storeID = id
                case .newName(let name):
                    if let store = storedStores.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        storeID = store.id
                    } else {
                        storeID = UUID()
                        storedStores.append(SharedStore(id: storeID, groupId: groupID, name: name))
                    }
                }
                return SharedItem(
                    id: UUID(),
                    groupId: groupID,
                    storeId: storeID,
                    name: entry.name,
                    quantity: entry.quantity,
                    status: "pending",
                    version: 1,
                    createdBy: user.id,
                    createdAt: fixture.group.createdAt,
                    purchasedBy: nil,
                    purchasedAt: nil
                )
            }
            storedItems.append(contentsOf: result)
            additions[request.operationId] = result
            return result
        }
        #else
        throw SharedAPIError.transport
        #endif
    }
    func finalizePurchase(
        _ request: FinalizePurchaseRequest,
        groupID: UUID,
        token: String
    ) async throws -> PurchaseResult {
        throw SharedAPIError.transport
    }

    func changeItem(_ request: SharedItemChangeRequest, item: SharedItem, token: String) async throws -> SharedItem {
        throw SharedAPIError.transport
    }

    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem] {
        await MainActor.run { storedItems.filter { $0.storeId == storeID } }
    }
}

private struct PreviewStoreReceipt {
    let action: SharedStoreAction
    let store: SharedStore
}

private enum GroupManagementPreviewScenario {
    case solo, owner, recipient
}

private struct PreviewStoreQuerySpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }
    func finish() async throws {}
    func cancel() async {}
}

/// Preview metadata is explicitly illustrative; no StoreKit or API call is made by this service.
private struct PreviewPremiumStore: SharedSubscriptionStore {
    func products(ids: [String]) async throws -> [SharedSubscriptionProduct] {
        [
            SharedSubscriptionProduct(
                id: "preview.premium.monthly",
                displayName: String(localized: "Example monthly premium"),
                displayPrice: String(localized: "Example price"),
                period: .monthly,
                subscriptionGroupID: "preview-only"
            ),
            SharedSubscriptionProduct(
                id: "preview.premium.annual",
                displayName: String(localized: "Example annual premium"),
                displayPrice: String(localized: "Example price"),
                period: .annual,
                subscriptionGroupID: "preview-only"
            )
        ]
    }
    func purchase(id: String, appAccountToken: UUID) async throws -> SharedSubscriptionPurchaseResult { .cancelled }
    func restore() async throws {}
    func transactions() async throws -> [SharedStoreTransaction] { [] }
    func updates() async -> AsyncStream<SharedStoreTransaction> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func finish(transactionID: String) async {}
}
