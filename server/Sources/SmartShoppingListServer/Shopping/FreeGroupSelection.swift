import Foundation
import FluentKit
import FluentSQL
import Vapor

extension ShoppingService {
    /// The receipt is account scoped; selection never changes membership.
    func selectFreeGroup(user: UUID, group: UUID, operation: UUID) async throws -> APIReply {
        let fingerprint = try fingerprint(
            type: "selectFreeGroup",
            group: nil,
            value: .string(group.uuidString.lowercased())
        )
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            // Lock even a closed target before the account, permitting historical receipt replay.
            guard try await sql.raw("SELECT id FROM groups WHERE id = \(bind: group) FOR UPDATE").first() != nil else {
                throw APIProblem.notFound
            }
            try await lockUser(user, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: "selectFreeGroup",
                group: nil,
                fingerprint: fingerprint,
                on: sql
            ) {
                return replay
            }
            guard try await isMember(user, group: group, on: sql) else { throw APIProblem.notFound }
            let access = try await accountCapacity.access(for: user, on: sql)
            let alreadySelected = access.storedFreeGroupIsValid && access.storedFreeGroupID == group
            if !alreadySelected && !access.canChangeFreeGroup {
                let problem = APIProblem(
                    status: .conflict,
                    code: "free_group_change_cooldown",
                    message: "Podrás volver a cambiar el grupo gratuito cuando termine el plazo indicado."
                )
                return try await save(
                    APIReply(status: .conflict, json: problem.json),
                    user: user,
                    operation: operation,
                    group: nil,
                    on: sql
                )
            }
            if !alreadySelected {
                // Replacing an unavailable explicit choice is exceptional, without erasing its previous cooldown.
                let exceptional = access.storedFreeGroupID != nil && !access.storedFreeGroupIsValid
                let changedAt: Date?
                if access.freeGroupID == group {
                    changedAt = access.freeGroupChangedAt
                } else {
                    changedAt = exceptional ? (access.freeGroupChangedAt ?? access.now) : access.now
                }
                try await sql.raw("""
                    UPDATE users SET free_group_id = \(bind: group), free_group_changed_at = \(bind: changedAt)
                    WHERE id = \(bind: user)
                    """).run()
            }
            let updated = try await accountCapacity.access(for: user, on: sql)
            let count = try await membershipCount(user: user, on: sql)
            return try await save(
                APIReply(status: .ok, json: updated.capabilities(membershipCount: count)),
                user: user,
                operation: operation,
                group: nil,
                on: sql
            )
        }
    }

    func canUseShopping(user: UUID, group: UUID, on sql: any SQLDatabase) async throws -> Bool {
        try await accountCapacity.access(for: user, on: sql).canUseShopping(in: group)
    }

    func restrictedGroupReply(
        user: UUID,
        group: UUID,
        operation: UUID,
        on sql: any SQLDatabase
    ) async throws -> APIReply? {
        guard !(try await canUseShopping(user: user, group: group, on: sql)) else { return nil }
        return try await saveStoreConflict(
            Self.groupAccessRestricted,
            user: user,
            operation: operation,
            group: group,
            on: sql
        )
    }

    static var groupAccessRestricted: APIProblem {
        APIProblem(
            status: .conflict,
            code: "group_access_restricted",
            message: "Elige este grupo como gratuito o recupera premium para continuar las compras."
        )
    }
}
