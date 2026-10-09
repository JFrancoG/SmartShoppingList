@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Free slots aggregate normalized stores and pending entries before any batch writes")
    func freeStoreAndPendingQuotasAreAtomic() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let first = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: " Mercadona ",
            count: 19
        )
        let store = try #require(first.first?["storeId"]?.string)
        let before = try await AdministrationFixture.itemSnapshot(group: group)
        let over: APIJSON = .object([
            "operationId": .string(UUID().uuidString.lowercased()),
            "items": .array([
                StoreQuotaFixture.item(store: .object(["id": .string(store)])),
                StoreQuotaFixture.item(store: .object(["newName": .string("MERCADONA")])),
                StoreQuotaFixture.item(store: .object(["newName": .string("No debe persistir")]))
            ])
        ])
        let rejected = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            owner,
            over
        )
        #expect(try StoreQuotaFixture.code(rejected) == "pending_item_limit_reached")
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == before)
        #expect(try await StoreQuotaFixture.stores(owner, group: group).count == 1)
        _ = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "MERCADONA",
            count: 1
        )
        _ = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Aldi",
            count: 1
        )
        let tooManyStores = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            owner,
            ShoppingFixture.batch(names: ["Uno", "Dos"], stores: ["Lidl", "Día"])
        )
        #expect(try StoreQuotaFixture.code(tooManyStores) == "store_limit_reached")
        #expect(try await StoreQuotaFixture.stores(owner, group: group).count == 2)
        _ = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Lidl",
            count: 1
        )
        let capacity = try await StoreQuotaFixture.capacity(owner, group: group)
        #expect(capacity["groupId"] == .string(group))
        #expect(capacity["activeStoreCount"] == .integer(3))
        #expect(capacity["canCreateStore"] == .bool(false))
        #expect(capacity["limits"] == StoreQuotaFixture.freeLimits)
        let stores = try await StoreQuotaFixture.stores(owner, group: group)
        let full = try #require(stores.first { $0["id"] == .string(store) })
        #expect(full["pendingItemCount"] == .integer(20))
        #expect(try StoreQuotaFixture.fields(full["capabilities"])["canAddItems"] == .bool(false))
    }

    @Test("A confirmed capacity rejection stays exact after cancellation frees room; a new intent succeeds")
    func quotaRejectionIsTerminalAndCancellationFreesRoom() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let items = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Casa",
            count: 20
        )
        let body = ShoppingFixture.batch(names: ["Nuevo"], stores: ["Casa"])
        let path = "/v1/groups/\(group)/item-batches"
        let rejected = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            body
        )
        #expect(try StoreQuotaFixture.code(rejected) == "pending_item_limit_reached")
        let cancelled = try await StoreQuotaFixture.cancel(owner, group: group, item: items[0])
        #expect(cancelled.status == .ok)
        let replay = try await ShoppingFixture.request(
            .POST,
            path,
            owner,
            body
        )
        #expect(replay.body.string == rejected.body.string)
        _ = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Casa",
            count: 1
        )
        let pending = try await ShoppingFixture.allPending(group: group, user: owner)
        #expect(pending.count == 20)
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT id FROM items WHERE status = 'cancelled'").all().count == 1)
    }

    @Test("The administrator's trusted premium policy supplies 10 stores and 100 entries to every member")
    func premiumGroupCapacityUsesAdministratorInsteadOfWriter() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(resolve: { id in
            id == owner.id ? .premium : .free
        })) {
            let group = try await ShoppingFixture.group(owner)
            try await ShoppingFixture.join(member, group: group)
            _ = try await StoreQuotaFixture.add(
                member,
                group: group,
                store: "Grande",
                count: 50
            )
            _ = try await StoreQuotaFixture.add(
                member,
                group: group,
                store: "Grande",
                count: 50
            )
            let blocked = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                member,
                ShoppingFixture.batch(names: ["Sobra"], stores: ["Grande"])
            )
            #expect(try StoreQuotaFixture.code(blocked) == "pending_item_limit_reached")
            for index in 1...9 {
                _ = try await StoreQuotaFixture.add(
                    member,
                    group: group,
                    store: "Tienda \(index)",
                    count: 1
                )
            }
            let capacity = try await StoreQuotaFixture.capacity(member, group: group)
            #expect(capacity["activeStoreCount"] == .integer(10))
            #expect(capacity["capacityOwnerUserId"] == .string(owner.id.uuidString.lowercased()))
            #expect(capacity["canCreateStore"] == .bool(false))
            let extra = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                member,
                ShoppingFixture.batch(names: ["Sobra"], stores: ["Undécima"])
            )
            #expect(try StoreQuotaFixture.code(extra) == "store_limit_reached")
            let administration = try await AdministrationFixture.snapshot(member, group: group)
            let capabilities = try StoreQuotaFixture.fields(administration["capabilities"])
            let limits = try StoreQuotaFixture.fields(capabilities["limits"])
            #expect(limits["groupsPerAccount"] == .object(["maximum": .integer(1), "enforced": .bool(true)]))
            #expect(limits["storesPerGroup"] == .object(["maximum": .integer(10), "enforced": .bool(true)]))
            #expect(limits["pendingItemsPerStore"] == .object(["maximum": .integer(100), "enforced": .bool(true)]))
        }
    }

    @Test("Moving frees its source and admits only positive destination growth; same-store edits remain possible")
    func movesAndEditsRespectNetPendingGrowth() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let full = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Completa",
            count: 20
        )
        let source = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Origen",
            count: 1
        )
        let fullStore = try #require(full.first?["storeId"]?.string)
        let before = try await AdministrationFixture.itemSnapshot(group: group)
        let refused = try await StoreQuotaFixture.edit(
            owner,
            group: group,
            item: source[0],
            store: fullStore
        )
        #expect(try StoreQuotaFixture.code(refused) == "pending_item_limit_reached")
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == before)
        let unchangedStore = try await StoreQuotaFixture.edit(
            owner,
            group: group,
            item: full[0],
            store: fullStore
        )
        #expect(unchangedStore.status == .ok)
        _ = try await StoreQuotaFixture.cancel(owner, group: group, item: full[1])
        let moved = try await StoreQuotaFixture.edit(
            owner,
            group: group,
            item: source[0],
            store: fullStore
        )
        #expect(moved.status == .ok)
        let stores = try await StoreQuotaFixture.stores(owner, group: group)
        #expect(stores.first { $0["name"] == .string("Origen") }?["pendingItemCount"] == .integer(0))
        #expect(stores.first { $0["name"] == .string("Completa") }?["pendingItemCount"] == .integer(20))
    }

    @Test("A premium administrator cannot lend its account membership allowance to a free invitee")
    func invitedAccountKeepsItsOwnGroupAllowance() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(resolve: { id in
            id == owner.id ? .premium : .free
        })) {
            let own = try await ShoppingFixture.group(member)
            _ = try await ShoppingFixture.group(owner)
            let shared = try await ShoppingFixture.group(owner)
            let invitation = try await ShoppingFixture.invitation(shared)
            let refused = try await MembershipFixture.accept(invitation, user: member)
            #expect(try StoreQuotaFixture.code(refused) == "group_limit_reached")
            #expect(try await MembershipFixture.groupIDs(ShoppingFixture.request(.GET, "/v1/groups", member)) == [own])
            _ = try await MembershipFixture.depart(member, group: own)
            #expect(try await MembershipFixture.accept(invitation, user: member).status == .ok)
            let another = try await ShoppingFixture.invitation(shared)
            #expect(try await MembershipFixture.accept(another, user: member).status == .ok)
            let me = try await ShoppingFixture.request(.GET, "/v1/me", member)
            #expect(try MembershipFixture.capabilities(me)["membershipCount"] == .integer(1))
            for _ in 0..<3 {
                _ = try await ShoppingFixture.group(owner)
            }
            let sixth = try await ShoppingFixture.request(
                .POST,
                "/v1/groups",
                owner,
                MembershipFixture.creationBody()
            )
            #expect(try StoreQuotaFixture.code(sixth) == "group_limit_reached")
        }
    }
}

