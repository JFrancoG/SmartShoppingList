import FluentKit
import FluentSQL

struct AddGroupMemberships: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("LOCK TABLE groups, users IN ACCESS EXCLUSIVE MODE").run()
            try await sql.raw("""
                CREATE TABLE group_memberships (
                    group_id UUID NOT NULL REFERENCES groups(id), user_id UUID NOT NULL REFERENCES users(id),
                    joined_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), PRIMARY KEY(group_id, user_id)
                )
                """).run()
            try await sql.raw("""
                INSERT INTO group_memberships(group_id,user_id)
                SELECT group_id,id FROM users WHERE group_id IS NOT NULL
                """).run()
            try await sql.raw("CREATE INDEX memberships_user_idx ON group_memberships(user_id,group_id)").run()
            try await sql.raw("ALTER TABLE groups DROP CONSTRAINT groups_administrator_membership_fkey").run()
            try await sql.raw("""
                ALTER TABLE groups ADD CONSTRAINT groups_administrator_membership_fkey
                    FOREIGN KEY(id,administrator_user_id) REFERENCES group_memberships(group_id,user_id)
                    DEFERRABLE INITIALLY DEFERRED
                """).run()
            try await sql.raw("ALTER TABLE users DROP CONSTRAINT users_group_and_id_unique").run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("LOCK TABLE groups, users, group_memberships IN ACCESS EXCLUSIVE MODE").run()
            // A singular schema cannot retain extra memberships or a missing legacy projection.
            guard try await sql.raw("""
                SELECT 1 FROM group_memberships AS membership JOIN users ON users.id = membership.user_id
                WHERE users.group_id IS DISTINCT FROM membership.group_id
                UNION ALL
                SELECT 1 FROM users WHERE group_id IS NOT NULL AND NOT EXISTS (
                    SELECT 1 FROM group_memberships WHERE user_id = users.id AND group_id = users.group_id
                ) LIMIT 1
                """).first() == nil else { throw ReversionError.multipleMembershipsCannotBeRepresented }
            try await sql.raw("ALTER TABLE groups DROP CONSTRAINT groups_administrator_membership_fkey").run()
            try await sql.raw("ALTER TABLE users ADD CONSTRAINT users_group_and_id_unique UNIQUE(group_id,id)").run()
            try await sql.raw("""
                ALTER TABLE groups ADD CONSTRAINT groups_administrator_membership_fkey
                    FOREIGN KEY(id,administrator_user_id) REFERENCES users(group_id,id)
                    DEFERRABLE INITIALLY DEFERRED
                """).run()
            try await sql.raw("DROP TABLE group_memberships").run()
        }
    }

    enum ReversionError: Error, Equatable {
        case multipleMembershipsCannotBeRepresented
    }
}
