import Foundation
import FluentSQL
import Vapor

struct AccountDeletionImpact: Codable, Sendable {
    struct Group: Codable, Sendable {
        let id: String
        let name: String
        let memberCount: Int64
        let administers: Bool
        let willDelete: Bool
    }

    let groups: [Group]
    let ownContentCount: Int
    let legacyContentCount: Int
    let revision: String
}

/// The caller holds the deletion coordination lock and a transaction throughout planning and purging.
/// This component never contacts Apple and never deletes somebody else's known text.
enum AccountDataPurger {
    static func affectedGroups(user: UUID, on sql: any SQLDatabase) async throws -> [UUID] {
        let rows = try await sql.raw("""
            SELECT group_id FROM group_memberships WHERE user_id = \(bind: user)
            UNION SELECT id FROM groups WHERE creator_user_id = \(bind: user) OR administrator_user_id = \(bind: user)
            UNION SELECT group_id FROM stores WHERE created_by = \(bind: user)
            UNION SELECT group_id FROM items WHERE created_by = \(bind: user) OR purchased_by = \(bind: user)
                OR name_author_user_id = \(bind: user) OR quantity_author_user_id = \(bind: user)
            UNION SELECT group_id FROM group_administration_transfers
                WHERE proposer_user_id = \(bind: user) OR recipient_user_id = \(bind: user)
            UNION SELECT group_id FROM invitations WHERE accepted_by = \(bind: user)
            UNION SELECT group_id FROM mutation_receipts WHERE group_id IS NOT NULL
                AND user_id = \(bind: user)
            ORDER BY group_id
            """).all()
        return try rows.map { try $0.decode(column: "group_id", as: UUID.self) }
    }

    static func preview(user: UUID, on sql: any SQLDatabase) async throws -> AccountDeletionImpact {
        try await plan(user: user, on: sql).impact
    }

    static func purge(user: UUID, on sql: any SQLDatabase) async throws {
        guard let account = try await sql.raw("SELECT deleting_at FROM users WHERE id = \(bind: user)").first() else {
            return
        }
        guard try account.decode(column: "deleting_at", as: Date?.self) != nil else {
            throw APIProblem(status: .conflict, code: "deletion_not_accepted", message: "Confirma la eliminación primero.")
        }
        let plan = try await plan(user: user, on: sql)
        for group in plan.groups {
            if group.otherMembers == 0 {
                try await eraseGroup(group.id, on: sql)
                continue
            }
            for item in group.items {
                if item.delete {
                    try await sql.raw("DELETE FROM items WHERE id = \(bind: item.id)").run()
                } else {
                    try await sql.raw("""
                        UPDATE items SET name = \(bind: item.name), quantity = \(bind: item.quantity),
                            name_author_user_id = \(bind: item.nameAuthor),
                            quantity_author_user_id = \(bind: item.quantityAuthor),
                            name_redacted = \(bind: item.nameRedacted),
                            created_by = CASE WHEN created_by = \(bind: user) THEN NULL ELSE created_by END,
                            purchased_by = CASE WHEN purchased_by = \(bind: user) THEN NULL ELSE purchased_by END,
                            version = LEAST(9007199254740991, version + CASE WHEN \(bind: item.changed) THEN 1 ELSE 0 END)
                        WHERE id = \(bind: item.id)
                        """).run()
                }
            }
            for (index, store) in group.stores.enumerated() where store.redact {
                let key = try await neutralStoreKey(store.id, group: group.id, on: sql)
                try await sql.raw("""
                    UPDATE stores SET name = \(bind: "Tienda sin nombre \(index + 1)"), normalized_key = \(bind: key),
                        created_by = NULL, name_redacted = true WHERE id = \(bind: store.id)
                    """).run()
            }
            try await sql.raw("""
                UPDATE stores SET created_by = NULL WHERE group_id = \(bind: group.id) AND created_by = \(bind: user)
                """).run()
            try await sql.raw("""
                UPDATE groups SET
                    name = CASE WHEN creator_user_id = \(bind: user) THEN 'Grupo sin nombre' ELSE name END,
                    creator_user_id = CASE WHEN creator_user_id = \(bind: user) THEN NULL ELSE creator_user_id END,
                    pending_administration = pending_administration OR administrator_user_id IS NOT DISTINCT FROM \(bind: user),
                    administrator_user_id = CASE WHEN administrator_user_id = \(bind: user)
                        THEN NULL ELSE administrator_user_id END
                WHERE id = \(bind: group.id)
                """).run()
            if group.wasAdministrator {
                try await sql.raw("""
                    DELETE FROM invitations WHERE group_id = \(bind: group.id) AND accepted_by IS NULL
                    """).run()
            }
            try await removeReceiptContent(group: group.id, on: sql)
        }
        try await sql.raw("DELETE FROM mutation_receipts WHERE user_id = \(bind: user)").run()
        try await sql.raw("""
            UPDATE mutation_receipts SET fingerprint = NULL, body = NULL, status = NULL, group_id = NULL,
                result_removed = true WHERE lower(body) LIKE \(bind: "%" + user.uuidString.lowercased() + "%")
            """).run()
        try await sql.raw("DELETE FROM invitations WHERE accepted_by = \(bind: user)").run()
        try await sql.raw("""
            DELETE FROM group_administration_transfers
            WHERE proposer_user_id = \(bind: user) OR recipient_user_id = \(bind: user)
            """).run()
        try await sql.raw("DELETE FROM group_memberships WHERE user_id = \(bind: user)").run()
        try await sql.raw("DELETE FROM account_premium_access WHERE user_id = \(bind: user)").run()
        try await sql.raw("UPDATE app_store_transactions SET user_id = NULL WHERE user_id = \(bind: user)").run()
        try await sql.raw("""
            UPDATE app_store_subscriptions SET user_id = NULL, detached_at = clock_timestamp()
            WHERE user_id = \(bind: user)
            """).run()
        try await sql.raw("""
            DELETE FROM subscription_recovery_jobs WHERE user_id = \(bind: user) AND state = 'completed'
                AND NOT request_in_flight AND NOT has_uncertain_update
            """).run()
        // An Apple update already sent can finish after this commit. Block reuse without keeping the deleted identity.
        try await sql.raw("""
            UPDATE subscription_recovery_jobs SET user_id = NULL,challenge_id = NULL,
                state = 'quarantined',request_in_flight = FALSE WHERE user_id = \(bind: user)
            """).run()
        try await sql.raw("DELETE FROM subscription_recovery_challenges WHERE user_id = \(bind: user)").run()
        try await sql.raw("DELETE FROM app_sessions WHERE user_id = \(bind: user)").run()
        try await sql.raw("DELETE FROM apple_grants WHERE user_id = \(bind: user)").run()
        try await sql.raw("DELETE FROM users WHERE id = \(bind: user)").run()
    }

