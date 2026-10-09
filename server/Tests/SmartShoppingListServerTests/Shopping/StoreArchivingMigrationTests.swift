@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Migrating above-free legacy data retains all stores, entries and exact receipts as active")
    func storeArchivingMigrationPreservesLegacyExcess() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let batch = ShoppingFixture.batch(
            names: Array(repeating: "Producto", count: 21),
            stores: Array(repeating: "Grande", count: 21)
        )
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(resolve: { _ in .premium })) {
            let created = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                owner,
                batch
            )
            try #require(created.status == .created)
            for name in ["A", "B", "C"] {
                _ = try await StoreQuotaFixture.add(
                    owner,
                    group: group,
                    store: name,
                    count: 1
                )
            }
        }
        try await AddStoreArchiving().revert(on: database)
        let before = try await StoreMigrationFixture.snapshot(includeArchiveState: false)
        try await AddStoreArchiving().prepare(on: database)
        #expect(try await StoreMigrationFixture.snapshot(includeArchiveState: false) == before)
        let stores = try await StoreQuotaFixture.stores(owner, group: group)
        #expect(stores.count == 4)
        #expect(stores.allSatisfy { $0["archivedAt"] == .null })
        #expect(stores.first { $0["name"] == .string("Grande") }?["pendingItemCount"] == .integer(21))
        #expect(try await StoreQuotaFixture.capacity(owner, group: group)["canCreateStore"] == .bool(false))
        let replay = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            owner,
            batch
        )
        #expect(replay.status == .created)
        #expect(try StoreQuotaFixture.array(replay, key: "items").count == 21)
        #expect(try await StoreMigrationFixture.snapshot(includeArchiveState: false) == before)

    }

    @Test("A rollback with archived stores fails before mutation; restoring all stores makes it lossless")
    func storeArchivingRollbackRejectsLossOfState() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let item = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Casa",
            count: 1
        )[0]
        let store = try #require(item["storeId"]?.string)
        _ = try await StoreQuotaFixture.cancel(owner, group: group, item: item)
        _ = try await StoreQuotaFixture.archive(owner, group: group, store: store)
        let before = try await StoreMigrationFixture.snapshot(includeArchiveState: true)
        await #expect(throws: AddStoreArchiving.ReversionError.archivedStoresCannotBeRepresented) {
            try await AddStoreArchiving().revert(on: database)
        }
        #expect(try await StoreMigrationFixture.snapshot(includeArchiveState: true) == before)
        _ = try await StoreQuotaFixture.restore(owner, group: group, store: store)
        let restored = try await StoreMigrationFixture.snapshot(includeArchiveState: false)
        try await AddStoreArchiving().revert(on: database)
        #expect(try await StoreMigrationFixture.snapshot(includeArchiveState: false) == restored)
        try await AddStoreArchiving().prepare(on: database)
    }
}

private enum StoreMigrationFixture {
    static func snapshot(includeArchiveState: Bool) async throws -> [String: [String]] {
        let sql = try shoppingSQL(database)
        var snapshots: [String: [String]] = [:]
        for table in ["stores", "items", "users", "groups", "group_memberships", "mutation_receipts"] {
            let rows: [any SQLRow]
            if table == "stores", !includeArchiveState {
                rows = try await sql.raw("""
                    SELECT (to_jsonb(record) - 'archived_at')::text AS snapshot FROM stores AS record ORDER BY snapshot
                    """).all()
            } else {
                rows = try await sql.raw("""
                    SELECT to_jsonb(record)::text AS snapshot FROM \(ident: table) AS record ORDER BY snapshot
                    """).all()
            }
            snapshots[table] = try rows.map { try $0.decode(column: "snapshot", as: String.self) }
        }
        return snapshots
    }
}
