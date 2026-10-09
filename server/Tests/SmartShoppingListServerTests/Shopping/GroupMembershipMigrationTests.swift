@testable import SmartShoppingListServer
import FluentKit
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Membership migration preserves every existing domain row and exact legacy receipts")
    func membershipMigrationPreservesHistory() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let creation = MembershipFixture.creationBody()
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            owner,
            creation
        )
        let group = try #require(try ShoppingFixture.object(response)["id"]?.string)
        try await ShoppingFixture.join(member, group: group)
        _ = try await AdministrationFixture.seedHistory(owner, group: group)
        _ = try await ShoppingFixture.invitation(group)
        _ = try await AdministrationFixture.propose(owner, recipient: member, group: group)
        let former = try await ShoppingFixture.user()
        let closed = try await ShoppingFixture.group(former)
        _ = try await MembershipFixture.depart(former, group: closed)
        let sql = try shoppingSQL(database)
        // Model the previously deployed receipt shape. Migration must never normalize its bytes.
        try await sql.raw("""
            UPDATE mutation_receipts SET body = (body::jsonb - 'administratorUserId')::text
            WHERE user_id = \(bind: owner.id) AND operation_type = 'createGroup'
            """).run()
        let receipt = try #require(try await sql.raw("""
            SELECT body FROM mutation_receipts WHERE user_id = \(bind: owner.id) AND operation_type = 'createGroup'
            """).first()).decode(column: "body", as: String.self)
        try await AddStoreArchiving().revert(on: database)
        try await AddGroupMemberships().revert(on: database)
        let before = try await MembershipMigrationFixture.snapshot()
        try await AddGroupMemberships().prepare(on: database)
        #expect(try await MembershipMigrationFixture.snapshot() == before)
        try await AddStoreArchiving().prepare(on: database)
        let memberships = try await sql.raw("SELECT user_id FROM group_memberships").all()
        #expect(Set(try memberships.map { try $0.decode(column: "user_id", as: UUID.self) }) == [owner.id, member.id])
        let own = try await ShoppingFixture.request(.GET, "/v1/groups", owner)
        #expect(try MembershipFixture.groupIDs(own) == [group])
        let replay = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            owner,
            creation
        )
        #expect(replay.status == .created)
        #expect(replay.body.string == receipt)
        let closedGroups = try await ShoppingFixture.request(.GET, "/v1/groups", former)
        #expect(try MembershipFixture.groupIDs(closedGroups).isEmpty)
    }

    @Test(
        "A lossy singular rollback fails before modifying data or authorization",
        arguments: ["multiple", "missing", "phantom"]
    )
    func membershipRollbackRejectsUnrepresentableState(scenario: String) async throws {
        let owner = try await ShoppingFixture.user()
        let other = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let sql = try shoppingSQL(database)
        switch scenario {
        case "multiple":
            let second = try await ShoppingFixture.group(other)
            try await ShoppingFixture.join(owner, group: second)
        case "missing":
            try await sql.raw("UPDATE users SET group_id = NULL WHERE id = \(bind: owner.id)").run()
        default:
            try await sql.raw("UPDATE users SET group_id = \(bind: group)::uuid WHERE id = \(bind: other.id)").run()
        }
        let before = try await MembershipMigrationFixture.snapshot(includeMemberships: true)
        await #expect(throws: AddGroupMemberships.ReversionError.multipleMembershipsCannotBeRepresented) {
            try await AddGroupMemberships().revert(on: database)
        }
        #expect(try await MembershipMigrationFixture.snapshot(includeMemberships: true) == before)
        let accessible = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", owner)
        #expect(accessible.status == .ok)
        if scenario == "phantom" {
            let denied = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", other)
            #expect(denied.status == .notFound)
            let me = try await ShoppingFixture.request(.GET, "/v1/me", other)
            #expect(try MembershipFixture.legacyGroup(me) == nil)
        }
    }
}

private enum MembershipMigrationFixture {
    static func snapshot(includeMemberships: Bool = false) async throws -> [String: [String]] {
        let sql = try shoppingSQL(database)
        var result: [String: [String]] = [:]
        let tables = [
            "users", "groups", "stores", "items", "invitations", "group_administration_transfers", "mutation_receipts"
        ] + (includeMemberships ? ["group_memberships"] : [])
        for table in tables {
            let rows = try await sql.raw("""
                SELECT to_jsonb(record)::text AS snapshot FROM \(ident: table) AS record ORDER BY snapshot
                """).all()
            result[table] = try rows.map { try $0.decode(column: "snapshot", as: String.self) }
        }
        return result
    }
}
