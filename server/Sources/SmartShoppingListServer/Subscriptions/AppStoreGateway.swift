import Foundation

protocol AppStoreGateway: Sendable {
    var configuration: AppStoreConfiguration? { get }
    func verifyTransaction(_ signed: String) async throws -> AppStoreTransaction
    func subscriptionStates(originalTransactionID: String) async throws -> [VerifiedAppStoreSubscription]
    func verifyNotification(_ signed: String) async throws -> AppStoreNotification
}

struct UnconfiguredAppStoreGateway: AppStoreGateway {
    var configuration: AppStoreConfiguration? { nil }

    func verifyTransaction(_ signed: String) async throws -> AppStoreTransaction {
        throw AppStoreGatewayError.unavailable
    }

    func subscriptionStates(originalTransactionID: String) async throws -> [VerifiedAppStoreSubscription] {
        throw AppStoreGatewayError.unavailable
    }

    func verifyNotification(_ signed: String) async throws -> AppStoreNotification {
        throw AppStoreGatewayError.unavailable
    }
}

struct LiveAppStoreGateway: AppStoreGateway {
    let configuration: AppStoreConfiguration?
    private let verifier: AppStoreSignedDataVerifier
    private let transport: any AppStoreHTTPTransport
    private let now: @Sendable () -> Date

    init(
        configuration: AppStoreConfiguration,
        transport: any AppStoreHTTPTransport = AppStoreURLSessionTransport(),
        verifier suppliedVerifier: AppStoreSignedDataVerifier? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.configuration = configuration
        self.transport = transport
        self.now = now
        verifier = try suppliedVerifier ?? .live(transport: transport)
    }

    /// The historical client JWS only locates the purchase. Apple's response must independently confirm it.
    func verifyTransaction(_ signed: String) async throws -> AppStoreTransaction {
        let located = try await verifier.verify(signed, as: AppStoreTransaction.self, online: false)
        try validate(located)
        let response: TransactionResponse = try await get("/inApps/v1/transactions/" + located.transactionId)
        let current = try await verifier.verify(
            response.signedTransactionInfo,
            as: AppStoreTransaction.self,
            online: true
        )
        try validate(current)
        guard current.transactionId == located.transactionId,
              current.originalTransactionId == located.originalTransactionId,
              current.appAccountToken == located.appAccountToken
        else {
            throw AppStoreGatewayError.rejected
        }
        return current
    }

    func subscriptionStates(originalTransactionID: String) async throws -> [VerifiedAppStoreSubscription] {
        guard AppStoreTransaction.isTransactionID(originalTransactionID), let configuration else {
            throw AppStoreGatewayError.rejected
        }
        let response: StatusResponse = try await get("/inApps/v1/subscriptions/" + originalTransactionID)
        guard response.bundleId == configuration.bundleID, response.environment == configuration.environment,
              response.appAppleId == configuration.appAppleID
                  || configuration.environment == .sandbox && response.appAppleId == nil,
              response.data.count <= 32
        else {
            throw AppStoreGatewayError.rejected
        }
        var result: [VerifiedAppStoreSubscription] = []
        for group in response.data {
            guard group.subscriptionGroupIdentifier == configuration.subscriptionGroupID else { continue }
            guard group.lastTransactions.count <= 32 else { throw AppStoreGatewayError.rejected }
            for item in group.lastTransactions {
                // Ignore unrelated products only after authenticating their Apple-signed representation.
                let transaction = try await verifier.verify(
                    item.signedTransactionInfo,
                    as: AppStoreTransaction.self,
                    online: true
                )
                guard configuration.productIDs.contains(transaction.productId) else { continue }
                try validate(transaction)
                let renewal = try await verifier.verify(item.signedRenewalInfo, as: AppStoreRenewal.self, online: true)
                guard item.originalTransactionId == transaction.originalTransactionId,
                      renewal.originalTransactionId == transaction.originalTransactionId,
                      renewal.environment == configuration.environment,
                      renewal.appAccountToken == nil || renewal.appAccountToken == transaction.appAccountToken,
                      configuration.productIDs.contains(renewal.productId),
                      (1...5).contains(item.status), renewal.signedDate <= now().addingTimeInterval(300),
                      item.status != 4 || renewal.gracePeriodExpiresDate != nil
                else {
                    throw AppStoreGatewayError.rejected
                }
                result.append(.init(transaction: transaction, renewal: renewal, status: item.status))
            }
        }
        guard result.contains(where: { $0.transaction.originalTransactionId == originalTransactionID }) else {
            throw AppStoreGatewayError.unavailable
        }
        return result
    }

    func verifyNotification(_ signed: String) async throws -> AppStoreNotification {
        let envelope = try await verifier.verify(signed, as: AppStoreNotification.self, online: true)
        guard let configuration, let data = envelope.data,
              data.bundleId == configuration.bundleID, data.environment == configuration.environment,
              data.appAppleId == configuration.appAppleID
                  || configuration.environment == .sandbox && data.appAppleId == nil,
              envelope.signedDate <= now().addingTimeInterval(300)
        else {
            throw AppStoreGatewayError.rejected
        }
        return envelope
    }

    private func validate(_ transaction: AppStoreTransaction) throws {
        guard let configuration, transaction.bundleId == configuration.bundleID,
              transaction.environment == configuration.environment,
              configuration.productIDs.contains(transaction.productId), transaction.appAccountToken != nil,
              transaction.subscriptionGroupIdentifier == configuration.subscriptionGroupID,
              transaction.signedDate <= now().addingTimeInterval(300)
        else {
            throw AppStoreGatewayError.rejected
        }
    }

    private func get<Result: Decodable>(_ path: String) async throws -> Result {
        guard let configuration else { throw AppStoreGatewayError.unavailable }
        do {
            let token = try await configuration.authorization(now: now())
            let response = try await transport.get(
                path: path,
                authorization: token,
                environment: configuration.environment
            )
            guard response.status != 404 else { throw AppStoreGatewayError.rejected }
            guard response.status == 200 else { throw AppStoreGatewayError.unavailable }
            return try JSONDecoder().decode(Result.self, from: response.body)
        } catch let error as AppStoreGatewayError {
            throw error
        } catch {
            throw AppStoreGatewayError.unavailable
        }
    }

    private struct TransactionResponse: Decodable {
        let signedTransactionInfo: String
    }

    private struct StatusResponse: Decodable {
        let bundleId: String
        let environment: AppStoreEnvironment
        let appAppleId: Int64?
        let data: [StatusGroup]
    }

    private struct StatusGroup: Decodable {
        let subscriptionGroupIdentifier: String
        let lastTransactions: [LastTransaction]
    }

    private struct LastTransaction: Decodable {
        let originalTransactionId: String
        let status: Int
        let signedTransactionInfo: String
        let signedRenewalInfo: String
    }
}
