@testable import SmartShoppingListServer
import Foundation
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Deletion reconstructs a complete legacy edit chain and preserves another member's quantity")
    func deletionReconstructsLegacyFieldsAndKeepsOtherContributions() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let item = try await DeletionDataFixture.add(owner, group: group, name: "Pan", quantity: "2")
        let edit = try await ShoppingFixture.request(
            .PATCH,
            "/v1/groups/\(group)/items/\(item)",
            member,
            .object([
                "operationId": .string(UUID().uuidString.lowercased()), "expectedVersion": .integer(1),
                "name": .string("Pan"), "quantity": .string("3"),
                "store": .object(["newName": .string("Aldi")])
            ])
        )
        try #require(edit.status == .ok)
        let other = try await DeletionDataFixture.add(member, group: group, name: "Leche", quantity: nil)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            UPDATE items SET name_author_user_id = NULL,quantity_author_user_id = NULL WHERE id = \(bind: item)::uuid
            """).run()
        try await sql.raw("UPDATE stores SET created_by = NULL WHERE group_id = \(bind: group)::uuid").run()
        let impact = try await AccountDataPurger.preview(user: owner.id, on: sql)
        #expect(impact.legacyContentCount == 1)
        #expect(impact.groups.first?.administers == true)
        try await DeletionDataFixture.purge(owner.id)
        let retained = try #require(try await sql.raw("SELECT * FROM items WHERE id = \(bind: item)::uuid").first())
        #expect(try retained.decode(column: "name", as: String.self) == "Producto sin nombre")
        #expect(try retained.decode(column: "quantity", as: String?.self) == "3")
        #expect(try retained.decode(column: "name_redacted", as: Bool.self))
        #expect(try retained.decode(column: "created_by", as: UUID?.self) == nil)
        #expect(try retained.decode(column: "quantity_author_user_id", as: UUID?.self) == member.id)
        let untouched = try #require(try await sql.raw("SELECT * FROM items WHERE id = \(bind: other)::uuid").first())
        #expect(try untouched.decode(column: "name", as: String.self) == "Leche")
        let administration = try #require(try await sql.raw("SELECT * FROM groups WHERE id = \(bind: group)::uuid").first())
        #expect(try administration.decode(column: "administrator_user_id", as: UUID?.self) == nil)
        #expect(try administration.decode(column: "pending_administration", as: Bool.self))
        #expect(try await sql.raw("SELECT 1 FROM users WHERE id = \(bind: owner.id)").first() == nil)
        let receipts = try await sql.raw("SELECT * FROM mutation_receipts WHERE user_id = \(bind: member.id)").all()
        try #require(!receipts.isEmpty)
        for receipt in receipts {
            #expect(try receipt.decode(column: "result_removed", as: Bool.self))
            #expect(try receipt.decode(column: "body", as: String?.self) == nil)
            #expect(try receipt.decode(column: "fingerprint", as: String?.self) == nil)
            #expect(try receipt.decode(column: "group_id", as: UUID?.self) == nil)
        }
    }

    @Test("Unknown legacy text is removed only in groups to which the deleted account is connected")
    func deletionScopesUnknownTextAndKeepsUnrelatedGroups() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let otherGroup = try await ShoppingFixture.group(outsider)
        let uncertain = try await DeletionDataFixture.add(member, group: group, name: "Texto antiguo", quantity: "personal")
        let unrelated = try await DeletionDataFixture.add(outsider, group: otherGroup, name: "No cambiar", quantity: "2")
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE items SET name_author_user_id = NULL,quantity_author_user_id = NULL").run()
        try await sql.raw("UPDATE stores SET created_by = NULL").run()
        try await sql.raw("DELETE FROM mutation_receipts WHERE operation_type = 'addItems'").run()
        let before = try #require(try await sql.raw("""
            SELECT to_jsonb(items)::text AS value FROM items WHERE id = \(bind: unrelated)::uuid
            """).first()).decode(column: "value", as: String.self)
        let impact = try await AccountDataPurger.preview(user: owner.id, on: sql)
        #expect(impact.legacyContentCount == 3)
        #expect(impact.groups.map(\.id) == [group])
        try await DeletionDataFixture.purge(owner.id)
        let retained = try #require(try await sql.raw("SELECT * FROM items WHERE id = \(bind: uncertain)::uuid").first())
        #expect(try retained.decode(column: "name", as: String.self) == "Producto sin nombre")
        #expect(try retained.decode(column: "quantity", as: String?.self) == nil)
        #expect(try retained.decode(column: "created_by", as: UUID?.self) == member.id)
        let after = try #require(try await sql.raw("""
            SELECT to_jsonb(items)::text AS value FROM items WHERE id = \(bind: unrelated)::uuid
            """).first()).decode(column: "value", as: String.self)
        #expect(after == before)
    }

    @Test("Deleting the last member removes all operational dependencies and detaches a paid subscription")
    func deletionOfLastMemberPurgesDependenciesAndDetachesSubscription() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        _ = try await DeletionDataFixture.add(owner, group: group, name: "Pan", quantity: nil)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            INSERT INTO app_store_subscriptions(environment,original_transaction_id,user_id,transaction_id,product_id,state,
                purchase_date,expires_at,auto_renew_enabled,revision,verified_at)
            VALUES ('Sandbox','500001',\(bind: owner.id),'500002','monthly','subscribed',clock_timestamp(),
                clock_timestamp()+INTERVAL '1 day',true,clock_timestamp(),clock_timestamp())
            """).run()
        try await sql.raw("""
            INSERT INTO app_store_transactions(environment,transaction_id,user_id,original_transaction_id,verified_at)
            VALUES ('Sandbox','500002',\(bind: owner.id),'500001',clock_timestamp())
            """).run()
        try await DeletionDataFixture.purge(owner.id)
        for table in ["users", "groups", "stores", "items", "group_memberships", "app_sessions", "apple_grants"] {
            #expect(try await sql.raw("SELECT 1 FROM \(ident: table) LIMIT 1").first() == nil)
        }
        let subscription = try #require(try await sql.raw("SELECT * FROM app_store_subscriptions").first())
        #expect(try subscription.decode(column: "user_id", as: UUID?.self) == nil)
        #expect(try subscription.decode(column: "detached_at", as: Date?.self) != nil)
        #expect(try subscription.decode(column: "state", as: String.self) == "subscribed")
        #expect(try await sql.raw("SELECT 1 FROM app_store_transactions WHERE user_id IS NOT NULL").first() == nil)
        try await AccountDataPurger.purge(user: owner.id, on: sql)
    }

    @Test("The purger refuses an account whose deletion was not accepted")
    func deletionPurgeRequiresAcceptedIntent() async throws {
        let owner = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        let sql = try shoppingSQL(database)
        await #expect(throws: APIProblem.self) {
            try await AccountDataPurger.purge(user: owner.id, on: sql)
        }
        #expect(try await sql.raw("SELECT 1 FROM groups WHERE id = \(bind: group)::uuid").first() != nil)
        #expect(try await sql.raw("SELECT 1 FROM users WHERE id = \(bind: owner.id)").first() != nil)
    }

    @Test("Deletion quarantines unresolved Apple recovery chains without retaining the former account identity")
    func deletionAnonymizesUncertainRecoveryJobs() async throws {
        let owner = try await ShoppingFixture.user()
        let sql = try shoppingSQL(database)
        let cases: [(String, String, Bool, Bool)] = [
            ("complete", "completed", false, false),
            ("reserved", "reserved", false, false),
            ("flight", "reserved", true, false),
            ("uncertain", "completed", false, true)
        ]
        for (chain, state, inFlight, uncertain) in cases {
            let challenge = UUID()
            try await sql.raw("""
                INSERT INTO subscription_recovery_challenges(id,user_id,environment,original_transaction_id,
                    transaction_hash,key_id,nonce,expires_at)
                VALUES(\(bind: challenge),\(bind: owner.id),'Sandbox',\(bind: chain),'hash',\(bind: chain),
                    'nonce',clock_timestamp() + INTERVAL '5 minutes')
                """).run()
            try await sql.raw("""
                INSERT INTO subscription_recovery_jobs(environment,original_transaction_id,user_id,challenge_id,
                    state,request_in_flight,has_uncertain_update)
                VALUES('Sandbox',\(bind: chain),\(bind: owner.id),\(bind: challenge),\(bind: state),
                    \(bind: inFlight),\(bind: uncertain))
                """).run()
        }
        try await DeletionDataFixture.purge(owner.id)
        let jobs = try await sql.raw("SELECT * FROM subscription_recovery_jobs ORDER BY original_transaction_id").all()
        #expect(try jobs.map { try $0.decode(column: "original_transaction_id", as: String.self) } == ["flight", "reserved", "uncertain"])
        for job in jobs {
            #expect(try job.decode(column: "state", as: String.self) == "quarantined")
            #expect(try job.decode(column: "user_id", as: UUID?.self) == nil)
            #expect(try job.decode(column: "challenge_id", as: UUID?.self) == nil)
            #expect(try job.decode(column: "request_in_flight", as: Bool.self) == false)
        }
        #expect(try await sql.raw("SELECT 1 FROM subscription_recovery_challenges").first() == nil)
        #expect(try await sql.raw("SELECT 1 FROM users WHERE id = \(bind: owner.id)").first() == nil)
    }
}

