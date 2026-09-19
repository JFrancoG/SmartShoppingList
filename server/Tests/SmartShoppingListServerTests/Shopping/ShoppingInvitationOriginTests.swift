@testable import SmartShoppingListServer
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test(arguments: ["https://links.test", "https://links.test/"])
    func `configured HTTPS origins create usable canonical invitation links`(origin: String) async throws {
        let databases = try testDatabases
        let authentication = AppleAuthenticationService(
            databases: databases, gateway: UnconfiguredAppleGateway(), vault: nil
        )
        try app.grouped("origin-test").register(collection: ShoppingRoutes(
            databases: databases, authentication: authentication, invitationOrigin: origin
        ))
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let created = try await ShoppingFixture.request(
            .POST, "/origin-test/v1/groups/\(group)/invitations", owner, .object([:])
        )
        try #require(created.status == .created)
        let fields = try ShoppingFixture.object(created)
        let link = try #require(fields["url"]?.string)
        let components = try #require(URLComponents(string: link))
        let invitation = try APIObject(
            try #require(fields["invitation"]),
            allowed: ["id", "groupId", "createdAt", "expiresAt", "revokedAt", "acceptedAt", "acceptedBy"],
            required: ["id"]
        )
        let identifier = try invitation.string("id")
        #expect(components.scheme == "https")
        #expect(components.host == "links.test")
        #expect(components.path == "/invite/\(identifier)")
        let fragment = try #require(components.fragment)
        try #require(fragment.hasPrefix("token="))
        let accepted = try await ShoppingFixture.request(
            .POST, "/v1/invitations/\(identifier)/accept", recipient,
            .object(["token": .string(String(fragment.dropFirst(6)))])
        )
        #expect(accepted.status == .ok)
        #expect(try ShoppingFixture.object(accepted)["id"] == .string(group))
        let persisted = try await ShoppingFixture.request(.GET, "/v1/me", recipient)
        guard case .object(let membership) = try ShoppingFixture.object(persisted)["group"] else {
            Issue.record("The generated invitation did not persist membership")
            return
        }
        #expect(membership["id"] == .string(group))
    }
}
