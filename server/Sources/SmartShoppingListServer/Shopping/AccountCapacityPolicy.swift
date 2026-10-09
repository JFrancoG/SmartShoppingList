import Foundation
import FluentSQL

/// Server-owned account capacity. Production keeps its free allowance until an entitlement provider exists.
struct AccountCapacityPolicy: Sendable {
    var maximumGroups: @Sendable (UUID) -> Int64 = { _ in 1 }

    func maximum(for user: UUID) -> Int64 { max(1, maximumGroups(user)) }

    func capabilities(user: UUID, membershipCount: Int64) -> APIJSON {
        let maximum = maximum(for: user)
        return .object([
            "membershipCount": .integer(membershipCount),
            "canCreateGroup": .bool(membershipCount < maximum),
            "canJoinGroup": .bool(membershipCount < maximum),
            "limits": .object([
                "groupsPerAccount": .object(["maximum": .integer(maximum), "enforced": .bool(true)])
            ])
        ])
    }
}

extension ShoppingService {
    func membershipCount(user: UUID, on sql: any SQLDatabase) async throws -> Int64 {
        guard let row = try await sql.raw("""
            SELECT COUNT(*) AS count FROM group_memberships JOIN groups ON groups.id = group_memberships.group_id
            WHERE user_id = \(bind: user) AND groups.closed_at IS NULL
            """).first() else { throw APIProblem.unavailable }
        return try row.decode(column: "count", as: Int64.self)
    }

    func isMember(_ user: UUID, group: UUID, on sql: any SQLDatabase) async throws -> Bool {
        try await sql.raw("""
            SELECT 1 FROM group_memberships JOIN groups ON groups.id = group_memberships.group_id
            WHERE user_id = \(bind: user) AND group_id = \(bind: group) AND groups.closed_at IS NULL
            """).first() != nil
    }

    func requireMembership(_ user: UUID, group: UUID, on sql: any SQLDatabase) async throws {
        try await lockUser(user, on: sql)
        guard try await isMember(user, group: group, on: sql) else { throw APIProblem.notFound }
    }

    func insertMembership(_ user: UUID, group: UUID, on sql: any SQLDatabase) async throws {
        try await sql.raw("""
            INSERT INTO group_memberships(group_id,user_id) VALUES (\(bind: group),\(bind: user))
            """).run()
        // The group is already locked (or newly created). Never select a different group while holding the account lock.
        try await sql.raw("""
            UPDATE users SET group_id = \(bind: group) WHERE id = \(bind: user) AND group_id IS NULL
            """).run()
    }
}
