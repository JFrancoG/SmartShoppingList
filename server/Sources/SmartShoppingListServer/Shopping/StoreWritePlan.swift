import Foundation
import FluentSQL

/// Resolved destinations and capacity admission, before inserting any store or item.
struct StoreWritePlan: Sendable {
    struct NewStore: Sendable {
        let id: UUID
        let name: String
        let key: String
    }

    let destinations: [UUID]
    let newStores: [NewStore]

    func insertStores(group: UUID, on sql: any SQLDatabase) async throws {
        for store in newStores.sorted(by: { $0.key < $1.key }) {
            try await sql.raw("""
                INSERT INTO stores(id,group_id,name,normalized_key)
                VALUES (\(bind: store.id),\(bind: group),\(bind: store.name),\(bind: store.key))
                """).run()
        }
    }
}

extension ShoppingService {
    func planStoreWrites(
        _ items: [ShoppingNewItem],
        group: UUID,
        movingFrom: UUID? = nil,
        on sql: any SQLDatabase
    ) async throws -> StoreWritePlan {
        let capacity = try await storeCapacity(group: group, on: sql)
        let rows = try await sql.raw("""
            SELECT stores.*, (SELECT COUNT(*) FROM items
                WHERE store_id = stores.id AND group_id = stores.group_id AND status = 'pending') AS pending_count
            FROM stores WHERE group_id = \(bind: group)
            """).all()
        let stores = try rows.map(ShoppingStore.init(row:))
        let byID = Dictionary(uniqueKeysWithValues: stores.map { ($0.id, $0) })
        let byKey = Dictionary(uniqueKeysWithValues: stores.map { ($0.key, $0) })
        var newStores: [String: StoreWritePlan.NewStore] = [:]
        var destinations: [UUID] = []
        var additions: [UUID: Int64] = [:]
        for item in items {
            let existing: ShoppingStore?
            let destination: UUID
            switch item.store {
            case .existing(let id):
                guard let store = byID[id] else { throw APIProblem.notFound }
                existing = store
                destination = id
            case .named(let name, let key):
                existing = byKey[key]
                if let existing {
                    destination = existing.id
                } else if let planned = newStores[key] {
                    destination = planned.id
                } else {
                    let planned = StoreWritePlan.NewStore(id: UUID(), name: name, key: key)
                    newStores[key] = planned
                    destination = planned.id
                }
            }
            guard existing?.archivedAt == nil else { throw Self.storeProblem("store_archived") }
            destinations.append(destination)
            additions[destination, default: 0] += 1
        }
        if !newStores.isEmpty,
           capacity.activeStoreCount + Int64(newStores.count) > capacity.limits.activeStores {
            throw Self.storeProblem("store_limit_reached")
        }
        if let movingFrom {
            additions[movingFrom, default: 0] -= 1
        }
        for (id, increase) in additions where increase > 0 {
            guard (byID[id]?.pendingCount ?? 0) + increase <= capacity.limits.pendingItems else {
                throw Self.storeProblem("pending_item_limit_reached")
            }
        }
        return StoreWritePlan(destinations: destinations, newStores: Array(newStores.values))
    }
}
