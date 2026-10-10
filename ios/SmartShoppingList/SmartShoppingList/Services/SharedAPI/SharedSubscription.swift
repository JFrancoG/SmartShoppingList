import Foundation

struct SharedSubscriptionStatus: Codable, Equatable {
    let appAccountToken: UUID
    let isConfigured: Bool
    let productIDs: [String]
    let state: SharedSubscriptionState
    let expiresAt: Date?
    let gracePeriodExpiresAt: Date?
    let autoRenewEnabled: Bool?
    let verifiedAt: Date?
}

extension SharedSubscriptionStatus {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appAccountToken = try values.decode(UUID.self, forKey: .appAccountToken)
        isConfigured = try values.decode(Bool.self, forKey: .isConfigured)
        productIDs = try values.decode([String].self, forKey: .productIDs)
        state = try values.decode(SharedSubscriptionState.self, forKey: .state)
        expiresAt = try values.decode(Date?.self, forKey: .expiresAt)
        gracePeriodExpiresAt = try values.decode(Date?.self, forKey: .gracePeriodExpiresAt)
        autoRenewEnabled = try values.decode(Bool?.self, forKey: .autoRenewEnabled)
        verifiedAt = try values.decode(Date?.self, forKey: .verifiedAt)
        guard productIDs.count <= 2, Set(productIDs).count == productIDs.count,
              productIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 }),
              isConfigured || productIDs.isEmpty,
              state != .subscribed || (expiresAt != nil && verifiedAt != nil),
              state != .inGracePeriod || (gracePeriodExpiresAt != nil && verifiedAt != nil) else {
            throw SharedAPIError.invalidResponse
        }
    }

    private enum CodingKeys: String, CodingKey {
        case appAccountToken, isConfigured, productIDs, state, expiresAt, gracePeriodExpiresAt
        case autoRenewEnabled, verifiedAt
    }
}

enum SharedSubscriptionState: String, Codable {
    case free, subscribed, expired, revoked
    case inGracePeriod = "in_grace_period"
}

struct VerifySharedSubscriptionRequest: Codable, Equatable {
    let signedTransaction: String
}

struct SharedSubscriptionAcknowledgement: Decodable, Equatable {
    let subscription: SharedSubscriptionStatus
    let acknowledgedTransactionId: String
}

/// A separate Keychain value: restoring a purchase never overwrites a saved shopping submission.
struct PendingSubscriptionVerification: Codable, Equatable {
    let userID: UUID
    let transactionID: String
    let request: VerifySharedSubscriptionRequest
}

protocol SharedSubscriptionCredentialStoring: Sendable {
    func loadSubscriptionVerification() async throws -> PendingSubscriptionVerification?
    func saveSubscriptionVerification(_ verification: PendingSubscriptionVerification?) async throws
}

protocol SharedSubscriptionAPI: Sendable {
    func subscription(token: String) async throws -> SharedSubscriptionStatus
    func verifySubscription(
        _ request: VerifySharedSubscriptionRequest,
        token: String
    ) async throws -> SharedSubscriptionAcknowledgement
}
