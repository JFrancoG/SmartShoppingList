import FluentKit
import FluentSQL

/// Adds transferable responsibility without rewriting the MVP's historical creator or shared data.
struct AddGroupAdministration: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            for statement in Self.statements {
                try await sql.raw(SQLQueryString(stringLiteral: statement)).run()
            }
        }
    }

    func revert(on database: any Database) async throws {
        let sql = try shoppingSQL(database)
        try await sql.raw("DROP TABLE group_administration_transfers").run()
        try await sql.raw("ALTER TABLE groups DROP CONSTRAINT groups_administrator_membership_fkey").run()
        try await sql.raw("ALTER TABLE groups DROP COLUMN administrator_user_id, DROP COLUMN closed_at").run()
        try await sql.raw("ALTER TABLE users DROP CONSTRAINT users_group_and_id_unique").run()
        // Do not reintroduce creator uniqueness: valid closed groups can now share a historical creator.
    }

    private static let statements = [
        "ALTER TABLE groups ADD COLUMN administrator_user_id UUID, ADD COLUMN closed_at TIMESTAMPTZ",
        "UPDATE groups SET administrator_user_id = creator_user_id",
        "ALTER TABLE groups DROP CONSTRAINT groups_creator_user_id_key",
        "ALTER TABLE users ADD CONSTRAINT users_group_and_id_unique UNIQUE(group_id, id)",
        """
        ALTER TABLE groups ADD CONSTRAINT groups_administrator_membership_fkey
            FOREIGN KEY(id, administrator_user_id) REFERENCES users(group_id, id)
            DEFERRABLE INITIALLY DEFERRED
        """,
        """
        ALTER TABLE groups ADD CONSTRAINT groups_active_administrator_check
            CHECK((closed_at IS NULL) = (administrator_user_id IS NOT NULL))
        """,
        """
        CREATE TABLE group_administration_transfers (
            id UUID PRIMARY KEY, group_id UUID NOT NULL REFERENCES groups(id),
            proposer_user_id UUID NOT NULL REFERENCES users(id),
            recipient_user_id UUID NOT NULL REFERENCES users(id),
            status TEXT NOT NULL CHECK(status IN ('pending','accepted','rejected','withdrawn','expired','invalidated')),
            created_at TIMESTAMPTZ NOT NULL, expires_at TIMESTAMPTZ NOT NULL, resolved_at TIMESTAMPTZ,
            CHECK(proposer_user_id <> recipient_user_id), CHECK(expires_at > created_at),
            CHECK((status = 'pending') = (resolved_at IS NULL))
        )
        """,
        """
        CREATE UNIQUE INDEX group_administration_one_pending_idx
            ON group_administration_transfers(group_id) WHERE status = 'pending'
        """,
        "CREATE INDEX group_administration_history_idx ON group_administration_transfers(group_id, created_at, id)"
    ]
}
