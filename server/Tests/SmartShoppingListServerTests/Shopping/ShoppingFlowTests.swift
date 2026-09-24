@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

// These tests join the existing serialized PostgreSQL suite, sharing its isolated migration lifecycle.
extension SmartShoppingListServerTests {
    @Test
    func `database failure rolls back new stores and earlier items in the batch`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let sql = try shoppingSQL(database)
        // A database-enforced failure occurs after the service has inserted the first product.
        // The isolated test migration drops this table and its temporary constraint afterwards.
        try await sql.raw("ALTER TABLE items ADD CONSTRAINT test_rejected_item CHECK(name <> 'Rechazado')").run()
        let payload = ShoppingFixture.batch(names: ["Pan", "Rechazado"], stores: ["Tienda nueva", "Otra tienda"])
        let failed = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            payload
        )
        #expect(failed.status == .serviceUnavailable)
        let stores = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", user)
        #expect(try ShoppingFixture.object(stores)["stores"] == .array([]))
        let items = try await sql.raw("SELECT id FROM items WHERE group_id = \(bind: group)::uuid").all()
        #expect(items.isEmpty)
        let receipts = try await sql.raw("""
            SELECT operation_id FROM mutation_receipts WHERE user_id = \(bind: user.id) AND operation_type = 'addItems'
            """).all()
        #expect(receipts.isEmpty)
    }

    @Test
    func `confirmed batch is shared and replayed without duplicating stores or products`() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let path = "/v1/groups/\(group)/item-batches"
        let payload = ShoppingFixture.batch(names: ["Leche sin lactosa", "Pan"], stores: [" Mercadona ", "MERCADONA"])
        let first = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            payload
        )
        try #require(first.status == .created)
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            payload
        )
        #expect(replay.status == .created)
        #expect(replay.body.string == first.body.string)

        let stores = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", member)
        let page = try ShoppingFixture.object(stores)
        guard case .array(let storeValues) = page["stores"] else {
            Issue.record("Expected store page")
            return
        }
        try #require(storeValues.count == 1)
        let store = try APIObject(storeValues[0], allowed: ["id", "groupId", "name"], required: ["id"])
        let storeID = try store.string("id")
        let pending = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores/\(storeID)/items", member)
        let persisted = try ShoppingFixture.object(pending)
        guard case .array(let values) = persisted["items"] else {
            Issue.record("Expected persisted items")
            return
        }
        #expect(values.count == 2)
        let names = values.compactMap { value -> String? in
            guard case .object(let fields) = value else { return nil }
            return fields["name"]?.string
        }
        #expect(Set(names) == ["Leche sin lactosa", "Pan"])
    }

    @Test
    func `group creation replays its original result and rejects a reused intent`() async throws {
        let user = try await ShoppingFixture.user()
        let operation = UUID().uuidString.lowercased()
        let body: APIJSON = .object(["operationId": .string(operation), "name": .string(" Casa ")])
        let first = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            body
        )
        try #require(first.status == .created)
        let repeated = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            body
        )
        #expect(repeated.body.string == first.body.string)
        let changed: APIJSON = .object(["operationId": .string(operation), "name": .string("Otro grupo")])
        let conflict = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            user,
            changed
        )
        #expect(conflict.status == .conflict)
        #expect(try ShoppingFixture.object(conflict)["code"] == .string("idempotency_key_reused"))
        let userResponse = try await ShoppingFixture.request(.GET, "/v1/me", user)
        let saved = try ShoppingFixture.object(userResponse)
        guard case .object(let group) = saved["group"] else {
            Issue.record("Expected the original group")
            return
        }
        #expect(group["name"] == .string("Casa"))
    }

    @Test
    func `an invalid batch cannot leave a new store or partial products`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let other = try await ShoppingFixture.user()
        let otherGroup = try await ShoppingFixture.group(other)
        let foreign = UUID()
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            INSERT INTO stores(id,group_id,name,normalized_key)
            VALUES (\(bind: foreign),\(bind: otherGroup)::uuid, 'Ajena','ajena')
            """).run()
        let body: APIJSON = .object([
            "operationId": .string(UUID().uuidString.lowercased()),
            "items": .array([
                .object([
                    "name": .string("Pan"), "quantity": .null,
                    "store": .object(["newName": .string("No debe persistir")])
                ]),
                .object([
                    "name": .string("Leche"), "quantity": .null,
                    "store": .object(["id": .string(foreign.uuidString.lowercased())])
                ])
            ])
        ])
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            body
        )
        #expect(response.status == .notFound)
        let stores = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores", user)
        #expect(try ShoppingFixture.object(stores)["stores"] == .array([]))
        let rows = try await sql.raw("SELECT id FROM items WHERE group_id = \(bind: group)::uuid").all()
        #expect(rows.isEmpty)
    }

    @Test
    func `strict validation and current membership prevent unauthorized writes and receipt disclosure`() async throws {
        let owner = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let path = "/v1/groups/\(group)/item-batches"
        let body = ShoppingFixture.batch(names: ["Pan"], stores: ["Día"])
        let forbidden = try await ShoppingFixture.request(
            .POST,
            path,
            outsider,
            body
        )
        #expect(forbidden.status == .notFound)
        let created = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            body
        )
        try #require(created.status == .created)
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE users SET group_id = NULL WHERE id = \(bind: owner.id)").run()
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            body
        )
        #expect(replay.status == .notFound)
        let unknown: APIJSON = .object([
            "name": .string("Casa"), "operationId": .string(UUID().uuidString.lowercased()), "creatorUserId": .string("spoof")
        ])
        let rejected = try await ShoppingFixture.request(
            .POST,
            "/v1/groups",
            outsider,
            unknown
        )
        #expect(rejected.status == .badRequest)
    }
}

struct ShoppingFixture {
    struct User: Sendable {
        let id: UUID
        let token: String
    }

    static func user() async throws -> User {
        let sql = try shoppingSQL(database)
        let id = UUID()
        let grant = UUID()
        let token = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let hash = SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
        try await sql.raw("INSERT INTO users(id,apple_subject) VALUES (\(bind: id),\(bind: id.uuidString))").run()
        try await sql.raw("""
            INSERT INTO apple_grants(id,user_id,encrypted_refresh_token,key_version,last_validated_at)
            VALUES (\(bind: grant),\(bind: id),\(bind: Data()),'test',clock_timestamp())
            """).run()
        try await sql.raw("""
            INSERT INTO app_sessions(id,user_id,apple_grant_id,token_hash,created_at,expires_at)
            VALUES (\(bind: UUID()),\(bind: id),\(bind: grant),\(bind: hash),clock_timestamp(),clock_timestamp()+INTERVAL '1 day')
            """).run()
        return User(id: id, token: token)
    }

    static func group(_ user: User) async throws -> String {
        let body: APIJSON = .object([
            "operationId": .string(UUID().uuidString.lowercased()), "name": .string("Casa")
        ])
        let response = try await request(
            .POST,
            "/v1/groups",
            user,
            body
        )
        try #require(response.status == .created)
        return try #require(try object(response)["id"]?.string)
    }

    static func join(_ user: User, group: String) async throws {
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE users SET group_id = \(bind: group)::uuid WHERE id = \(bind: user.id)").run()
    }

    static func batch(names: [String], stores: [String]) -> APIJSON {
        .object([
            "operationId": .string(UUID().uuidString.lowercased()),
            "items": .array(zip(names, stores).map { name, store in
                .object([
                    "name": .string(name), "quantity": .null,
                    "store": .object(["newName": .string(store)])
                ])
            })
        ])
    }

    static func request(
        _ method: HTTPMethod,
        _ path: String,
        _ user: User,
        _ body: APIJSON? = nil
    ) async throws -> TestingHTTPResponse {
        var headers: HTTPHeaders = ["Authorization": "Bearer \(user.token)"]
        let buffer: ByteBuffer?
        if let body {
            headers.contentType = .json
            buffer = ByteBuffer(bytes: try APIEncoding.data(body))
        } else {
            buffer = nil
        }
        return try await app.sendRequest(
            method,
            path,
            headers: headers,
            body: buffer
        )
    }

    static func object(_ response: TestingHTTPResponse) throws -> [String: APIJSON] {
        let value = try JSONDecoder().decode(APIJSON.self, from: Data(response.body.readableBytesView))
        guard case .object(let object) = value else { throw APIProblem.invalidRequest }
        return object
    }
}

extension SmartShoppingListServerTests {
    @Test
    func `products added after selection remain pending when the original purchase completes`() async throws {
        let buyer = try await ShoppingFixture.user()
        let contributor = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(buyer)
        try await ShoppingFixture.join(contributor, group: group)
        let fixture = try await PurchaseFixture.items(buyer, group: group)
        let selected = Array(fixture.ids.prefix(3))
        let payload = PurchaseFixture.body(store: fixture.store, ids: selected)

        let addition = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            contributor,
            ShoppingFixture.batch(names: ["Fresas"], stores: ["Mercadona"])
        )
        try #require(addition.status == .created)
        let added = try ShoppingFixture.object(addition)
        guard case .array(let items) = added["items"], case .object(let item) = items.first else {
            throw APIProblem.invalidRequest
        }
        let addedID = try #require(item["id"]?.string)
        try #require(item["storeId"] == .string(fixture.store))

        let purchase = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            buyer,
            payload
        )
        try #require(purchase.status == .ok)
        let sql = try shoppingSQL(database)
        let purchased = try await sql.raw("""
            SELECT id FROM items WHERE group_id = \(bind: group)::uuid AND status = 'purchased'
            """).all()
        let purchasedIDs = try purchased.map {
            try $0.decode(column: "id", as: UUID.self).uuidString.lowercased()
        }
        #expect(Set(purchasedIDs) == Set(selected))
        let pending = try await sql.raw("""
            SELECT id FROM items WHERE group_id = \(bind: group)::uuid AND status = 'pending'
            """).all()
        #expect(pending.count == 4)
        let row = try #require(try await sql.raw("SELECT * FROM items WHERE id = \(bind: addedID)::uuid").first())
        #expect(try row.decode(column: "name", as: String.self) == "Fresas")
        #expect(try row.decode(column: "status", as: String.self) == "pending")
        #expect(try row.decode(column: "version", as: Int.self) == 1)
        #expect(try row.decode(column: "created_by", as: UUID.self) == contributor.id)
        #expect(try row.decode(column: "purchased_by", as: UUID?.self) == nil)
        #expect(try row.decode(column: "purchased_at", as: Date?.self) == nil)
    }

    @Test(arguments: [
        ("Pan integral", "2 bolsas", "pending", "version_mismatch"),
        ("Pan", nil, "cancelled", "not_pending")
    ] as [(String, String?, String, String)])
    func `an intervening edit or cancellation rejects the whole purchase without overwriting products`(
        name: String,
        quantity: String?,
        status: String,
        reason: String
    ) async throws {
        let buyer = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(buyer)
        let fixture = try await PurchaseFixture.items(buyer, group: group)
        let payload = PurchaseFixture.body(store: fixture.store, ids: Array(fixture.ids.prefix(3)))
        let sql = try shoppingSQL(database)

        // Edit/cancel routes are outside this block; seed a committed change after selection.
        try await sql.raw("""
            UPDATE items SET name = \(bind: name), quantity = \(bind: quantity),
                status = \(bind: status), version = 2 WHERE id = \(bind: fixture.ids[0])::uuid
            """).run()
        let before = try await sql.raw("""
            SELECT row_to_json(items)::text AS snapshot FROM items
            WHERE group_id = \(bind: group)::uuid ORDER BY id
            """).all().map {
                try $0.decode(column: "snapshot", as: String.self)
            }
        try #require(before.count == 6)

        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            buyer,
            payload
        )
        try #require(response.status == .conflict)
        let body = try ShoppingFixture.object(response)
        #expect(body["code"] == .string("item_conflict"))
        guard case .array(let conflicts) = body["conflicts"],
              case .object(let conflict) = conflicts.first,
              case .object(let current) = conflict["current"] else {
            throw APIProblem.invalidRequest
        }
        #expect(conflicts.count == 1)
        #expect(conflict["itemId"] == .string(fixture.ids[0]))
        #expect(conflict["reason"] == .string(reason))
        #expect(current["name"] == .string(name))
        #expect(current["quantity"] == (quantity.map(APIJSON.string) ?? .null))
        #expect(current["status"] == .string(status))
        #expect(current["version"] == .integer(2))
        let after = try await sql.raw("""
            SELECT row_to_json(items)::text AS snapshot FROM items
            WHERE group_id = \(bind: group)::uuid ORDER BY id
            """).all().map {
                try $0.decode(column: "snapshot", as: String.self)
            }
        #expect(after == before)
    }

    @Test
    func `purchase changes only the selected products and replays the original receipt`() async throws {
        let owner = try await ShoppingFixture.user()
        let buyer = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(buyer, group: group)
        let fixture = try await PurchaseFixture.items(owner, group: group)
        let selected = Array(fixture.ids.prefix(3))
        let payload = PurchaseFixture.body(store: fixture.store, ids: selected)
        let path = "/v1/groups/\(group)/purchases"
        let first = try await ShoppingFixture.request(
            .POST,
            path,
            buyer,
            payload
        )
        try #require(first.status == .ok)
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            buyer,
            payload
        )
        #expect(replay.body.string == first.body.string)
        let sql = try shoppingSQL(database)
        let rows = try await sql.raw("SELECT * FROM items WHERE group_id = \(bind: group)::uuid").all()
        #expect(rows.count == 6)
        for row in rows {
            let id = try row.decode(column: "id", as: UUID.self).uuidString.lowercased()
            if selected.contains(id) {
                #expect(try row.decode(column: "status", as: String.self) == "purchased")
                #expect(try row.decode(column: "version", as: Int.self) == 2)
                #expect(try row.decode(column: "purchased_by", as: UUID.self) == buyer.id)
            } else {
                #expect(try row.decode(column: "status", as: String.self) == "pending")
                #expect(try row.decode(column: "version", as: Int.self) == 1)
            }
        }
        let result = try ShoppingFixture.object(first)
        guard case .array(let bought) = result["items"] else {
            Issue.record("Expected purchased entries")
            return
        }
        #expect(bought.count == 3)
        for item in bought {
            guard case .object(let fields) = item else { throw APIProblem.invalidRequest }
            #expect(fields["purchasedAt"] == result["confirmedAt"])
        }
    }

    @Test
    func `one stale product rejects the whole purchase and preserves its conflict receipt`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let fixture = try await PurchaseFixture.items(user, group: group)
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE items SET version = 2 WHERE id = \(bind: fixture.ids[0])::uuid").run()
        let payload = PurchaseFixture.body(store: fixture.store, ids: Array(fixture.ids.prefix(3)))
        let path = "/v1/groups/\(group)/purchases"
        let failed = try await ShoppingFixture.request(
            .POST,
            path,
            user,
            payload
        )
        try #require(failed.status == .conflict)
        let body = try ShoppingFixture.object(failed)
        #expect(body["code"] == .string("item_conflict"))
        guard case .array(let conflicts) = body["conflicts"], case .object(let conflict) = conflicts.first else {
            Issue.record("Expected explicit conflicts")
            return
        }
        #expect(conflict["reason"] == .string("version_mismatch"))
        let purchased = try await sql.raw("SELECT id FROM items WHERE status = 'purchased'").all()
        #expect(purchased.isEmpty)
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            user,
            payload
        )
        #expect(replay.body.string == failed.body.string)
    }

    @Test
    func `competing buyers cannot overwrite a purchase or partially buy their remaining selection`() async throws {
        let firstBuyer = try await ShoppingFixture.user()
        let secondBuyer = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(firstBuyer)
        try await ShoppingFixture.join(secondBuyer, group: group)
        let fixture = try await PurchaseFixture.items(firstBuyer, group: group)
        let path = "/v1/groups/\(group)/purchases"
        async let first = ShoppingFixture.request(
            .POST,
            path,
            firstBuyer,
            PurchaseFixture.body(store: fixture.store, ids: Array(fixture.ids.prefix(2)))
        )
        async let second = ShoppingFixture.request(
            .POST,
            path,
            secondBuyer,
            PurchaseFixture.body(store: fixture.store, ids: Array(fixture.ids[1...2]))
        )
        let replies = try await [first, second]
        #expect(replies.map(\.status.code).sorted() == [200, 409])
        let winner = replies[0].status == .ok ? firstBuyer.id : secondBuyer.id
        let sql = try shoppingSQL(database)
        let rows = try await sql.raw("SELECT purchased_by FROM items WHERE status = 'purchased'").all()
        #expect(rows.count == 2)
        for row in rows {
            #expect(try row.decode(column: "purchased_by", as: UUID.self) == winner)
        }
    }
}

private enum PurchaseFixture {
    static func items(_ user: ShoppingFixture.User, group: String) async throws -> (store: String, ids: [String]) {
        let created = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            ShoppingFixture.batch(
                names: ["Pan", "Leche", "Huevos", "Arroz", "Yogur", "Leche"],
                stores: ["Mercadona", "Mercadona", "Mercadona", "Mercadona", "Mercadona", "Aldi"]
            )
        )
        try #require(created.status == .created)
        let result = try ShoppingFixture.object(created)
        guard case .array(let items) = result["items"], case .object(let first) = items.first else {
            throw APIProblem.invalidRequest
        }
        let ids = try items.prefix(5).map { item -> String in
            guard case .object(let value) = item, let id = value["id"]?.string else { throw APIProblem.invalidRequest }
            return id
        }
        return (try #require(first["storeId"]?.string), ids)
    }

    static func body(store: String, ids: [String], operation: UUID = UUID()) -> APIJSON {
        .object([
            "operationId": .string(operation.uuidString.lowercased()), "storeId": .string(store),
            "items": .array(ids.map { .object(["id": .string($0), "expectedVersion": .integer(1)]) })
        ])
    }
}

extension SmartShoppingListServerTests {
    @Test
    func `purchase conflicts hide foreign products and reject every selected entry atomically`() async throws {
        let owner = try await ShoppingFixture.user()
        let foreignOwner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let otherGroup = try await ShoppingFixture.group(foreignOwner)
        let local = try await PurchaseFixture.items(owner, group: group)
        let foreign = try await PurchaseFixture.items(foreignOwner, group: otherGroup)
        let missing = UUID().uuidString.lowercased()
        let body = PurchaseFixture.body(store: local.store, ids: [local.ids[0], foreign.ids[0], missing])
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            owner,
            body
        )
        try #require(response.status == .conflict)
        let result = try ShoppingFixture.object(response)
        guard case .array(let conflicts) = result["conflicts"] else { throw APIProblem.invalidRequest }
        #expect(conflicts.count == 2)
        for conflict in conflicts {
            guard case .object(let fields) = conflict else { throw APIProblem.invalidRequest }
            #expect(fields["reason"] == .string("not_found"))
            #expect(fields["current"] == .null)
        }
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT id FROM items WHERE status = 'purchased'").all().isEmpty)
        let unauthorized = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            foreignOwner,
            body
        )
        #expect(unauthorized.status == .notFound)
    }

    @Test
    func `invalid purchase selections never reserve a receipt or change products`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let fixture = try await PurchaseFixture.items(user, group: group)
        let invalid: [[String]] = [[], [fixture.ids[0], fixture.ids[0]], (0..<51).map { _ in UUID().uuidString.lowercased() }]
        for ids in invalid {
            let response = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/purchases",
                user,
                PurchaseFixture.body(store: fixture.store, ids: ids)
            )
            #expect(response.status == .badRequest)
        }
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT id FROM items WHERE status = 'purchased'").all().isEmpty)
        #expect(try await sql.raw("""
            SELECT operation_id FROM mutation_receipts WHERE operation_type = 'finalizePurchase'
            """).all().isEmpty)
    }

    @Test
    func `purchase database failure rolls back both transitions and receipt`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let fixture = try await PurchaseFixture.items(user, group: group)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            ALTER TABLE items ADD CONSTRAINT reject_test_purchase CHECK(status <> 'purchased' OR name <> 'Huevos')
            """).run()
        let payload = PurchaseFixture.body(store: fixture.store, ids: Array(fixture.ids.prefix(3)))
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            user,
            payload
        )
        #expect(response.status == .serviceUnavailable)
        #expect(try await sql.raw("SELECT id FROM items WHERE status = 'purchased'").all().isEmpty)
        #expect(try await sql.raw("""
            SELECT operation_id FROM mutation_receipts WHERE operation_type = 'finalizePurchase'
            """).all().isEmpty)
        try await sql.raw("ALTER TABLE items DROP CONSTRAINT reject_test_purchase").run()
        let retry = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            user,
            payload
        )
        #expect(retry.status == .ok)
    }

    @Test
    func `simultaneous same purchase intent replays regardless of selection order`() async throws {
        let user = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(user)
        let fixture = try await PurchaseFixture.items(user, group: group)
        let operation = UUID()
        let ids = Array(fixture.ids.prefix(3))
        let path = "/v1/groups/\(group)/purchases"
        async let first = ShoppingFixture.request(
            .POST,
            path,
            user,
            PurchaseFixture.body(store: fixture.store, ids: ids, operation: operation)
        )
        async let second = ShoppingFixture.request(
            .POST,
            path,
            user,
            PurchaseFixture.body(store: fixture.store, ids: ids.reversed(), operation: operation)
        )
        let (a, b) = try await (first, second)
        #expect(a.status == .ok)
        #expect(b.body.string == a.body.string)
        let changed = try await ShoppingFixture.request(
            .POST,
            path,
            user,
            PurchaseFixture.body(store: fixture.store, ids: Array(ids.prefix(1)), operation: operation)
        )
        #expect(changed.status == .conflict)
        #expect(try ShoppingFixture.object(changed)["code"] == .string("idempotency_key_reused"))
    }
}
