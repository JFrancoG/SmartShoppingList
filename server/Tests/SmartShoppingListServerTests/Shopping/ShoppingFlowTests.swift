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
