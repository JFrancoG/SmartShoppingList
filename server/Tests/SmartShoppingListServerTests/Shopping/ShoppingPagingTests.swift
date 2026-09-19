@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test
    func `store folding preserves accents and pages reject cursors from another resource`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let body = ShoppingFixture.batch(
            names: ["Uno", "Dos", "Tres", "Cuatro", "Cinco"],
            stores: ["Straße", "STRASSE", "Di\u{0061}\u{0301}", "Diá", "Dia"]
        )
        let created = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            body
        )
        try #require(created.status == .created)
        let path = "/v1/groups/\(group)/stores"
        let first = try await ShoppingFixture.request(.GET, path + "?limit=2", user)
        let firstPage = try ShoppingFixture.object(first)
        guard case .array(let initial) = firstPage["stores"] else {
            Issue.record("Missing store page")
            return
        }
        #expect(initial.count == 2)
        let cursor = try #require(firstPage["nextCursor"]?.string)
        let last = try await ShoppingFixture.request(.GET, path + "?limit=2&cursor=\(cursor)", user)
        let lastPage = try ShoppingFixture.object(last)
        guard case .array(let final) = lastPage["stores"] else {
            Issue.record("Missing final store page")
            return
        }
        #expect(final.count == 1)
        #expect(lastPage["nextCursor"] == .null)
        let combined = initial + final
        let names = Set(combined.compactMap { row -> String? in
            guard case .object(let fields) = row else { return nil }
            return fields["name"]?.string
        })
        #expect(names == ["Straße", "Diá", "Dia"])
        let wrongResource = try await ShoppingFixture.request(
            .GET, "/v1/groups/\(group)/invitations?cursor=\(cursor)", user
        )
        #expect(wrongResource.status == .badRequest)
        let changed = cursor.dropLast() + (cursor.last == "A" ? "B" : "A")
        let forged = try await ShoppingFixture.request(.GET, path + "?cursor=\(changed)", user)
        #expect(forged.status == .badRequest)
    }

    @Test
    func `terminal group conflict is replayed even after membership changes`() async throws {
        let user = try await ShoppingFixture.user()
        _ = try await ShoppingFixture.group(user)
        let body: APIJSON = .object([
            "operationId": .string(UUID().uuidString.lowercased()), "name": .string("Otra intención")
        ])
        let original = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            body
        )
        try #require(original.status == .conflict)
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE users SET group_id = NULL WHERE id = \(bind: user.id)").run()
        let replay = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            body
        )
        #expect(replay.status == .conflict)
        #expect(replay.body.string == original.body.string)
        let current = try await ShoppingFixture.request(.GET, "/v1/me", user)
        #expect(try ShoppingFixture.object(current)["group"] == .null)
    }

    @Test
    func `oversized and incomplete batches fail before writing`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let oversized = ShoppingFixture.batch(
            names: Array(repeating: "Pan", count: 51),
            stores: Array(repeating: "Día", count: 51)
        )
        let tooMany = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            oversized
        )
        #expect(tooMany.status == .badRequest)
        let absentQuantity: APIJSON = .object([
            "operationId": .string(UUID().uuidString.lowercased()),
            "items": .array([.object([
                "name": .string("Pan"), "store": .object(["newName": .string("Día")])
            ])])
        ])
        let incomplete = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            absentQuantity
        )
        #expect(incomplete.status == .badRequest)
        let stores = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", user)
        #expect(try ShoppingFixture.object(stores)["stores"] == .array([]))
    }
}
