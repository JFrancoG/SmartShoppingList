import FluentKit
import FluentSQL

/// Only verified server ingestion can populate access; existing accounts remain free.
struct AddAccountPremiumAccess: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                ALTER TABLE users ADD COLUMN free_group_id UUID REFERENCES groups(id),
                    ADD COLUMN free_group_changed_at TIMESTAMPTZ
                """).run()
            try await sql.raw("""
                CREATE TABLE account_premium_access (
                    user_id UUID NOT NULL REFERENCES users(id), premium_until TIMESTAMPTZ,
                    verification_environment TEXT NOT NULL DEFAULT 'Production'
                        CHECK(verification_environment IN ('Production','Sandbox')),
                    transition_started_at TIMESTAMPTZ, transition_allowed BOOLEAN NOT NULL,
                    CHECK(premium_until IS NOT NULL OR transition_started_at IS NULL),
                    PRIMARY KEY(user_id,verification_environment)
                )
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("LOCK TABLE users, account_premium_access IN ACCESS EXCLUSIVE MODE").run()
            guard try await sql.raw("""
                SELECT 1 FROM account_premium_access
                UNION ALL SELECT 1 FROM users WHERE free_group_id IS NOT NULL OR free_group_changed_at IS NOT NULL
                LIMIT 1
                """).first() == nil else { throw ReversionError.premiumAccessCannotBeRepresented }
            try await sql.raw("DROP TABLE account_premium_access").run()
            try await sql.raw("ALTER TABLE users DROP COLUMN free_group_id, DROP COLUMN free_group_changed_at").run()
        }
    }

    enum ReversionError: Error, Equatable {
        case premiumAccessCannotBeRepresented
    }
}
