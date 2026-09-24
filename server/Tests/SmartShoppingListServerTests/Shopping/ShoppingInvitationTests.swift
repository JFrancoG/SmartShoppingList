@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test
    func `creating an invitation returns its secret once and metadata never reveals it`() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let path = "/v1/groups/\(group)/invitations"
        let created = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            .object([:])
        )
        try #require(created.status == .created)
        let value = try ShoppingFixture.object(created)
        let link = try #require(value["url"]?.string)
        let fragment = try #require(URLComponents(string: link)?.fragment)
        try #require(fragment.hasPrefix("token="))
        let secret = String(fragment.dropFirst(6))
        #expect(secret.utf8.count == 43)
        let listed = try await ShoppingFixture.request(.GET, path, owner)
        try #require(listed.status == .ok)
        #expect(!listed.body.string.contains(secret))
        #expect(!listed.body.string.contains("secret_hash"))
        guard case .array(let metadata) = try ShoppingFixture.object(listed)["invitations"] else {
            Issue.record("Invitation metadata is missing")
            return
        }
        #expect(metadata.count == 1)
    }

    @Test
    func `invitation acceptance is one use and the same member can recover after expiry`() async throws {
        let creator = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(creator)
        let invitation = try await ShoppingFixture.invitation(group)
        let path = "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept"
        let body: APIJSON = .object(["token": .string(invitation.secret)])
        let preview = try await ShoppingFixture.request(
            .POST,
            "/v1/invitations/\(invitation.id.uuidString.lowercased())/preview",
            member,
            body
        )
        #expect(preview.status == .ok)
        let before = try await ShoppingFixture.request(.GET, "/v1/me", member)
        #expect(try ShoppingFixture.object(before)["group"] == .null)
        let accepted = try await ShoppingFixture.request(
            .POST,
            path,
            member,
            body
        )
        try #require(accepted.status == .ok)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            UPDATE invitations SET created_at = clock_timestamp()-INTERVAL '2 days',
                expires_at = clock_timestamp()-INTERVAL '1 day' WHERE id = \(bind: invitation.id)
            """).run()
        let retry = try await ShoppingFixture.request(
            .POST,
            path,
            member,
            body
        )
        #expect(retry.body.string == accepted.body.string)
        let other = try await ShoppingFixture.request(
            .POST,
            path,
            outsider,
            body
        )
        #expect(other.status == .gone)
        #expect(try ShoppingFixture.object(other)["code"] == .string("invitation_consumed"))
        let recovered = try await ShoppingFixture.request(.GET, "/v1/me", member)
        guard case .object(let shared) = try ShoppingFixture.object(recovered)["group"] else {
            Issue.record("Accepted membership was not persisted")
            return
        }
        #expect(shared["id"] == .string(group))
    }

    @Test
    func `a user already in another group does not consume an invitation`() async throws {
        let owner = try await ShoppingFixture.user()
        let grouped = try await ShoppingFixture.user()
        let free = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let originalGroup = try await ShoppingFixture.group(grouped)
        let invitation = try await ShoppingFixture.invitation(group)
        let body: APIJSON = .object(["token": .string(invitation.secret)])
        let path = "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept"
        let denied = try await ShoppingFixture.request(
            .POST,
            path,
            grouped,
            body
        )
        #expect(denied.status == .conflict)
        #expect(try ShoppingFixture.object(denied)["code"] == .string("already_in_group"))
        let accepted = try await ShoppingFixture.request(
            .POST,
            path,
            free,
            body
        )
        #expect(accepted.status == .ok)
        #expect(try ShoppingFixture.object(accepted)["id"] == .string(group))
        let unaffected = try await ShoppingFixture.request(.GET, "/v1/me", grouped)
        guard case .object(let unchanged) = try ShoppingFixture.object(unaffected)["group"] else {
            Issue.record("Original group is missing")
            return
        }
        #expect(unchanged["id"] == .string(originalGroup))
    }

    @Test
    func `invitation revocation is creator only and hides state from incorrect secrets`() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let invitation = try await ShoppingFixture.invitation(group)
        let path = "/v1/groups/\(group)/invitations/\(invitation.id.uuidString.lowercased())"
        let denied = try await ShoppingFixture.request(.DELETE, path, member)
        #expect(denied.status == .forbidden)
        let revoked = try await ShoppingFixture.request(.DELETE, path, owner)
        #expect(revoked.status == .noContent)
        let retry = try await ShoppingFixture.request(.DELETE, path, owner)
        #expect(retry.status == .noContent)
        let previewPath = "/v1/invitations/\(invitation.id.uuidString.lowercased())/preview"
        let authentic = try await ShoppingFixture.request(
            .POST, previewPath, outsider, .object(["token": .string(invitation.secret)])
        )
        #expect(authentic.status == .gone)
        #expect(try ShoppingFixture.object(authentic)["code"] == .string("invitation_revoked"))
        let wrong = try await ShoppingFixture.request(
            .POST, previewPath, outsider, .object(["token": .string(ShoppingSecret.generate())])
        )
        #expect(wrong.status == .notFound)
        #expect(try ShoppingFixture.object(wrong)["code"] == .string("not_found"))
    }

    @Test
    func `expired invitations cannot assign a group`() async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let invitation = try await ShoppingFixture.invitation(group)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            UPDATE invitations SET created_at = clock_timestamp()-INTERVAL '2 days',
                expires_at = clock_timestamp()-INTERVAL '1 day' WHERE id = \(bind: invitation.id)
            """).run()
        let response = try await ShoppingFixture.request(
            .POST, "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept", recipient,
            .object(["token": .string(invitation.secret)])
        )
        #expect(response.status == .gone)
        #expect(try ShoppingFixture.object(response)["code"] == .string("invitation_expired"))
        let user = try await ShoppingFixture.request(.GET, "/v1/me", recipient)
        #expect(try ShoppingFixture.object(user)["group"] == .null)
    }
}

extension ShoppingFixture {
    struct Invitation: Sendable {
        let id: UUID
        let secret: String
    }

    static func invitation(_ group: String) async throws -> Invitation {
        let sql = try shoppingSQL(database)
        let id = UUID()
        let secret = ShoppingSecret.generate()
        let hash = ShoppingSecret.hash(secret)
        try await sql.raw("""
            INSERT INTO invitations(id,group_id,secret_hash,created_at,expires_at)
            VALUES (\(bind: id),\(bind: group)::uuid,\(bind: hash),clock_timestamp(),clock_timestamp()+INTERVAL '1 day')
            """).run()
        return Invitation(id: id, secret: secret)
    }
}