struct LegacyContentProvenanceTests {
    @Test("A complete history preserves field authors across no-op edits and store movement")
    func completeHistoryPreservesFieldAuthors() {
        let creator = UUID()
        let editor = UUID()
        let first = item(name: "Pan", quantity: "2", version: 1, creator: creator)
        let second = copy(first, quantity: "3", version: 2)
        let third = copy(second, quantity: "3", version: 3, store: UUID())
        let revisions: [LegacyContentProvenance.Revision] = [
            .init(actor: creator, operation: "addItems", item: first),
            .init(actor: editor, operation: "editItem", item: second),
            .init(actor: creator, operation: "editItem", item: third)
        ]
        #expect(LegacyContentProvenance.authors(of: third, revisions: revisions) == .init(name: creator, quantity: editor))
        #expect(LegacyContentProvenance.authors(of: third, revisions: [revisions[0], revisions[2]]) == nil)
        #expect(LegacyContentProvenance.authors(of: third, revisions: revisions + [revisions[2]]) == nil)
        let inconsistent = copy(third, quantity: "Dato sin recibo", version: 3)
        #expect(LegacyContentProvenance.authors(of: inconsistent, revisions: revisions) == nil)
    }

    private func item(
        name: String,
        quantity: String?,
        version: Int64,
        creator: UUID
    ) -> LegacyContentProvenance.Item {
        .init(
            id: UUID(),
            groupId: UUID(),
            storeId: UUID(),
            name: name,
            quantity: quantity,
            status: "pending",
            version: version,
            createdBy: creator,
            purchasedBy: nil
        )
    }

