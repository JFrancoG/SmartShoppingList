@testable import SmartShoppingListServer
import Foundation
import FluentKit
import FluentSQL
import FluentPostgresDriver
import Testing

extension SmartShoppingListServerTests {
    @Test("The upgrade preserves legacy identities and history and derives administration from the original creator")
    func administrationMigrationPreservesLegacyData() async throws {
        let owner = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(member, group: group)
        let history = try await AdministrationFixture.seedHistory(owner, group: group)
        let invitation = try await ShoppingFixture.invitation(group)
        let sql = try shoppingSQL(database)
        let original = try #require(try await sql.raw("SELECT created_at FROM groups WHERE id = \(bind: group)::uuid").first())
        let createdAt = try original.decode(column: "created_at", as: Date.self)
        // Reconstruct the already-deployed schema around representative persisted MVP records.
        try await AddGroupMemberships().revert(on: database)
        try await AddGroupAdministration().revert(on: database)
        try await sql.raw("ALTER TABLE groups ADD CONSTRAINT groups_creator_user_id_key UNIQUE(creator_user_id)").run()
        try await AddGroupAdministration().prepare(on: database)
        try await AddGroupMemberships().prepare(on: database)
        let migrated = try #require(try await sql.raw("SELECT * FROM groups WHERE id = \(bind: group)::uuid").first())
        #expect(try migrated.decode(column: "administrator_user_id", as: UUID.self) == owner.id)
        #expect(try migrated.decode(column: "creator_user_id", as: UUID.self) == owner.id)
        #expect(try migrated.decode(column: "created_at", as: Date.self) == createdAt)
        let members = try await sql.raw(
            "SELECT user_id AS id FROM group_memberships WHERE group_id = \(bind: group)::uuid"
        ).all()
        #expect(Set(try members.map { try $0.decode(column: "id", as: UUID.self) }) == [owner.id, member.id])
        #expect(try await AdministrationFixture.itemSnapshot(group: group) == history)
        let retained = try await sql.raw("SELECT id FROM invitations WHERE id = \(bind: invitation.id)").all()
        #expect(retained.count == 1)
    }

    @Test("Database constraints reject missing or foreign administrators and duplicate pending proposals")
    func administrationDatabaseInvariants() async throws {
        let owner = try await ShoppingFixture.user()
        let recipient = try await ShoppingFixture.user()
        let outsider = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(owner)
        try await ShoppingFixture.join(recipient, group: group)
        let sql = try shoppingSQL(database)
        await #expect {
            try await sql.raw("UPDATE groups SET administrator_user_id = NULL WHERE id = \(bind: group)::uuid").run()
        } throws: { error in
            (error as? any DatabaseError)?.isConstraintFailure == true
        }
        await #expect {
            try await database.transaction { transaction in
                let transactionSQL = try shoppingSQL(transaction)
                try await transactionSQL.raw("""
                    UPDATE groups SET administrator_user_id = \(bind: outsider.id) WHERE id = \(bind: group)::uuid
                    """).run()
            }
        } throws: { error in
            let postgres = error as? PSQLError
            return postgres?.serverInfo?[.sqlState] == "23503"
                && postgres?.serverInfo?[.constraintName] == "groups_administrator_membership_fkey"
        }
        await #expect {
            try await database.transaction { transaction in
                let transactionSQL = try shoppingSQL(transaction)
                try await transactionSQL.raw("DELETE FROM group_memberships WHERE user_id = \(bind: owner.id)").run()
            }
        } throws: { error in
            let postgres = error as? PSQLError
            return postgres?.serverInfo?[.sqlState] == "23503"
                && postgres?.serverInfo?[.constraintName] == "groups_administrator_membership_fkey"
        }
        _ = try await AdministrationFixture.propose(owner, recipient: recipient, group: group)
        await #expect {
            try await sql.raw("""
                INSERT INTO group_administration_transfers
                    (id,group_id,proposer_user_id,recipient_user_id,status,created_at,expires_at)
                VALUES (\(bind: UUID()),\(bind: group)::uuid,\(bind: owner.id),\(bind: recipient.id),'pending',
                    clock_timestamp(),clock_timestamp() + INTERVAL '1 day')
                """).run()
        } throws: { error in
            (error as? any DatabaseError)?.isConstraintFailure == true
        }
        let actual = try #require(try await sql.raw("""
            SELECT administrator_user_id FROM groups WHERE id = \(bind: group)::uuid
            """).first())
        #expect(try actual.decode(column: "administrator_user_id", as: UUID.self) == owner.id)
    }
}
