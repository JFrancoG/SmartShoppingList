@testable import SmartShoppingListServer
import FluentKit
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Verified Sandbox and Production access never grant allowances across their environment boundary")
    func premiumAccessIsIsolatedByVerificationEnvironment() async throws {
        let sandboxUser = try await ShoppingFixture.user()
        let productionUser = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(sandboxUser, expiresIn: 86_400, verificationEnvironment: .sandbox)
        try await PremiumAccessFixture.access(productionUser, expiresIn: 86_400)
        #expect(try await PremiumAccessFixture.capabilities(sandboxUser)["premiumActive"] == .bool(false))
        #expect(try await PremiumAccessFixture.capabilities(productionUser)["premiumActive"] == .bool(true))
        let sandboxGroup = try await ShoppingFixture.group(sandboxUser)
        let productionGroup = try await ShoppingFixture.group(productionUser)
        let isolatedCapacity = try await StoreQuotaFixture.capacity(sandboxUser, group: sandboxGroup)
        #expect(isolatedCapacity["limits"] == StoreQuotaFixture.freeLimits)
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(verificationEnvironment: .sandbox)) {
            #expect(try await PremiumAccessFixture.capabilities(sandboxUser)["premiumActive"] == .bool(true))
            #expect(try await PremiumAccessFixture.capabilities(productionUser)["premiumActive"] == .bool(false))
            _ = try await StoreQuotaFixture.add(sandboxUser, group: sandboxGroup, store: "Sandbox", count: 21)
            let denied = try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(productionGroup)/item-batches",
                productionUser,
                ShoppingFixture.batch(
                    names: Array(repeating: "Exceso", count: 21),
                    stores: Array(repeating: "Casa", count: 21)
                )
            )
            #expect(try StoreQuotaFixture.code(denied) == "pending_item_limit_reached")
        }
        // Updating one environment retains the other environment's verified state for the same account.
        try await PremiumAccessFixture.access(sandboxUser, expiresIn: 86_400)
        try await PremiumAccessFixture.access(
            sandboxUser,
            expiresIn: -1,
            transitionAllowed: false,
            verificationEnvironment: .sandbox
        )
        #expect(try await PremiumAccessFixture.capabilities(sandboxUser)["premiumActive"] == .bool(true))
        try await MembershipFixture.withPolicy(AccountCapacityPolicy(verificationEnvironment: .sandbox)) {
            () async throws in
            #expect(try await PremiumAccessFixture.capabilities(sandboxUser)["premiumActive"] == .bool(false))
        }
    }

    @Test("Ordinary expiry gives seven days of existing-group access while shared quotas already return to free")
    func premiumExpiryTransitionAndQuotas() async throws {
        let user = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let first = try await ShoppingFixture.group(user)
        let second = try await ShoppingFixture.group(user)
        _ = try await StoreQuotaFixture.add(user, group: second, store: "Grande", count: 21)
        try await PremiumAccessFixture.access(user, expiresIn: -86_400)
        let capabilities = try await PremiumAccessFixture.capabilities(user)
        #expect(capabilities["premiumActive"] == .bool(false))
        #expect(capabilities["canJoinGroup"] == .bool(false))
        #expect(capabilities["freeGroupId"] == .string(first))
        let expires = try #require(capabilities["premiumExpiresAt"]?.string).premiumDate()
        let transition = try #require(capabilities["transitionEndsAt"]?.string).premiumDate()
        #expect(transition.timeIntervalSince(expires) == 7 * 86_400)
        let shared = try await StoreQuotaFixture.capacity(user, group: second)
        #expect(shared["limits"] == StoreQuotaFixture.freeLimits)
        let atQuota = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(second)/item-batches",
            user,
            ShoppingFixture.batch(names: ["Exceso"], stores: ["Grande"])
        )
        #expect(try StoreQuotaFixture.code(atQuota) == "pending_item_limit_reached")
        _ = try await StoreQuotaFixture.add(user, group: second, store: "Vacía", count: 1)
        let groups = try await PremiumAccessFixture.groups(user)
        #expect(groups.values.allSatisfy { $0["canUseShopping"] == .bool(true) })
        let denied = try await ShoppingFixture.request(.POST, "/v1/groups", user, MembershipFixture.creationBody())
        #expect(try StoreQuotaFixture.code(denied) == "group_limit_reached")
        try await PremiumAccessFixture.access(user, expiresIn: -8 * 86_400)
        let after = try await PremiumAccessFixture.groups(user)
        #expect(after[first]?["canUseShopping"] == .bool(true))
        #expect(after[second]?["canUseShopping"] == .bool(false))
        #expect(try await ShoppingFixture.allPending(group: second, user: user).count == 22)
        let restriction = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(second)/item-batches",
            user,
            ShoppingFixture.batch(names: ["Otro"], stores: ["Casa"])
        )
        #expect(try StoreQuotaFixture.code(restriction) == "group_access_restricted")
    }

    @Test("Revocation skips courtesy access and a previously chosen free group survives renewed premium")
    func revokedPremiumAndRetainedFreeChoice() async throws {
        let user = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let first = try await ShoppingFixture.group(user)
        let second = try await ShoppingFixture.group(user)
        #expect(try await PremiumAccessFixture.choose(user, group: second).status == .ok)
        let before = try await PremiumAccessFixture.capabilities(user)
        try await PremiumAccessFixture.access(user, expiresIn: -1, transitionAllowed: false)
        let restricted = try await PremiumAccessFixture.groups(user)
        #expect(restricted[first]?["canUseShopping"] == .bool(false))
        #expect(restricted[second]?["canUseShopping"] == .bool(true))
        #expect(try await PremiumAccessFixture.capabilities(user)["transitionEndsAt"] == .null)
        try await PremiumAccessFixture.access(user, expiresIn: 2 * 86_400)
        let resumed = try await PremiumAccessFixture.capabilities(user)
        #expect(resumed["premiumActive"] == .bool(true))
        #expect(resumed["freeGroupId"] == .string(second))
        #expect(resumed["freeGroupChangeAvailableAt"] == before["freeGroupChangeAvailableAt"])
        #expect(try await PremiumAccessFixture.groups(user).values.allSatisfy { $0["canUseShopping"] == .bool(true) })
    }

    @Test("The first explicit choice is immediate, later choices wait thirty days and replay never changes the live choice")
    func freeGroupSelectionCooldownAndReceipts() async throws {
        let user = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let first = try await ShoppingFixture.group(user)
        let second = try await ShoppingFixture.group(user)
        try await PremiumAccessFixture.access(user, expiresIn: -8 * 86_400)
        let automatic = try await PremiumAccessFixture.capabilities(user)
        #expect(automatic["freeGroupId"] == .string(first))
        #expect(automatic["canChangeFreeGroup"] == .bool(true))
        #expect(automatic["freeGroupChangeAvailableAt"] == .null)
        #expect(try await PremiumAccessFixture.choose(user, group: first).status == .ok)
        let confirmedFallback = try await PremiumAccessFixture.capabilities(user)
        #expect(confirmedFallback["freeGroupChangeAvailableAt"] == .null)
        #expect(confirmedFallback["canChangeFreeGroup"] == .bool(true))
        let intention = PremiumAccessFixture.choice(second)
        let selected = try await PremiumAccessFixture.choose(user, body: intention)
        try #require(selected.status == .ok)
        let selectedFields = try ShoppingFixture.object(selected)
        let changedAt = try await PremiumAccessFixture.changedAt(user)
        let available = try #require(selectedFields["freeGroupChangeAvailableAt"]?.string).premiumDate()
        #expect(abs(available.timeIntervalSince(changedAt) - 30 * 86_400) < 0.001)
        let deniedBody = PremiumAccessFixture.choice(first)
        let rejected = try await PremiumAccessFixture.choose(user, body: deniedBody)
        #expect(try StoreQuotaFixture.code(rejected) == "free_group_change_cooldown")
        #expect(try await PremiumAccessFixture.choose(user, group: second).status == .ok)
        #expect(try await PremiumAccessFixture.changedAt(user) == changedAt)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            UPDATE users SET free_group_changed_at = clock_timestamp() - INTERVAL '30 days 1 second'
            WHERE id = \(bind: user.id)
            """).run()
        let repeatedRejection = try await PremiumAccessFixture.choose(user, body: deniedBody)
        #expect(repeatedRejection.body.string == rejected.body.string)
        let next = try await PremiumAccessFixture.choose(user, group: first)
        #expect(next.status == .ok)
        let historical = try await PremiumAccessFixture.choose(user, body: intention)
        #expect(historical.body.string == selected.body.string)
        #expect(try await PremiumAccessFixture.capabilities(user)["freeGroupId"] == .string(first))
    }

    @Test("Safely leaving a chosen group permits one replacement without clearing the previous thirty-day stamp")
    func unavailableFreeGroupReplacementRetainsCooldown() async throws {
        let user = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let first = try await ShoppingFixture.group(user)
        let second = try await ShoppingFixture.group(user)
        let third = try await ShoppingFixture.group(user)
        let chosenBody = PremiumAccessFixture.choice(second)
        let selected = try await PremiumAccessFixture.choose(user, body: chosenBody)
        try #require(selected.status == .ok)
        let before = try await PremiumAccessFixture.changedAt(user)
        try await PremiumAccessFixture.access(user, expiresIn: -8 * 86_400)
        #expect(try await MembershipFixture.depart(user, group: second).status == .ok)
        let fallback = try await PremiumAccessFixture.capabilities(user)
        #expect(fallback["freeGroupId"] == .string(first))
        #expect(fallback["canChangeFreeGroup"] == .bool(true))
        #expect(try await PremiumAccessFixture.choose(user, group: third).status == .ok)
        #expect(try await PremiumAccessFixture.changedAt(user) == before)
        let denied = try await PremiumAccessFixture.choose(user, group: first)
        #expect(try StoreQuotaFixture.code(denied) == "free_group_change_cooldown")
        let historical = try await PremiumAccessFixture.choose(user, body: chosenBody)
        #expect(historical.body.string == selected.body.string)
        #expect(try await PremiumAccessFixture.capabilities(user)["freeGroupId"] == .string(third))
    }

    @Test("Restricted groups preserve confirmed receipts, consultation and cancellation but deny ordinary shopping intentions")
    func restrictedGroupActionsAndExactReplay() async throws {
        let user = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        _ = try await ShoppingFixture.group(user)
        let second = try await ShoppingFixture.group(user)
        let path = "/v1/groups/\(second)/item-batches"
        let additionBody = ShoppingFixture.batch(names: ["Pan", "Leche"], stores: ["Casa", "Casa"])
        let addition = try await ShoppingFixture.request(.POST, path, user, additionBody)
        try #require(addition.status == .created)
        let items = try StoreQuotaFixture.array(addition, key: "items")
        let firstItem = try #require(items.first)
        let id = try #require(firstItem["id"]?.string)
        let store = try #require(firstItem["storeId"]?.string)
        try await PremiumAccessFixture.access(user, expiresIn: -8 * 86_400)
        let before = try await AdministrationFixture.itemSnapshot(group: second)
        let replay = try await ShoppingFixture.request(.POST, path, user, additionBody)
        #expect(replay.body.string == addition.body.string)
        let blockedBody = ShoppingFixture.batch(names: ["Nuevo"], stores: ["Debe no existir"])
        let blocked = try await ShoppingFixture.request(.POST, path, user, blockedBody)
        #expect(try StoreQuotaFixture.code(blocked) == "group_access_restricted")
        let edit = try await StoreQuotaFixture.edit(user, group: second, item: firstItem, store: store)
        #expect(try StoreQuotaFixture.code(edit) == "group_access_restricted")
        let purchase = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(second)/purchases",
            user,
            PurchaseFixture.body(store: store, ids: [id])
        )
        #expect(try StoreQuotaFixture.code(purchase) == "group_access_restricted")
        let invitation = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(second)/invitations",
            user,
            .object([:])
        )
        #expect(try StoreQuotaFixture.code(invitation) == "group_access_restricted")
        #expect(try await AdministrationFixture.itemSnapshot(group: second) == before)
        let stores = try await StoreQuotaFixture.stores(user, group: second)
        #expect(stores.count == 1)
        #expect(try StoreQuotaFixture.fields(stores[0]["capabilities"])["canAddItems"] == .bool(false))
        #expect(try await StoreQuotaFixture.capacity(user, group: second)["canCreateStore"] == .bool(false))
        for item in items {
            #expect(try await StoreQuotaFixture.cancel(user, group: second, item: item).status == .ok)
        }
        #expect(try await StoreQuotaFixture.archive(user, group: second, store: store).status == .ok)
        let restore = try await StoreQuotaFixture.restore(user, group: second, store: store)
        #expect(try StoreQuotaFixture.code(restore) == "group_access_restricted")
        let administration = try await ShoppingFixture.request(.GET, "/v1/groups/\(second)/administration", user)
        #expect(administration.status == .ok)
        let management = try StoreQuotaFixture.fields(ShoppingFixture.object(administration)["capabilities"])
        #expect(management["canManageInvitations"] == .bool(true))
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let rejectedReplay = try await ShoppingFixture.request(.POST, path, user, blockedBody)
        #expect(rejectedReplay.body.string == blocked.body.string)
        #expect(try await StoreQuotaFixture.add(user, group: second, store: "Nueva", count: 1).count == 1)
    }

    @Test(
        "Concurrent free-group choices serialize at the account and consume only one manual choice",
        .timeLimit(.minutes(1))
    )
    func concurrentFreeGroupChoices() async throws {
        let user = try await ShoppingFixture.user()
        try await PremiumAccessFixture.access(user, expiresIn: 86_400)
        let first = try await ShoppingFixture.group(user)
        let second = try await ShoppingFixture.group(user)
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM users WHERE id = \(bind: user.id) FOR NO KEY UPDATE",
            waitingQuery: "%FROM users%FOR NO KEY UPDATE%",
            first: { try await PremiumAccessFixture.choose(user, group: second) },
            second: { try await PremiumAccessFixture.choose(user, group: first) }
        )
        #expect(responses.0.status == .ok)
        #expect(try StoreQuotaFixture.code(responses.1) == "free_group_change_cooldown")
        #expect(try await PremiumAccessFixture.capabilities(user)["freeGroupId"] == .string(second))
    }
}

enum PremiumAccessFixture {
    static func access(
        _ user: ShoppingFixture.User,
        expiresIn seconds: TimeInterval,
        transitionAllowed: Bool = true,
        verificationEnvironment: AppStoreEnvironment = .production
    ) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            let service = ShoppingService(
                database: transaction,
                invitationOrigin: nil,
                cursorKey: SymmetricKey(size: .bits256)
            )
            try await service.lockUser(user.id, on: sql)
            let now = try await databaseClock(sql)
            try await persistTrustedPremiumAccess(
                user: user.id,
                premiumUntil: now.addingTimeInterval(seconds),
                transitionStartedAt: nil,
                transitionAllowed: transitionAllowed,
                verificationEnvironment: verificationEnvironment,
                on: sql
            )
        }
    }

    static func choice(_ group: String) -> APIJSON {
        .object(["operationId": .string(UUID().uuidString.lowercased()), "groupId": .string(group)])
    }

    static func choose(_ user: ShoppingFixture.User, group: String) async throws -> TestingHTTPResponse {
        try await choose(user, body: choice(group))
    }

    static func choose(_ user: ShoppingFixture.User, body: APIJSON) async throws -> TestingHTTPResponse {
        try await ShoppingFixture.request(.POST, "/v1/account/free-group", user, body)
    }

    static func capabilities(_ user: ShoppingFixture.User) async throws -> [String: APIJSON] {
        try MembershipFixture.capabilities(try await ShoppingFixture.request(.GET, "/v1/me", user))
    }

    static func changedAt(_ user: ShoppingFixture.User) async throws -> Date {
        let sql = try shoppingSQL(database)
        let row = try #require(try await sql.raw("""
            SELECT free_group_changed_at FROM users WHERE id = \(bind: user.id)
            """).first())
        return try row.decode(column: "free_group_changed_at", as: Date.self)
    }

    static func groups(_ user: ShoppingFixture.User) async throws -> [String: [String: APIJSON]] {
        let response = try await ShoppingFixture.request(.GET, "/v1/groups", user)
        let groups = try StoreQuotaFixture.array(response, key: "data")
        var result: [String: [String: APIJSON]] = [:]
        for group in groups {
            let id = try #require(group["id"]?.string)
            result[id] = try StoreQuotaFixture.fields(group["capabilities"])
        }
        return result
    }
}

private extension String {
    func premiumDate() throws -> Date {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(parser.date(from: self))
    }
}
