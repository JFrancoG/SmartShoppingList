import Foundation
import StoreKit

struct SharedSubscriptionProduct: Identifiable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String
    let period: SharedSubscriptionPeriod
    let subscriptionGroupID: String
}

enum SharedSubscriptionPeriod: Equatable {
    case monthly, annual
}

struct SharedStoreTransaction: Equatable {
    let id: String
    let appAccountToken: UUID?
    let productID: String
    let signedTransaction: String
}

enum SharedSubscriptionPurchaseResult {
    case verified(SharedStoreTransaction)
    case pending, cancelled
}

enum SharedSubscriptionStoreError: Error {
    case unavailable, unverified
}

protocol SharedSubscriptionStore: Sendable {
    func products(ids: [String]) async throws -> [SharedSubscriptionProduct]
    func purchase(id: String, appAccountToken: UUID) async throws -> SharedSubscriptionPurchaseResult
    func restore() async throws
    func transactions() async throws -> [SharedStoreTransaction]
    func updates() async -> AsyncStream<SharedStoreTransaction>
    func finish(transactionID: String) async
}

/// StoreKit verifies device transactions; only the server decides membership rights and quota limits.
actor StoreKitSubscriptionStore: SharedSubscriptionStore {
    private var loadedProducts: [String: Product] = [:]
    private var unfinished: [String: Transaction] = [:]

    func products(ids: [String]) async throws -> [SharedSubscriptionProduct] {
        loadedProducts = [:]
        let products = try await Product.products(for: ids)
        guard Set(products.map(\.id)) == Set(ids),
              products.allSatisfy({ $0.type == .autoRenewable && $0.subscription != nil }),
              Set(products.compactMap { $0.subscription?.subscriptionGroupID }).count == 1 else {
            throw SharedSubscriptionStoreError.unavailable
        }
        var result: [SharedSubscriptionProduct] = []
        var resolved: [String: Product] = [:]
        for product in products {
            guard let subscription = product.subscription else { throw SharedSubscriptionStoreError.unavailable }
            let period: SharedSubscriptionPeriod
            switch (subscription.subscriptionPeriod.unit, subscription.subscriptionPeriod.value) {
            case (.month, 1): period = .monthly
            case (.year, 1): period = .annual
            default: throw SharedSubscriptionStoreError.unavailable
            }
            resolved[product.id] = product
            result.append(SharedSubscriptionProduct(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                period: period,
                subscriptionGroupID: subscription.subscriptionGroupID
            ))
        }
        guard result.filter({ $0.period == .monthly }).count == 1,
              result.filter({ $0.period == .annual }).count == 1 else {
            throw SharedSubscriptionStoreError.unavailable
        }
        loadedProducts = resolved
        return result.sorted { $0.period == .monthly && $1.period == .annual }
    }

    func purchase(id: String, appAccountToken: UUID) async throws -> SharedSubscriptionPurchaseResult {
        guard let product = loadedProducts[id] else { throw SharedSubscriptionStoreError.unavailable }
        switch try await product.purchase(options: [.appAccountToken(appAccountToken)]) {
        case .success(let verification):
            return .verified(try remember(verification))
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw SharedSubscriptionStoreError.unavailable
        }
    }

    func restore() async throws {
        // Explicit user action only: AppStore.sync can ask the customer to authenticate.
        try await AppStore.sync()
    }

    func transactions() async throws -> [SharedStoreTransaction] {
        var transactions: [String: SharedStoreTransaction] = [:]
        for await verification in Transaction.currentEntitlements {
            let value = try remember(verification)
            transactions[value.id] = value
        }
        for await verification in Transaction.unfinished {
            let value = try remember(verification)
            transactions[value.id] = value
        }
        return transactions.values.sorted { $0.id < $1.id }
    }

    func updates() -> AsyncStream<SharedStoreTransaction> {
        let (stream, continuation) = AsyncStream.makeStream(of: SharedStoreTransaction.self)
        let task = Task {
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { break }
                if let transaction = try? remember(verification) {
                    continuation.yield(transaction)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func finish(transactionID: String) async {
        if unfinished[transactionID] == nil {
            // A Keychain verification may outlive this actor and its in-memory transaction cache.
            for await verification in Transaction.unfinished {
                guard case .verified(let transaction) = verification else { continue }
                if String(transaction.id) == transactionID {
                    unfinished[transactionID] = transaction
                    break
                }
            }
        }
        guard let transaction = unfinished[transactionID] else { return }
        await transaction.finish()
        unfinished[transactionID] = nil
    }

    private func remember(_ verification: VerificationResult<Transaction>) throws -> SharedStoreTransaction {
        guard case .verified(let transaction) = verification else { throw SharedSubscriptionStoreError.unverified }
        let id = String(transaction.id)
        unfinished[id] = transaction
        return SharedStoreTransaction(
            id: id,
            appAccountToken: transaction.appAccountToken,
            productID: transaction.productID,
            signedTransaction: verification.jwsRepresentation
        )
    }
}
