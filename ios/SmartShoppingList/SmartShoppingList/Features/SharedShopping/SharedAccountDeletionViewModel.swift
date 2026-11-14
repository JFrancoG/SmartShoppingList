import AuthenticationServices
import Foundation
import Observation
import Security

@Observable @MainActor
final class SharedAccountDeletionViewModel {
    private(set) var preview: SharedDeletionPreview?
    private(set) var pending: PendingAccountDeletion?
    private(set) var isBusy = false
    private(set) var notice: LocalizedStringResource?
    private(set) var hasAuthorization = false
    private(set) var hasLoaded = false
    private(set) var storageFailed = false
    @ObservationIgnored private let api: (any SharedAccountDeletionAPI)?
    @ObservationIgnored private let credentials: (any SharedDeletionCredentialStoring)?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var restoreTask: Task<PendingAccountDeletion?, any Error>?
    @ObservationIgnored private var challenge: SharedChallenge?
    @ObservationIgnored private var appleState: String?
    @ObservationIgnored private var authorization: (identityToken: String, code: String)?

    init(
        api: (any SharedAccountDeletionAPI)?,
        credentials: (any SharedDeletionCredentialStoring)?,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.api = api
        self.credentials = credentials
        self.now = now
    }

    var isAvailable: Bool { api != nil && credentials != nil }
    var hasCompletedLocalDeletion: Bool {
        pending?.lastStatus?.status == .completed && pending?.localDataCleared == true
    }
    var blocksAccountUse: Bool { storageFailed || (pending != nil && !hasCompletedLocalDeletion) }
    var needsStatusRefresh: Bool { pending?.submitted == true && !hasCompletedLocalDeletion }
    var canRefreshStatus: Bool { needsStatusRefresh && !isBusy && !storageFailed }
    var canAuthorize: Bool {
        !isBusy && !storageFailed && pending != nil && pending?.submitted == false
            && (challenge?.expiresAt.timeIntervalSince(now()) ?? 0) > 30
    }
    var acceptedUserID: UUID? {
        guard pending?.lastStatus?.status.wasAccepted == true else { return nil }
        return pending?.userID
    }
    var canDismissResult: Bool {
        !isBusy && !storageFailed && hasCompletedLocalDeletion
    }
    var accessibilityMessage: String {
        String(localized: isBusy ? "Updating deletion request…" : notice ?? statusMessage)
    }

    var statusMessage: LocalizedStringResource {
        switch pending?.lastStatus?.status {
        case .completed:
            return hasCompletedLocalDeletion
                ? "Account deleted. Your deleted lists and groups cannot be restored."
                : "Account deletion is confirmed. Local cleanup still needs to finish."
        case .accepted, .purging, .dataDeleted:
            return "Deletion in progress. Your account can no longer be used."
        case .cancelled:
            return "Deletion cancelled. Your account and data are kept."
        case .prepared, nil:
            return pending?.submitted == true
                ? "The deletion result is not confirmed. Check this request before using your account again."
                : "Review what will be deleted, verify your identity with Apple, then confirm deletion."
        }
    }

    func restore() async {
        guard !hasLoaded, let credentials else {
            hasLoaded = true
            return
        }
        if restoreTask == nil {
            restoreTask = Task {
                try await credentials.loadAccountDeletion()
            }
        }
        do {
            let restored = try await restoreTask?.value
            guard !hasLoaded else { return }
            pending = restored
            storageFailed = false
            hasLoaded = true
            restoreTask = nil
        } catch {
            restoreTask = nil
            storageFailed = true
            notice = "The saved deletion request could not be read. Unlock this device and try again. Your data is kept."
        }
    }

    func prepare(session: SharedSession) async {
        guard !isBusy, let api, let credentials else { return }
        await restore()
        guard !isBusy, !storageFailed else { return }
        if pending?.submitted == true || pending?.lastStatus?.status.wasAccepted == true {
            await checkStatus()
            return
        }
        guard pending == nil || pending?.userID == session.user.id else {
            notice = "Resolve the saved deletion request before using another account."
            return
        }
        isBusy = true
        defer { isBusy = false }
        resetAuthorization()
        do {
            let current = try await api.deletionPreview(token: session.accessToken)
            preview = current
            var receipt = try pending ?? PendingAccountDeletion(
                userID: session.user.id,
                receipt: makeReceipt(),
                revision: current.revision
            )
            receipt.revision = current.revision
            try await credentials.saveAccountDeletion(receipt)
            pending = receipt
            challenge = try await api.deletionChallenge(
                SharedDeletionPreparation(
                    operationId: receipt.receipt.operationId,
                    statusSecret: receipt.receipt.statusSecret,
                    revision: receipt.revision
                ),
                token: session.accessToken
            )
            appleState = UUID().uuidString
            notice = nil
        } catch {
            notice = "Deletion could not be prepared. Check your connection and retry. Nothing has been confirmed."
        }
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard canAuthorize, let challenge, let appleState else {
            request.state = UUID().uuidString
            notice = "This identity check has expired. Refresh the deletion details and try again."
            return
        }
        request.requestedScopes = []
        request.nonce = challenge.nonce
        request.state = appleState
    }

