@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Only the administrator can archive an empty store; history and receipt bytes survive restoration")
    func archivingPreservesHistoryAndRequiresExplicitRestoration() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let batch = ShoppingFixture.batch(names: ["Comprado", "Cancelado"], stores: ["Mercadona", "MERCADONA"])
        let original = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            owner,
            batch
        )
        let entries = try StoreQuotaFixture.array(original, key: "items")
        let store = try #require(entries.first?["storeId"]?.string)
        #expect(try await StoreQuotaFixture.archive(member, group: group, store: store).status == .forbidden)
        #expect(try await StoreQuotaFixture.archive(outsider, group: group, store: store).status == .notFound)
        let nonempty = try await StoreQuotaFixture.archive(owner, group: group, store: store)
        #expect(try StoreQuotaFixture.code(nonempty) == "store_not_empty")
        let purchaseBody = PurchaseFixture.body(store: store, ids: [try #require(entries[0]["id"]?.string)])
        let purchased = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            member,
            purchaseBody
        )
        try #require(purchased.status == .ok)
        _ = try await StoreQuotaFixture.cancel(member, group: group, item: entries[1])
        let history = try await AdministrationFixture.itemSnapshot(group: group)
        let archiveBody = AdministrationFixture.operation()
        let archived = try await StoreQuotaFixture.archive(
            owner,
            group: group,
            store: store,
            body: archiveBody
        )
        try #require(archived.status == .ok)
        let archiveFields = try ShoppingFixture.object(archived)
        #expect(archiveFields["id"] == .string(store))
        #expect(archiveFields["archivedAt"]?.string != nil)
        #expect(archiveFields["pendingItemCount"] == .integer(0))
        #expect(try await StoreQuotaFixture.stores(owner, group: group).isEmpty)
        let archivedPage = try await StoreQuotaFixture.stores(member, group: group, state: "archived")
        #expect(archivedPage.count == 1)
        #expect(try StoreQuotaFixture.fields(archivedPage[0]["capabilities"])["canRestore"] == .bool(false))
        let pending = try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/stores/\(store)/items", member)
        #expect(pending.status == .ok)
        #expect(try StoreQuotaFixture.array(pending, key: "items").isEmpty)
        let noOp = try await StoreQuotaFixture.archive(owner, group: group, store: store)
        #expect(try ShoppingFixture.object(noOp)["archivedAt"] == archiveFields["archivedAt"])
        let references: [APIJSON] = [
            .object(["id": .string(store)]), .object(["newName": .string(" MERCADONA ")])
        ]
        for reference in references {
            let blocked = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                member,
                .object([
                    "operationId": .string(UUID().uuidString.lowercased()),
                    "items": .array([StoreQuotaFixture.item(store: reference)])
                ])
            )
            #expect(try StoreQuotaFixture.code(blocked) == "store_archived")
        }
        let batchReplay = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            owner,
            batch
        )
        #expect(batchReplay.body.string == original.body.string)
        let purchaseReplay = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            member,
            purchaseBody
        )
        #expect(purchaseReplay.body.string == purchased.body.string)
        #expect(try await StoreQuotaFixture.restore(member, group: group, store: store).status == .forbidden)
        let restored = try await StoreQuotaFixture.restore(owner, group: group, store: store)
        #expect(restored.status == .ok)
        #expect(try ShoppingFixture.object(restored)["id"] == .string(store))
        #expect(try ShoppingFixture.object(restored)["archivedAt"] == .null)
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == history)
        let replay = try await StoreQuotaFixture.archive(
            owner,
            group: group,
            store: store,
            body: archiveBody
        )
        #expect(replay.body.string == archived.body.string)
        #expect(try await StoreQuotaFixture.stores(owner, group: group).count == 1)
        let newItems = try await StoreQuotaFixture.add(
            member,
            group: group,
            store: "mercadona",
            count: 1
        )
        #expect(newItems[0]["storeId"] == .string(store))
    }

    @Test("Archiving releases a store slot; restoring needs a slot and a fresh intent after a confirmed refusal")
    func restoringConsumesExactlyOneActiveSlot() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        var ids: [String] = []
        for name in ["A", "B", "C"] {
            let item = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: name,
                count: 1
            )[0]
            ids.append(try #require(item["storeId"]?.string))
            _ = try await StoreQuotaFixture.cancel(owner, group: group, item: item)
        }
        _ = try await StoreQuotaFixture.archive(owner, group: group, store: ids[0])
        _ = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "D",
            count: 1
        )
        let body = AdministrationFixture.operation()
        let refused = try await StoreQuotaFixture.restore(
            owner,
            group: group,
            store: ids[0],
            body: body
        )
        #expect(try StoreQuotaFixture.code(refused) == "store_limit_reached")
        #expect(try await StoreQuotaFixture.restore(owner, group: group, store: ids[1]).status == .ok)
        _ = try await StoreQuotaFixture.archive(owner, group: group, store: ids[1])
        let replay = try await StoreQuotaFixture.restore(
            owner,
            group: group,
            store: ids[0],
            body: body
        )
        #expect(replay.body.string == refused.body.string)
        let restored = try await StoreQuotaFixture.restore(owner, group: group, store: ids[0])
        #expect(restored.status == .ok)
        #expect(try await StoreQuotaFixture.capacity(owner, group: group)["activeStoreCount"] == .integer(3))
        #expect(try await StoreQuotaFixture.stores(owner, group: group, state: "archived").count == 1)
    }

    @Test("A lower-capacity successor preserves data and admits only growth of resources with remaining room")
    func administrationTransferRecomputesCapacityWithoutDeletingExcess() async throws {
        let owner = try await ShoppingFixture.user()
        let successor = try await ShoppingFixture.user()
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(resolve: { id in
            id == owner.id ? .premium : .free
        })) {
            let group = try await ShoppingFixture.group(owner)
            try await ShoppingFixture.join(successor, group: group)
            let over = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: "Grande",
                count: 21
            )
            let spare = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: "Pequeña",
                count: 1
            )
            for name in ["Vacía A", "Vacía B"] {
                let item = try await StoreQuotaFixture.add(
                    owner,
                    group: group,
                    store: name,
                    count: 1
                )[0]
                _ = try await StoreQuotaFixture.cancel(owner, group: group, item: item)
            }
            let before = try await AdministrationFixture.itemSnapshot(group: group)
            let transfer = try await AdministrationFixture.propose(owner, recipient: successor, group: group)
            let accepted = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/administration-transfers/\(transfer)/accept",
                successor,
                AdministrationFixture.operation()
            )
            try #require(accepted.status == .ok)
            #expect(try await AdministrationFixture.itemSnapshot(group: group) == before)
            let capacity = try await StoreQuotaFixture.capacity(owner, group: group)
            #expect(capacity["activeStoreCount"] == .integer(4))
            #expect(capacity["limits"] == StoreQuotaFixture.freeLimits)
            #expect(capacity["capacityOwnerUserId"] == .string(successor.id.uuidString.lowercased()))
            let sourceID = try #require(over[0]["storeId"]?.string)
            let edited = try await StoreQuotaFixture.edit(
                owner,
                group: group,
                item: over[0],
                store: sourceID
            )
            #expect(edited.status == .ok)
            let destID = try #require(spare[0]["storeId"]?.string)
            let moved = try await StoreQuotaFixture.edit(
                owner,
                group: group,
                item: over[1],
                store: destID
            )
            #expect(moved.status == .ok)
            _ = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: "Pequeña",
                count: 1
            )
            for (name, code) in [("Grande", "pending_item_limit_reached"), ("Nueva", "store_limit_reached")] {
                let refused = try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    owner,
                    ShoppingFixture.batch(names: ["Extra"], stores: [name])
                )
                #expect(try StoreQuotaFixture.code(refused) == code)
            }
            let purchased = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/purchases",
                owner,
                PurchaseFixture.body(store: sourceID, ids: [try #require(over[2]["id"]?.string)])
            )
            #expect(purchased.status == .ok)
            _ = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: "Grande",
                count: 1
            )
            let empty = try #require(try await StoreQuotaFixture.stores(successor, group: group).first {
                $0["name"] == .string("Vacía A")
            }?["id"]?.string)
            #expect(try await StoreQuotaFixture.archive(owner, group: group, store: empty).status == .forbidden)
            #expect(try await StoreQuotaFixture.archive(successor, group: group, store: empty).status == .ok)
            #expect(try await StoreQuotaFixture.capacity(owner, group: group)["activeStoreCount"] == .integer(3))
        }
    }

    @Test("Downgrading retains confirmed writes and a former administrator can replay its own archive receipt")
    func confirmedReceiptsSurviveDowngradeAndRoleChange() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let batch = ShoppingFixture.batch(
            names: Array(repeating: "Producto", count: 21),
            stores: Array(repeating: "Grande", count: 21)
        )
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(resolve: { _ in .premium })) {
            let accepted = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                owner,
                batch
            )
            try #require(accepted.status == .created)
        }
        let history = try await AdministrationFixture.itemSnapshot(group: group)
        let replay = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            owner,
            batch
        )
        #expect(replay.status == .created)
        #expect(try StoreQuotaFixture.array(replay, key: "items").count == 21)
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == history)
        #expect(try await StoreQuotaFixture.capacity(owner, group: group)["limits"] == StoreQuotaFixture.freeLimits)
        let item = try await StoreQuotaFixture.add(
            owner,
            group: group,
            store: "Vacía",
            count: 1
        )[0]
        let store = try #require(item["storeId"]?.string)
        _ = try await StoreQuotaFixture.cancel(owner, group: group, item: item)
        let body = AdministrationFixture.operation()
        let archived = try await StoreQuotaFixture.archive(
            owner,
            group: group,
            store: store,
            body: body
        )
        let transfer = try await AdministrationFixture.propose(owner, recipient: member, group: group)
        let transferred = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-transfers/\(transfer)/accept",
            member,
            AdministrationFixture.operation()
        )
        try #require(transferred.status == .ok)
        let archiveReplay = try await StoreQuotaFixture.archive(
            owner,
            group: group,
            store: store,
            body: body
        )
        #expect(archiveReplay.body.string == archived.body.string)
        _ = try await MembershipFixture.depart(owner, group: group)
        let denied = try await StoreQuotaFixture.archive(
            owner,
            group: group,
            store: store,
            body: body
        )
        #expect(denied.status == .notFound)
    }

    @Test("Store cursors bind archive state and group; every member can read archived history metadata")
    func storePagesBindArchiveStateAndPermissions() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        for name in ["A", "B", "C"] {
            let item = try await StoreQuotaFixture.add(
                owner,
                group: group,
                store: name,
                count: 1
            )[0]
            _ = try await StoreQuotaFixture.cancel(owner, group: group, item: item)
            let store = try #require(item["storeId"]?.string)
            _ = try await StoreQuotaFixture.archive(owner, group: group, store: store)
        }
        let path = "/v1/groups/\(group)/stores"
        let first = try await ShoppingFixture.request(.GET, path + "?state=archived&limit=2", member)
        #expect(try StoreQuotaFixture.array(first, key: "stores").count == 2)
        let cursor = try #require(try ShoppingFixture.object(first)["nextCursor"]?.string)
        let last = try await ShoppingFixture.request(.GET, path + "?state=archived&limit=2&cursor=\(cursor)", member)
        #expect(try StoreQuotaFixture.array(last, key: "stores").count == 1)
        let invalidQueries = [
            "cursor=\(cursor)", "state=active&cursor=\(cursor)", "state=all", "state=", "state=active&state=archived"
        ]
        for query in invalidQueries {
            #expect(try await ShoppingFixture.request(.GET, path + "?" + query, owner).status == .badRequest)
        }
        #expect(try await ShoppingFixture.request(.GET, path + "?state=archived", outsider).status == .notFound)
        #expect(try await ShoppingFixture.request(.GET, "/v1/groups/\(group)/capacity", outsider).status == .notFound)
    }
}