enum StoreQuotaFixture {
    static let freeLimits: APIJSON = .object([
        "storesPerGroup": .object(["maximum": .integer(3), "enforced": .bool(true)]),
        "pendingItemsPerStore": .object(["maximum": .integer(20), "enforced": .bool(true)])
    ])

    static func item(store: APIJSON) -> APIJSON {
        .object(["name": .string("Producto"), "quantity": .null, "store": store])
    }

    static func fields(_ value: APIJSON?) throws -> [String: APIJSON] {
        guard case .object(let fields) = value else { throw APIProblem.invalidRequest }
        return fields
    }

    static func code(_ response: TestingHTTPResponse) throws -> String {
        try #require(response.status == .conflict)
        return try #require(try ShoppingFixture.object(response)["code"]?.string)
    }

    static func add(
        _ user: ShoppingFixture.User,
        group: String,
        store: String,
        count: Int
    ) async throws -> [[String: APIJSON]] {
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            ShoppingFixture.batch(
                names: Array(repeating: "Producto", count: count),
                stores: Array(repeating: store, count: count)
            )
        )
        try #require(response.status == .created)
        return try array(response, key: "items")
    }

    static func array(_ response: TestingHTTPResponse, key: String) throws -> [[String: APIJSON]] {
        guard case .array(let values) = try ShoppingFixture.object(response)[key] else {
            throw APIProblem.invalidRequest
        }
        return try values.map { try fields($0) }
    }

    static func stores(
        _ user: ShoppingFixture.User,
        group: String,
        state: String = "active"
    ) async throws -> [[String: APIJSON]] {
        let response = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores?state=\(state)", user)
        try #require(response.status == .ok)
        return try array(response, key: "stores")
    }

    static func capacity(_ user: ShoppingFixture.User, group: String) async throws -> [String: APIJSON] {
        let response = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/capacity", user)
        try #require(response.status == .ok)
        return try ShoppingFixture.object(response)
    }

    static func cancel(
        _ user: ShoppingFixture.User,
        group: String,
        item: [String: APIJSON]
    ) async throws -> TestingHTTPResponse {
        let id = try #require(item["id"]?.string)
        return try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/items/\(id)/cancellation",
            user,
            .object([
                "operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": item["version"] ?? .null
            ])
        )
    }

    static func edit(
        _ user: ShoppingFixture.User,
        group: String,
        item: [String: APIJSON],
        store: String
    ) async throws -> TestingHTTPResponse {
        let id = try #require(item["id"]?.string)
        return try await ShoppingFixture.request(
            .PATCH,
            "/v1/groups/\(group)/items/\(id)",
            user,
            .object([
                "operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": item["version"] ?? .null,
                "name": .string("Editado"), "quantity": .string("2"), "store": .object(["id": .string(store)])
            ])
        )
    }

    static func archive(
        _ user: ShoppingFixture.User,
        group: String,
        store: String,
        body: APIJSON = AdministrationFixture.operation()
    ) async throws -> TestingHTTPResponse {
        try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/stores/\(store)/archive",
            user,
            body
        )
    }

    static func restore(
        _ user: ShoppingFixture.User,
        group: String,
        store: String,
        body: APIJSON = AdministrationFixture.operation()
    ) async throws -> TestingHTTPResponse {
        try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/stores/\(store)/restore",
            user,
            body
        )
    }
}