    private static func removeReceiptContent(group: UUID, on sql: any SQLDatabase) async throws {
        try await sql.raw("""
            UPDATE mutation_receipts SET fingerprint = NULL, body = NULL, status = NULL, group_id = NULL,
                result_removed = true WHERE group_id = \(bind: group)
            """).run()
    }

    static func eraseEmptyGroup(_ group: UUID, on sql: any SQLDatabase) async throws {
        guard try await sql.raw("SELECT 1 FROM group_memberships WHERE group_id = \(bind: group) LIMIT 1").first() == nil else {
            throw APIProblem(status: .conflict, code: "group_not_empty", message: "El grupo conserva miembros.")
        }
        try await eraseGroup(group, on: sql)
    }

    private static func eraseGroup(_ group: UUID, on sql: any SQLDatabase) async throws {
        try await removeReceiptContent(group: group, on: sql)
        try await sql.raw("DELETE FROM group_administration_transfers WHERE group_id = \(bind: group)").run()
        try await sql.raw("DELETE FROM invitations WHERE group_id = \(bind: group)").run()
        try await sql.raw("DELETE FROM items WHERE group_id = \(bind: group)").run()
        try await sql.raw("DELETE FROM stores WHERE group_id = \(bind: group)").run()
        try await sql.raw("UPDATE users SET group_id = NULL WHERE group_id = \(bind: group)").run()
        try await sql.raw("UPDATE users SET free_group_id = NULL WHERE free_group_id = \(bind: group)").run()
        try await sql.raw("DELETE FROM group_memberships WHERE group_id = \(bind: group)").run()
        try await sql.raw("DELETE FROM groups WHERE id = \(bind: group)").run()
    }

    private static func neutralStoreKey(_ store: UUID, group: UUID, on sql: any SQLDatabase) async throws -> String {
        var key = "removed-" + store.uuidString.lowercased()
        while try await sql.raw("""
            SELECT 1 FROM stores WHERE group_id = \(bind: group) AND normalized_key = \(bind: key) AND id <> \(bind: store)
            """).first() != nil {
            key += "_"
        }
        return key
    }
}

private extension AccountDataPurger {
    struct Plan {
        let groups: [GroupPlan]
        let impact: AccountDeletionImpact
    }

    struct GroupPlan {
        let id: UUID
        let otherMembers: Int64
        let wasAdministrator: Bool
        let items: [ItemPlan]
        let stores: [StorePlan]
    }

    struct ItemPlan {
        let id: UUID
        let name: String
        let quantity: String?
        let nameAuthor: UUID?
        let quantityAuthor: UUID?
        let nameRedacted: Bool
        let changed: Bool
        let delete: Bool
    }

    struct StorePlan {
        let id: UUID
        let redact: Bool
    }