    func receiveAppleAuthorization(_ result: Result<ASAuthorization, any Error>) {
        guard case .success(let response) = result,
              let credential = response.credential as? ASAuthorizationAppleIDCredential,
              let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
              let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) else {
            resetAuthorization()
            notice = "Identity verification was not completed. Your account has not been deleted."
            return
        }
        acceptAuthorization(token: token, code: code, state: credential.state)
    }

    func acceptAuthorization(token: String, code: String, state: String?) {
        guard canAuthorize, state == appleState, !token.isEmpty, !code.isEmpty else {
            resetAuthorization()
            notice = "This identity check could not be verified. Refresh the deletion details and try again."
            return
        }
        authorization = (token, code)
        hasAuthorization = true
        notice = nil
    }

    func confirm(session: SharedSession) async {
        guard canAuthorize, hasAuthorization, var pending, pending.userID == session.user.id,
              let challenge, let authorization, let api, let credentials else { return }
        isBusy = true
        defer {
            isBusy = false
            resetAuthorization()
        }
        do {
            pending.submitted = true
            try await credentials.saveAccountDeletion(pending)
            self.pending = pending
            let result = try await api.deleteAccount(
                SharedDeletionRequest(
                    operationId: pending.receipt.operationId,
                    statusSecret: pending.receipt.statusSecret,
                    revision: pending.revision,
                    challengeId: challenge.id,
                    identityToken: authorization.identityToken,
                    authorizationCode: authorization.code
                ),
                token: session.accessToken
            )
            try await record(result)
        } catch {
            notice = "The deletion result is not confirmed. Check this request before using your account again."
        }
    }

    func checkStatus() async {
        guard !isBusy, let pending, pending.lastStatus?.status != .completed, let api else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await record(api.deletionStatus(pending.receipt))
        } catch {
            notice = "The deletion result is not confirmed. Check this request before using your account again."
        }
    }

    func cancel() async {
        guard !isBusy, let pending, let api else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await record(api.cancelDeletion(pending.receipt))
            if self.pending?.lastStatus?.status == .cancelled {
                try await credentials?.saveAccountDeletion(nil)
                self.pending = nil
                preview = nil
                resetAuthorization()
            }
        } catch {
            notice = "Cancellation could not be confirmed. Check the saved deletion request before continuing."
        }
    }

    func markLocalDataCleared() async throws {
        guard var pending, pending.lastStatus?.status.wasAccepted == true, let credentials else { return }
        pending.localDataCleared = true
        try await credentials.saveAccountDeletion(pending)
        self.pending = pending
    }

    @discardableResult
    func dismissResult() async -> Bool {
        guard pending != nil else { return !storageFailed }
        guard canDismissResult, let credentials else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await credentials.saveAccountDeletion(nil)
            pending = nil
            preview = nil
            notice = nil
            return true
        } catch {
            notice = "The saved deletion result could not be cleared. Unlock this device and try again."
            return false
        }
    }

    private func record(_ result: SharedDeletionStatus) async throws {
        guard var pending, result.operationId == pending.receipt.operationId, let credentials else {
            throw SharedAPIError.invalidResponse
        }
        guard pending.lastStatus?.status.wasAccepted != true || result.status.wasAccepted else {
            throw SharedAPIError.invalidResponse
        }
        pending.lastStatus = result
        pending.submitted = result.status.wasAccepted
        self.pending = pending
        try await credentials.saveAccountDeletion(pending)
        notice = nil
    }

    private func makeReceipt() throws -> SharedDeletionReceipt {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SharedCredentialError.unavailable(status: errSecNotAvailable)
        }
        let secret = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return SharedDeletionReceipt(operationId: UUID(), statusSecret: secret)
    }

    private func resetAuthorization() {
        authorization = nil
        hasAuthorization = false
    }
#if DEBUG
    func preparePreview(completed: Bool = false, awaitingCompletion: Bool = false, authorized: Bool = false) {
        resetAuthorization()
        let receipt = SharedDeletionReceipt(operationId: UUID(), statusSecret: "preview-only")
        let status: SharedDeletionStatus.State = completed ? .completed : awaitingCompletion ? .accepted : .prepared
        pending = PendingAccountDeletion(
            userID: UUID(),
            receipt: receipt,
            revision: "preview",
            submitted: completed || awaitingCompletion,
            lastStatus: SharedDeletionStatus(operationId: receipt.operationId, status: status),
            localDataCleared: completed || awaitingCompletion
        )
        preview = SharedDeletionPreview(
            revision: "preview",
            groups: [
                .init(id: UUID(), name: "Familia", memberCount: 3, administers: true, willDelete: false),
                .init(id: UUID(), name: "Personal", memberCount: 1, administers: true, willDelete: true)
            ],
            ownContentCount: 8, legacyContentCount: 2
        )
        if status == .prepared {
            challenge = SharedChallenge(id: UUID(), nonce: "preview-only", expiresAt: now().addingTimeInterval(300))
            appleState = "preview-only"
            if authorized {
                authorization = (identityToken: "preview-only", code: "preview-only")
                hasAuthorization = true
            }
        }
        hasLoaded = true
    }
#endif

}
