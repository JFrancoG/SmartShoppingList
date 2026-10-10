import AuthenticationServices
import Foundation
import Observation
import Security

struct DraftStoreChoice: Identifiable {
    let id: String
    var selection = ""
    var needsClarification = false
}

enum StoreItemsState {
    case notLoaded
    case loading
    case loaded
    case failed
}

@Observable @MainActor
final class SharedShoppingViewModel {
    private struct ReviewOwner: Equatable {
        let userID: UUID
        let groupID: UUID
    }

    private struct GroupContext: Equatable {
        let userID: UUID
        let groupID: UUID
        let generation: UUID
    }

    private(set) var storeItemsState = StoreItemsState.notLoaded
    private(set) var session: SharedSession?
    private(set) var groups: [SharedGroup] = []
    private(set) var groupsAreVerified = false
    private var groupGeneration = UUID()
    private var groupLoadID: UUID?
    private(set) var pendingInvitation: PendingInvitation?
    private(set) var invitationPreview: InvitationPreview?
    private(set) var pendingOperation: PendingSharedOperation?
    private var purchaseSelections: [UUID: [SharedItem]] = [:]
    private var purchaseSelectionOwner: UUID?
    private var loadedStoreID: UUID?
    private(set) var stores: [SharedStore] = []
    private(set) var archivedStores: [SharedStore] = []
    private(set) var groupCapacity: SharedGroupCapacity?
    private(set) var storeManagementState = GroupManagementLoadState.notLoaded
    private(set) var items: [SharedItem] = []
    private(set) var invitations: [SharedInvitation] = []
    private(set) var shareURL: URL?
    private(set) var administration: SharedGroupAdministration?
    private(set) var groupMembers: [SharedGroupMember] = []
    private(set) var groupManagementState = GroupManagementLoadState.notLoaded
    var selectedSuccessorID: UUID?
    private(set) var hasLoaded = false
    private var isPerformingAction = false
    private var isProcessingShoppingIntent = false
    private(set) var draftIntentNavigationID: UUID?
    private(set) var sessionIsVerified = false
    private(set) var notice: LocalizedStringResource? {
        didSet {
            noticeStoreDestination = nil
        }
    }
    private var noticeStoreDestination: ShoppingNotice.StoreDestination?
    private(set) var challenge: SharedChallenge?
    private(set) var appleLoginPreparationError: LocalizedStringResource?
    private var applePreparationID: UUID?
    private var isAuthorizingWithApple = false
    private(set) var reviewedItems: [PreparedDraftItem] = []
    private var reviewOwner: ReviewOwner?
    var storeChoices: [DraftStoreChoice] = []
    var selectedStoreID: UUID? {
        didSet {
            guard oldValue != selectedStoreID else { return }
            items = []
            loadedStoreID = nil
            storeItemsState = .notLoaded
        }
    }
    private(set) var editingItem: SharedItem?
    var editName = ""
    var editQuantity = ""
    var editStoreID: UUID?
    var editNewStore = ""
    private(set) var editNeedsReview = false
    var isItemEditorPresented = false {
        didSet {
            if isItemEditorPresented {
                closeStoreQuery()
                isItemEditorPresentationActive = true
            }
        }
    }
    private(set) var isItemEditorPresentationActive = false
    var groupName = ""
    var isReviewPresented = false {
        didSet {
            if isReviewPresented {
                closeStoreQuery()
                isReviewPresentationActive = true
            }
        }
    }
    var isInvitationsPresented = false {
        didSet {
            if isInvitationsPresented {
                closeStoreQuery()
                isInvitationsPresentationActive = true
            }
        }
    }
    private(set) var isReviewPresentationActive = false
    private(set) var isInvitationsPresentationActive = false

    private(set) var isStoreQueryVisible = false
    @ObservationIgnored private var storeQueryRevision: UUID?
    @ObservationIgnored let storeQuery: StoreQueryViewModel
    @ObservationIgnored let draft: ShoppingDraftViewModel
    @ObservationIgnored let premium: SharedPremiumViewModel
    @ObservationIgnored private let subscriptionStore: (any SharedSubscriptionStore)?
    @ObservationIgnored private var subscriptionUpdatesTask: Task<Void, Never>?
    @ObservationIgnored private var deferredSubscriptionUpdates: [String: SharedStoreTransaction] = [:]
    @ObservationIgnored private var isDrainingSubscriptionUpdates = false
    @ObservationIgnored private let api: (any SharedShoppingAPI)?
    @ObservationIgnored private let configuration: SharedAPIConfiguration?
    @ObservationIgnored private let credentials: any SharedCredentialStoring
    @ObservationIgnored private var appleState: String?
    @ObservationIgnored private let appleLoginDate: @MainActor () -> Date
    @ObservationIgnored private var storageFailed = false
    @ObservationIgnored private var hasRestoredLocalState = false
    @ObservationIgnored private var localStateLoadTask: Task<Void, Never>?
    @ObservationIgnored private var initialLoadTask: Task<Void, Never>?
    @ObservationIgnored private var reviewSnapshot: ShoppingDraftSnapshot?
    @ObservationIgnored private var retryNotBefore: Date?

    init(
        api: (any SharedShoppingAPI)?,
        configuration: SharedAPIConfiguration?,
        credentials: any SharedCredentialStoring,
        draft: ShoppingDraftViewModel,
        storeQuery: StoreQueryViewModel,
        appleLoginDate: @escaping @MainActor () -> Date = { Date() },
        subscriptionStore: (any SharedSubscriptionStore)? = nil
    ) {
        self.subscriptionStore = subscriptionStore
        premium = SharedPremiumViewModel(
            api: api,
            store: subscriptionStore,
            credentials: credentials as? any SharedSubscriptionCredentialStoring
        )
        self.api = api
        self.configuration = configuration
        self.credentials = credentials
        self.draft = draft
        self.storeQuery = storeQuery
        self.appleLoginDate = appleLoginDate
    }

    deinit {
        subscriptionUpdatesTask?.cancel()
    }

    var group: SharedGroup? { groups.first { $0.id == session?.activeGroupID } }
    var isConfigured: Bool { api != nil && configuration != nil }
    var isBusy: Bool { isPerformingAction || isProcessingShoppingIntent || groupLoadID != nil || premium.isBusy }
    var isPreparingAppleLogin: Bool { applePreparationID != nil }
    var shouldMaintainAppleLogin: Bool {
        hasLoaded && isConfigured && session == nil && !isAuthorizingWithApple && !storageFailed
            && appleLoginPreparationError == nil
    }
    var canRequestAppleLogin: Bool {
        shouldMaintainAppleLogin && !isBusy && !isPreparingAppleLogin && hasReadyAppleChallenge
    }
    private var hasReadyAppleChallenge: Bool {
        appleState != nil && (challenge?.expiresAt.timeIntervalSince(appleLoginDate()) ?? 0) > 30
    }
    var canMutate: Bool {
        hasLoaded && sessionIsVerified && groupsAreVerified && !isBusy && !storageFailed && pendingOperation == nil
            && storeQuery.activity == .idle && !draft.isReceivingIntent
    }
    var canUseShopping: Bool { group?.capabilities?.canUseShopping == true && groupsAreVerified }
    var canPerformShopping: Bool { canMutate && canUseShopping }
    var membershipAccess: SharedMembershipAccess? { session?.user.accountCapabilities?.membershipAccess }
    var freeGroupName: String? { groups.first { $0.id == membershipAccess?.freeGroupId }?.name }
    var canSelectFreeGroup: Bool {
        canSelectGroup && membershipAccess?.canChangeFreeGroup == true
    }
    var hasRestrictedGroup: Bool { groupsAreVerified && group?.capabilities?.canUseShopping == false }

    var draftIsLocked: Bool {
        !hasLoaded || pendingOperation != nil || isBusy || isReviewPresented || draft.isReceivingIntent
    }
    var isAdministrator: Bool {
        sessionIsVerified && groupsAreVerified && group?.administratorUserId == session?.user.id
            && group?.administratorUserId != nil
    }
    var canManageInvitations: Bool {
        sessionIsVerified && groupsAreVerified && administration?.group.id == group?.id
            && administration?.capabilities.canManageInvitations == true
    }
    var canConfirmReview: Bool {
        canPerformShopping && reviewOwner != nil && reviewOwner?.userID == session?.user.id
            && reviewOwner?.groupID == group?.id && !reviewedItems.isEmpty
            && storeChoices.allSatisfy { !$0.selection.isEmpty }
            && submissionCapacityMessage == nil
    }
    var canRetryOperation: Bool {
        !isBusy && sessionIsVerified && pendingOperation?.userID == session?.user.id && !storageFailed
    }
    var selectedStoreName: String {
        stores.first { $0.id == selectedStoreID }?.name ?? ""
    }

    var canSelectGroup: Bool {
        hasLoaded && sessionIsVerified && groupsAreVerified && !storageFailed
            && !isPerformingAction && !isProcessingShoppingIntent && pendingOperation == nil
            && !isReviewPresentationActive && !isItemEditorPresentationActive && !isInvitationsPresentationActive
            && !draft.isEditorPresentationActive && !draft.isReceivingIntent && draft.activity == .idle
            && storeQuery.activity == .idle
    }

    var canCreateGroup: Bool { canMutate && session?.user.accountCapabilities?.canCreateGroup == true }

    var canAcceptInvitation: Bool {
        canMutate && (session?.user.accountCapabilities?.canJoinGroup == true
            || invitationPreview.map { preview in groups.contains { $0.id == preview.group.id } } == true)
    }

