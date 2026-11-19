@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test
    func contentProvenanceTracksNewContentWithoutReassigningExistingStores() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let original = try await ProvenanceFixture.add(owner, group: group)
        let body = ShoppingFixture.batch(names: ["Leche"], stores: ["ALDI"])
        let path = "/v1/groups/\(group)/item-batches"
        let added = try await ShoppingFixture.request(.POST, path, member, body)
        try #require(added.status == .created)
        let entry = try #require(try StoreQuotaFixture.array(added, key: "items").first)
        let identifier = try #require(entry["id"]?.string)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: owner.id))
        #expect(try await ProvenanceFixture.authors(identifier) == .init(name: member.id, quantity: nil))
        #expect(try await ProvenanceFixture.storeAuthor(original.store) == owner.id)
        #expect(entry["storeId"] == .string(original.store))
        let before = try await ProvenanceFixture.snapshot()
        let replay = try await ShoppingFixture.request(.POST, path, member, body)
        #expect(replay.body.string == added.body.string)
        #expect(try await ProvenanceFixture.snapshot() == before)
    }

    @Test
    func contentProvenanceChangesOnlyTheEditedFieldAndClearsRemovedQuantity() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let original = try await ProvenanceFixture.add(owner, group: group)
        let path = "/v1/groups/\(group)/items/\(original.item)"
        let quantityEdit = ProvenanceFixture.edit(version: 1, name: "Pan", quantity: "3", store: "Aldi")
        let changedQuantity = try await ShoppingFixture.request(.PATCH, path, member, quantityEdit)
        try #require(changedQuantity.status == .ok)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: member.id))
        let renamed = try await ShoppingFixture.request(
            .PATCH,
            path,
            owner,
            ProvenanceFixture.edit(version: 2, name: "Pan integral", quantity: "3", store: "Aldi")
        )
        try #require(renamed.status == .ok)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: member.id))
        let unchanged = try await ShoppingFixture.request(
            .PATCH,
            path,
            member,
            ProvenanceFixture.edit(version: 3, name: "Pan integral", quantity: "3", store: "Aldi")
        )
        try #require(unchanged.status == .ok)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: member.id))
        let moved = try await ShoppingFixture.request(
            .PATCH,
            path,
            owner,
            ProvenanceFixture.edit(version: 4, name: "Pan integral", quantity: "3", store: "Lidl")
        )
        try #require(moved.status == .ok)
        let newStore = try #require(try ShoppingFixture.object(moved)["storeId"]?.string)
        #expect(newStore != original.store)
        #expect(try await ProvenanceFixture.storeAuthor(newStore) == owner.id)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: member.id))
        let cleared = try await ShoppingFixture.request(
            .PATCH,
            path,
            owner,
            ProvenanceFixture.edit(version: 5, name: "Pan integral", quantity: nil, store: "Lidl")
        )
        try #require(cleared.status == .ok)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: nil))
        #expect(try ShoppingFixture.object(cleared)["quantity"] == .null)
        #expect(try ShoppingFixture.object(cleared)["createdBy"] == .string(owner.id.uuidString.lowercased()))
    }

    @Test
    func contentProvenanceIsNotRewoundByAReplayOrAStaleEdit() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let original = try await ProvenanceFixture.add(owner, group: group)
        let path = "/v1/groups/\(group)/items/\(original.item)"
        let firstBody = ProvenanceFixture.edit(version: 1, name: "Integral", quantity: "2", store: "Aldi")
        let first = try await ShoppingFixture.request(.PATCH, path, member, firstBody)
        try #require(first.status == .ok)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: member.id, quantity: owner.id))
        let second = try await ShoppingFixture.request(
            .PATCH,
            path,
            owner,
            ProvenanceFixture.edit(version: 2, name: "Centeno", quantity: "2", store: "Aldi")
        )
        try #require(second.status == .ok)
        let before = try await ProvenanceFixture.snapshot()
        let replay = try await ShoppingFixture.request(.PATCH, path, member, firstBody)
        #expect(replay.body.string == first.body.string)
        #expect(try await ProvenanceFixture.snapshot() == before)
        let stale = try await ShoppingFixture.request(
            .PATCH,
            path,
            member,
            ProvenanceFixture.edit(version: 2, name: "Viejo", quantity: "7", store: "No crear")
        )
        #expect(stale.status == .conflict)
        #expect(try ShoppingFixture.object(stale)["code"] == .string("item_conflict"))
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: owner.id, quantity: owner.id))
        let contentBeforeConflict = before.filter { $0.key != "mutation_receipts" }
        #expect(try await ProvenanceFixture.snapshot(includeReceipts: false) == contentBeforeConflict)
    }

    @Test
    func contentProvenanceAndNewStoresRollBackWhenTheEditFails() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let original = try await ProvenanceFixture.add(owner, group: group)
        let sql = try shoppingSQL(database)
        try await sql.raw("ALTER TABLE items ADD CONSTRAINT provenance_rejected_name CHECK(name <> 'Rechazado')").run()
        let before = try await ProvenanceFixture.snapshot()
        let body = ProvenanceFixture.edit(version: 1, name: "Rechazado", quantity: "8", store: "Nueva")
        let path = "/v1/groups/\(group)/items/\(original.item)"
        let failed = try await ShoppingFixture.request(.PATCH, path, member, body)
        #expect(failed.status == .serviceUnavailable)
        #expect(try await ProvenanceFixture.snapshot() == before)
        try await sql.raw("ALTER TABLE items DROP CONSTRAINT provenance_rejected_name").run()
        let retried = try await ShoppingFixture.request(.PATCH, path, member, body)
        try #require(retried.status == .ok)
        #expect(try await ProvenanceFixture.authors(original.item) == .init(name: member.id, quantity: member.id))
        let newStore = try #require(try ShoppingFixture.object(retried)["storeId"]?.string)
        #expect(try await ProvenanceFixture.storeAuthor(newStore) == member.id)
    }

    @Test
    func contentProvenanceMigrationPreservesLegacyDataWithoutGuessingAuthors() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        try await AddContentProvenance().revert(on: database)
        let sql = try shoppingSQL(database)
        let store = UUID()
        let item = UUID()
        try await sql.raw("""
            INSERT INTO stores(id,group_id,name,normalized_key)
            VALUES (\(bind: store),\(bind: group)::uuid,'Aldi','aldi')
            """).run()
        try await sql.raw("""
            INSERT INTO items(id,group_id,store_id,name,quantity,status,version,created_by)
            VALUES (\(bind: item),\(bind: group)::uuid,\(bind: store),'Pan','2','pending',4,\(bind: owner.id))
            """).run()
        let before = try await ProvenanceFixture.snapshot(withoutProvenance: true)
        try await AddContentProvenance().prepare(on: database)
        #expect(try await ProvenanceFixture.snapshot(withoutProvenance: true) == before)
        #expect(try await ProvenanceFixture.authors(item.uuidString) == .init(name: nil, quantity: nil))
        #expect(try await ProvenanceFixture.storeAuthor(store.uuidString) == nil)
        try await AddContentProvenance().revert(on: database)
        #expect(try await ProvenanceFixture.snapshot(withoutProvenance: true) == before)
        try await AddContentProvenance().prepare(on: database)
        let path = "/v1/groups/\(group)/items/\(item.uuidString.lowercased())"
        let changed = try await ShoppingFixture.request(
            .PATCH,
            path,
            member,
            ProvenanceFixture.edit(version: 4, name: "Pan", quantity: "3", store: "Aldi")
        )
        try #require(changed.status == .ok)
        #expect(try await ProvenanceFixture.authors(item.uuidString) == .init(name: nil, quantity: member.id))
        #expect(try await ProvenanceFixture.storeAuthor(store.uuidString) == nil)
    }

    @Test
    func contentProvenanceRollbackRefusesToDiscardKnownAuthorship() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        _ = try await ProvenanceFixture.add(owner, group: group)
        let before = try await ProvenanceFixture.snapshot()
        await #expect(throws: AddContentProvenance.ReversionError.contentProvenanceCannotBeDiscarded) {
            try await AddContentProvenance().revert(on: database)
        }
        #expect(try await ProvenanceFixture.snapshot() == before)
    }
}

