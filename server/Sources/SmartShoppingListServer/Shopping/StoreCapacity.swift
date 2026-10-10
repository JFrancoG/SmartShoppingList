import Foundation
import FluentKit
import FluentSQL
import Vapor

struct GroupStoreCapacity: Sendable {
    let group: UUID
    let owner: UUID
    let activeStoreCount: Int64
    let limits: AccountResourceLimits
    var canUseShopping = true

    var canCreateStore: Bool { canUseShopping && activeStoreCount < limits.activeStores }

    var json: APIJSON {
        .object([
            "groupId": .string(group.uuidString.lowercased()),
            "capacityOwnerUserId": .string(owner.uuidString.lowercased()),
            "activeStoreCount": .integer(activeStoreCount), "limits": limits.groupResourceJSON,
            "canCreateStore": .bool(canCreateStore)
        ])
    }
}

struct ShoppingStore: Sendable {
    let id: UUID
    let group: UUID
    let name: String
    let key: String
    let archivedAt: Date?
    let pendingCount: Int64

    func json(user: UUID, capacity: GroupStoreCapacity) -> APIJSON {
        let active = archivedAt == nil
        let administrator = capacity.owner == user
        return .object([
            "id": .string(id.uuidString.lowercased()), "groupId": .string(group.uuidString.lowercased()),
            "name": .string(name), "archivedAt": .optional(archivedAt.map(APIEncoding.timestamp)),
            "pendingItemCount": .integer(pendingCount),
            "capabilities": .object([
                "canAddItems": .bool(capacity.canUseShopping && active && pendingCount < capacity.limits.pendingItems),
                "canArchive": .bool(administrator && active && pendingCount == 0),
                "canRestore": .bool(administrator && !active && capacity.canCreateStore)
            ])
        ])
    }
}

extension ShoppingStore {
    init(row: any SQLRow) throws {
        id = try row.decode(column: "id", as: UUID.self)
        group = try row.decode(column: "group_id", as: UUID.self)
        name = try row.decode(column: "name", as: String.self)
        key = try row.decode(column: "normalized_key", as: String.self)
        archivedAt = try row.decode(column: "archived_at", as: Date?.self)
        pendingCount = try row.decode(column: "pending_count", as: Int64.self)
    }
}

extension ShoppingService {
    enum StoreState: String, Sendable {
        case active
        case archived

        // Keep the existing active-store cursor scope; archived cursors cannot cross the filter boundary.
        var cursorResource: String { self == .active ? "stores" : "archivedStores" }
    }

