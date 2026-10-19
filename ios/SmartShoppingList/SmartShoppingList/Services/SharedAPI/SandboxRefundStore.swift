#if DEBUG
import Foundation
import OSLog
import StoreKit

struct SandboxRefundRequest {
    let id = UUID()
    let transactionID: UInt64
    let userID: UUID
    let accessToken: String
}

enum SandboxRefundOutcome {
    case submitted, cancelled, duplicate, failed

    init(_ result: Result<Transaction.RefundRequestStatus, Transaction.RefundRequestError>) {
        switch result {
        case .success(.success): self = .submitted
        case .success(.userCancelled): self = .cancelled
        case .failure(let error):
            // Only the SDK error case is logged, never account tokens or signed transaction data.
            Logger(subsystem: "com.plusprojects.SmartShoppingList", category: "SandboxRefund")
                .error("Refund sheet failed: \(String(describing: error), privacy: .public)")
            self = error == .duplicateRequest ? .duplicate : .failed
        @unknown default: self = .failed
        }
    }
}

protocol SandboxRefundStore: Sendable {
    func refundableTransactionID(appAccountToken: UUID, productIDs: [String]) async -> UInt64?
}

/// Only verified StoreKit values enter this selection; it never changes entitlement or finishes transactions.
struct SandboxRefundCandidate {
    let id: UInt64
    let appAccountToken: UUID?
    let productID: String
    let environment: AppStore.Environment
    let purchaseDate: Date
    let expirationDate: Date?
    let revocationDate: Date?
    let isUpgraded: Bool

    static func select(
        from candidates: [Self],
        appAccountToken: UUID,
        productIDs: [String],
        now: Date
    ) -> UInt64? {
        candidates.filter {
            $0.environment == .sandbox && $0.appAccountToken == appAccountToken &&
                productIDs.contains($0.productID) && $0.revocationDate == nil && !$0.isUpgraded &&
                ($0.expirationDate ?? .distantPast) > now
        }.max {
            if $0.purchaseDate == $1.purchaseDate {
                return $0.id < $1.id
            }
            return $0.purchaseDate < $1.purchaseDate
        }?.id
    }
}

extension StoreKitSubscriptionStore: SandboxRefundStore {
    func refundableTransactionID(appAccountToken: UUID, productIDs: [String]) async -> UInt64? {
        var candidates: [SandboxRefundCandidate] = []
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  transaction.productType == .autoRenewable else { continue }
            candidates.append(SandboxRefundCandidate(
                id: transaction.id,
                appAccountToken: transaction.appAccountToken,
                productID: transaction.productID,
                environment: transaction.environment,
                purchaseDate: transaction.purchaseDate,
                expirationDate: transaction.expirationDate,
                revocationDate: transaction.revocationDate,
                isUpgraded: transaction.isUpgraded
            ))
        }
        return SandboxRefundCandidate.select(
            from: candidates,
            appAccountToken: appAccountToken,
            productIDs: productIDs,
            now: .now
        )
    }
}
#endif
