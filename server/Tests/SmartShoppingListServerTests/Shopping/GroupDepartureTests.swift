@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("A departure replay cannot remove a later membership in the same or another group")
    func departureReceiptDoesNotRepeatItsMutation() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let path = "/v1/groups/\(group)/departure"
        let body = AdministrationFixture.departureBody(confirmClosure: false)
        let departed = try await ShoppingFixture.request(
            .POST,
            path,
            member,
            body
        )
        try #require(departed.status == .ok)
        let invitation = try await ShoppingFixture.invitation(group)
        let joined = try await ShoppingFixture.request(
            .POST,
            "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept",
            member,
            .object(["token": .string(invitation.secret)])
        )
        try #require(joined.status == .ok)
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            member,
            body
        )
        #expect(replay.body.string == departed.body.string)
        let sameGroup = try await AdministrationFixture.snapshot(member, group: group)
        #expect(sameGroup["memberCount"] == .integer(2))
        try await ShoppingFixture.depart(member, group: group)
        let newGroup = try await ShoppingFixture.group(member)
        let replayElsewhere = try await ShoppingFixture.request(
            .POST,
            path,
            member,
            body
        )
        #expect(replayElsewhere.body.string == departed.body.string)
        let current = try await AdministrationFixture.snapshot(member, group: newGroup)
        #expect(current["memberCount"] == .integer(1))
    }

    @Test("Closure preserves history and only its exact departure receipt replays after creating another group")
    func closedGroupDepartureRecovery() async throws {
        let owner = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let history = try await AdministrationFixture.seedHistory(owner, group: group)
        let invitation = try await ShoppingFixture.invitation(group)
        let path = "/v1/groups/\(group)/departure"
        let confirmation = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            AdministrationFixture.departureBody(confirmClosure: false)
        )
        #expect(confirmation.status == .conflict)
        #expect(try ShoppingFixture.object(confirmation)["code"] == .string("closure_confirmation_required"))
        let body = AdministrationFixture.departureBody(confirmClosure: true)
        let closed = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            body
        )
        try #require(closed.status == .ok)
        let closedFields = try ShoppingFixture.object(closed)
        #expect(Set(closedFields.keys) == ["userId", "groupId", "leftAt", "groupClosed"])
        #expect(closedFields["groupClosed"] == .bool(true))
        let newGroup = try await ShoppingFixture.group(owner)
        #expect(newGroup != group)
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            body
        )
        #expect(replay.body.string == closed.body.string)
        let foreignReplay = try await ShoppingFixture.request(
            .POST,
            path,
            outsider,
            body
        )
        #expect(foreignReplay.status == .notFound)
        var changed = try APIObject(body, allowed: ["operationId", "confirmClosure"], required: []).values
        changed["confirmClosure"] = .bool(false)
        let reused = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            .object(changed)
        )
        #expect(reused.status == .conflict)
        #expect(try ShoppingFixture.object(reused)["code"] == .string("idempotency_key_reused"))
        let denied = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", owner)
        #expect(denied.status == .notFound)
        let accept = try await ShoppingFixture.request(
            .POST,
            "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept",
            outsider,
            .object(["token": .string(invitation.secret)])
        )
        #expect(accept.status == .notFound)
        let sql = try shoppingSQL(database)
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == history)
        let archived = try #require(try await sql.raw("SELECT * FROM groups WHERE id = \(bind: group)::uuid").first())
        #expect(try archived.decode(column: "administrator_user_id", as: UUID?.self) == nil)
        #expect(try archived.decode(column: "closed_at", as: Date?.self) != nil)
        #expect(try archived.decode(column: "creator_user_id", as: UUID.self) == owner.id)
        let revoked = try #require(try await sql.raw("""
            SELECT revoked_at FROM invitations WHERE id = \(bind: invitation.id)
            """).first())
        #expect(try revoked.decode(column: "revoked_at", as: Date?.self) != nil)
    }

    @Test("Member pagination exposes only business identities and binds the cursor to its resource")
    func memberPagination() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let first = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/members?limit=1", member)
        try #require(first.status == .ok)
        let firstFields = try ShoppingFixture.object(first)
        let cursor = try #require(firstFields["nextCursor"]?.string)
        let last = try await ShoppingFixture.request(
            .GET, "/v1/groups/\(group)/members?limit=1&cursor=\(cursor)", member
        )
        let lastFields = try ShoppingFixture.object(last)
        #expect(lastFields["nextCursor"] == .null)
        guard case .array(let initial) = firstFields["data"], case .array(let final) = lastFields["data"] else {
            throw APIProblem.invalidRequest
        }
        let ids = try (initial + final).map { value -> String in
            guard case .object(let entry) = value else { throw APIProblem.invalidRequest }
            #expect(Set(entry.keys) == ["id", "displayName"])
            return try #require(entry["id"]?.string)
        }
        #expect(Set(ids) == [owner.id.uuidString.lowercased(), member.id.uuidString.lowercased()])
        let wrong = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores?cursor=\(cursor)", owner)
        #expect(wrong.status == .badRequest)
        let denied = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/members", outsider)
        #expect(denied.status == .notFound)
    }
}