    func capacity(user: UUID, group: UUID) async throws -> APIReply {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await lockGroup(group, on: sql)
            try await requireMembership(user, group: group, on: sql)
            let snapshot = try await storeCapacity(group: group, user: user, on: sql)
            return try APIReply(status: .ok, json: snapshot.json)
        }
    }

    /// Called while holding the group lock so its administrator and all counts belong to this mutation.
    func storeCapacity(group: UUID, user: UUID? = nil, on sql: any SQLDatabase) async throws -> GroupStoreCapacity {
        guard let row = try await sql.raw("""
            SELECT administrator_user_id, (SELECT COUNT(*) FROM stores
                WHERE group_id = groups.id AND archived_at IS NULL) AS active_count
            FROM groups WHERE id = \(bind: group) AND closed_at IS NULL
            """).first()
        else {
            throw APIProblem.notFound
        }
        let owner = try row.decode(column: "administrator_user_id", as: UUID.self)
        let canUse: Bool
        if let user {
            canUse = try await canUseShopping(user: user, group: group, on: sql)
        } else {
            canUse = true
        }
        return GroupStoreCapacity(
            group: group,
            owner: owner,
            activeStoreCount: try row.decode(column: "active_count", as: Int64.self),
            limits: try await accountCapacity.limits(for: owner, on: sql),
            canUseShopping: canUse
        )
    }

    func loadStore(_ id: UUID, group: UUID, on sql: any SQLDatabase) async throws -> ShoppingStore {
        guard let row = try await sql.raw("""
            SELECT stores.*, (SELECT COUNT(*) FROM items
                WHERE store_id = stores.id AND group_id = stores.group_id AND status = 'pending') AS pending_count
            FROM stores WHERE id = \(bind: id) AND group_id = \(bind: group)
            """).first()
        else {
            throw APIProblem.notFound
        }
        return try ShoppingStore(row: row)
    }

    func changeStoreState(
        user: UUID,
        group: UUID,
        store: UUID,
        operation: UUID,
        state: StoreState
    ) async throws -> APIReply {
        let type = state == .archived ? "archiveStore" : "restoreStore"
        let fingerprint = try fingerprint(type: type, group: group, value: .string(store.uuidString.lowercased()))
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await lockGroup(group, on: sql)
            try await requireMembership(user, group: group, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: type,
                group: group,
                fingerprint: fingerprint,
                on: sql
            ) {
                return replay
            }
            if state == .active, let restriction = try await restrictedGroupReply(
                user: user,
                group: group,
                operation: operation,
                on: sql
            ) {
                return restriction
            }
            let capacity = try await storeCapacity(group: group, user: user, on: sql)
            guard capacity.owner == user else {
                throw APIProblem(
                    status: .forbidden,
                    code: "administrator_required",
                    message: "Se requiere el administrador del grupo."
                )
            }
            let actual = try await loadStore(store, group: group, on: sql)
            let alreadyDesired = (actual.archivedAt != nil) == (state == .archived)
            if !alreadyDesired {
                let problem: APIProblem?
                if state == .archived, actual.pendingCount > 0 {
                    problem = Self.storeProblem("store_not_empty")
                } else if state == .active, !capacity.canCreateStore {
                    problem = Self.storeProblem("store_limit_reached")
                } else {
                    problem = nil
                }
                if let problem {
                    return try await saveStoreConflict(
                        problem,
                        user: user,
                        operation: operation,
                        group: group,
                        on: sql
                    )
                }
                if state == .archived {
                    try await sql.raw("""
                        UPDATE stores SET archived_at = clock_timestamp() WHERE id = \(bind: store)
                        """).run()
                } else {
                    try await sql.raw("UPDATE stores SET archived_at = NULL WHERE id = \(bind: store)").run()
                }
            }
            // Reuse the same trusted policy snapshot; only this transaction changed the active count.
            let countDelta: Int64 = alreadyDesired ? 0 : (state == .archived ? -1 : 1)
            let updatedCapacity = GroupStoreCapacity(
                group: group,
                owner: capacity.owner,
                activeStoreCount: capacity.activeStoreCount + countDelta,
                limits: capacity.limits,
                canUseShopping: capacity.canUseShopping
            )
            let updated = try await loadStore(store, group: group, on: sql)
            return try await save(
                APIReply(status: .ok, json: updated.json(user: user, capacity: updatedCapacity)),
                user: user,
                operation: operation,
                group: group,
                on: sql
            )
        }
    }

    static func storeProblem(_ code: String) -> APIProblem {
        let message: String
        switch code {
        case "store_limit_reached":
            message = "El grupo ha alcanzado su límite de tiendas activas."
        case "pending_item_limit_reached":
            message = "La tienda ha alcanzado su límite de productos pendientes."
        case "store_archived":
            message = "Restaura la tienda antes de añadir productos."
        case "store_not_empty":
            message = "Completa, mueve o cancela los productos pendientes antes de archivar."
        default:
            message = "La operación no está disponible."
        }
        return APIProblem(status: .conflict, code: code, message: message)
    }

    func saveStoreConflict(
        _ problem: APIProblem,
        user: UUID,
        operation: UUID,
        group: UUID,
        on sql: any SQLDatabase
    ) async throws -> APIReply {
        try await save(
            APIReply(status: problem.status, json: problem.json),
            user: user,
            operation: operation,
            group: group,
            on: sql
        )
    }
}
