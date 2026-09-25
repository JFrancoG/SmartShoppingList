@testable import SmartShoppingListServer
import Foundation
import FluentKit
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test(.timeLimit(.minutes(1)))
    func `two acceptances blocked on the same invitation commit only one membership`() async throws {
        let owner = try await ShoppingFixture.user()
        let first = try await ShoppingFixture.user()
        let second = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let invitation = try await ShoppingFixture.invitation(group)
        let testDatabase = try database
        let gate = ShoppingSQLGate()
        let holder = Task {
            do {
                try await testDatabase.transaction { transaction in
                    let sql = try shoppingSQL(transaction)
                    _ = try await sql.raw(
                    "SELECT id FROM invitations WHERE id = \(bind: invitation.id) FOR UPDATE"
                ).first()
                    let row = try #require(try await sql.raw("SELECT pg_backend_pid() AS pid").first())
                    await gate.locked(try row.decode(column: "pid", as: Int32.self))
                    await gate.waitForRelease()
                }
            } catch {
                await gate.failed(error)
                throw error
            }
        }
        let pid: Int32
        do {
            pid = try await gate.waitUntilLocked()
        } catch {
            await gate.release()
            _ = try? await holder.value
            throw error
        }
        let path = "/v1/invitations/\(invitation.id.uuidString.lowercased())/accept"
        let body: APIJSON = .object(["token": .string(invitation.secret)])
        let firstRequest = Task {
            try await ShoppingFixture.request(
                .POST,
                path,
                first,
                body
            )
        }
        let secondRequest = Task {
            try await ShoppingFixture.request(
                .POST,
                path,
                second,
                body
            )
        }
        do {
            try await ShoppingFixture.waitForInvitationWaiters(blockedBy: pid, count: 2, database: testDatabase)
        } catch {
            await gate.release()
            _ = try? await holder.value
            _ = try? await firstRequest.value
            _ = try? await secondRequest.value
            throw error
        }
        await gate.release()
        try await holder.value
        let responses = try await [firstRequest.value, secondRequest.value]
        #expect(responses.map(\.status.code).sorted() == [200, 410])
        let firstUser = try await ShoppingFixture.request(.GET, "/v1/me", first)
        let secondUser = try await ShoppingFixture.request(.GET, "/v1/me", second)
        let groups = try [ShoppingFixture.object(firstUser)["group"], ShoppingFixture.object(secondUser)["group"]]
        #expect(groups.filter { $0 != .null }.count == 1)
        let sql = try shoppingSQL(testDatabase)
        let persisted = try #require(try await sql.raw("""
            SELECT accepted_by FROM invitations WHERE id = \(bind: invitation.id)
            """).first())
        let winner = try persisted.decode(column: "accepted_by", as: UUID.self)
        #expect(winner == (responses[0].status == .ok ? first.id : second.id))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func `acceptance and revocation preserve the first committed transition`(acceptFirst: Bool) async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let invitation = try await ShoppingFixture.invitation(group)
        let identifier = invitation.id.uuidString.lowercased()
        let accept: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(
                .POST, "/v1/invitations/\(identifier)/accept", recipient,
                .object(["token": .string(invitation.secret)])
            )
        }
        let revoke: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(.DELETE, "/v1/groups/\(group)/invitations/\(identifier)", owner)
        }
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM invitations WHERE id = \(bind: invitation.id) FOR UPDATE",
            waitingQuery: "%FROM invitations%FOR UPDATE%",
            first: acceptFirst ? accept : revoke,
            second: acceptFirst ? revoke : accept
        )
        let sql = try shoppingSQL(database)
        let persisted = try #require(try await sql.raw("""
            SELECT accepted_by, accepted_at, revoked_at FROM invitations WHERE id = \(bind: invitation.id)
            """).first())
        let membership = try await ShoppingFixture.request(.GET, "/v1/me", recipient)
        let memberFields = try ShoppingFixture.object(membership)
        if acceptFirst {
            #expect(responses.0.status == .ok)
            #expect(responses.1.status == .conflict)
            #expect(try ShoppingFixture.object(responses.1)["code"] == .string("invitation_consumed"))
            #expect(try persisted.decode(column: "accepted_by", as: UUID?.self) == recipient.id)
            #expect(try persisted.decode(column: "accepted_at", as: Date?.self) != nil)
            #expect(try persisted.decode(column: "revoked_at", as: Date?.self) == nil)
            guard case .object(let savedGroup) = memberFields["group"] else {
                Issue.record("Revocation undid a confirmed membership")
                return
            }
            #expect(savedGroup["id"] == .string(group))
        } else {
            #expect(responses.0.status == .noContent)
            #expect(responses.1.status == .gone)
            #expect(try ShoppingFixture.object(responses.1)["code"] == .string("invitation_revoked"))
            #expect(try persisted.decode(column: "accepted_by", as: UUID?.self) == nil)
            #expect(try persisted.decode(column: "accepted_at", as: Date?.self) == nil)
            #expect(try persisted.decode(column: "revoked_at", as: Date?.self) != nil)
            #expect(memberFields["group"] == .null)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `simultaneous identical batches share one receipt and one set of products`() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let payload = ShoppingFixture.batch(names: ["Pan", "Leche"], stores: ["Día", "DÍA"])
        let request: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/item-batches",
                owner,
                payload
            )
        }
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM users WHERE id = \(bind: owner.id) FOR UPDATE",
            waitingQuery: "%FROM users%FOR UPDATE%",
            first: request,
            second: request
        )
        try #require(responses.0.status == .created)
        try #require(responses.1.status == .created)
        #expect(responses.0.body.string == responses.1.body.string)
        let pending = try await ShoppingFixture.allPending(group: group, user: owner)
        #expect(pending.count == 2)
        #expect(Set(pending.compactMap { $0["name"]?.string }) == ["Pan", "Leche"])
        #expect(Set(pending.compactMap { $0["storeId"]?.string }).count == 1)
        let sql = try shoppingSQL(database)
        let receipts = try await sql.raw("""
            SELECT operation_id FROM mutation_receipts
            WHERE user_id = \(bind: owner.id) AND operation_type = 'addItems'
            """).all()
        #expect(receipts.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func `members creating the same stores in opposite orders retain both complete batches`() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let first = ShoppingFixture.batch(names: ["Pan", "Arroz"], stores: ["Alfa", "Beta"])
        let second = ShoppingFixture.batch(names: ["Café", "Leche"], stores: ["BETA", "ALFA"])
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "LOCK TABLE stores IN SHARE MODE",
            waitingQuery: "%INSERT INTO stores%",
            first: {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    owner,
                    first
                )
            },
            second: {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    member,
                    second
                )
            }
        )
        try #require(responses.0.status == .created)
        try #require(responses.1.status == .created)
        let ownerItems = try await ShoppingFixture.allPending(group: group, user: owner)
        let memberItems = try await ShoppingFixture.allPending(group: group, user: member)
        #expect(ownerItems.count == 4)
        #expect(Set(ownerItems.compactMap { $0["name"]?.string }) == ["Pan", "Arroz", "Café", "Leche"])
        #expect(Set(ownerItems.compactMap { $0["id"]?.string }) == Set(memberItems.compactMap { $0["id"]?.string }))
        let storeIDs = Set(ownerItems.compactMap { $0["storeId"]?.string })
        #expect(storeIDs.count == 2)
        let productsByStore = Set(storeIDs.map { id in
            Set(ownerItems.filter { $0["storeId"] == .string(id) }.compactMap { $0["name"]?.string })
        })
        #expect(productsByStore == [Set(["Pan", "Leche"]), Set(["Arroz", "Café"])])
        #expect(ownerItems.filter { $0["createdBy"] == .string(owner.id.uuidString.lowercased()) }.count == 2)
        #expect(ownerItems.filter { $0["createdBy"] == .string(member.id.uuidString.lowercased()) }.count == 2)
        let sql = try shoppingSQL(database)
        let stores = try await sql.raw("SELECT id FROM stores WHERE group_id = \(bind: group)::uuid").all()
        #expect(stores.count == 2)
    }
}

private extension ShoppingFixture {
    static func waitForInvitationWaiters(blockedBy holder: Int32, count: Int, database: any Database) async throws {
        try await waitForLockWaiters(
            blockedBy: holder, count: count, query: "%FROM invitations%FOR UPDATE%", database: database
        )
    }

    static func waitForLockWaiters(
        blockedBy holder: Int32,
        count: Int,
        query: String,
        database: any Database
    ) async throws {
        let sql = try shoppingSQL(database)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            // PostgreSQL may queue a tuple waiter behind another waiter: inspect the whole lock graph.
            let row = try #require(try await sql.raw("""
                WITH RECURSIVE blocked(pid) AS (
                    SELECT pid FROM pg_stat_activity
                    WHERE datname = current_database() AND \(bind: holder) = ANY(pg_blocking_pids(pid))
                    UNION
                    SELECT a.pid FROM pg_stat_activity a JOIN blocked b ON b.pid = ANY(pg_blocking_pids(a.pid))
                    WHERE a.datname = current_database()
                )
                SELECT count(*) AS waiting FROM pg_stat_activity
                WHERE pid IN (SELECT pid FROM blocked) AND wait_event_type = 'Lock'
                    AND query LIKE \(bind: query)
                """).first())
            if try row.decode(column: "waiting", as: Int64.self) == Int64(count) {
                return
            }
        }
        throw ShoppingRaceError.requestsDidNotOverlap
    }

    /// Observe each request blocked in PostgreSQL before releasing either production transaction.
    static func overlappingRequests(
        lockedBy query: SQLQueryString,
        waitingQuery: String,
        first: @escaping @Sendable () async throws -> TestingHTTPResponse,
        second: @escaping @Sendable () async throws -> TestingHTTPResponse
    ) async throws -> (TestingHTTPResponse, TestingHTTPResponse) {
        let testDatabase = try database
        let gate = ShoppingSQLGate()
        let holder = Task {
            do {
                try await testDatabase.transaction { transaction in
                    let sql = try shoppingSQL(transaction)
                    try await sql.raw(query).run()
                    let row = try #require(try await sql.raw("SELECT pg_backend_pid() AS pid").first())
                    await gate.locked(try row.decode(column: "pid", as: Int32.self))
                    await gate.waitForRelease()
                }
            } catch {
                await gate.failed(error)
                throw error
            }
        }
        let pid: Int32
        do {
            pid = try await gate.waitUntilLocked()
        } catch {
            await gate.release()
            _ = try? await holder.value
            throw error
        }
        let firstRequest = Task {
            try await first()
        }
        var secondRequest: Task<TestingHTTPResponse, any Error>?
        do {
            try await waitForLockWaiters(
                blockedBy: pid,
                count: 1,
                query: waitingQuery,
                database: testDatabase
            )
            secondRequest = Task {
                try await second()
            }
            try await waitForLockWaiters(
                blockedBy: pid,
                count: 2,
                query: waitingQuery,
                database: testDatabase
            )
        } catch {
            await gate.release()
            _ = try? await holder.value
            _ = try? await firstRequest.value
            _ = try? await secondRequest?.value
            throw error
        }
        await gate.release()
        try await holder.value
        let startedSecond = try #require(secondRequest)
        return try await (firstRequest.value, startedSecond.value)
    }

    static func allPending(group: String, user: User) async throws -> [[String: APIJSON]] {
        let stores = try await request(.GET, "/v1/groups/\(group)/stores", user)
        try #require(stores.status == .ok)
        let fields = try object(stores)
        guard case .array(let values) = fields["stores"] else {
            throw ShoppingRaceError.missingPage
        }
        var result: [[String: APIJSON]] = []
        for value in values {
            guard case .object(let store) = value else { throw ShoppingRaceError.missingPage }
            let id = try #require(store["id"]?.string)
            let items = try await request(.GET, "/v1/groups/\(group)/stores/\(id)/items", user)
            try #require(items.status == .ok)
            guard case .array(let products) = try object(items)["items"] else {
                throw ShoppingRaceError.missingPage
            }
            for product in products {
                guard case .object(let item) = product else { throw ShoppingRaceError.missingPage }
                result.append(item)
            }
        }
        return result
    }
}

private enum ShoppingRaceError: Error {
    case requestsDidNotOverlap
    case missingPage
}

private actor ShoppingSQLGate {
    private var result: Result<Int32, any Error>?
    private var waitingForLock: CheckedContinuation<Int32, any Error>?
    private var waitingForRelease: CheckedContinuation<Void, Never>?
    private var released = false

    func locked(_ pid: Int32) {
        result = .success(pid)
        waitingForLock?.resume(returning: pid)
        waitingForLock = nil
    }

    func failed(_ error: any Error) {
        result = .failure(error)
        waitingForLock?.resume(throwing: error)
        waitingForLock = nil
    }

    func waitUntilLocked() async throws -> Int32 {
        if let result {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation {
            waitingForLock = $0
        }
    }

    func waitForRelease() async {
        guard !released else { return }
        await withCheckedContinuation {
            waitingForRelease = $0
        }
    }

    func release() {
        released = true
        waitingForRelease?.resume()
        waitingForRelease = nil
    }
}

extension SmartShoppingListServerTests {
    @Test(
        "Item changes and purchases serialize without overwriting the first transition",
        .timeLimit(.minutes(1)),
        arguments: [false, true],
        [false, true]
    )
    func itemChangePurchaseRace(cancelling: Bool, purchaseFirst: Bool) async throws {
        let buyer = try await ShoppingFixture.user()
        let editor = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(buyer)
        try await ShoppingFixture.join(editor, group: group)
        let fixture = try await PurchaseFixture.items(buyer, group: group)
        let itemID = fixture.ids[0]
        var fields: [String: APIJSON] = [
            "operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": .integer(1)
        ]
        if !cancelling {
            fields["name"] = .string("Editado")
            fields["quantity"] = .null
            fields["store"] = .object(["id": .string(fixture.store)])
        }
        let payload = APIJSON.object(fields)
        let change: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(
                cancelling ? .POST : .PATCH,
                "/v1/groups/\(group)/items/\(itemID)" + (cancelling ? "/cancellation" : ""),
                editor,
                payload
            )
        }
        let purchase: @Sendable () async throws -> TestingHTTPResponse = {
            try await ShoppingFixture.request(
                .POST,
                "/v1/groups/\(group)/purchases",
                buyer,
                PurchaseFixture.body(store: fixture.store, ids: Array(fixture.ids.prefix(2)))
            )
        }
        let responses = try await ShoppingFixture.overlappingRequests(
            lockedBy: "SELECT id FROM items WHERE id = \(bind: itemID)::uuid FOR UPDATE",
            waitingQuery: "%FROM items%FOR UPDATE%",
            first: purchaseFirst ? purchase : change,
            second: purchaseFirst ? change : purchase
        )
        #expect(responses.0.status == .ok)
        #expect(responses.1.status == .conflict)
        let sql = try shoppingSQL(database)
        let row = try #require(try await sql.raw("SELECT * FROM items WHERE id = \(bind: itemID)::uuid").first())
        #expect(try row.decode(column: "version", as: Int64.self) == 2)
        #expect(try row.decode(column: "status", as: String.self) == (purchaseFirst ? "purchased" : (cancelling ? "cancelled" : "pending")))
        #expect(try row.decode(column: "purchased_by", as: UUID?.self) == (purchaseFirst ? buyer.id : nil))
        let purchased = try await sql.raw("SELECT id FROM items WHERE status = 'purchased'").all()
        #expect(purchased.count == (purchaseFirst ? 2 : 0))
        let repeated = try await change()
        #expect(repeated.body.string == (purchaseFirst ? responses.1.body.string : responses.0.body.string))
    }
}