private enum ProvenanceFixture {
    struct Authors: Equatable {
        let name: UUID?
        let quantity: UUID?
    }

    static func add(_ user: ShoppingFixture.User, group: String) async throws -> (item: String, store: String) {
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            .object([
                "operationId": .string(UUID().uuidString.lowercased()),
                "items": .array([.object([
                    "name": .string("Pan"), "quantity": .string("2"),
                    "store": .object(["newName": .string("Aldi")])
                ])])
            ])
        )
        try #require(response.status == .created)
        let item = try #require(try StoreQuotaFixture.array(response, key: "items").first)
        return try (#require(item["id"]?.string), #require(item["storeId"]?.string))
    }

    static func edit(
        version: Int64,
        name: String,
        quantity: String?,
        store: String
    ) -> APIJSON {
        .object([
            "operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": .integer(version),
            "name": .string(name), "quantity": .optional(quantity),
            "store": .object(["newName": .string(store)])
        ])
    }

    static func authors(_ item: String) async throws -> Authors {
        let sql = try shoppingSQL(database)
        let row = try #require(try await sql.raw("""
            SELECT name_author_user_id,quantity_author_user_id FROM items WHERE id = \(bind: item)::uuid
            """).first())
        return try Authors(
            name: row.decode(column: "name_author_user_id", as: UUID?.self),
            quantity: row.decode(column: "quantity_author_user_id", as: UUID?.self)
        )
    }

    static func storeAuthor(_ store: String) async throws -> UUID? {
        let sql = try shoppingSQL(database)
        let row = try #require(try await sql.raw("SELECT created_by FROM stores WHERE id = \(bind: store)::uuid").first())
        return try row.decode(column: "created_by", as: UUID?.self)
    }

    static func snapshot(includeReceipts: Bool = true, withoutProvenance: Bool = false) async throws -> [String: [String]] {
        let sql = try shoppingSQL(database)
        let tables = ["stores", "items"] + (includeReceipts ? ["mutation_receipts"] : [])
        var result: [String: [String]] = [:]
        for table in tables {
            let rows: [any SQLRow]
            if withoutProvenance, table == "stores" {
                rows = try await sql.raw("""
                    SELECT (to_jsonb(record) - 'created_by')::text AS snapshot FROM stores AS record ORDER BY snapshot
                    """).all()
            } else if withoutProvenance, table == "items" {
                rows = try await sql.raw("""
                    SELECT (to_jsonb(record) - 'name_author_user_id' - 'quantity_author_user_id')::text AS snapshot
                    FROM items AS record ORDER BY snapshot
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
}
