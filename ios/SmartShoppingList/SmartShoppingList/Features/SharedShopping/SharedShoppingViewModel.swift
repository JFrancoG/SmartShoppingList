import AuthenticationServices
import Foundation
import Observation
import Security

struct DraftStoreChoice: Identifiable {
    let id: String
    var selection = ""
}

enum StoreItemsState {
    case notLoaded
    case loading
    case loaded
    case failed
}

@Observable @MainActor
final class SharedShoppingViewModel {
    private(set) var storeItemsState = StoreItemsState.notLoaded
    private(set) var session: SharedSession?
    private(set) var pendingInvitation: PendingInvitation?
    private(set) var invitationPreview: InvitationPreview?
    private(set) var pendingOperation: PendingSharedOperation?
    private var purchaseSelections: [UUID: [SharedItem]] = [:]
    private var purchaseSelectionOwner: UUID?
    private var loadedStoreID: UUID?
    private(set) var stores: [SharedStore] = []
    private(set) var items: [SharedItem] = []
    private(set) var invitations: [SharedInvitation] = []
    private(set) var shareURL: URL?
    private(set) var hasLoaded = false
    private(set) var isBusy = false
    private(set) var sessionIsVerified = false
    private(set) var notice: LocalizedStringResource?
    private(set) var challenge: SharedChallenge?
    private(set) var reviewedItems: [PreparedDraftItem] = []
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
                isItemEditorPresentationActive = true
            }
        }
    }
    private(set) var isItemEditorPresentationActive = false
    var groupName = ""
    var isReviewPresented = false {
        didSet {
            if isReviewPresented {
                isReviewPresentationActive = true
            }
        }
    }
    var isInvitationsPresented = false {
        didSet {
            if isInvitationsPresented {
                isInvitationsPresentationActive = true
            }
        }
    }
    private(set) var isReviewPresentationActive = false
    private(set) var isInvitationsPresentationActive = false

    @ObservationIgnored let draft: ShoppingDraftViewModel
    @ObservationIgnored private let api: (any SharedShoppingAPI)?
    @ObservationIgnored private let configuration: SharedAPIConfiguration?
    @ObservationIgnored private let credentials: any SharedCredentialStoring
    @ObservationIgnored private var appleState: String?
    @ObservationIgnored private var storageFailed = false
    @ObservationIgnored private var reviewSnapshot: ShoppingDraftSnapshot?
    @ObservationIgnored private var retryNotBefore: Date?

    init(
        api: (any SharedShoppingAPI)?,
        configuration: SharedAPIConfiguration?,
        credentials: any SharedCredentialStoring,
        draft: ShoppingDraftViewModel
    ) {
        self.api = api
        self.configuration = configuration
        self.credentials = credentials
        self.draft = draft
    }

    var group: SharedGroup? { session?.user.group }
    var isConfigured: Bool { api != nil && configuration != nil }
    var canMutate: Bool { hasLoaded && sessionIsVerified && !isBusy && !storageFailed && pendingOperation == nil }
    var draftIsLocked: Bool { !hasLoaded || pendingOperation != nil || isBusy || isReviewPresented }
    var isCreator: Bool { group?.creatorUserId == session?.user.id && group != nil }
    var canConfirmReview: Bool {
        canMutate && !reviewedItems.isEmpty && storeChoices.allSatisfy { !$0.selection.isEmpty }
    }
    var canRetryOperation: Bool {
        !isBusy && sessionIsVerified && pendingOperation?.userID == session?.user.id && !storageFailed
    }
    var selectedStoreName: String {
        stores.first { $0.id == selectedStoreID }?.name ?? ""
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
        guard !hasLoaded, !isBusy else { return }
        await performAction {
            defer {
                hasLoaded = true
            }
            await draft.load()
            do {
                pendingOperation = try await credentials.loadOperation()
                pendingInvitation = try await credentials.loadInvitation()
                session = try await credentials.loadSession()
            } catch {
                storageFailed = true
                notice = "Your saved access could not be restored. Unlock the device and reopen the app; your data is kept without overwriting it."
                return
            }
            guard isConfigured else {
                notice = "The group connection is not configured yet. You can prepare your draft manually."
                return
            }
            await refreshSessionAndLists()
        }
    }

    func refresh() async {
        guard hasLoaded, !isBusy, !storageFailed else { return }
        await performAction {
            await refreshSessionAndLists()
        }
    }

    func prepareAppleLogin() async {
        guard hasLoaded, !isBusy, !storageFailed, let api else { return }
        await performAction {
            challenge = nil
            appleState = nil
            notice = nil
            do {
                let result = try await api.createChallenge()
                var bytes = [UInt8](repeating: 0, count: 32)
                guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                    throw SharedAPIError.invalidResponse
                }
                appleState = Data(bytes).base64EncodedString()
                challenge = result
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let challenge, challenge.expiresAt > Date(), let appleState, !isBusy else {
            request.state = UUID().uuidString
            notice = "This sign-in attempt has expired. Prepare Sign in with Apple again."
            return
        }
        request.requestedScopes = [.fullName]
        request.nonce = challenge.nonce
        request.state = appleState
        isBusy = true
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
        guard canMutate, let api, let session, let invitation = pendingInvitation else { return }
        await performAction {
            do {
                let group = try await api.acceptInvitation(invitation, token: session.accessToken)
                try await updateGroup(group)
                try await credentials.saveInvitation(nil)
                pendingInvitation = nil
                invitationPreview = nil
                await refreshSessionAndLists()
            } catch {
                await handle(error)
            }
        }
    }

    func createGroup() async {
        guard canMutate, let session, session.user.group == nil else { return }
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
                await performPendingOperation()
            } catch {
                notice = SharedErrorMessage.message(for: error)
            }
        }
    }

    func prepareReview() async {
        guard canMutate, group != nil, let api, let session, let group else { return }
        draft.reviewDraft()
        guard let prepared = draft.preparedItems else { return }
        await performAction {
            do {
                stores = try await api.stores(groupID: group.id, token: session.accessToken)
                reviewedItems = prepared
                reviewSnapshot = ShoppingDraftSnapshot(text: draft.text, items: draft.items)
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

    private func performPendingOperation() async {
        guard let api, let session, let operation = pendingOperation, operation.userID == session.user.id else {
            return
        }
        do {
            switch operation {
            case .changeItem(_, let original, let request):
                _ = try await api.changeItem(request, item: original, token: session.accessToken)
            case .purchase(_, let groupID, let request, _):
                let result = try await api.finalizePurchase(request, groupID: groupID, token: session.accessToken)
                guard result.items.allSatisfy({ $0.purchasedBy == session.user.id }) else {
                    throw SharedAPIError.invalidResponse
                }
            case .createGroup(_, let request):
                let group = try await api.createGroup(request, token: session.accessToken)
                try await updateGroup(group)
            case .addItems(_, let groupID, let request, let sourceDraft):
                _ = try await api.addItems(request, groupID: groupID, token: session.accessToken)
                guard await draft.consumeConfirmedItems(sourceDraft.items) else {
                    notice = "The server confirmed the batch, but the result still needs to be saved on this device. Retry to complete the same submission."
                    return
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
            } else {
                notice = "The operation is confirmed in the group."
            }
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
                        if case .purchase = operation {
                            let previousSelection = purchaseSelection
                            let refreshed = await refreshSessionAndLists()
                            if code == "item_conflict", refreshed, previousSelection != purchaseSelection, notice != nil {
                                return
                            }
                        }
                        if case .changeItem(_, let original, let request) = operation {
                            if request.replacement != nil {
                                restoreItemEditor(original: original, request: request)
                                editNeedsReview = true
                            }
                            await refreshSessionAndLists()
                        }
                    } catch {
                        notice = SharedErrorMessage.message(for: error)
                        return
                    }
                }
            }
            await handle(error)
        } catch {
            // Cancellation and local storage failures cannot establish whether the server committed.
            notice = SharedErrorMessage.message(for: error)
        }
    }

    func loadSelectedStore() async {
        guard !isBusy, sessionIsVerified, let api, let session, let group, let storeID = selectedStoreID else {
            return
        }
        await performAction {
            items = []
            loadedStoreID = nil
            storeItemsState = .loading
            do {
                let loaded = try await api.pendingItems(groupID: group.id, storeID: storeID, token: session.accessToken)
                guard selectedStoreID == storeID else { return }
                items = loaded
                loadedStoreID = storeID
                storeItemsState = .loaded
                notice = nil
                reconcilePurchaseSelection()
            } catch {
                guard selectedStoreID == storeID else { return }
                storeItemsState = .failed
                await handle(error)
            }
        }
    }

    func openInvitations() async {
        guard canMutate, isCreator, let api, let session, let group else { return }
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
        guard canMutate, isCreator, let api, let session, let group else { return }
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
        guard canMutate, isCreator, let api, let session, let group else { return }
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
        notice.map { ShoppingNotice(source: .group, message: $0) }
    }

    var canPresentRootNotice: Bool {
        !isReviewPresentationActive && !isInvitationsPresentationActive
            && !isItemEditorPresentationActive && !draft.isEditorPresentationActive
    }

    func reviewPresentationDidDismiss() {
        isReviewPresentationActive = false
    }

    func invitationsPresentationDidDismiss() {
        isInvitationsPresentationActive = false
    }

    func dismissPresentedNotice(_ snapshot: ShoppingNotice) {
        guard snapshot.source == .group, notice == snapshot.message else { return }
        notice = nil
    }

    func dismissNotice() {
        notice = nil
    }

    @discardableResult
    private func refreshSessionAndLists() async -> Bool {
        guard let api, var current = session else { return false }
        var requestedStoreID = selectedStoreID
        loadedStoreID = nil
        storeItemsState = selectedStoreID == nil ? .notLoaded : .loading
        do {
            current.user = try await api.currentUser(token: current.accessToken)
            try await credentials.saveSession(current)
            session = current
            sessionIsVerified = true
            restorePurchaseSelection()
            requestedStoreID = selectedStoreID
            storeItemsState = selectedStoreID == nil ? .notLoaded : .loading
            notice = nil
            if let group = current.user.group {
                stores = try await api.stores(groupID: group.id, token: current.accessToken)
                if let selectedStoreID, !stores.contains(where: { $0.id == selectedStoreID }) {
                    self.selectedStoreID = nil
                    items = []
                }
                if let storeID = selectedStoreID {
                    requestedStoreID = storeID
                    storeItemsState = .loading
                    let loaded = try await api.pendingItems(groupID: group.id, storeID: storeID, token: current.accessToken)
                    guard selectedStoreID == storeID else { return false }
                    items = loaded
                    loadedStoreID = storeID
                    storeItemsState = .loaded
                }
            } else {
                stores = []
                selectedStoreID = nil
            }
            await previewPendingInvitation()
            reconcilePurchaseSelection()
            return true
        } catch {
            if selectedStoreID == requestedStoreID {
                storeItemsState = selectedStoreID == nil ? .notLoaded : .failed
            } else if (error as? SharedAPIError)?.isSessionInvalid != true {
                return false
            }
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

    private func updateGroup(_ group: SharedGroup) async throws {
        guard var session else { throw SharedAPIError.invalidResponse }
        session.user.group = group
        try await credentials.saveSession(session)
        self.session = session
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
        isBusy = true
        await action()
        await finishAction()
    }

    private func finishAction() async {
        isBusy = false
        await promoteIncomingInvitation()
    }

    private func promoteIncomingInvitation() async {
        guard hasLoaded, !isBusy, !storageFailed else { return }
        isBusy = true
        defer { isBusy = false }
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
    }

    private func clearSessionPresentation() {
        editingItem = nil
        isItemEditorPresented = false
        purchaseSelections = [:]
        purchaseSelectionOwner = nil
        loadedStoreID = nil
        session = nil
        sessionIsVerified = false
        stores = []
        items = []
        invitations = []
        invitationPreview = nil
        shareURL = nil
        selectedStoreID = nil
        storeItemsState = .notLoaded
    }
}

#if DEBUG
extension SharedShoppingViewModel {
    /// Preview context caches values; every rendered preview owns a separately seeded model and dependencies.
    convenience init(
        preview: SharedPreviewPresentation,
        api: (any SharedShoppingAPI)?,
        configuration: SharedAPIConfiguration?,
        credentials: any SharedCredentialStoring,
        draft: ShoppingDraftViewModel
    ) {
        self.init(
            api: api,
            configuration: configuration,
            credentials: credentials,
            draft: draft
        )
        session = preview.session
        pendingInvitation = preview.pendingInvitation
        invitationPreview = preview.invitationPreview
        pendingOperation = preview.pendingOperation
        stores = preview.stores
        selectedStoreID = preview.selectedStoreID
        items = preview.items
        invitations = preview.invitations
        shareURL = preview.shareURL
        hasLoaded = true
        isBusy = false
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
        canMutate && loadedStoreID != nil && loadedStoreID == selectedStoreID
            && (1...50).contains(purchaseSelection.count) && !purchaseSelectionNeedsReview
    }

    var purchaseActionTitle: LocalizedStringResource { "Finish shopping · \(purchaseSelection.count)" }

    func isPurchaseSelected(_ item: SharedItem) -> Bool {
        purchaseSelection.contains { $0.id == item.id }
    }

    func canTogglePurchaseItem(_ item: SharedItem) -> Bool {
        canMutate && loadedStoreID == selectedStoreID && item.storeId == selectedStoreID
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
           userID == session.user.id, original.groupId == session.user.group?.id {
            if editingItem == nil, request.replacement != nil {
                restoreItemEditor(original: original, request: request)
            }
            selectedStoreID = original.storeId
        }
        if case .purchase(let userID, let groupID, let request, let selection) = pendingOperation,
           userID == session.user.id, groupID == session.user.group?.id,
           purchaseSelections[request.storeId] == nil {
            purchaseSelections[request.storeId] = selection
            selectedStoreID = request.storeId
        }
    }
}


extension SharedShoppingViewModel {
    func canChangeItem(_ item: SharedItem) -> Bool {
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
        return canChangeItem(editingItem) && !editNeedsReview && preparedItemEdit != nil
    }

    var latestEditingItem: SharedItem? {
        guard let editingItem, loadedStoreID == selectedStoreID else { return nil }
        return items.first { $0.id == editingItem.id }
    }

    /// Explicitly review the current row before confirming a new intent after a conflict.
    func reviewLatestItem() {
        guard canMutate, let current = latestEditingItem else { return }
        editingItem = current
        editNeedsReview = false
    }

    func saveItemEdit() async {
        guard canSaveItemEdit, let original = editingItem, let replacement = preparedItemEdit else { return }
        await submitItemChange(original, replacement: replacement)
    }

    func cancelItem(_ item: SharedItem) async {
        guard canChangeItem(item) else { return }
        await submitItemChange(item, replacement: nil)
    }

    var itemEditRequiresReview: Bool {
        editNeedsReview || latestEditingItem != editingItem
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
        let nameCount = ShoppingDraftRules.normalized(editName)?.unicodeScalars.count ?? 161
        let quantityCount = ShoppingDraftRules.normalized(editQuantity)?.unicodeScalars.count ?? 81
        let storeCount = ShoppingDraftRules.normalized(editNewStore)?.unicodeScalars.count ?? 81
        if max(editName.unicodeScalars.count, nameCount) > 160
            || max(editQuantity.unicodeScalars.count, quantityCount) > 80
            || (editStoreID == nil && max(editNewStore.unicodeScalars.count, storeCount) > 80) {
            return "Shorten the name to 160 characters and the quantity or store to 80 characters."
        }
        return nil
    }

    private var preparedItemEdit: SharedNewItem? {
        guard editValidationMessage == nil else { return nil }
        guard let name = ShoppingDraftRules.normalized(editName), (1...160).contains(name.unicodeScalars.count),
              editName.unicodeScalars.count <= 160,
              let quantity = ShoppingDraftRules.normalized(editQuantity), quantity.unicodeScalars.count <= 80,
              editQuantity.unicodeScalars.count <= 80 else { return nil }
        let store: SharedStoreReference
        if let editStoreID {
            guard stores.contains(where: { $0.id == editStoreID }) else { return nil }
            store = .existing(editStoreID)
        } else {
            guard let name = ShoppingDraftRules.normalized(editNewStore), (1...80).contains(name.unicodeScalars.count),
                  editNewStore.unicodeScalars.count <= 80 else { return nil }
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