    static func plan(user: UUID, on sql: any SQLDatabase) async throws -> Plan {
        let ids = try await affectedGroups(user: user, on: sql)
        var groups: [GroupPlan] = []
        var summaries: [AccountDeletionImpact.Group] = []
        var own = 0
        var legacy = 0
        var evidence: [String] = [user.uuidString.lowercased()]
        for id in ids {
            guard let group = try await sql.raw("""
                SELECT groups.*,to_jsonb(groups)::text AS snapshot,
                    (SELECT COUNT(*) FROM group_memberships WHERE group_id = groups.id) AS member_count,
                    (SELECT COUNT(*) FROM group_memberships WHERE group_id = groups.id
                        AND user_id <> \(bind: user)) AS other_count,
                    EXISTS(SELECT 1 FROM group_memberships WHERE group_id = groups.id
                        AND user_id = \(bind: user)) AS is_member
                FROM groups WHERE id = \(bind: id)
                """).first() else { continue }
            let administrator = try group.decode(column: "administrator_user_id", as: UUID?.self)
            let creator = try group.decode(column: "creator_user_id", as: UUID?.self)
            let others = try group.decode(column: "other_count", as: Int64.self)
            let isMember = try group.decode(column: "is_member", as: Bool.self)
            summaries.append(try .init(
                id: id.uuidString.lowercased(),
                name: isMember ? group.decode(column: "name", as: String.self) : "Grupo anterior",
                memberCount: group.decode(column: "member_count", as: Int64.self),
                administers: administrator == user,
                willDelete: others == 0
            ))
            evidence.append(try group.decode(column: "snapshot", as: String.self))
            if creator == user {
                own += 1
            }
            let revisions = try await LegacyContentProvenance.revisions(group: id, on: sql)
            let rows = try await sql.raw("SELECT * FROM items WHERE group_id = \(bind: id) ORDER BY id").all()
            var items: [ItemPlan] = []
            for row in rows {
                let item = try LegacyContentProvenance.Item(
                    id: row.decode(column: "id", as: UUID.self),
                    groupId: row.decode(column: "group_id", as: UUID.self),
                    storeId: row.decode(column: "store_id", as: UUID.self),
                    name: row.decode(column: "name", as: String.self),
                    quantity: row.decode(column: "quantity", as: String?.self),
                    status: row.decode(column: "status", as: String.self),
                    version: row.decode(column: "version", as: Int64.self),
                    createdBy: row.decode(column: "created_by", as: UUID?.self),
                    purchasedBy: row.decode(column: "purchased_by", as: UUID?.self)
                )
                let recovered = LegacyContentProvenance.authors(of: item, revisions: revisions)
                let wasRedacted = try row.decode(column: "name_redacted", as: Bool.self)
                let nameAuthor = try row.decode(column: "name_author_user_id", as: UUID?.self)
                    ?? (wasRedacted ? nil : recovered?.name)
                let quantityAuthor = try row.decode(column: "quantity_author_user_id", as: UUID?.self)
                    ?? recovered?.quantity
                let removeName = nameAuthor == user || nameAuthor == nil && !wasRedacted
                let removeQuantity = item.quantity != nil && (quantityAuthor == user || quantityAuthor == nil)
                own += (nameAuthor == user ? 1 : 0) + (quantityAuthor == user ? 1 : 0)
                legacy += (removeName && nameAuthor == nil ? 1 : 0)
                    + (removeQuantity && quantityAuthor == nil ? 1 : 0)
                let hasOther = [nameAuthor, quantityAuthor, item.createdBy, item.purchasedBy].contains {
                    $0 != nil && $0 != user
                }
                let changed = removeName || removeQuantity || item.createdBy == user || item.purchasedBy == user
                items.append(.init(
                    id: item.id,
                    name: removeName ? "Producto sin nombre" : item.name,
                    quantity: removeQuantity ? nil : item.quantity,
                    nameAuthor: removeName ? nil : nameAuthor,
                    quantityAuthor: removeQuantity ? nil : quantityAuthor,
                    nameRedacted: wasRedacted || removeName,
                    changed: changed,
                    delete: !hasOther
                ))
            }
            let storeRows = try await sql.raw("SELECT * FROM stores WHERE group_id = \(bind: id) ORDER BY id").all()
            var stores: [StorePlan] = []
            for row in storeRows {
                let author = try row.decode(column: "created_by", as: UUID?.self)
                let wasRedacted = try row.decode(column: "name_redacted", as: Bool.self)
                let redact = author == user || author == nil && !wasRedacted
                own += author == user ? 1 : 0
                legacy += author == nil && !wasRedacted ? 1 : 0
                stores.append(try .init(id: row.decode(column: "id", as: UUID.self), redact: redact))
            }
            groups.append(.init(
                id: id,
                otherMembers: others,
                wasAdministrator: administrator == user,
                items: items,
                stores: stores
            ))
            for table in ["group_memberships", "stores", "items", "mutation_receipts"] {
                let rows = try await sql.raw("""
                    SELECT to_jsonb(record)::text AS snapshot FROM \(ident: table) AS record
                    WHERE group_id = \(bind: id) ORDER BY snapshot
                    """).all()
                evidence.append(table)
                evidence += try rows.map { try $0.decode(column: "snapshot", as: String.self) }
            }
        }
        let fingerprint = SHA256.hash(data: try APIEncoding.data(evidence)).map { String(format: "%02x", $0) }.joined()
        return Plan(
            groups: groups,
            impact: .init(groups: summaries, ownContentCount: own, legacyContentCount: legacy, revision: fingerprint)
        )
    }
}
