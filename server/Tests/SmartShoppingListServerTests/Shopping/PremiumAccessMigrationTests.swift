@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Premium migration preserves legacy memberships and receipts without granting paid access or consuming a manual choice")
    func premiumMigrationPreservesLegacyData() async throws {
        let user = try await ShoppingFixture.user()
        let first = try await ShoppingFixture.group(user)
        let second = try await MembershipFixture.withPolicyReturningGroup(user)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            UPDATE group_memberships SET joined_at = clock_timestamp() - INTERVAL '2 days'
            WHERE user_id = \(bind: user.id) AND group_id = \(bind: second)::uuid
            """).run()
        let before = try await PremiumMigrationFixture.preservedSnapshot()
        try await AddAccountPremiumAccess().revert(on: database)
        try await AddAccountPremiumAccess().prepare(on: database)
        #expect(try await PremiumMigrationFixture.preservedSnapshot() == before)
        let capabilities = try await PremiumAccessFixture.capabilities(user)
        #expect(capabilities["premiumActive"] == .bool(false))
        #expect(capabilities["freeGroupId"] == .string(second))
        #expect(capabilities["freeGroupChangeAvailableAt"] == .null)
        #expect(capabilities["canChangeFreeGroup"] == .bool(true))
        let groups = try await PremiumAccessFixture.groups(user)
        #expect(groups[first]?["canUseShopping"] == .bool(false))
        #expect(groups[second]?["canUseShopping"] == .bool(true))
        #expect(try await PremiumAccessFixture.choose(user, group: first).status == .ok)
    }

    @Test("A premium rollback refuses to erase verified access or a manual choice before any schema mutation")
    func premiumRollbackRefusesEntitlementAndSelectionLoss() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        #expect(try await PremiumAccessFixture.choose(user, group: group).status == .ok)
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let before = try await PremiumMigrationFixture.accessSnapshot()
        await #expect(throws: AddAccountPremiumAccess.ReversionError.premiumAccessCannotBeRepresented) {
            try await AddAccountPremiumAccess().revert(on: database)
        }
        #expect(try await PremiumMigrationFixture.accessSnapshot() == before)
        #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(true))
    }
}

private enum PremiumMigrationFixture {
    static func preservedSnapshot() async throws -> [String: [String]] {
        let sql = try shoppingSQL(database)
        var result: [String: [String]] = [:]
        for table in ["users", "groups", "group_memberships", "mutation_receipts"] {
            let rows: [any SQLRow]
            if table == "users" {
                rows = try await sql.raw("""
                    SELECT (to_jsonb(record) - 'free_group_id' - 'free_group_changed_at')::text AS snapshot
                    FROM users AS record ORDER BY snapshot
                    """).all()
            } else {
                rows = try await sql.raw("""
                    SELECT to_jsonb(record)::text AS snapshot FROM \(ident: table) AS record ORDER BY snapshot
                    """).all()
            }
            result[table] = try rows.map { try $0.decode(column: "snapshot", as: String.self) }
        }
        return result
    }

    static func accessSnapshot() async throws -> [String: [String]] {
        let sql = try shoppingSQL(database)
        var result: [String: [String]] = [:]
        for table in ["users", "account_premium_access"] {
            let rows = try await sql.raw("""
                SELECT to_jsonb(record)::text AS snapshot FROM \(ident: table) AS record ORDER BY snapshot
                """).all()
            result[table] = try rows.map { try $0.decode(column: "snapshot", as: String.self) }
        }
        return result
    }
}

private extension MembershipFixture {
    static func withPolicyReturningGroup(_ user: ShoppingFixture.User) async throws -> String {
        // Each route collection uses the production persistence and only the trusted allowance seam differs.
        let sql = try shoppingSQL(database)
        let count = try #require(try await sql.raw("SELECT COUNT(*) AS count FROM groups").first())
        let initialCount = try count.decode(column: "count", as: Int64.self)
        try await withCapacity(2) {
            _ = try await ShoppingFixture.group(user)
        }
        let rows = try await sql.raw("""
            SELECT id FROM groups WHERE creator_user_id = \(bind: user.id) ORDER BY created_at DESC,id DESC LIMIT 1
            """).all()
        try #require(rows.count == 1)
        let current = try #require(try await sql.raw("SELECT COUNT(*) AS count FROM groups").first())
        try #require(try current.decode(column: "count", as: Int64.self) == initialCount + 1)
        return try rows[0].decode(column: "id", as: UUID.self).uuidString.lowercased()
    }
}
