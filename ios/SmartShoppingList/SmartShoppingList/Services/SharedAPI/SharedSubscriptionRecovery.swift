import CryptoKit
import DeviceCheck
import Foundation

protocol SharedSubscriptionRecoveryAPI: Sendable {
    func subscriptionRecoveryChallenge(_ request: SharedRecoveryChallengeRequest, token: String) async throws -> SharedRecoveryChallenge
    func recoverSubscription(_ request: SharedRecoveryRequest, token: String) async throws -> SharedSubscriptionAcknowledgement
}

struct SharedRecoveryChallengeRequest: Encodable {
    let signedTransaction: String
    let keyId: String
}

struct SharedRecoveryChallenge: Codable, Equatable {
    let id: UUID
    let nonce: String
    let expiresAt: Date
    let clientDataHash: String
    let appAccountToken: UUID
    let environment: String

    func verifiedHash(userID: UUID, keyID: String, transaction: String, storeEnvironment: SharedStoreEnvironment) throws -> Data {
        let expectedEnvironment = switch storeEnvironment {
        case .sandbox: "Sandbox"
        case .production: "Production"
        case .xcode, .unknown: ""
        }
        guard !expectedEnvironment.isEmpty, environment == expectedEnvironment, appAccountToken == userID,
              !nonce.isEmpty, nonce.utf8.count <= 256, expiresAt > Date() else { throw SharedAPIError.invalidResponse }
        let transactionHash = SHA256.hash(data: Data(transaction.utf8)).map { String(format: "%02x", $0) }.joined()
        let canonical = [
            "smartlist.subscription-recovery.v1", id.uuidString.lowercased(), userID.uuidString.lowercased(),
            environment, keyID, nonce, transactionHash
        ].joined(separator: "\n")
        let expected = Data(SHA256.hash(data: Data(canonical.utf8)))
        guard Data(base64Encoded: clientDataHash) == expected else { throw SharedAPIError.invalidResponse }
        return expected
    }
}

struct SharedRecoveryRequest: Codable, Equatable {
    let challengeId: UUID
    let keyId: String
    let attestation: String
    let signedTransaction: String

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(challengeId.uuidString.lowercased(), forKey: .challengeId)
        try values.encode(keyId, forKey: .keyId)
        try values.encode(attestation, forKey: .attestation)
        try values.encode(signedTransaction, forKey: .signedTransaction)
    }
}

struct PendingSubscriptionRecovery: Codable, Equatable {
    let userID: UUID
    let transactionID: String
    let environment: SharedStoreEnvironment
    let keyID: String
    let signedTransaction: String
    var challenge: SharedRecoveryChallenge?
    var request: SharedRecoveryRequest?
}

protocol SharedSubscriptionRecoveryStoring: Sendable {
    func loadSubscriptionRecovery() async throws -> PendingSubscriptionRecovery?
    func saveSubscriptionRecovery(_ recovery: PendingSubscriptionRecovery?) async throws
}

@MainActor
protocol SharedRecoveryAttesting {
    func generateKey() async throws -> String
    func attest(keyID: String, hash: Data) async throws -> Data
}

struct AppleSubscriptionRecoveryAttester: SharedRecoveryAttesting {
    func generateKey() async throws -> String {
        guard DCAppAttestService.shared.isSupported else { throw SharedSubscriptionStoreError.unavailable }
        return try await DCAppAttestService.shared.generateKey()
    }

    func attest(keyID: String, hash: Data) async throws -> Data {
        guard DCAppAttestService.shared.isSupported else { throw SharedSubscriptionStoreError.unavailable }
        return try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: hash)
    }
}
