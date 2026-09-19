import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.integration))
struct SharedAPIKeychainTests {
    @Test
    func `Signing out and reopening retain the original unresolved operation and invitation`() async throws {
        let service = "SharedAPIKeychainTests.\(UUID().uuidString)"
        let store = SharedKeychainStore(service: service)
        do {
            let userID = UUID()
            let originalOperationID = UUID()
            let invitation = PendingInvitation(id: UUID(), token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
            let session = SharedSession(
                accessToken: "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSQ",
                tokenType: "Bearer",
                expiresAt: Date(timeIntervalSince1970: 1_792_404_000),
                user: SharedUser(id: userID, displayName: "Alex", group: nil)
            )
            let original = PendingSharedOperation.createGroup(
                userID: userID,
                request: CreateGroupRequest(operationId: originalOperationID, name: "Casa revisada")
            )
            try await store.saveInvitation(invitation)
            try await store.saveSession(session)
            try await store.saveOperation(original)
            try await store.saveSession(nil)

            let reopened = SharedKeychainStore(service: service)
            #expect(try await reopened.loadSession() == nil)
            #expect(try await reopened.loadInvitation() == invitation)
            let unresolved = try #require(try await reopened.loadOperation())
            #expect(unresolved.userID == userID)
            #expect(unresolved.operationID == originalOperationID)
            guard case .createGroup(_, let request) = unresolved else {
                Issue.record("The unresolved create-group operation changed its route")
                try await clear(store)
                return
            }
            #expect(request.name == "Casa revisada")

            // Failed replacement must preserve the original durable intent, not erase it first.
            let oversized = PendingSharedOperation.createGroup(
                userID: userID,
                request: CreateGroupRequest(operationId: UUID(), name: String(repeating: "a", count: 513 * 1_024))
            )
            await #expect(throws: SharedCredentialError.tooLarge) {
                try await reopened.saveOperation(oversized)
            }
            #expect(try await reopened.loadOperation() == original)

            try await reopened.saveOperation(nil)
            #expect(try await store.loadOperation() == nil)
            #expect(try await store.loadInvitation() == invitation)
        } catch {
            try? await clear(store)
            throw error
        }
        try await clear(store)
    }

    private func clear(_ store: SharedKeychainStore) async throws {
        try await store.saveSession(nil)
        try await store.saveInvitation(nil)
        try await store.saveOperation(nil)
    }
}
