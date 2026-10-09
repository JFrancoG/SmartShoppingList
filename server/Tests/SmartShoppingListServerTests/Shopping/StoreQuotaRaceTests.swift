@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test(
        "Two writers cannot both consume the final pending-item or active-store slot",
        .timeLimit(.minutes(1)),
        arguments: ["pending", "store"]
    )
    func concurrentStoreQuotaAdmissions(resource: String) async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        _ = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "A",
            count: resource == "pending" ? 19 : 1
        )
        if resource == "store" {
            _ = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: "B",
                count: 1
            )
        }
        let firstBody = ShoppingFixture.batch(names: ["Primero"], stores: [resource == "pending" ? "A" : "C"])
        let secondBody = ShoppingFixture.batch(names: ["Segundo"], stores: [resource == "pending" ? "A" : "D"])
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM groups WHERE id = \(bind: group)::uuid FOR UPDATE",
            waitingQuery: "%FROM groups%FOR UPDATE%",
            first: {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    owner,
                    firstBody
                )
            },
            second: {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    member,
                    secondBody
                )
            }
        )
        #expect(responses.0.status == .created)
        #expect(try StoreQuotaFixture.code(responses.1) == (resource == "pending"
            ? "pending_item_limit_reached" : "store_limit_reached"))
        let stores = try await StoreQuotaFixture.stores(owner, group: group)
        #expect(stores.count == (resource == "pending" ? 1 : 3))
        #expect(
            try await ShoppingFixture.allPending(group: group, user: owner).count == (resource == "pending" ? 20 : 3)
        )
    }

    @Test(
        "Restoration and implicit creation share the same final store slot",
        .timeLimit(.minutes(1)),
        arguments: [true, false]
    )
    func restorationRacesNewStoreCreation(restoreFirst: Bool) async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let item = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Archivada",
            count: 1
        )[0]
        let archived = try #require(item["storeId"]?.string)
        _ = try await StoreQuotaFixture.cancel(owner, group: group, item: item)
        _ = try await StoreQuotaFixture.archive(owner, group: group, store: archived)
        for name in ["A", "B"] {
            _ = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: name,
                count: 1
            )
        }
        let restore: @Sendable () async throws -> TestingHTTPResponse = {
            try await StoreQuotaFixture.restore(owner, group: group, store: archived)
        }
        let create: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                member,
                ShoppingFixture.batch(names: ["Nuevo"], stores: ["Nueva"])
            )
        }
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM groups WHERE id = \(bind: group)::uuid FOR UPDATE",
            waitingQuery: "%FROM groups%FOR UPDATE%",
            first: restoreFirst ? restore : create,
            second: restoreFirst ? create : restore
        )
        #expect(responses.0.status == (restoreFirst ? .ok : .created))
        #expect(try StoreQuotaFixture.code(responses.1) == "store_limit_reached")
        #expect(try await StoreQuotaFixture.capacity(owner, group: group)["activeStoreCount"] == .integer(3))
        let archivedStores = try await StoreQuotaFixture.stores(owner, group: group, state: "archived")
        #expect(archivedStores.count == (restoreFirst ? 0 : 1))
    }

    @Test(
        "Archiving and incoming pending items serialize without hiding a pending product",
        .timeLimit(.minutes(1)),
        arguments: [true, false],
        ["add", "move"]
    )
    func archivingRacesIncomingPendingItems(archiveFirst: Bool, mutation: String) async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let empty = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Destino",
            count: 1
        )[0]
        _ = try await StoreQuotaFixture.cancel(owner, group: group, item: empty)
        let store = try #require(empty["storeId"]?.string)
        let source = try await StoreQuotaFixture.add(
            member,
            group: group,
            store: "Origen",
            count: 1
        )[0]
        let archive: @Sendable () async throws -> TestingHTTPResponse = {
            try await StoreQuotaFixture.archive(owner, group: group, store: store)
        }
        let write: @Sendable () async throws -> TestingHTTPResponse = {
            if mutation == "move" {
                return try await StoreQuotaFixture.edit(
                    member,
                    group: group,
                    item: source,
                    store: store
                )
            }
            return try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                member,
                ShoppingFixture.batch(names: ["Nuevo"], stores: ["Destino"])
            )
        }
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM groups WHERE id = \(bind: group)::uuid FOR UPDATE",
            waitingQuery: "%FROM groups%FOR UPDATE%",
            first: archiveFirst ? archive : write,
            second: archiveFirst ? write : archive
        )
        #expect(responses.0.status == (archiveFirst || mutation == "move" ? .ok : .created))
        #expect(try StoreQuotaFixture.code(responses.1) == (archiveFirst ? "store_archived" : "store_not_empty"))
        let sql = try shoppingSQL(database)
        let hidden = try await sql.raw("""
            SELECT items.id FROM items JOIN stores ON stores.id = items.store_id
            WHERE items.status = 'pending' AND stores.archived_at IS NOT NULL
            """).all()
        #expect(hidden.isEmpty)
        let pending = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores/\(store)/items", owner)
        #expect(try StoreQuotaFixture.array(pending, key: "items").count == (archiveFirst ? 0 : 1))
    }

    @Test(
        "A transfer and pending growth use the administrator that wins the group lock",
        .timeLimit(.minutes(1)),
        arguments: [true, false]
    )
    func administrationTransferRacesCapacityAdmission(transferFirst: Bool) async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(resolve: { id in
            id == owner.id ? .premium : .free
        })) {
            let group = try await ShoppingFixture.group(owner)
            try await ShoppingFixture.join(recipient, group: group)
            _ = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: "Casa",
                count: 20
            )
            let proposal = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
            let transfer: @Sendable () async throws -> TestingHTTPResponse = {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/administration-transfers/\(proposal)/accept",
                    recipient,
                    AdministrationFixture.operation()
                )
            }
            let add: @Sendable () async throws -> TestingHTTPResponse = {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    owner,
                    ShoppingFixture.batch(names: ["Extra"], stores: ["Casa"])
                )
            }
            let responses = try await ShoppingFixture.overlappingRequests(
                lockedBy: "SELECT id FROM groups WHERE id = \(bind: group)::uuid FOR UPDATE",
                waitingQuery: "%FROM groups%FOR UPDATE%",
                first: transferFirst ? transfer : add,
                second: transferFirst ? add : transfer
            )
            #expect(responses.0.status == (transferFirst ? .ok : .created))
            #expect(responses.1.status == (transferFirst ? .conflict : .ok))
            #expect(
                try await ShoppingFixture.allPending(group: group, user: recipient).count == (transferFirst ? 20 : 21)
            )
            #expect(
                try await StoreQuotaFixture.capacity(recipient, group: group)["limits"] == StoreQuotaFixture.freeLimits
            )
        }
    }
}
