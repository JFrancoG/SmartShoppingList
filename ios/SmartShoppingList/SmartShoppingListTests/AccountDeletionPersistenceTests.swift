import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.integration))
struct AccountDeletionPersistenceTests {
    @Test
    func `Deletion receipt and recovery proof reopen in their original environment only`() async throws {
        let prefix = "DeletionPersistence.\(UUID().uuidString)"
        let sandbox = SharedKeychainStore(service: "\(prefix).sandbox")
        let production = SharedKeychainStore(service: "\(prefix).production")
        let userID = UUID()
        let receipt = PendingAccountDeletion(
            userID: userID,
            receipt: SharedDeletionReceipt(operationId: UUID(), statusSecret: "test-status-secret"),
            revision: "revision", submitted: true
        )
        let proof = PendingSubscriptionRecovery(
            userID: userID, transactionID: "test-transaction", environment: .sandbox,
            keyID: "test-key", signedTransaction: "test-jws",
            request: SharedRecoveryRequest(
                challengeId: UUID(), keyId: "test-key", attestation: "test-attestation", signedTransaction: "test-jws"
            )
        )
        do {
            try await sandbox.saveAccountDeletion(receipt)
            try await sandbox.saveDeletedAccountUserID(userID)
            try await sandbox.saveSubscriptionRecovery(proof)
            try await sandbox.saveSession(nil)
            let reopened = SharedKeychainStore(service: "\(prefix).sandbox")
            #expect(try await reopened.loadAccountDeletion() == receipt)
            #expect(try await reopened.loadDeletedAccountUserID() == userID)
            #expect(try await production.loadDeletedAccountUserID() == nil)
            #expect(try await reopened.loadSubscriptionRecovery() == proof)
            #expect(try await production.loadAccountDeletion() == nil)
            #expect(try await production.loadSubscriptionRecovery() == nil)
            try await reopened.saveAccountDeletion(nil)
            #expect(try await sandbox.loadSubscriptionRecovery() == proof)
        } catch {
            try? await sandbox.saveDeletedAccountUserID(nil)
            try? await sandbox.saveAccountDeletion(nil)
            try? await sandbox.saveSubscriptionRecovery(nil)
            throw error
        }
        try await sandbox.saveDeletedAccountUserID(nil)
        try await sandbox.saveAccountDeletion(nil)
        try await sandbox.saveSubscriptionRecovery(nil)
    }
}
