import Foundation
import FluentSQL

/// Server time and persisted account state decide access, independently of login or device state.
struct AccountAccess: Sendable {
    let limits: AccountResourceLimits
    let now: Date
    let premiumActive: Bool
    let premiumExpiresAt: Date?
    let transitionEndsAt: Date?
    let freeGroupID: UUID?
    let storedFreeGroupID: UUID?
    let storedFreeGroupIsValid: Bool
    let freeGroupChangedAt: Date?

    var inTransition: Bool { !premiumActive && transitionEndsAt.map { $0 > now } == true }
    var canAdmitMembership: Bool { !inTransition }
    var freeGroupChangeAvailableAt: Date? { freeGroupChangedAt?.addingTimeInterval(30 * 86_400) }
    var canChangeFreeGroup: Bool {
        !storedFreeGroupIsValid || freeGroupChangeAvailableAt.map { $0 <= now } != false
    }

    func canUseShopping(in group: UUID) -> Bool { premiumActive || inTransition || freeGroupID == group }

    func groupCapabilities(_ group: UUID) -> APIJSON {
        .object([
            "canUseShopping": .bool(canUseShopping(in: group)),
            "isFreeGroup": .bool(freeGroupID == group)
        ])
    }

    func capabilities(membershipCount: Int64) -> APIJSON {
        .object([
            "membershipCount": .integer(membershipCount),
            "canCreateGroup": .bool(canAdmitMembership && membershipCount < limits.groups),
            "canJoinGroup": .bool(canAdmitMembership && membershipCount < limits.groups),
            "limits": .object([
                "groupsPerAccount": .object(["maximum": .integer(limits.groups), "enforced": .bool(true)])
            ]),
            "premiumActive": .bool(premiumActive),
            "premiumExpiresAt": .optional(premiumExpiresAt.map(APIEncoding.timestamp)),
            "transitionEndsAt": .optional(transitionEndsAt.map(APIEncoding.timestamp)),
            "freeGroupId": .optional(freeGroupID?.uuidString.lowercased()),
            "freeGroupChangeAvailableAt": .optional(freeGroupChangeAvailableAt.map(APIEncoding.timestamp)),
            "canChangeFreeGroup": .bool(canChangeFreeGroup)
        ])
    }
}

/// Internal boundary for a snapshot assembled only from verified Apple subscription state.
/// The caller holds the account lock; no group is locked after it.
func persistTrustedPremiumAccess(
    user: UUID,
    premiumUntil: Date?,
    transitionStartedAt: Date?,
    transitionAllowed: Bool,
    verificationEnvironment: AppStoreEnvironment = .production,
    on sql: any SQLDatabase
) async throws {
    try await sql.raw("""
        INSERT INTO account_premium_access
            (user_id,premium_until,transition_started_at,transition_allowed,verification_environment)
        VALUES (\(bind: user),\(bind: premiumUntil),\(bind: transitionStartedAt),\(bind: transitionAllowed),
            \(bind: verificationEnvironment.rawValue))
        ON CONFLICT(user_id,verification_environment) DO UPDATE SET premium_until = EXCLUDED.premium_until,
            transition_started_at = EXCLUDED.transition_started_at, transition_allowed = EXCLUDED.transition_allowed
        """).run()
}

extension AccountCapacityPolicy {
    func access(for user: UUID, on sql: any SQLDatabase) async throws -> AccountAccess {
        guard let row = try await sql.raw("""
            SELECT clock_timestamp() AS now, users.free_group_id, users.free_group_changed_at,
                access.premium_until, access.transition_started_at, COALESCE(access.transition_allowed,FALSE) AS transition_allowed,
                EXISTS (SELECT 1 FROM group_memberships JOIN groups ON groups.id = group_memberships.group_id
                    WHERE group_memberships.user_id = users.id AND groups.id = users.free_group_id
                        AND groups.closed_at IS NULL) AS selected_is_valid,
                (SELECT groups.id FROM group_memberships JOIN groups ON groups.id = group_memberships.group_id
                    WHERE group_memberships.user_id = users.id AND groups.closed_at IS NULL
                    ORDER BY group_memberships.joined_at ASC,groups.id ASC LIMIT 1) AS fallback_group_id
            FROM users LEFT JOIN account_premium_access AS access ON access.user_id = users.id
                AND access.verification_environment = \(bind: verificationEnvironment.rawValue)
            WHERE users.id = \(bind: user)
            """).first() else { throw APIProblem.notFound }
        let now = try row.decode(column: "now", as: Date.self)
        let expires = try row.decode(column: "premium_until", as: Date?.self)
        let storedGroup = try row.decode(column: "free_group_id", as: UUID?.self)
        let selectedIsValid = try row.decode(column: "selected_is_valid", as: Bool.self)
        let transitionAllowed = try row.decode(column: "transition_allowed", as: Bool.self)
        let transitionStart = try row.decode(column: "transition_started_at", as: Date?.self) ?? expires
        let injected = resolve?(user)
        let active = injected.map { $0.groups > 1 } ?? (expires.map { $0 > now } == true)
        let effective = injected ?? (active ? .premium : .free)
        return AccountAccess(
            limits: AccountResourceLimits(
                groups: max(1, effective.groups),
                activeStores: max(1, effective.activeStores),
                pendingItems: max(1, effective.pendingItems)
            ),
            now: now,
            premiumActive: active,
            premiumExpiresAt: expires,
            transitionEndsAt: !active && transitionAllowed ? transitionStart?.addingTimeInterval(7 * 86_400) : nil,
            freeGroupID: selectedIsValid ? storedGroup : try row.decode(column: "fallback_group_id", as: UUID?.self),
            storedFreeGroupID: storedGroup,
            storedFreeGroupIsValid: selectedIsValid,
            freeGroupChangedAt: try row.decode(column: "free_group_changed_at", as: Date?.self)
        )
    }

    func limits(for user: UUID, on sql: any SQLDatabase) async throws -> AccountResourceLimits {
        try await access(for: user, on: sql).limits
    }

    func maximum(for user: UUID, on sql: any SQLDatabase) async throws -> Int64 {
        try await access(for: user, on: sql).limits.groups
    }

    func capabilities(user: UUID, membershipCount: Int64, on sql: any SQLDatabase) async throws -> APIJSON {
        try await access(for: user, on: sql).capabilities(membershipCount: membershipCount)
    }
}
