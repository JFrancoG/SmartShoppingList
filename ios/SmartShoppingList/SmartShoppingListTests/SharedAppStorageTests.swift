import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.integration))
struct SharedAppStorageTests {
    @Test
    func `Changing backend keeps credentials and unresolved work in their original namespace`() async throws {
        let host = "\(UUID().uuidString.lowercased()).test"
        let first = try SharedAPIConfiguration(baseURL: "https://\(host)", invitationOrigin: "https://\(host)")
        let other = try SharedAPIConfiguration(baseURL: "https://\(host)", invitationOrigin: "https://links.\(host)")
        let equivalent = try SharedAPIConfiguration(
            baseURL: "https://\(host.uppercased()):443/",
            invitationOrigin: "https://\(host):443/"
        )
        let original = SharedKeychainStore(service: SharedAppStorage(configuration: first).keychainService)
        let isolated = SharedKeychainStore(service: SharedAppStorage(configuration: other).keychainService)
        let reopened = SharedKeychainStore(service: SharedAppStorage(configuration: equivalent).keychainService)
        let fixture = try SharedPreviewFixture.sample()
        let invitation = PendingInvitation(id: UUID(), token: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let operation = PendingSharedOperation.createGroup(
            userID: fixture.session.user.id,
            request: CreateGroupRequest(operationId: UUID(), name: "Unresolved original group")
        )
        let verification = PendingSubscriptionVerification(
            userID: fixture.session.user.id,
            transactionID: "original-transaction",
            request: VerifySharedSubscriptionRequest(signedTransaction: "original-signed-evidence")
        )
        do {
            try await original.saveSession(fixture.session)
            try await original.saveInvitation(invitation)
            try await original.saveIncomingInvitation(invitation)
            try await original.saveOperation(operation)
            try await original.saveSubscriptionVerification(verification)

            #expect(try await isolated.loadSession() == nil)
            #expect(try await isolated.loadInvitation() == nil)
            #expect(try await isolated.loadIncomingInvitation() == nil)
            #expect(try await isolated.loadOperation() == nil)
            #expect(try await isolated.loadSubscriptionVerification() == nil)
            try await isolated.saveSession(fixture.session)
            try await isolated.saveOperation(operation)
            try await clear(isolated)

            #expect(try await reopened.loadSession() == fixture.session)
            #expect(try await reopened.loadInvitation() == invitation)
            #expect(try await reopened.loadIncomingInvitation() == invitation)
            #expect(try await reopened.loadOperation() == operation)
            #expect(try await reopened.loadSubscriptionVerification() == verification)
        } catch {
            try? await clear(original)
            try? await clear(isolated)
            throw error
        }
        try await clear(original)
    }

    @Test
    func `Sandbox and missing configuration cannot import or replace a legacy production draft`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SharedAppStorageTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appending(path: "SmartShoppingList/draft-v1.json")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = Data(#"{"text":"Original production draft","items":[]}"#.utf8)
        try legacy.write(to: legacyURL)
        let production = try SharedAPIConfiguration(
            baseURL: "https://smartshoppinglist-production.up.railway.app",
            invitationOrigin: "https://smartshoppinglist-production.up.railway.app"
        )
        let sandbox = try SharedAPIConfiguration(
            baseURL: "https://smartshoppinglistsandbox-sandbox.up.railway.app",
            invitationOrigin: "https://smartshoppinglistsandbox-sandbox.up.railway.app"
        )
        let original = SharedAppStorage(configuration: production, supportDirectory: directory)
        let isolated = SharedAppStorage(configuration: sandbox, supportDirectory: directory)
        let unconfigured = SharedAppStorage(configuration: nil, supportDirectory: directory)
        #expect(original.keychainService == "com.plusprojects.SmartShoppingList.shared-v1")
        let productionDraft = FileDraftPersistence(fileURL: original.draftFileURL)
        #expect(try await productionDraft.load()?.text == "Original production draft")
        let sandboxDraft = FileDraftPersistence(fileURL: isolated.draftFileURL)
        let missingDraft = FileDraftPersistence(fileURL: unconfigured.draftFileURL)
        #expect(try await sandboxDraft.load() == nil)
        #expect(try await missingDraft.load() == nil)
        try await sandboxDraft.save(ShoppingDraftSnapshot(text: "Sandbox draft", items: []))
        try await missingDraft.save(ShoppingDraftSnapshot(text: "Unconfigured draft", items: []))
        #expect(try Data(contentsOf: legacyURL) == legacy)
        let reopened = SharedAppStorage(configuration: sandbox, supportDirectory: directory)
        let restored = FileDraftPersistence(fileURL: reopened.draftFileURL)
        #expect(try await restored.load()?.text == "Sandbox draft")
        #expect(try await missingDraft.load()?.text == "Unconfigured draft")
    }

    private func clear(_ store: SharedKeychainStore) async throws {
        try await store.saveSession(nil)
        try await store.saveInvitation(nil)
        if let incoming = try await store.loadIncomingInvitation() {
            _ = try await store.clearIncomingInvitation(matching: incoming)
        }
        try await store.saveOperation(nil)
        try await store.saveSubscriptionVerification(nil)
    }
}
