import Foundation
import JWTKit

enum AppStoreGatewayError: Error, Equatable {
    case invalidConfiguration
    case rejected
    case unavailable
}

enum SubscriptionState: String, Codable, Sendable {
    case free
    case subscribed
    case inGracePeriod = "in_grace_period"
    case expired
    case revoked
}

struct AppStoreTransaction: ValidationTimePayload {
    let transactionId: String
    let originalTransactionId: String
    let bundleId: String
    let productId: String
    let environment: AppStoreEnvironment
    let appAccountToken: UUID?
    let type: String
    let inAppOwnershipType: String
    let purchaseDate: Date
    let expiresDate: Date?
    let revocationDate: Date?
    let signedDate: Date
    var subscriptionGroupIdentifier: String? = nil

    func verify(using algorithm: some JWTAlgorithm) throws {
        guard algorithm.name == "ES256", Self.isTransactionID(transactionId),
              Self.isTransactionID(originalTransactionId), type == "Auto-Renewable Subscription",
              inAppOwnershipType == "PURCHASED",
              !bundleId.isEmpty, !productId.isEmpty, expiresDate != nil, purchaseDate <= signedDate
        else {
            throw AppStoreGatewayError.rejected
        }
    }

    static func isTransactionID(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count) && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

struct AppStoreRenewal: ValidationTimePayload {
    let originalTransactionId: String
    let appAccountToken: UUID?
    let productId: String
    let environment: AppStoreEnvironment
    let autoRenewStatus: Int
    let gracePeriodExpiresDate: Date?
    let signedDate: Date

    func verify(using algorithm: some JWTAlgorithm) throws {
        guard algorithm.name == "ES256", AppStoreTransaction.isTransactionID(originalTransactionId),
              [0, 1].contains(autoRenewStatus), !productId.isEmpty
        else {
            throw AppStoreGatewayError.rejected
        }
    }
}

struct AppStoreNotification: ValidationTimePayload {
    let notificationUUID: UUID
    let notificationType: String
    let signedDate: Date
    let data: NotificationData?

    struct NotificationData: Codable, Sendable {
        let bundleId: String
        let appAppleId: Int64?
        let environment: AppStoreEnvironment
        let signedTransactionInfo: String?
        let signedRenewalInfo: String?
    }

    func verify(using algorithm: some JWTAlgorithm) throws {
        guard algorithm.name == "ES256", !notificationType.isEmpty else { throw AppStoreGatewayError.rejected }
    }
}

/// A coherent current snapshot from Apple's authenticated status endpoint, with both JWS values verified.
struct VerifiedAppStoreSubscription: Sendable {
    let transaction: AppStoreTransaction
    let renewal: AppStoreRenewal
    let status: Int

    var revision: Date { max(transaction.signedDate, renewal.signedDate) }
    var isRevoked: Bool { status == 5 || transaction.revocationDate != nil }
    var expiry: Date {
        max(transaction.expiresDate ?? transaction.purchaseDate, renewal.gracePeriodExpiresDate ?? .distantPast)
    }
    var state: SubscriptionState {
        if isRevoked {
            return .revoked
        }
        return status == 4 ? .inGracePeriod : (status == 1 ? .subscribed : .expired)
    }
    var premiumUntil: Date? {
        guard !isRevoked else { return nil }
        switch status {
        case 1: return transaction.expiresDate
        case 4: return renewal.gracePeriodExpiresDate
        default: return nil
        }
    }
}

struct SubscriptionStatus: Codable, Sendable {
    let appAccountToken: UUID
    let isConfigured: Bool
    let productIDs: [String]
    let state: SubscriptionState
    let expiresAt: String?
    let gracePeriodExpiresAt: String?
    let autoRenewEnabled: Bool?
    let verifiedAt: String?

    var json: APIJSON {
        .object([
            "appAccountToken": .string(appAccountToken.uuidString.lowercased()),
            "isConfigured": .bool(isConfigured), "productIDs": .array(productIDs.map(APIJSON.string)),
            "state": .string(state.rawValue), "expiresAt": .optional(expiresAt),
            "gracePeriodExpiresAt": .optional(gracePeriodExpiresAt),
            "autoRenewEnabled": autoRenewEnabled.map(APIJSON.bool) ?? .null,
            "verifiedAt": .optional(verifiedAt)
        ])
    }
}
