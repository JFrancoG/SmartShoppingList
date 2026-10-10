import Foundation
import Observation

@Observable @MainActor
final class SharedPremiumViewModel {
    private(set) var status: SharedSubscriptionStatus?
    private(set) var products: [SharedSubscriptionProduct] = []
    private(set) var pendingVerification: PendingSubscriptionVerification?
    private(set) var isBusy = false
    private(set) var notice: LocalizedStringResource?
    private var ownerID: UUID?
    @ObservationIgnored private let api: (any SharedSubscriptionAPI)?
    @ObservationIgnored private let store: (any SharedSubscriptionStore)?
    @ObservationIgnored private let credentials: (any SharedSubscriptionCredentialStoring)?

    init(
        api: (any SharedSubscriptionAPI)?,
        store: (any SharedSubscriptionStore)?,
        credentials: (any SharedSubscriptionCredentialStoring)?
    ) {
        self.api = api
        self.store = store
        self.credentials = credentials
    }

    var canPurchase: Bool {
        !isBusy && pendingVerification == nil && status?.isConfigured == true && !products.isEmpty
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
        isBusy = true
        defer { isBusy = false }
        if ownerID != session.user.id {
            clearPresentation()
            ownerID = session.user.id
        }
        var receivedAuthority = false
        do {
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
                // Metadata controls which prices can be offered, never existing purchase delivery or account rights.
                notice = "Subscription options could not be loaded. Your existing access and saved purchases are kept. Refresh to try again."
            }
            for transaction in try await store.transactions() {
                guard isCurrentSession(session) else { return false }
                if accepts(transaction, status: current) {
                    _ = await receive(transaction, session: session, isCurrentSession: isCurrentSession)
                    if pendingVerification != nil { break }
                }
            }
            return isCurrentSession(session)
        } catch {
            guard isCurrentSession(session) else { return false }
            notice = message(for: error)
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
                guard isCurrentSession(session), accepts(transaction, status: status) else {
                    if isCurrentSession(session) {
                        notice = "This purchase belongs to another app account. Sign in with its original account."
                    }
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
        return await load(session: session, isCurrentSession: isCurrentSession)
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
            request: VerifySharedSubscriptionRequest(signedTransaction: transaction.signedTransaction)
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

    private func message(for error: any Error) -> LocalizedStringResource {
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
