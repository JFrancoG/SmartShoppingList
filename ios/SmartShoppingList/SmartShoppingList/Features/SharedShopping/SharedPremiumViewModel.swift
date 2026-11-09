import DeviceCheck
import Foundation
import Observation

@Observable @MainActor
final class SharedPremiumViewModel {
    private(set) var status: SharedSubscriptionStatus?
    private(set) var products: [SharedSubscriptionProduct] = []
    private(set) var pendingRecovery: PendingSubscriptionRecovery?
    private(set) var pendingVerification: PendingSubscriptionVerification?
    private(set) var isBusy = false
    private(set) var notice: LocalizedStringResource?
    @ObservationIgnored private(set) var lastLoadAttemptedVerification = false
    private var ownerID: UUID?
    @ObservationIgnored private let api: (any SharedSubscriptionAPI)?
    @ObservationIgnored private let store: (any SharedSubscriptionStore)?
    @ObservationIgnored private let recoveryAttester: any SharedRecoveryAttesting
    @ObservationIgnored private let credentials: (any SharedSubscriptionCredentialStoring)?

    init(
        api: (any SharedSubscriptionAPI)?,
        store: (any SharedSubscriptionStore)?,
        credentials: (any SharedSubscriptionCredentialStoring)?,
        recoveryAttester: any SharedRecoveryAttesting = AppleSubscriptionRecoveryAttester()
    ) {
        self.api = api
        self.store = store
        self.credentials = credentials
        self.recoveryAttester = recoveryAttester
    }

    var canPurchase: Bool {
        !isBusy && pendingRecovery == nil && pendingVerification == nil && status?.isConfigured == true && !products.isEmpty
    }

    var canRestore: Bool { !isBusy && status?.isConfigured == true && pendingVerification == nil }

    func takeActionNotice() -> LocalizedStringResource? {
        defer { notice = nil }
        return notice
    }

    func clearPresentation() {
        ownerID = nil
        status = nil
        products = []
        notice = nil
        // A transaction still awaiting server acknowledgement belongs to its original account.
    }

