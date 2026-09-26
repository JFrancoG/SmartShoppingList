@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("New products accept 60 Unicode scalars and new stores accept 40", arguments: [false, true])
    func nameLimitBoundaries(editing: Bool) async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let fixture = try await PurchaseFixture.items(user, group: group)
        let name = String(repeating: "👩🏽", count: 30)
        let store = String(repeating: "👩🏽", count: 20)
        let quantity = String(repeating: "Q", count: 80)
        let body = ShoppingNameLimitFixture.body(
            name: name,
            store: store,
            quantity: quantity,
            editing: editing
        )
        let path = "/v1/groups/\(group)/" + (editing ? "items/\(fixture.ids[0])" : "item-batches")
        let response = try await ShoppingFixture.request(
            editing ? .PATCH : .POST,
            path,
            user,
            body
        )
        try #require(response.status == (editing ? .ok : .created))
        let sql = try shoppingSQL(database)
        let rows = try await sql.raw("""
            SELECT items.name,items.quantity,stores.name AS store_name FROM items
            JOIN stores ON items.store_id = stores.id WHERE items.name = \(bind: name)
            """).all()
        try #require(rows.count == 1)
        #expect(try rows[0].decode(column: "name", as: String.self) == name)
        #expect(try rows[0].decode(column: "store_name", as: String.self) == store)
        #expect(try rows[0].decode(column: "quantity", as: String.self) == quantity)
    }

    @Test("Overlong received names cannot create stores or mutate products", arguments: [false, true], [
        (String(repeating: "👩🏽", count: 30) + "x", "New store"),
        ("New product", String(repeating: "👩🏽", count: 20) + "x"),
        (String(repeating: "P", count: 60) + " ", "New store"),
        ("New product", String(repeating: "S", count: 40) + " ")
    ])
    func overlongNamesAreAtomic(editing: Bool, names: (String, String)) async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let fixture = try await PurchaseFixture.items(user, group: group)
        let operation = UUID()
        var body = ShoppingNameLimitFixture.body(
            name: names.0,
            store: names.1,
            editing: editing,
            operation: operation
        )
        if !editing, case .object(var fields) = body, case .array(let items) = fields["items"] {
            fields["items"] = .array([.object([
                "name": .string("Bread"), "quantity": .null, "store": .object(["newName": .string("Bakery")])
            ])] + items)
            body = .object(fields)
        }
        let path = "/v1/groups/\(group)/" + (editing ? "items/\(fixture.ids[0])" : "item-batches")
        let response = try await ShoppingFixture.request(
            editing ? .PATCH : .POST,
            path,
            user,
            body
        )
        #expect(response.status == .badRequest)
        #expect(try ShoppingFixture.object(response)["code"] == .string("invalid_request"))
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT id FROM stores").all().count == 2)
        #expect(try await sql.raw("SELECT id FROM items").all().count == 6)
        #expect(try await sql.raw("SELECT id FROM items WHERE version <> 1").all().isEmpty)
        #expect(try await sql.raw("""
            SELECT operation_id FROM mutation_receipts WHERE operation_id = \(bind: operation)
            """).all().isEmpty)
    }

    @Test("Legacy confirmed requests replay and existing long names remain usable", arguments: [false, true])
    func legacyNameReceiptsRemainRecoverable(editing: Bool) async throws {
        let user = try await ShoppingFixture.user()
        let group = "00000000-0000-4000-8000-000000000010"
        let store = "00000000-0000-4000-8000-000000000020"
        let item = "00000000-0000-4000-8000-000000000030"
        let name = String(repeating: "P", count: 160)
        let storeName = String(repeating: "S", count: 80)
        let operation = UUID()
        let version = editing ? 2 : 1
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            INSERT INTO groups(id,name,creator_user_id) VALUES (\(bind: group)::uuid,'Legacy group',\(bind: user.id))
            """).run()
        try await sql.raw("UPDATE users SET group_id = \(bind: group)::uuid WHERE id = \(bind: user.id)").run()
        try await sql.raw("""
            INSERT INTO stores(id,group_id,name,normalized_key)
            VALUES (\(bind: store)::uuid,\(bind: group)::uuid,\(bind: storeName),\(bind: storeName.lowercased()))
            """).run()
        try await sql.raw("""
            INSERT INTO items(id,group_id,store_id,name,status,version,created_by)
            VALUES (\(bind: item)::uuid,\(bind: group)::uuid,\(bind: store)::uuid,\(bind: name),
                'pending',\(bind: version),\(bind: user.id))
            """).run()
        let persisted = try #require(try await sql.raw("SELECT * FROM items WHERE id = \(bind: item)::uuid").first())
        let itemJSON = try ShoppingService.itemJSON(persisted)
        let result: APIJSON = editing ? itemJSON : .object(["items": .array([itemJSON])])
        let receipt = String(decoding: try APIEncoding.data(result), as: UTF8.self)
        // Fixed fingerprints from the prior 160/80 contract, independent of the current parser.
        let fingerprint = editing
            ? "a97866cb50e54f345f70fbdd9a388360c90c9e681d4a60207be15c2f32692863"
            : "a2b19b41333010bb452adcafc2bddad379a97fc87a1fb20205dd580fcda06db2"
        try await sql.raw("""
            INSERT INTO mutation_receipts(user_id,operation_id,operation_type,group_id,fingerprint,status,body)
            VALUES (\(bind: user.id),\(bind: operation),\(bind: editing ? "editItem" : "addItems"),
                \(bind: group)::uuid,\(bind: fingerprint),\(bind: editing ? 200 : 201),\(bind: receipt))
            """).run()
        let body = ShoppingNameLimitFixture.body(
            name: name,
            store: storeName,
            editing: editing,
            operation: operation
        )
        let path = "/v1/groups/\(group)/" + (editing ? "items/\(item)" : "item-batches")
        let method: HTTPMethod = editing ? .PATCH : .POST
        let replay = try await ShoppingFixture.request(
            method,
            path,
            user,
            body
        )
        #expect(replay.status == (editing ? .ok : .created))
        #expect(replay.body.string == receipt)
        let changed = ShoppingNameLimitFixture.body(
            name: String(repeating: "P", count: 159) + "X",
            store: storeName,
            editing: editing,
            operation: operation
        )
        let reused = try await ShoppingFixture.request(
            method,
            path,
            user,
            changed
        )
        #expect(reused.status == .conflict)
        #expect(try ShoppingFixture.object(reused)["code"] == .string("idempotency_key_reused"))
        let newIntent = ShoppingNameLimitFixture.body(name: name, store: storeName, editing: editing)
        let rejected = try await ShoppingFixture.request(
            method,
            path,
            user,
            newIntent
        )
        #expect(rejected.status == .badRequest)
        let page = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores/\(store)/items", user)
        guard case .array(let items) = try ShoppingFixture.object(page)["items"],
              case .object(let existing) = items.first else { throw APIProblem.invalidRequest }
        #expect(existing["name"] == .string(name))
        #expect(try await sql.raw("SELECT id FROM items").all().count == 1)
        #expect(try await sql.raw("SELECT operation_id FROM mutation_receipts").all().count == 1)
        let transition: APIJSON = editing
            ? .object(["operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": .integer(2)])
            : PurchaseFixture.body(store: store, ids: [item])
        let transitionPath = "/v1/groups/\(group)/" + (editing ? "items/\(item)/cancellation" : "purchases")
        let transitioned = try await ShoppingFixture.request(
            .POST,
            transitionPath,
            user,
            transition
        )
        #expect(transitioned.status == .ok)
    }
}

private enum ShoppingNameLimitFixture {
    static func body(
        name: String,
        store: String,
        quantity: String? = nil,
        editing: Bool,
        operation: UUID = UUID()
    ) -> APIJSON {
        let item: APIJSON = .object([
            "name": .string(name), "quantity": .optional(quantity), "store": .object(["newName": .string(store)])
        ])
        if editing, case .object(var fields) = item {
            fields["operationId"] = .string(operation.uuidString.lowercased())
            fields["expectedVersion"] = .integer(1)
            return .object(fields)
        }
        return .object(["operationId": .string(operation.uuidString.lowercased()), "items": .array([item])])
    }
}