    var groupAccessMessage: LocalizedStringResource? {
        guard sessionIsVerified, groupsAreVerified else { return nil }
        guard let capabilities = session?.user.accountCapabilities else {
            return "Group availability could not be verified. Refresh before creating or joining a group."
        }
        return capabilities.canCreateGroup
            ? nil
            : "Your account has reached its group limit. Your current groups and draft are kept."
    }

    var reviewedGroupName: String { group?.name ?? "" }

    func groupNeedsIdentifier(_ candidate: SharedGroup) -> Bool {
        groups.contains {
            $0.id != candidate.id && $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                == candidate.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
    }

    func groupConfirmationName(_ candidate: SharedGroup) -> String {
        groupNeedsIdentifier(candidate) ? "\(candidate.name) (\(candidate.id.uuidString))" : candidate.name
    }

    func selectFreeGroup(id: UUID) async {
        guard canSelectFreeGroup, id != membershipAccess?.freeGroupId,
              groups.contains(where: { $0.id == id }), let session else { return }
        let request = SelectFreeGroupRequest(operationId: UUID(), groupId: id)
        await performAction {
            do {
                let operation = PendingSharedOperation.selectFreeGroup(userID: session.user.id, request: request)
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                await performPendingOperation()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    func loadPremium(reportsActionErrors: Bool = false) async {
        guard subscriptionStore != nil, !isBusy, sessionIsVerified, let session else { return }
        await performAction {
            let receivedAuthority = await premium.load(session: session, isCurrentSession: isCurrentSubscriptionSession)
            let actionNotice = reportsActionErrors ? premium.takeActionNotice() : nil
            if receivedAuthority, isCurrentSubscriptionSession(session) {
                await refreshSessionAndLists()
            }
            if isCurrentSubscriptionSession(session), let actionNotice {
                notice = actionNotice
            }
        }
    }

    func purchasePremium(productID: String) async {
        guard !isBusy, sessionIsVerified, let session else { return }
        await performAction {
            let acknowledged = await premium.purchase(
                productID: productID,
                session: session,
                isCurrentSession: isCurrentSubscriptionSession
            )
            let actionNotice = premium.takeActionNotice()
            if acknowledged, isCurrentSubscriptionSession(session) {
                await refreshSessionAndLists()
            }
            if isCurrentSubscriptionSession(session), let actionNotice {
                notice = actionNotice
            }
        }
    }

    func restorePremium() async {
        guard !isBusy, sessionIsVerified, let session else { return }
        await performAction {
            let acknowledged = await premium.restore(session: session, isCurrentSession: isCurrentSubscriptionSession)
            let actionNotice = premium.takeActionNotice()
            if acknowledged, isCurrentSubscriptionSession(session) {
                await refreshSessionAndLists()
            }
            if isCurrentSubscriptionSession(session), let actionNotice {
                notice = actionNotice
            }
        }
    }

    private func isCurrentSubscriptionSession(_ candidate: SharedSession) -> Bool {
        sessionIsVerified && session?.user.id == candidate.user.id && session?.accessToken == candidate.accessToken
    }

    private func startSubscriptionUpdates() {
        guard subscriptionUpdatesTask == nil, let subscriptionStore else { return }
        subscriptionUpdatesTask = Task { [weak self] in
            let updates = await subscriptionStore.updates()
            for await transaction in updates {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                self.deferredSubscriptionUpdates[transaction.id] = transaction
                if self.deferredSubscriptionUpdates.count > 100,
                   let oldest = self.deferredSubscriptionUpdates.keys.sorted().first {
                    // StoreKit's unfinished sequence remains the durable recovery source after bounded eviction.
                    self.deferredSubscriptionUpdates[oldest] = nil
                }
                await self.drainSubscriptionUpdates()
            }
        }
    }

    private func drainSubscriptionUpdates() async {
        guard !isDrainingSubscriptionUpdates, !isBusy, sessionIsVerified,
              premium.status != nil, premium.pendingVerification == nil, let session else { return }
        isDrainingSubscriptionUpdates = true
        defer { isDrainingSubscriptionUpdates = false }
        while !deferredSubscriptionUpdates.isEmpty, !isBusy,
              isCurrentSubscriptionSession(session), premium.pendingVerification == nil {
            guard let id = deferredSubscriptionUpdates.keys.sorted().first,
                  let transaction = deferredSubscriptionUpdates.removeValue(forKey: id) else { break }
            await performAction {
                let acknowledged = await premium.receiveUpdate(
                    transaction,
                    session: session,
                    isCurrentSession: isCurrentSubscriptionSession
                )
                if acknowledged, isCurrentSubscriptionSession(session) {
                    await refreshSessionAndLists()
                }
            }
        }
    }

    func selectGroup(id: UUID) async {
        guard canSelectGroup, id != group?.id, groups.contains(where: { $0.id == id }), var current = session else {
            return
        }
        isPerformingAction = true
        // Invalidate an older read before suspending on Keychain. Its failure cannot revive or clear this selection.
        groupGeneration = UUID()
        groupLoadID = nil
        let originalToken = current.accessToken
        current.activeGroupID = id
        do {
            try await credentials.saveSession(current)
            guard session?.user.id == current.user.id, session?.accessToken == originalToken,
                  sessionIsVerified, groupsAreVerified else {
                isPerformingAction = false
                await drainSubscriptionUpdates()
                return
            }
            clearGroupPresentation()
            session = current
            notice = nil
        } catch {
            notice = SharedErrorMessage.message(for: error)
            storeItemsState = loadedStoreID == nil ? .notLoaded : .loaded
            isPerformingAction = false
            await drainSubscriptionUpdates()
            return
        }
        isPerformingAction = false
        await loadActiveGroup()
        await drainSubscriptionUpdates()
    }

    private var groupContext: GroupContext? {
        guard let session, let group else { return nil }
        return GroupContext(userID: session.user.id, groupID: group.id, generation: groupGeneration)
    }

    var storeItemsMessage: LocalizedStringResource? {
        switch storeItemsState {
        case .notLoaded:
            "Refresh to load this store."
        case .loading:
            nil
        case .loaded:
            items.isEmpty ? "No pending products in this store." : nil
        case .failed:
            items.isEmpty
                ? "Could not load this store. Refresh to try again."
                : "The list could not be refreshed. Products shown may be out of date. Refresh before continuing."
        }
    }

    func load() async {
        startSubscriptionUpdates()
        if let initialLoadTask {
            await initialLoadTask.value
            return
        }
        guard !hasLoaded, !isPerformingAction else { return }
        let task = Task {
            await performAction {
                defer {
                    hasLoaded = true
                }
                await restoreLocalState()
                guard !storageFailed else { return }
                guard isConfigured else {
                    notice = "The group connection is not configured yet. You can prepare your draft manually."
                    return
                }
                await refreshSessionAndLists()
            }
        }
        initialLoadTask = task
        await task.value
        initialLoadTask = nil
    }

    private func restoreLocalState() async {
        guard !hasRestoredLocalState, !hasLoaded else { return }
        if let localStateLoadTask {
            await localStateLoadTask.value
            return
        }
        let task = Task {
            await draft.load()
            do {
                pendingOperation = try await credentials.loadOperation()
                pendingInvitation = try await credentials.loadInvitation()
                session = try await credentials.loadSession()
            } catch {
                storageFailed = true
                notice = "Your saved access could not be restored. Unlock the device and reopen the app; your data is kept without overwriting it."
            }
            hasRestoredLocalState = true
        }
        localStateLoadTask = task
        await task.value
        localStateLoadTask = nil
    }

    /// Explicit shortcut input only changes the local draft, even while initial session verification is pending.
    @discardableResult
    func addDraftItemFromIntent(_ item: ShoppingDraftItem) async throws -> Bool {
        try Task.checkCancellation()
        guard !isProcessingShoppingIntent else { throw DraftIntentError.busy }
        await restoreLocalState()
        try Task.checkCancellation()
        guard !storageFailed else { throw DraftIntentError.storageUnavailable }
        guard !isProcessingShoppingIntent, pendingOperation == nil, !(hasLoaded && isBusy),
              storeQuery.activity == .idle,
              !isReviewPresented, !isReviewPresentationActive,
              !isItemEditorPresented, !isItemEditorPresentationActive else {
            throw DraftIntentError.busy
        }
        let added = try await draft.addItemFromIntent(item)
        draftIntentNavigationID = UUID()
        return added
    }

    /// Publishes only this saved input when its store has one exact match in the current group.
    func addShoppingItemFromIntent(_ item: ShoppingDraftItem) async throws -> ShoppingIntentOutcome {
        try Task.checkCancellation()
        guard !isProcessingShoppingIntent, !isPerformingAction || initialLoadTask != nil else {
            throw DraftIntentError.busy
        }
        isProcessingShoppingIntent = true
        do {
            let outcome = try await processShoppingItemFromIntent(item)
            isProcessingShoppingIntent = false
            await promoteIncomingInvitation()
            return outcome
        } catch {
            isProcessingShoppingIntent = false
            await promoteIncomingInvitation()
            throw error
        }
    }

    private func processShoppingItemFromIntent(_ item: ShoppingDraftItem) async throws -> ShoppingIntentOutcome {
        await restoreLocalState()
        try Task.checkCancellation()
        guard !storageFailed else { throw DraftIntentError.storageUnavailable }
        guard pendingOperation == nil, storeQuery.activity == .idle,
              !isReviewPresented, !isReviewPresentationActive,
              !isItemEditorPresented, !isItemEditorPresentationActive,
              !isInvitationsPresented, !isInvitationsPresentationActive else {
            throw DraftIntentError.busy
        }
        let isNewRequest = try await draft.addItemFromIntent(item)
        try Task.checkCancellation()
        guard isNewRequest else { return .alreadyProcessed }
        guard let savedItem = draft.items.first(where: { $0.id == item.id }) else {
            throw DraftIntentError.saveFailed
        }
        if hasLoaded {
            await refreshSessionAndLists()
        } else {
            await load()
        }
        try Task.checkCancellation()
        guard sessionIsVerified, groupsAreVerified, groups.count == 1, canUseShopping, !storageFailed,
              let api, let session, let group, let context = groupContext else {
            return keepShoppingIntentInDraft()
        }
        let fetchedStores: [SharedStore]
        do {
            fetchedStores = try await api.stores(groupID: group.id, token: session.accessToken)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            await handle(error)
            return keepShoppingIntentInDraft()
        }
        try Task.checkCancellation()
        guard groupContext == context, sessionIsVerified, groupsAreVerified, groups.count == 1, canUseShopping else {
            return keepShoppingIntentInDraft()
        }
        stores = fetchedStores
        let matches = fetchedStores.filter {
            $0.groupId == group.id && Self.storeNameKey($0.name) == Self.storeNameKey(savedItem.store)
        }
        guard matches.count == 1, let store = matches.first, store.capabilities?.canAddItems == true else {
            return keepShoppingIntentInDraft()
        }
        let preparedItem = try PreparedDraftItem(validating: savedItem)
        let entry = SharedNewItem(name: preparedItem.name, quantity: preparedItem.quantity, store: .existing(store.id))
        let operation = PendingSharedOperation.addItems(
            userID: session.user.id,
            groupID: group.id,
            request: AddItemsRequest(operationId: item.id, items: [entry]),
            sourceDraft: ShoppingDraftSnapshot(items: [savedItem])
        )
        try Task.checkCancellation()
        do {
            try await credentials.saveOperation(operation)
        } catch {
            notice = SharedErrorMessage.message(for: error)
            throw ShoppingIntentError.needsReview
        }
        pendingOperation = operation
        try Task.checkCancellation()
        guard await performPendingOperation() else { throw ShoppingIntentError.needsReview }
        draftIntentNavigationID = UUID()
        return .added(storeName: store.name)
    }

    private func keepShoppingIntentInDraft() -> ShoppingIntentOutcome {
        draftIntentNavigationID = UUID()
        return .savedToDraft
    }

    func acknowledgeDraftIntentNavigation(id: UUID) {
        guard draftIntentNavigationID == id else { return }
        draftIntentNavigationID = nil
    }

    func refresh() async {
        guard hasLoaded, !isBusy, !storageFailed else { return }
        await performAction {
            await refreshSessionAndLists()
        }
    }

    func prepareAppleLogin() async {
        guard !Task.isCancelled, shouldMaintainAppleLogin, let api else { return }
        guard !hasReadyAppleChallenge else { return }
        // A new visible task may supersede a cancelled request that has not returned yet.
        let preparationID = UUID()
        applePreparationID = preparationID
        resetAppleAttempt()
        defer {
            if applePreparationID == preparationID {
                applePreparationID = nil
            }
        }
        do {
            let result = try await api.createChallenge()
            try Task.checkCancellation()
            guard applePreparationID == preparationID, shouldMaintainAppleLogin else { return }
            guard result.expiresAt.timeIntervalSince(appleLoginDate()) > 30 else {
                throw SharedAPIError.invalidResponse
            }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw SharedAPIError.invalidResponse
            }
            appleState = Data(bytes).base64EncodedString()
            challenge = result
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                  applePreparationID == preparationID, shouldMaintainAppleLogin else { return }
            if case SharedAPIError.server(_, "rate_limited", _, _) = error {
                appleLoginPreparationError = SharedErrorMessage.message(for: error)
            } else {
                appleLoginPreparationError = "Could not start Sign in with Apple. Please try again."
            }
        }
    }

    func maintainAppleLogin() async {
        while !Task.isCancelled, shouldMaintainAppleLogin {
            await prepareAppleLogin()
            guard !Task.isCancelled, shouldMaintainAppleLogin, hasReadyAppleChallenge, let challenge else { return }
            let renewalDelay = challenge.expiresAt.timeIntervalSince(appleLoginDate()) - 30
            do {
                try await Task.sleep(for: .seconds(min(270, max(1, renewalDelay))))
            } catch {
                return
            }
        }
    }

    func retryAppleLoginPreparation() {
        appleLoginPreparationError = nil
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard canRequestAppleLogin, let challenge, let appleState else {
            request.state = UUID().uuidString
            notice = "This sign-in attempt has expired. Try signing in again."
            return
        }
        request.requestedScopes = [.fullName]
        request.nonce = challenge.nonce
        request.state = appleState
        isAuthorizingWithApple = true
        isPerformingAction = true
    }

    func receiveAppleAuthorization(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let codeData = credential.authorizationCode,
                  let token = String(data: tokenData, encoding: .utf8),
                  let code = String(data: codeData, encoding: .utf8) else {
                resetAppleAttempt()
                notice = "Apple did not return the required credentials. Start signing in again."
                Task {
                    await finishAction()
                }
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            let state = credential.state
            Task {
                await completeAppleLogin(
                    token: token,
                    code: code,
                    returnedState: state,
                    displayName: name
                )
            }
        case .failure:
            resetAppleAttempt()
            notice = "Sign in with Apple was not completed. Your draft and invitation are kept."
            Task {
                await finishAction()
            }
        }
    }

    func completeAppleLogin(
        token: String,
        code: String,
        returnedState: String?,
        displayName: String?
    ) async {
        guard let challenge, let appleState, returnedState == appleState, let api else {
            resetAppleAttempt()
            notice = "This sign-in attempt could not be verified. Start again."
            await finishAction()
            return
        }
        await performAction {
            defer { resetAppleAttempt() }
            do {
                let request = AppleLoginRequest(
                    challengeId: challenge.id,
                    identityToken: token,
                    authorizationCode: code,
                    displayName: displayName?.isEmpty == false ? displayName : nil
                )
                let result = try await api.loginWithApple(request)
                try await credentials.saveSession(result)
                session = result
                sessionIsVerified = true
                notice = nil
                await refreshSessionAndLists()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    func receiveInvitation(_ url: URL) async {
        guard let configuration else {
            notice = "The invitation cannot be opened until the group connection is configured."
            return
        }
        do {
            let invitation = try configuration.invitation(from: url)
            // Receiving a URL must remain durable even while startup, Apple or another request owns the UI.
            try await credentials.saveIncomingInvitation(invitation)
            await promoteIncomingInvitation()
        } catch let error as SharedAPIError {
            notice = SharedErrorMessage.message(for: error)
        } catch {
            notice = "This link could not be saved. Open it again after unlocking the device."
        }
    }

    func discardInvitation() async {
        guard !isBusy else { return }
        await performAction {
            do {
                try await credentials.saveInvitation(nil)
                pendingInvitation = nil
                invitationPreview = nil
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    func acceptInvitation() async {
        guard canAcceptInvitation, let api, let session, let invitation = pendingInvitation else { return }
        await performAction {
            do {
                let group = try await api.acceptInvitation(invitation, token: session.accessToken)
                guard await refreshSessionAndLists(preferredGroupID: group.id) else { return }
                try await credentials.saveInvitation(nil)
                pendingInvitation = nil
                invitationPreview = nil
            } catch {
                await handle(error)
            }
        }
    }

    func createGroup() async {
        guard canCreateGroup, let session else { return }
        guard groupName.unicodeScalars.count <= 80,
              let name = ShoppingDraftRules.normalized(groupName), !name.isEmpty,
              name.unicodeScalars.count <= 80,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            notice = "Enter a valid group name of up to 80 Unicode characters."
            return
        }
        await performAction {
            do {
                let operation = PendingSharedOperation.createGroup(
                    userID: session.user.id,
                    request: CreateGroupRequest(operationId: UUID(), name: name)
                )
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                await performPendingOperation(selectCreatedGroup: true)
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    /// The visible editable summary is the confirmation surface for this explicit Add action.
    func addDraftItems() async {
        guard canPerformShopping, group != nil else { return }
        draft.reviewDraft()
        guard draft.preparedItems != nil else { return }
        let snapshot = ShoppingDraftSnapshot(text: draft.text, items: draft.items)
        await prepareInlineSubmission(snapshot)
        if canConfirmReview {
            await confirmReviewedBatch()
        }
    }

    /// Only the manually entered row joins this operation; unrelated draft rows keep their own intent.
    func addManualItem() async {
        guard canPerformShopping, group != nil, let item = draft.saveEditor(closeEditor: false) else { return }
        await prepareInlineSubmission(ShoppingDraftSnapshot(items: [item]))
        if canConfirmReview {
            await confirmReviewedBatch()
        }
    }

    var draftConfirmationNotice: ShoppingNotice? {
        guard let proposal = draft.interpretationProposal, let session, let group, sessionIsVerified else { return nil }
        return ShoppingNotice(
            source: .draftConfirmation,
            message: SharedAdditionMessage.proposed(items: proposal.snapshot.items),
            draftConfirmation: .init(
                proposalID: proposal.id,
                userID: session.user.id,
                groupID: group.id,
                groupName: group.name
            )
        )
    }

    /// Confirmation consumes only the displayed interpretation, never unrelated draft rows.
    func confirmInterpretationProposal(_ snapshot: ShoppingNotice) async {
        guard canMutate, draftConfirmationNotice == snapshot, let reference = snapshot.draftConfirmation else { return }
        guard canUseShopping else {
            draft.editInterpretationProposal(id: reference.proposalID)
            notice = "Choose this as your free group or renew premium to use its shopping list. Your group and draft are kept."
            return
        }
        guard let source = draft.takeInterpretationProposal(id: reference.proposalID) else { return }
        await prepareInlineSubmission(source)
        guard session?.user.id == reference.userID, group?.id == reference.groupID else {
            draft.revealRecoveryControls()
            return
        }
        if canConfirmReview {
            await confirmReviewedBatch()
        } else if reviewSnapshot == source, hasStoreClarifications() {
            draft.revealRecoveryControls()
            isReviewPresented = true
        } else {
            draft.revealRecoveryControls()
        }
        if source.items.contains(where: { draft.items.contains($0) }) {
            draft.revealRecoveryControls()
        }
    }

    func editInterpretationProposal(_ snapshot: ShoppingNotice) {
        guard canMutate, draftConfirmationNotice == snapshot, let reference = snapshot.draftConfirmation else { return }
        draft.editInterpretationProposal(id: reference.proposalID)
    }

    private func prepareInlineSubmission(_ snapshot: ShoppingDraftSnapshot) async {
        guard canPerformShopping, let api, let session, let group else { return }
        // Clear stale preparation before a fetch so failure cannot submit a previous summary.
        let previousChoices = storeChoices
        reviewedItems = []
        reviewOwner = nil
        reviewSnapshot = nil
        storeChoices = []
        await performAction {
            do {
                let prepared = try ShoppingDraftRules.prepare(snapshot.items)
                let fetchedStores = try await api.stores(groupID: group.id, token: session.accessToken)
                guard self.session?.user.id == session.user.id, self.group?.id == group.id,
                      sessionIsVerified else { return }
                stores = fetchedStores
                reviewedItems = prepared
                reviewSnapshot = snapshot
                reviewOwner = ReviewOwner(userID: session.user.id, groupID: group.id)
                var seen = Set<String>()
                storeChoices = prepared.compactMap { item in
                    guard seen.insert(item.store).inserted else { return nil }
                    let key = Self.storeNameKey(item.store)
                    let matches = stores.filter { Self.storeNameKey($0.name) == key }
                    let selection: String
                    if matches.count == 1, let match = matches.first {
                        selection = match.id.uuidString
                    } else if matches.isEmpty {
                        selection = "new"
                    } else {
                        let previous = previousChoices.first { $0.id == item.store }?.selection
                        selection = matches.contains { $0.id.uuidString == previous } ? previous ?? "" : ""
                    }
                    return DraftStoreChoice(id: item.store, selection: selection, needsClarification: matches.count > 1)
                }
                notice = submissionCapacityMessage
            } catch {
                await handle(error)
            }
        }
    }

    func needsStoreClarification(_ choice: DraftStoreChoice, storeName: String? = nil) -> Bool {
        choice.needsClarification && (storeName == nil || choice.id == storeName.flatMap(ShoppingDraftRules.normalized))
    }

    func hasStoreClarifications(for storeName: String? = nil) -> Bool {
        storeChoices.contains { needsStoreClarification($0, storeName: storeName) }
    }

    func storeCandidates(for name: String) -> [SharedStore] {
        let key = Self.storeNameKey(name)
        return stores.filter { Self.storeNameKey($0.name) == key }
    }

    /// Match the backend's case-folded exact names, preserving accents and punctuation.
    private static func storeNameKey(_ name: String) -> String? {
        ShoppingDraftRules.normalized(name)?.folding(options: [.caseInsensitive], locale: Locale(identifier: "und"))
    }

    func prepareReview() async {
        guard canPerformShopping, group != nil, let api, let session, let group else { return }
        draft.reviewDraft()
        guard let prepared = draft.preparedItems else { return }
        await performAction {
            do {
                stores = try await api.stores(groupID: group.id, token: session.accessToken)
                reviewedItems = prepared
                reviewSnapshot = ShoppingDraftSnapshot(text: draft.text, items: draft.items)
                reviewOwner = ReviewOwner(userID: session.user.id, groupID: group.id)
                var seen = Set<String>()
                storeChoices = prepared.compactMap { item in
                    seen.insert(item.store).inserted ? DraftStoreChoice(id: item.store) : nil
                }
                isReviewPresented = true
            } catch {
                await handle(error)
            }
        }
    }

    func confirmReviewedBatch() async {
        guard canConfirmReview, let session, let group, let reviewSnapshot else { return }
        await performAction {
            do {
                let entries = try reviewedItems.map { item -> SharedNewItem in
                    guard let choice = storeChoices.first(where: { $0.id == item.store }) else {
                        throw SharedAPIError.invalidResponse
                    }
                    let reference: SharedStoreReference
                    if choice.selection == "new" {
                        reference = .newName(item.store)
                    } else if let id = UUID(uuidString: choice.selection), stores.contains(where: { $0.id == id }) {
                        reference = .existing(id)
                    } else {
                        throw SharedAPIError.invalidResponse
                    }
                    return SharedNewItem(name: item.name, quantity: item.quantity, store: reference)
                }
                let operation = PendingSharedOperation.addItems(
                    userID: session.user.id,
                    groupID: group.id,
                    request: AddItemsRequest(operationId: UUID(), items: entries),
                    sourceDraft: reviewSnapshot
                )
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                isReviewPresented = false
                draft.cancelEditor()
                await performPendingOperation()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    func retryPendingOperation() async {
        guard canRetryOperation else { return }
        if let retryNotBefore, Date() < retryNotBefore {
            notice = "The service has asked you to wait before retrying. The original submission is kept."
            return
        }
        await performAction {
            await performPendingOperation()
        }
    }

    @discardableResult
    private func performPendingOperation(selectCreatedGroup: Bool = false) async -> Bool {
        guard let api, let session, let operation = pendingOperation, operation.userID == session.user.id else {
            return false
        }
        let submissionStores = stores
        var additionNotice: LocalizedStringResource?
        var additionDestination: ShoppingNotice.StoreDestination?
        do {
            switch operation {
            case .proposeTransfer, .resolveTransfer, .leaveGroup:
                return await performPendingGroupOperation(operation)
            case .selectFreeGroup(_, let request):
                _ = try await api.selectFreeGroup(request, token: session.accessToken)
            case .changeStoreState:
                return await performPendingStoreOperation(operation)
            case .changeItem(_, let original, let request):
                _ = try await api.changeItem(request, item: original, token: session.accessToken)
            case .purchase(_, let groupID, let request, _):
                let result = try await api.finalizePurchase(request, groupID: groupID, token: session.accessToken)
                guard result.items.allSatisfy({ $0.purchasedBy == session.user.id }) else {
                    throw SharedAPIError.invalidResponse
                }
            case .createGroup(_, let request):
                let group = try await api.createGroup(request, token: session.accessToken)
                guard await refreshSessionAndLists(preferredGroupID: selectCreatedGroup ? group.id : nil) else {
                    return false
                }
            case .addItems(_, let groupID, let request, let sourceDraft):
                let addedItems = try await api.addItems(request, groupID: groupID, token: session.accessToken)
                let storeIDs = Set(addedItems.map(\.storeId))
                if storeIDs.count == 1, let storeID = storeIDs.first {
                    additionDestination = ShoppingNotice.StoreDestination(
                        operationID: request.operationId,
                        userID: session.user.id,
                        groupID: groupID,
                        storeID: storeID
                    )
                }
                additionNotice = SharedAdditionMessage.confirmed(
                    request: request, sourceDraft: sourceDraft, stores: submissionStores
                )
                guard await draft.consumeConfirmedItems(sourceDraft.items) else {
                    notice = "The server confirmed the batch, but the result still needs to be saved on this device. Retry to complete the same submission."
                    return false
                }
            }
            try await credentials.saveOperation(nil)
            if case .purchase(_, _, let request, _) = operation {
                purchaseSelections[request.storeId] = nil
                let purchasedIDs = Set(request.items.map(\.id))
                items.removeAll { purchasedIDs.contains($0.id) }
                loadedStoreID = nil
            }
            if case .changeItem(_, let original, _) = operation {
                items.removeAll { $0.id == original.id }
                loadedStoreID = nil
                editingItem = nil
                isItemEditorPresented = false
            }
            pendingOperation = nil
            reviewSnapshot = nil
            reviewedItems = []
            storeChoices = []
            retryNotBefore = nil
            let refreshed = await refreshSessionAndLists()
            if case .purchase = operation {
                if refreshed {
                    notice = nil
                } else {
                    notice = "The purchase is confirmed, but the list could not be refreshed. Refresh before continuing."
                }
            } else if case .changeItem = operation {
                if !refreshed {
                    notice = "The product change is confirmed, but the list could not be refreshed. Refresh before continuing."
                }
            } else if let additionNotice {
                notice = additionNotice
                if refreshed, let destination = additionDestination,
                   destination.userID == self.session?.user.id, destination.groupID == group?.id,
                   stores.contains(where: { $0.id == destination.storeID && $0.groupId == destination.groupID }) {
                    noticeStoreDestination = destination
                }
            } else {
                notice = "The operation is confirmed in the group."
            }
            return true
        } catch let error as SharedAPIError {
            if case .server(let status, let code, _, let retryAfter) = error {
                if let retryAfter {
                    retryNotBefore = Date().addingTimeInterval(Double(max(0, retryAfter)))
                }
                // Authentication failure keeps the exact envelope for the original account.
                if [400, 403, 404, 409, 410, 413].contains(status), !error.isUncertain {
                    do {
                        try await credentials.saveOperation(nil)
                        pendingOperation = nil
                        if case .addItems = operation,
                           ["store_limit_reached", "pending_item_limit_reached", "store_archived",
                            "group_access_restricted"].contains(code) {
                            await refreshSessionAndLists()
                            draft.revealRecoveryControls()
                        }
                        if case .selectFreeGroup = operation {
                            await refreshSessionAndLists()
                        }
                        if case .purchase = operation {
                            let previousSelection = purchaseSelection
                            let refreshed = await refreshSessionAndLists()
                            if code == "item_conflict", refreshed, previousSelection != purchaseSelection, notice != nil {
                                return false
                            }
                        }
                        if case .changeItem(_, let original, let request) = operation {
                            if request.replacement != nil {
                                restoreItemEditor(original: original, request: request)
                                editNeedsReview = ![
                                    "store_limit_reached", "pending_item_limit_reached", "store_archived"
                                ].contains(code)
                            }
                            let refreshed = await refreshSessionAndLists()
                            if code == "item_conflict", request.replacement != nil, refreshed,
                               storeItemsState == .loaded, loadedStoreID == original.storeId, latestEditingItem == nil {
                                editingItem = nil
                                editNeedsReview = false
                                isItemEditorPresented = false
                                notice = "This product is no longer pending in this store. Your changes were not saved."
                                return false
                            }
                        }
                    } catch {
                        notice = SharedErrorMessage.message(for: error)
                        return false
                    }
                }
            }
            await handle(error)
        } catch {
            // Cancellation and local storage failures cannot establish whether the server committed.
            notice = SharedErrorMessage.message(for: error)
        }
        return false
    }

    var submissionCapacityMessage: LocalizedStringResource? {
        for choice in storeChoices where !choice.selection.isEmpty {
            let existing: SharedStore?
            if let id = UUID(uuidString: choice.selection) {
                existing = stores.first { $0.id == id }
            } else {
                let matches = storeCandidates(for: choice.id)
                existing = matches.count == 1 ? matches.first : nil
            }
            if let existing {
                guard let capabilities = existing.capabilities else {
                    return "Refresh to verify store availability before adding products."
                }
                if !capabilities.canAddItems {
                    return "This store has reached its pending product limit. Buying or cancelling products frees capacity."
                }
            } else if choice.selection == "new" {
                guard let groupCapacity else { return "Refresh to verify store availability before adding products." }
                if !groupCapacity.canCreateStore {
                    return "This group has reached its active store limit. Archive an empty store before adding another."
                }
            }
        }
        return nil
    }

    func canChangeStoreState(_ store: SharedStore, action: SharedStoreAction) -> Bool {
        guard canMutate, storeManagementState == .loaded, store.groupId == group?.id else { return false }
        switch action {
        case .archive:
            return stores.contains(store) && store.capabilities?.canArchive == true
        case .restore:
            return canUseShopping && archivedStores.contains(store) && store.capabilities?.canRestore == true
        }
    }

    func storeActionMessage(_ store: SharedStore, action: SharedStoreAction) -> LocalizedStringResource? {
        guard storeManagementState == .loaded, store.state != nil, groupCapacity != nil else {
            return "Refresh to verify store availability before making changes."
        }
        if !isAdministrator {
            return "Only the current group administrator can archive or restore stores."
        }
        if action == .archive, store.pendingItemCount != 0 {
            return "Buy or cancel the pending products before archiving this store."
        }
        if action == .restore, hasRestrictedGroup {
            return "Choose this as your free group or renew premium to use its shopping list. Your group and draft are kept."
        }
        if action == .restore, groupCapacity?.canCreateStore != true {
            return "Archive an empty active store to make room before restoring this one."
        }
        let allowed = action == .archive ? store.capabilities?.canArchive : store.capabilities?.canRestore
        if allowed != true {
            return "Refresh to verify store availability before making changes."
        }
        return nil
    }

    var storeManagementMessage: LocalizedStringResource? {
        switch storeManagementState {
        case .notLoaded: "Refresh to load stores and capacity."
        case .loading, .loaded: nil
        case .failed: "Store availability could not be verified. Refresh before making changes."
        }
    }

    func loadStoreManagement() async {
        guard hasLoaded, !isBusy, session != nil else { return }
        let context = groupContext
        isPerformingAction = true
        let refreshed = await refreshSessionAndLists()
        isPerformingAction = false
        guard refreshed else {
            if groupContext == context, sessionIsVerified {
                storeManagementState = .failed
            }
            await drainSubscriptionUpdates()
            return
        }
        await refreshStoreManagement()
        await drainSubscriptionUpdates()
    }

    @discardableResult
    private func refreshStoreManagement() async -> Bool {
        guard let api, let session, let group, let context = groupContext else { return true }
        let loadID = UUID()
        groupLoadID = loadID
        storeManagementState = .loading
        defer {
            if groupLoadID == loadID {
                groupLoadID = nil
            }
        }
        do {
            let capacity = try await api.groupCapacity(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return false }
            let active = try await api.stores(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return false }
            let archived = try await api.archivedStores(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return false }
            guard capacity.activeStoreCount == active.count,
                  active.allSatisfy({ $0.groupId == group.id && $0.state != nil && $0.archivedAt == nil }),
                  archived.allSatisfy({ $0.groupId == group.id && $0.state != nil && $0.archivedAt != nil }),
                  Set(active.map(\.id)).isDisjoint(with: archived.map(\.id)),
                  group.administratorUserId == nil || capacity.capacityOwnerUserId == group.administratorUserId else {
                groupCapacity = nil
                storeManagementState = .failed
                notice = "Store availability changed while loading or could not be verified. Refresh to check it again."
                return false
            }
            groupCapacity = capacity
            stores = active
            archivedStores = archived
            if let selectedStoreID, !active.contains(where: { $0.id == selectedStoreID }) {
                self.selectedStoreID = nil
            }
            storeManagementState = .loaded
            return true
        } catch {
            guard groupContext == context else { return false }
            groupCapacity = nil
            storeManagementState = .failed
            await handle(error)
            return false
        }
    }

    func changeStoreState(_ store: SharedStore, action: SharedStoreAction) async {
        guard canChangeStoreState(store, action: action), let session, let group else { return }
        await performAction {
            do {
                let operation = PendingSharedOperation.changeStoreState(
                    userID: session.user.id,
                    groupID: group.id,
                    storeID: store.id,
                    action: action,
                    request: ChangeStoreStateRequest(operationId: UUID())
                )
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                await performPendingOperation()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    @discardableResult
    private func performPendingStoreOperation(_ operation: PendingSharedOperation) async -> Bool {
        guard let api, let session,
              case .changeStoreState(let userID, let groupID, let storeID, let action, let request) = operation,
              userID == session.user.id else {
            return false
        }
        var confirmed = false
        do {
            _ = try await api.changeStoreState(
                request,
                groupID: groupID,
                storeID: storeID,
                action: action,
                token: session.accessToken
            )
            confirmed = true
            // A receipt is historical. Keep recovery until current membership and store state can be read again.
            guard await refreshSessionAndLists(), await refreshStoreManagement() else {
                if sessionIsVerified {
                    notice = "The store action is confirmed, but current availability could not be refreshed. Retry the saved request."
                }
                return false
            }
            try await credentials.saveOperation(nil)
            pendingOperation = nil
            retryNotBefore = nil
            notice = "The store action is confirmed. Current stores and capacity have been refreshed."
            return true
        } catch let error as SharedAPIError {
            storeManagementState = .failed
            if !confirmed, case .server(let status, _, _, let retryAfter) = error {
                if let retryAfter {
                    retryNotBefore = Date().addingTimeInterval(Double(max(0, retryAfter)))
                }
                if [400, 403, 404, 409, 410, 413].contains(status), !error.isUncertain {
                    do {
                        try await credentials.saveOperation(nil)
                        pendingOperation = nil
                        await refreshStoreManagement()
                    } catch {
                        notice = SharedErrorMessage.message(for: error)
                        return false
                    }
                }
            }
            await handle(error)
        } catch {
            storeManagementState = .failed
            notice = SharedErrorMessage.message(for: error)
        }
        return false
    }

    var canQueryStore: Bool {
        hasLoaded && sessionIsVerified && groupsAreVerified && !isBusy && group != nil && !stores.isEmpty
    }

    func openStoreQuery() {
        guard canQueryStore, storeQuery.activity == .idle else { return }
        storeQueryRevision = UUID()
        storeQuery.prepare(stores: stores)
        isStoreQueryVisible = true
    }

    @discardableResult
    func startStoreDictation() -> Task<Void, Never> {
        guard canQueryStore, storeQuery.activity == .idle else { return Task {} }
        openStoreQuery()
        return storeQuery.startDictation()
    }

    func finishStoreDictation() async {
        guard isStoreQueryVisible, storeQuery.activity == .recording, let revision = storeQueryRevision else { return }
        await storeQuery.finishDictation().value
        guard storeQueryRevision == revision else { return }
        await openUniqueStoreMatch()
    }

    func searchStoreQuery() async {
        guard isStoreQueryVisible, storeQuery.canSearch else { return }
        storeQuery.search()
        await openUniqueStoreMatch()
    }

    private func openUniqueStoreMatch() async {
        guard storeQuery.matches.count == 1, let store = storeQuery.matches.first else { return }
        await chooseQueriedStore(store)
    }

    func closeStoreQuery() {
        interruptStoreDictation()
        isStoreQueryVisible = false
    }

    @discardableResult
    func interruptStoreDictation() -> Task<Void, Never> {
        storeQueryRevision = nil
        return storeQuery.stopDictation()
    }

    func chooseQueriedStore(_ store: SharedStore) async {
        guard isStoreQueryVisible, canQueryStore, storeQuery.activity == .idle,
              storeQuery.matches.contains(where: { $0.id == store.id }),
              stores.contains(store), store.groupId == group?.id else { return }
        selectedStoreID = store.id
        closeStoreQuery()
        await loadSelectedStore()
    }

    func loadSelectedStore() async {
        await refreshSelectedStore()
        await drainSubscriptionUpdates()
    }

    private func refreshSelectedStore() async {
        guard !isBusy, sessionIsVerified, groupsAreVerified, let api, let session,
              let group, let storeID = selectedStoreID, let context = groupContext else { return }
        let loadID = UUID()
        groupLoadID = loadID
        defer {
            if groupLoadID == loadID {
                groupLoadID = nil
            }
        }
        items = []
        loadedStoreID = nil
        storeItemsState = .loading
        do {
            let loaded = try await api.pendingItems(groupID: group.id, storeID: storeID, token: session.accessToken)
            guard groupContext == context, selectedStoreID == storeID else { return }
            items = loaded
            loadedStoreID = storeID
            storeItemsState = .loaded
            notice = nil
            reconcilePurchaseSelection()
        } catch {
            guard groupContext == context, selectedStoreID == storeID else { return }
            storeItemsState = .failed
            await handle(error)
        }
    }

    func openInvitations() async {
        guard canMutate, canManageInvitations, let api, let session, let group else { return }
        await performAction {
            do {
                invitations = try await api.invitations(groupID: group.id, token: session.accessToken)
                isInvitationsPresented = true
            } catch {
                await handle(error)
            }
        }
    }

    func createInvitation() async {
        guard canPerformShopping, canManageInvitations, let api, let session, let group else { return }
        await performAction {
            shareURL = nil
            do {
                let result = try await api.createInvitation(groupID: group.id, token: session.accessToken)
                shareURL = result.url
                invitations = try await api.invitations(groupID: group.id, token: session.accessToken)
            } catch {
                await handle(error)
            }
        }
    }

    func revokeInvitation(_ invitation: SharedInvitation) async {
        guard canMutate, canManageInvitations, let api, let session, let group else { return }
        await performAction {
            do {
                try await api.revokeInvitation(
                    groupID: group.id,
                    invitationID: invitation.id,
                    token: session.accessToken
                )
                shareURL = nil
                invitations = try await api.invitations(groupID: group.id, token: session.accessToken)
            } catch {
                await handle(error)
            }
        }
    }

    func logout() async {
        guard !isBusy, let api, let session else { return }
        await performAction {
            do {
                try await api.logout(token: session.accessToken)
                try await credentials.saveSession(nil)
                clearSessionPresentation()
            } catch {
                notice = "Sign-out could not be confirmed. Your access is kept so you can retry."
            }
        }
    }

    var presentedNotice: ShoppingNotice? {
        notice.map { ShoppingNotice(source: .group, message: $0, storeDestination: noticeStoreDestination) }
    }

    var canPresentRootNotice: Bool {
        !isProcessingShoppingIntent && !isReviewPresentationActive && !isInvitationsPresentationActive
            && !isItemEditorPresentationActive && !draft.isEditorPresentationActive && storeQuery.activity == .idle
            && (noticeStoreDestination == nil || !isBusy)
    }

    func reviewPresentationDidDismiss() {
        isReviewPresentationActive = false
    }

    func invitationsPresentationDidDismiss() {
        isInvitationsPresentationActive = false
    }

    func dismissPresentedNotice(_ snapshot: ShoppingNotice) {
        guard presentedNotice == snapshot else { return }
        notice = nil
    }

    func openNoticeStore(_ snapshot: ShoppingNotice) -> Bool {
        guard canMutate, presentedNotice == snapshot, let destination = snapshot.storeDestination,
              destination.userID == session?.user.id, destination.groupID == group?.id,
              stores.contains(where: { $0.id == destination.storeID && $0.groupId == destination.groupID }) else {
            return false
        }
        closeStoreQuery()
        selectedStoreID = destination.storeID
        return true
    }

    func dismissNotice() {
        notice = nil
    }

    @discardableResult
    private func refreshSessionAndLists(preferredGroupID: UUID? = nil) async -> Bool {
        guard let api, var current = session else { return false }
        let accountID = current.user.id
        let accessToken = current.accessToken
        let generation = groupGeneration
        let previousGroupID = group?.id
        let requestedStoreID = selectedStoreID
        groupsAreVerified = false
        administration = nil
        groupCapacity = nil
        storeManagementState = .notLoaded
        loadedStoreID = nil
        storeItemsState = requestedStoreID == nil ? .notLoaded : .loading
        do {
            current.user = try await api.currentUser(token: current.accessToken)
            guard current.user.id == accountID, session?.user.id == accountID,
                  session?.accessToken == accessToken else {
                throw SharedAPIError.invalidResponse
            }
            let memberships = try await api.groups(token: current.accessToken)
            guard session?.user.id == accountID, session?.accessToken == accessToken else { return false }
            guard let capabilities = current.user.accountCapabilities,
                  capabilities.membershipCount == memberships.count else {
                throw SharedAPIError.invalidResponse
            }
            if let preferredGroupID, memberships.contains(where: { $0.id == preferredGroupID }) {
                current.activeGroupID = preferredGroupID
            } else if current.activeGroupID == nil, memberships.count == 1 {
                current.activeGroupID = memberships.first?.id
            }
            try await credentials.saveSession(current)
            guard session?.user.id == accountID, session?.accessToken == accessToken else { return false }
            let nextGroupID = memberships.first { $0.id == current.activeGroupID }?.id
            if nextGroupID != previousGroupID {
                clearGroupPresentation()
            }
            session = current
            groups = memberships
            sessionIsVerified = true
            groupsAreVerified = true
            restorePurchaseSelection()
            notice = nil
            let loaded = await loadActiveGroup()
            await previewPendingInvitation()
            return loaded
        } catch {
            guard session?.user.id == accountID, session?.accessToken == accessToken,
                  groupGeneration == generation else { return false }
            if selectedStoreID == requestedStoreID {
                storeItemsState = selectedStoreID == nil ? .notLoaded : .failed
            } else if (error as? SharedAPIError)?.isSessionInvalid != true {
                return false
            }
            await handle(error)
            return false
        }
    }

    @discardableResult
    private func loadActiveGroup() async -> Bool {
        guard let api, let session, let group, let context = groupContext else { return true }
        let loadID = UUID()
        groupLoadID = loadID
        defer {
            if groupLoadID == loadID {
                groupLoadID = nil
            }
        }
        administration = nil
        loadedStoreID = nil
        storeItemsState = selectedStoreID == nil ? .notLoaded : .loading
        do {
            if group.administratorUserId != nil {
                let latest = try await api.groupAdministration(groupID: group.id, token: session.accessToken)
                guard groupContext == context else { return false }
                updateMembership(latest.group)
                administration = latest
                if !latest.capabilities.canManageInvitations {
                    invitations = []
                    shareURL = nil
                    isInvitationsPresented = false
                }
            }
            let capacity = try await api.groupCapacity(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return false }
            guard group.administratorUserId == nil
                || capacity.capacityOwnerUserId == self.group?.administratorUserId else {
                throw SharedAPIError.invalidResponse
            }
            groupCapacity = capacity
            let fetchedStores = try await api.stores(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return false }
            stores = fetchedStores
            if let selectedStoreID, !stores.contains(where: { $0.id == selectedStoreID }) {
                self.selectedStoreID = nil
            }
            if let storeID = selectedStoreID {
                let loaded = try await api.pendingItems(groupID: group.id, storeID: storeID, token: session.accessToken)
                guard groupContext == context, selectedStoreID == storeID else { return false }
                items = loaded
                loadedStoreID = storeID
                storeItemsState = .loaded
            }
            reconcilePurchaseSelection()
            return true
        } catch {
            guard groupContext == context else { return false }
            storeItemsState = selectedStoreID == nil ? .notLoaded : .failed
            await handle(error)
            return false
        }
    }

    private func previewPendingInvitation() async {
        guard sessionIsVerified, let api, let session, let invitation = pendingInvitation else { return }
        do {
            invitationPreview = try await api.previewInvitation(invitation, token: session.accessToken)
        } catch let error as SharedAPIError {
            if case .server(let status, _, _, _) = error, status == 404 || status == 410, !error.isUncertain {
                do {
                    try await credentials.saveInvitation(nil)
                    pendingInvitation = nil
                    invitationPreview = nil
                } catch {
                    notice = SharedErrorMessage.message(for: error)
                    return
                }
            }
            await handle(error)
        } catch {
            notice = SharedErrorMessage.message(for: error)
        }
    }

    private func updateMembership(_ updated: SharedGroup) {
        guard let index = groups.firstIndex(where: { $0.id == updated.id }) else { return }
        groups[index] = updated
    }

    private func handle(_ error: any Error) async {
        if let apiError = error as? SharedAPIError, apiError.isSessionInvalid {
            sessionIsVerified = false
            do {
                try await credentials.saveSession(nil)
                clearSessionPresentation()
            } catch {
                storageFailed = true
            }
        }
        notice = SharedErrorMessage.message(for: error)
    }

    /// Finishing a foreground action awaits its bounded inbox work; no background drain can swallow the next action.
    private func performAction(_ action: @MainActor () async -> Void) async {
        isPerformingAction = true
        await action()
        await finishAction()
    }

    private func finishAction() async {
        isPerformingAction = false
        await promoteIncomingInvitation()
        await drainSubscriptionUpdates()
    }

    private func promoteIncomingInvitation() async {
        guard hasLoaded, !isBusy, !storageFailed else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            // Each iteration consumes one received value. An unresolved active invitation stops promotion.
            while let incoming = try await credentials.loadIncomingInvitation() {
                if let pendingInvitation, pendingInvitation != incoming {
                    notice = "Another invitation is saved. Resolve or discard it before reviewing the new link."
                    return
                }
                if pendingInvitation == nil {
                    try await credentials.saveInvitation(incoming)
                    pendingInvitation = incoming
                    invitationPreview = nil
                }
                // A second URL may arrive while the active value is saved; never delete that newer inbox value.
                _ = try await credentials.clearIncomingInvitation(matching: incoming)
                await previewPendingInvitation()
            }
        } catch {
            notice = "The saved invitation could not be prepared. Unlock the device and try again."
        }
    }

    private func resetAppleAttempt() {
        challenge = nil
        appleState = nil
        isAuthorizingWithApple = false
    }

    private func clearSessionPresentation() {
        clearGroupPresentation()
        groups = []
        groupsAreVerified = false
        session = nil
        premium.clearPresentation()
        sessionIsVerified = false
    }

    private func clearGroupPresentation() {
        groupGeneration = UUID()
        groupLoadID = nil
        draft.cancelInterpretation()
        notice = nil
        reviewedItems = []
        reviewSnapshot = nil
        reviewOwner = nil
        storeChoices = []
        noticeStoreDestination = nil
        closeStoreQuery()
        storeQuery.clear()
        editingItem = nil
        isItemEditorPresented = false
        purchaseSelections = [:]
        purchaseSelectionOwner = nil
        loadedStoreID = nil
        stores = []
        archivedStores = []
        groupCapacity = nil
        storeManagementState = .notLoaded
        items = []
        invitations = []
        invitationPreview = nil
        shareURL = nil
        selectedStoreID = nil
        storeItemsState = .notLoaded
        administration = nil
        groupMembers = []
        groupManagementState = .notLoaded
        selectedSuccessorID = nil
        isInvitationsPresented = false
    }

    func loadGroupManagement() async {
        await refreshGroupManagement()
        await drainSubscriptionUpdates()
    }

    private func refreshGroupManagement() async {
        guard hasLoaded, !isBusy, sessionIsVerified, groupsAreVerified,
              let api, let session, let group, let context = groupContext else { return }
        let loadID = UUID()
        groupLoadID = loadID
        groupManagementState = .loading
        defer {
            if groupLoadID == loadID {
                groupLoadID = nil
            }
        }
        do {
            let latest = try await api.groupAdministration(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return }
            let members = try await api.groupMembers(groupID: group.id, token: session.accessToken)
            guard groupContext == context else { return }
            updateMembership(latest.group)
            administration = latest
            groupMembers = members
            if !members.contains(where: { $0.id == selectedSuccessorID && $0.id != session.user.id }) {
                selectedSuccessorID = nil
            }
            groupManagementState = .loaded
        } catch {
            guard groupContext == context else { return }
            administration = nil
            groupMembers = []
            groupManagementState = .failed
            await handle(error)
        }
    }

    var canProposeGroupTransfer: Bool {
        canMutate && groupManagementState == .loaded && administration?.capabilities.canProposeTransfer == true
            && groupMembers.contains { $0.id == selectedSuccessorID && $0.id != session?.user.id }
    }

    func memberNeedsIdentifier(_ member: SharedGroupMember) -> Bool {
        guard let name = member.visibleName else { return true }
        return member.id == session?.user.id || groupMembers.contains {
            $0.id != member.id && $0.visibleName?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                == name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        }
    }

    var groupSuccessorCandidates: [SharedGroupMember] {
        groupMembers.filter { $0.id != session?.user.id }
    }

    func groupMember(id: UUID) -> SharedGroupMember? { groupMembers.first { $0.id == id } }

    func proposeGroupTransfer() async {
        guard canProposeGroupTransfer, let session, let group, let selectedSuccessorID else { return }
        await submitGroupOperation(.proposeTransfer(
            userID: session.user.id,
            groupID: group.id,
            request: ProposeGroupTransferRequest(operationId: UUID(), recipientUserId: selectedSuccessorID)
        ))
    }

    func resolveGroupTransfer(_ action: SharedGroupTransferAction) async {
        guard canMutate, let session, let group, let administration,
              let transfer = administration.pendingTransfer else { return }
        let allowed = switch action {
        case .accept: administration.capabilities.canAcceptTransfer
        case .reject: administration.capabilities.canRejectTransfer
        case .withdraw: administration.capabilities.canWithdrawTransfer
        }
        guard allowed else { return }
        await submitGroupOperation(.resolveTransfer(
            userID: session.user.id,
            groupID: group.id,
            transferID: transfer.id,
            action: action,
            request: ResolveGroupTransferRequest(operationId: UUID())
        ))
    }

    func leaveGroup(confirmClosure: Bool) async {
        guard canMutate, let session, let group, let administration, administration.capabilities.canLeave,
              !administration.capabilities.requiresClosureConfirmation || confirmClosure else { return }
        await submitGroupOperation(.leaveGroup(
            userID: session.user.id,
            groupID: group.id,
            request: LeaveGroupRequest(operationId: UUID(), confirmClosure: confirmClosure)
        ))
    }

    private func submitGroupOperation(_ operation: PendingSharedOperation) async {
        await performAction {
            do {
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                await performPendingGroupOperation(operation)
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    @discardableResult
    private func performPendingGroupOperation(_ operation: PendingSharedOperation) async -> Bool {
        guard let api, let session, operation.userID == session.user.id else { return false }
        var confirmed = false
        do {
            switch operation {
            case .proposeTransfer(_, let groupID, let request):
                let result = try await api.proposeTransfer(request, groupID: groupID, token: session.accessToken)
                guard result.transfer.proposerUserId == session.user.id else { throw SharedAPIError.invalidResponse }
            case .resolveTransfer(_, let groupID, let transferID, let action, let request):
                let result = try await api.resolveTransfer(
                    request,
                    groupID: groupID,
                    transferID: transferID,
                    action: action,
                    token: session.accessToken
                )
                let actorID = action == .withdraw ? result.transfer.proposerUserId : result.transfer.recipientUserId
                guard actorID == session.user.id else { throw SharedAPIError.invalidResponse }
            case .leaveGroup(_, let groupID, let request):
                let result = try await api.leaveGroup(request, groupID: groupID, token: session.accessToken)
                guard result.userId == session.user.id else { throw SharedAPIError.invalidResponse }
            default:
                return false
            }
            confirmed = true
            // Receipts describe the original commit. Reconcile current memberships before resolving recovery.
            guard await refreshSessionAndLists() else { return false }
            groupMembers = []
            groupManagementState = .notLoaded
            selectedSuccessorID = nil
            try await credentials.saveOperation(nil)
            pendingOperation = nil
            retryNotBefore = nil
            if case .leaveGroup = operation {
                notice = "Your departure is confirmed. Your current group access has been refreshed."
            } else {
                notice = "The transfer action is confirmed. Refresh group management to see its current state."
            }
            return true
        } catch let error as SharedAPIError {
            administration = nil
            groupManagementState = .failed
            if !confirmed, case .server(let status, _, _, let retryAfter) = error {
                if let retryAfter {
                    retryNotBefore = Date().addingTimeInterval(Double(max(0, retryAfter)))
                }
                if [400, 403, 404, 409, 410, 413].contains(status), !error.isUncertain {
                    do {
                        try await credentials.saveOperation(nil)
                        pendingOperation = nil
                    } catch {
                        notice = SharedErrorMessage.message(for: error)
                        return false
                    }
                }
            }
            await handle(error)
            if confirmed, !error.isSessionInvalid {
                notice = "The action is confirmed, but your current access could not be refreshed. Retry the saved request."
            }
        } catch {
            administration = nil
            groupManagementState = .failed
            notice = "The result still needs to be saved on this device. Retry the original request."
        }
        return false
    }
}

#if DEBUG
extension SharedShoppingViewModel {
    func seedStoreClarificationPreview() {
        guard let store = stores.first else { return }
        let second = SharedStore(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 34)),
            groupId: store.groupId,
            name: store.name.uppercased(),
            state: store.state
        )
        stores = [store, second]
        storeChoices = [DraftStoreChoice(id: store.name, needsClarification: true)]
    }

    /// Preview context caches values; every rendered preview owns a separately seeded model and dependencies.
    convenience init(
        preview: SharedPreviewPresentation,
        api: (any SharedShoppingAPI)?,
        configuration: SharedAPIConfiguration?,
        credentials: any SharedCredentialStoring,
        draft: ShoppingDraftViewModel,
        storeQuery: StoreQueryViewModel,
        subscriptionStore: (any SharedSubscriptionStore)? = nil
    ) {
        self.init(
            api: api,
            configuration: configuration,
            credentials: credentials,
            draft: draft,
            storeQuery: storeQuery,
            subscriptionStore: subscriptionStore
        )
        premium.applyPreview(preview)
        session = preview.session
        groups = preview.groups
        groupsAreVerified = preview.groupsAreVerified
        pendingInvitation = preview.pendingInvitation
        invitationPreview = preview.invitationPreview
        pendingOperation = preview.pendingOperation
        administration = preview.administration
        groupMembers = preview.groupMembers
        groupManagementState = preview.groupManagementState
        selectedSuccessorID = preview.selectedSuccessorID
        stores = preview.stores
        archivedStores = preview.archivedStores
        groupCapacity = preview.groupCapacity
        storeManagementState = preview.storeManagementState
        selectedStoreID = preview.selectedStoreID
        items = preview.items
        invitations = preview.invitations
        shareURL = preview.shareURL
        hasLoaded = true
        isPerformingAction = false
        sessionIsVerified = preview.sessionIsVerified
        notice = preview.notice
        reviewedItems = preview.reviewedItems
        storeChoices = preview.storeChoices
        loadedStoreID = preview.selectedStoreID
        storeItemsState = preview.selectedStoreID == nil ? .notLoaded : .loaded
        purchaseSelectionOwner = preview.session?.user.id
        if let storeID = preview.selectedStoreID {
            purchaseSelections[storeID] = preview.purchaseSelection
        }
        isReviewPresented = preview.isReviewPresented
        isInvitationsPresented = preview.isInvitationsPresented
        reviewSnapshot = preview.reviewSnapshot
    }
}
#endif

extension SharedShoppingViewModel {
    var purchaseSelection: [SharedItem] {
        guard let selectedStoreID, purchaseSelectionOwner == session?.user.id else { return [] }
        return purchaseSelections[selectedStoreID] ?? []
    }

    var purchaseSelectionNeedsReview: Bool {
        guard loadedStoreID == selectedStoreID else { return false }
        return purchaseSelection.contains { selected in
            !items.contains { $0.id == selected.id && $0.version == selected.version }
        }
    }

    var canFinalizePurchase: Bool {
        canPerformShopping && loadedStoreID != nil && loadedStoreID == selectedStoreID
            && (1...50).contains(purchaseSelection.count) && !purchaseSelectionNeedsReview
    }

    var purchaseActionTitle: LocalizedStringResource { "Confirm purchase · \(purchaseSelection.count)" }

    func isPurchaseSelected(_ item: SharedItem) -> Bool {
        purchaseSelection.contains { $0.id == item.id }
    }

    func canTogglePurchaseItem(_ item: SharedItem) -> Bool {
        canPerformShopping && loadedStoreID == selectedStoreID && item.storeId == selectedStoreID
            && item.groupId == group?.id && items.contains(item)
            && (isPurchaseSelected(item) || purchaseSelection.count < 50)
    }

    func togglePurchaseItem(_ item: SharedItem) {
        guard canTogglePurchaseItem(item) else { return }
        var selection = purchaseSelection
        if let index = selection.firstIndex(where: { $0.id == item.id }) {
            selection.remove(at: index)
        } else {
            selection.append(item)
        }
        purchaseSelections[item.storeId] = selection
    }

    private func reconcilePurchaseSelection() {
        guard pendingOperation == nil, storeItemsState == .loaded,
              let selectedStoreID, loadedStoreID == selectedStoreID else { return }
        let previousSelection = purchaseSelection
        purchaseSelections[selectedStoreID] = previousSelection.filter { selected in
            items.contains {
                $0.id == selected.id && $0.version == selected.version
                    && $0.status == "pending" && $0.storeId == selectedStoreID && $0.groupId == group?.id
            }
        }
        if previousSelection != purchaseSelection, notice == nil {
            notice = "Changed or unavailable products have been deselected. Review the list and select any products you still want to buy."
        }
    }

    func finalizePurchase() async {
        guard canFinalizePurchase, let session, let group, let store = selectedStoreID else { return }
        let selection = purchaseSelection
        let request = FinalizePurchaseRequest(
            operationId: UUID(),
            storeId: store,
            items: selection.map { SelectedPurchaseItem(id: $0.id, expectedVersion: $0.version) }
        )
        await performAction {
            do {
                let operation = PendingSharedOperation.purchase(
                    userID: session.user.id,
                    groupID: group.id,
                    request: request,
                    selection: selection
                )
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                await performPendingOperation()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    private func restorePurchaseSelection() {
        guard let session else { return }
        if purchaseSelectionOwner != session.user.id {
            purchaseSelections = [:]
            purchaseSelectionOwner = session.user.id
        }
        if case .changeItem(let userID, let original, let request) = pendingOperation,
           userID == session.user.id, original.groupId == group?.id {
            if editingItem == nil, request.replacement != nil {
                restoreItemEditor(original: original, request: request)
            }
            selectedStoreID = original.storeId
        }
        if case .purchase(let userID, let groupID, let request, let selection) = pendingOperation,
           userID == session.user.id, groupID == group?.id,
           purchaseSelections[request.storeId] == nil {
            purchaseSelections[request.storeId] = selection
            selectedStoreID = request.storeId
        }
    }
}


extension SharedShoppingViewModel {
    func canChangeItem(_ item: SharedItem) -> Bool {
        canPerformShopping && loadedStoreID == selectedStoreID && item.status == "pending"
            && item.groupId == group?.id && items.contains(item)
    }

    func canCancelItem(_ item: SharedItem) -> Bool {
        canMutate && loadedStoreID == selectedStoreID && item.status == "pending"
            && item.groupId == group?.id && items.contains(item)
    }

    func beginEditingItem(_ item: SharedItem) {
        guard canChangeItem(item) else { return }
        editingItem = item
        editName = item.name
        editQuantity = item.quantity ?? ""
        editStoreID = item.storeId
        editNewStore = ""
        editNeedsReview = false
        notice = nil
        isItemEditorPresented = true
    }

    func itemEditorPresentationDidDismiss() {
        isItemEditorPresentationActive = false
    }

    var canSaveItemEdit: Bool {
        guard let editingItem else { return false }
        return canPerformShopping && canChangeItem(editingItem) && !editNeedsReview && preparedItemEdit != nil
    }

    var latestEditingItem: SharedItem? {
        guard let editingItem, loadedStoreID == selectedStoreID else { return nil }
        return items.first { $0.id == editingItem.id }
    }

    /// Explicitly review the current row before confirming a new intent after a conflict.
    func reviewLatestItem() {
        guard canPerformShopping, let current = latestEditingItem else { return }
        editingItem = current
        editNeedsReview = false
    }

    func saveItemEdit() async {
        guard canSaveItemEdit, let original = editingItem, let replacement = preparedItemEdit else { return }
        await submitItemChange(original, replacement: replacement)
    }

    func cancelItem(_ item: SharedItem) async {
        guard canCancelItem(item) else { return }
        await submitItemChange(item, replacement: nil)
    }

    var itemEditRequiresReview: Bool {
        editNeedsReview || latestEditingItem != editingItem
    }

    var editHasLengthIssue: Bool {
        editLengthMessage(for: .name) != nil || editLengthMessage(for: .quantity) != nil
            || editLengthMessage(for: .store) != nil
    }

    func editLengthMessage(for field: DraftField) -> LocalizedStringResource? {
        let value = switch field {
        case .name: editName
        case .quantity: editQuantity
        case .store: editStoreID == nil ? editNewStore : ""
        }
        return ShoppingDraftRules.exceedsLength(value, field: field) ? ShoppingDraftRules.lengthMessage(for: field) : nil
    }

    var editValidationMessage: LocalizedStringResource? {
        if ShoppingDraftRules.normalized(editName)?.isEmpty != false {
            return "Enter a product name."
        }
        if editStoreID == nil && ShoppingDraftRules.normalized(editNewStore)?.isEmpty != false {
            return "Enter a store name."
        }
        let visibleFields = [editName, editQuantity] + (editStoreID == nil ? [editNewStore] : [])
        if visibleFields.contains(where: { value in
            value.unicodeScalars.contains { $0.properties.generalCategory == .control && !$0.properties.isWhitespace }
        }) {
            return "Remove unsupported control characters from the product details."
        }
        if let message = editLengthMessage(for: .name) ?? editLengthMessage(for: .quantity) ?? editLengthMessage(for: .store) {
            return message
        }
        let destination = editStoreID.flatMap { id in stores.first { $0.id == id } }
            ?? storeCandidates(for: editNewStore).first
        if let destination, destination.id != editingItem?.storeId {
            guard let capabilities = destination.capabilities else {
                return "Refresh to verify store availability before adding products."
            }
            if !capabilities.canAddItems {
                return "This store has reached its pending product limit. Buying or cancelling products frees capacity."
            }
        } else if destination == nil, editStoreID == nil {
            guard let groupCapacity else { return "Refresh to verify store availability before adding products." }
            if !groupCapacity.canCreateStore {
                return "This group has reached its active store limit. Archive an empty store before adding another."
            }
        }
        return nil
    }

    private var preparedItemEdit: SharedNewItem? {
        guard editValidationMessage == nil else { return nil }
        guard let name = ShoppingDraftRules.normalized(editName), !name.isEmpty,
              let quantity = ShoppingDraftRules.normalized(editQuantity) else { return nil }
        let store: SharedStoreReference
        if let editStoreID {
            guard stores.contains(where: { $0.id == editStoreID }) else { return nil }
            store = .existing(editStoreID)
        } else {
            guard let name = ShoppingDraftRules.normalized(editNewStore), !name.isEmpty else { return nil }
            store = .newName(name)
        }
        return SharedNewItem(name: name, quantity: quantity.isEmpty ? nil : quantity, store: store)
    }

    private func restoreItemEditor(original: SharedItem, request: SharedItemChangeRequest) {
        guard let replacement = request.replacement else { return }
        editingItem = original
        editName = replacement.name
        editQuantity = replacement.quantity ?? ""
        switch replacement.store {
        case .existing(let id):
            editStoreID = id
            editNewStore = ""
        case .newName(let name):
            editStoreID = nil
            editNewStore = name
        }
    }

    private func submitItemChange(_ original: SharedItem, replacement: SharedNewItem?) async {
        guard let session else { return }
        let request = SharedItemChangeRequest(
            operationId: UUID(),
            expectedVersion: original.version,
            replacement: replacement
        )
        await performAction {
            do {
                let operation = PendingSharedOperation.changeItem(
                    userID: session.user.id,
                    original: original,
                    request: request
                )
                try await credentials.saveOperation(operation)
                pendingOperation = operation
                await performPendingOperation()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }
}