    /// Fresh server status can reconcile account rights even when this device has no Apple transactions.
    func load(
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard !isBusy, let api, let credentials else { return false }
        lastLoadAttemptedVerification = false
        isBusy = true
        defer { isBusy = false }
        if ownerID != session.user.id {
            clearPresentation()
            ownerID = session.user.id
        }
        var receivedAuthority = false
        do {
            let storedRecovery = try await (credentials as? any SharedSubscriptionRecoveryStoring)?.loadSubscriptionRecovery()
            // Keep a proof returned by Apple if its following Keychain write failed in this process.
            if pendingRecovery?.userID != session.user.id || pendingRecovery?.keyID != storedRecovery?.keyID {
                pendingRecovery = storedRecovery
            } else if pendingRecovery?.request == nil && pendingRecovery?.challenge == nil {
                pendingRecovery = storedRecovery
            }
            pendingVerification = try await credentials.loadSubscriptionVerification()
            guard isCurrentSession(session) else { return false }
            let current = try await api.subscription(token: session.accessToken)
            guard isCurrentSession(session) else { return false }
            status = current
            receivedAuthority = true
            products = []
            notice = nil
            if let pendingVerification {
                guard pendingVerification.userID == session.user.id else {
                    notice = "Sign in with the account that started this purchase to finish verifying it."
                    return true
                }
                // Delivery recovery must not depend on the availability of Apple's product catalogue.
                lastLoadAttemptedVerification = true
                _ = await verify(pendingVerification, session: session, isCurrentSession: isCurrentSession)
                return isCurrentSession(session)
            }
            guard current.isConfigured, let store else { return true }
            do {
                let available = try await store.products(ids: current.productIDs)
                guard isCurrentSession(session) else { return false }
                guard Set(available.map(\.id)) == Set(current.productIDs),
                      available.count == current.productIDs.count,
                      Set(available.map(\.subscriptionGroupID)).count == 1,
                      available.allSatisfy({ !$0.subscriptionGroupID.isEmpty }),
                      available.filter({ $0.period == .monthly }).count == 1,
                      available.filter({ $0.period == .annual }).count == 1 else {
                    throw SharedSubscriptionStoreError.unavailable
                }
                products = available
            } catch {
                guard isCurrentSession(session) else { return false }
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    return receivedAuthority
                }
                // Metadata controls which prices can be offered, never existing purchase delivery or account rights.
                notice = "Subscription options could not be loaded. Your existing access and saved purchases are kept. Refresh to try again."
            }
            for transaction in try await store.transactions() {
                guard isCurrentSession(session) else { return false }
                if accepts(transaction, status: current) {
                    lastLoadAttemptedVerification = true
                    _ = await receive(transaction, session: session, isCurrentSession: isCurrentSession)
                    if pendingVerification != nil { break }
                }
            }
            return isCurrentSession(session)
        } catch {
            guard isCurrentSession(session) else { return false }
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else {
                return receivedAuthority
            }
            notice = SharedErrorMessage.readMessage(for: error)
            return receivedAuthority
        }
    }

    func purchase(
        productID: String,
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard canPurchase, ownerID == session.user.id, let status, let store,
              products.contains(where: { $0.id == productID }) else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await store.purchase(id: productID, appAccountToken: status.appAccountToken) {
            case .cancelled:
                return false
            case .pending:
                if isCurrentSession(session) {
                    notice = "Apple is awaiting approval of this purchase. Premium starts after verification."
                }
                return false
            case .verified(let transaction):
                guard isCurrentSession(session) else { return false }
                guard store.expectedEnvironment.accepts(transaction.environment) else {
                    throw SharedSubscriptionStoreError.incompatibleEnvironment
                }
                guard accepts(transaction, status: status) else {
                    notice = "This purchase belongs to another app account. Sign in with its original account."
                    return false
                }
                return await receive(transaction, session: session, isCurrentSession: isCurrentSession)
            }
        } catch {
            guard isCurrentSession(session) else { return false }
            notice = message(for: error)
            return false
        }
    }

    func restore(
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard canRestore, ownerID == session.user.id, let store else { return false }
        isBusy = true
        do {
            try await store.restore()
        } catch {
            isBusy = false
            if isCurrentSession(session) {
                notice = message(for: error)
            }
            return false
        }
        isBusy = false
        guard isCurrentSession(session) else { return false }
        let loaded = await load(session: session, isCurrentSession: isCurrentSession)
        guard isCurrentSession(session), pendingVerification == nil, let status else { return loaded }
        isBusy = true
        defer { isBusy = false }
        do {
            let candidates = try await store.recoveryTransactions().filter {
                $0.appAccountToken != status.appAccountToken && status.productIDs.contains($0.productID)
                    && store.expectedEnvironment.accepts($0.environment)
            }
            guard isCurrentSession(session) else { return false }
            if pendingRecovery != nil || !candidates.isEmpty {
                return await recover(candidates.first, session: session, isCurrentSession: isCurrentSession) || loaded
            }
            if status.state == .free || status.state == .expired || status.state == .revoked {
                notice = "No active subscription was found for this Apple purchase account."
            }
            return loaded
        } catch {
            if isCurrentSession(session) {
                notice = message(for: error)
            }
            return loaded
        }
    }

    private func recover(
        _ transaction: SharedStoreTransaction?,
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard let api = api as? any SharedSubscriptionRecoveryAPI,
              let credentials = credentials as? any SharedSubscriptionRecoveryStoring,
              let store, status?.appAccountToken == session.user.id else {
            notice = "Premium recovery is not available on this device. Your purchase is kept."
            return false
        }
        do {
            // Before any POST, an expired challenge starts a new explicit attempt with a new key.
            // A submitted proof remains unchanged because its server reservation may already exist.
            if let pendingRecovery, pendingRecovery.userID == session.user.id,
               store.expectedEnvironment.accepts(pendingRecovery.environment), pendingRecovery.request == nil,
               let challenge = pendingRecovery.challenge, challenge.expiresAt <= Date() {
                try await credentials.saveSubscriptionRecovery(nil)
                self.pendingRecovery = nil
            }
            var recovery: PendingSubscriptionRecovery
            if let pendingRecovery {
                guard pendingRecovery.userID == session.user.id,
                      store.expectedEnvironment.accepts(pendingRecovery.environment) else {
                    notice = "Sign in with the account that started this recovery to finish it."
                    return false
                }
                recovery = pendingRecovery
            } else {
                guard let transaction else { return false }
                let key = try await recoveryAttester.generateKey()
                guard isCurrentSession(session) else { return false }
                recovery = PendingSubscriptionRecovery(
                    userID: session.user.id,
                    transactionID: transaction.id,
                    environment: transaction.environment,
                    keyID: key,
                    signedTransaction: transaction.signedTransaction
                )
                try await credentials.saveSubscriptionRecovery(recovery)
                pendingRecovery = recovery
            }
            if recovery.request == nil {
                if recovery.challenge == nil {
                    recovery.challenge = try await api.subscriptionRecoveryChallenge(
                        SharedRecoveryChallengeRequest(signedTransaction: recovery.signedTransaction, keyId: recovery.keyID),
                        token: session.accessToken
                    )
                    guard isCurrentSession(session) else { return false }
                    pendingRecovery = recovery
                    try await credentials.saveSubscriptionRecovery(recovery)
                }
                guard let challenge = recovery.challenge else { throw SharedAPIError.invalidResponse }
                let hash = try challenge.verifiedHash(
                    userID: session.user.id,
                    keyID: recovery.keyID,
                    transaction: recovery.signedTransaction,
                    storeEnvironment: recovery.environment
                )
                let attestation = try await recoveryAttester.attest(keyID: recovery.keyID, hash: hash)
                guard isCurrentSession(session) else { return false }
                recovery.request = SharedRecoveryRequest(
                    challengeId: challenge.id,
                    keyId: recovery.keyID,
                    attestation: attestation.base64EncodedString(),
                    signedTransaction: recovery.signedTransaction
                )
                // Save the exact proof before submission: a lost acknowledgement must replay this proof.
                pendingRecovery = recovery
                try await credentials.saveSubscriptionRecovery(recovery)
            }
            guard let request = recovery.request else { throw SharedAPIError.invalidResponse }
            // Also retry a failed local proof write before attempting delivery.
            try await credentials.saveSubscriptionRecovery(recovery)
            guard isCurrentSession(session) else { return false }
            let acknowledgement = try await api.recoverSubscription(request, token: session.accessToken)
            guard isCurrentSession(session) else { return false }
            guard acknowledgement.acknowledgedTransactionId == recovery.transactionID,
                  acknowledgement.subscription.appAccountToken == session.user.id else { throw SharedAPIError.invalidResponse }
            status = acknowledgement.subscription
            await store.finish(transactionID: recovery.transactionID)
            guard isCurrentSession(session) else { return false }
            try await credentials.saveSubscriptionRecovery(nil)
            pendingRecovery = nil
            notice = "Premium was restored to this account. Deleted lists and groups have not been recovered."
            return true
        } catch {
            guard isCurrentSession(session) else { return false }
            let definitiveServerRejection: Bool
            if let apiError = error as? SharedAPIError {
                definitiveServerRejection = !apiError.isUncertain && !apiError.isSessionInvalid
            } else {
                definitiveServerRejection = false
            }
            let failedUnsubmittedKey = pendingRecovery?.request == nil && (
                (error as? DCError).map { $0.code != .serverUnavailable } == true
                    || (error as? SharedAPIError) == .invalidResponse
            )
            if definitiveServerRejection || failedUnsubmittedKey {
                do {
                    try await credentials.saveSubscriptionRecovery(nil)
                    pendingRecovery = nil
                } catch {
                    notice = message(for: error)
                    return false
                }
            }
            if case SharedAPIError.server(_, "subscription_recovery_pending_review", _, _) = error {
                notice = "This subscription recovery needs review. Contact soporte@jesusfranco.dev."
            } else {
                notice = "Premium recovery could not be confirmed. Your purchase is kept. Use Restore purchases to retry."
            }
            return false
        }
    }

    func receiveUpdate(
        _ transaction: SharedStoreTransaction,
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard !isBusy, ownerID == session.user.id, let status, status.isConfigured,
              pendingVerification == nil, accepts(transaction, status: status) else { return false }
        isBusy = true
        defer { isBusy = false }
        return await receive(transaction, session: session, isCurrentSession: isCurrentSession)
    }

    private func accepts(_ transaction: SharedStoreTransaction, status: SharedSubscriptionStatus) -> Bool {
        transaction.appAccountToken == status.appAccountToken && status.productIDs.contains(transaction.productID)
            && store?.expectedEnvironment.accepts(transaction.environment) == true
    }

    private func receive(
        _ transaction: SharedStoreTransaction,
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard let credentials, pendingVerification == nil, isCurrentSession(session) else { return false }
        let verification = PendingSubscriptionVerification(
            userID: session.user.id,
            transactionID: transaction.id,
            request: VerifySharedSubscriptionRequest(signedTransaction: transaction.signedTransaction),
            environment: transaction.environment
        )
        do {
            try await credentials.saveSubscriptionVerification(verification)
            pendingVerification = verification
            guard isCurrentSession(session) else { return false }
            return await verify(verification, session: session, isCurrentSession: isCurrentSession)
        } catch {
            if isCurrentSession(session) {
                notice = message(for: error)
            }
            return false
        }
    }

    private func verify(
        _ verification: PendingSubscriptionVerification,
        session: SharedSession,
        isCurrentSession: @MainActor (SharedSession) -> Bool
    ) async -> Bool {
        guard let api, let store, let credentials, verification.userID == session.user.id else { return false }
        do {
            let verification = try await compatibleVerification(verification, session: session)
            guard isCurrentSession(session) else { return false }
            let acknowledgement = try await api.verifySubscription(verification.request, token: session.accessToken)
            guard isCurrentSession(session) else { return false }
            guard acknowledgement.acknowledgedTransactionId == verification.transactionID,
                  acknowledgement.subscription.appAccountToken == status?.appAccountToken else {
                throw SharedAPIError.invalidResponse
            }
            // No client transaction activates premium. The server has persisted this result before acknowledging it.
            status = acknowledgement.subscription
            await store.finish(transactionID: verification.transactionID)
            guard isCurrentSession(session) else { return false }
            try await credentials.saveSubscriptionVerification(nil)
            guard isCurrentSession(session) else { return false }
            pendingVerification = nil
            notice = nil
            return true
        } catch {
            guard isCurrentSession(session) else { return false }
            if let apiError = error as? SharedAPIError, !apiError.isUncertain, !apiError.isSessionInvalid {
                do {
                    try await credentials.saveSubscriptionVerification(nil)
                    pendingVerification = nil
                } catch {
                    notice = message(for: error)
                    return false
                }
            }
            notice = message(for: error)
            return false
        }
    }

    /// Older Keychain envelopes lack environment metadata. Retain their original payload until StoreKit confirms it.
    private func compatibleVerification(
        _ verification: PendingSubscriptionVerification,
        session: SharedSession
    ) async throws -> PendingSubscriptionVerification {
        guard let store else { throw SharedSubscriptionStoreError.unavailable }
        if let environment = verification.environment {
            guard store.expectedEnvironment.accepts(environment) else {
                throw SharedSubscriptionStoreError.incompatibleEnvironment
            }
            return verification
        }
        guard let status,
              let transaction = try await store.transactions().first(where: {
                  $0.id == verification.transactionID && accepts($0, status: status)
              }) else {
            throw SharedSubscriptionStoreError.missingEnvironmentEvidence
        }
        return PendingSubscriptionVerification(
            userID: session.user.id,
            transactionID: verification.transactionID,
            request: verification.request,
            environment: transaction.environment
        )
    }

    private func message(for error: any Error) -> LocalizedStringResource {
        if let storeError = error as? SharedSubscriptionStoreError {
            switch storeError {
            case .incompatibleEnvironment:
                return "This purchase belongs to a different test or App Store environment. Open the version that started it; your purchase is kept."
            case .missingEnvironmentEvidence:
                return "Your saved purchase is kept, but its environment could not be verified on this device. Refresh to try again."
            case .unavailable, .unverified:
                break
            }
        }
        if error is SharedCredentialError {
            return "The purchase still needs verification, but it could not be saved on this device. Keep the app open and try again."
        }
        if let apiError = error as? SharedAPIError {
            return SharedErrorMessage.message(for: apiError)
        }
        return "The purchase could not be verified. No premium access has been confirmed. Try again or restore purchases."
    }
}

#if DEBUG
extension SharedPremiumViewModel {
    func applyPreview(_ presentation: SharedPreviewPresentation) {
        ownerID = presentation.session?.user.id
        status = presentation.subscriptionStatus
        products = presentation.subscriptionProducts
        pendingVerification = presentation.subscriptionVerification
        notice = presentation.subscriptionNotice
    }
}
#endif