    private func copy(
        _ source: LegacyContentProvenance.Item,
        quantity: String?,
        version: Int64,
        store: UUID? = nil
    ) -> LegacyContentProvenance.Item {
        .init(
            id: source.id,
            groupId: source.groupId,
            storeId: store ?? source.storeId,
            name: source.name,
            quantity: quantity,
            status: source.status,
            version: version,
            createdBy: source.createdBy,
            purchasedBy: source.purchasedBy
        )
    }
}

private enum DeletionDataFixture {
    static func add(
        _ user: ShoppingFixture.User,
        group: String,
        name: String,
        quantity: String?
    ) async throws -> String {
        let response = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            user,
            .object([
                "operationId": .string(UUID().uuidString.lowercased()),
                "items": .array([.object([
                    "name": .string(name), "quantity": .optional(quantity),
                    "store": .object(["newName": .string("Aldi")])
                ])])
            ])
        )
        try #require(response.status == .created)
        return try #require(try StoreQuotaFixture.array(response, key: "items").first?["id"]?.string)
    }

    static func purge(_ user: UUID) async throws {
        try await database.transaction { database in
            let sql = try shoppingSQL(database)
            try await sql.raw("UPDATE users SET deleting_at = clock_timestamp() WHERE id = \(bind: user)").run()
            try await AccountDataPurger.purge(user: user, on: sql)
        }
    }
}
