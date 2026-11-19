import FluentKit
import FluentSQL

/// Makes removed attribution explicit without retaining a synthetic deleted user.
struct AddAccountDeletion: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            for statement in Self.statements {
                try await sql.raw(SQLQueryString(stringLiteral: statement)).run()
            }
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                LOCK TABLE users,groups,stores,items,mutation_receipts,app_store_subscriptions,app_store_transactions
                IN ACCESS EXCLUSIVE MODE
                """).run()
            guard try await sql.raw("""
                SELECT 1 FROM users WHERE deleting_at IS NOT NULL
                UNION ALL SELECT 1 FROM groups WHERE creator_user_id IS NULL OR pending_administration
                UNION ALL SELECT 1 FROM stores WHERE name_redacted
                UNION ALL SELECT 1 FROM items WHERE name_redacted OR created_by IS NULL OR (status = 'purchased' AND purchased_by IS NULL)
                UNION ALL SELECT 1 FROM mutation_receipts WHERE result_removed
                UNION ALL SELECT 1 FROM app_store_subscriptions WHERE user_id IS NULL OR detached_at IS NOT NULL
                UNION ALL SELECT 1 FROM app_store_transactions WHERE user_id IS NULL LIMIT 1
                """).first() == nil else { throw ReversionError.deletedAccountsCannotBeRepresented }
            try await sql.raw("ALTER TABLE users DROP COLUMN deleting_at").run()
            try await sql.raw("ALTER TABLE stores DROP COLUMN name_redacted").run()
            try await sql.raw("""
                ALTER TABLE groups DROP CONSTRAINT groups_active_administrator_check,
                    DROP COLUMN pending_administration, ALTER COLUMN creator_user_id SET NOT NULL,
                    ADD CONSTRAINT groups_active_administrator_check
                        CHECK((closed_at IS NULL) = (administrator_user_id IS NOT NULL))
                """).run()
            try await sql.raw("""
                ALTER TABLE items DROP CONSTRAINT items_purchase_state_check, DROP COLUMN name_redacted,
                    ALTER COLUMN created_by SET NOT NULL,
                    ADD CONSTRAINT items_check CHECK(
                        (status = 'purchased' AND purchased_by IS NOT NULL AND purchased_at IS NOT NULL)
                        OR (status <> 'purchased' AND purchased_by IS NULL AND purchased_at IS NULL))
                """).run()
            try await sql.raw("""
                ALTER TABLE mutation_receipts DROP CONSTRAINT receipts_removed_content_check,
                    DROP COLUMN result_removed, ALTER COLUMN fingerprint SET NOT NULL
                """).run()
            try await sql.raw("""
                ALTER TABLE app_store_subscriptions DROP COLUMN detached_at, ALTER COLUMN user_id SET NOT NULL
                """).run()
            try await sql.raw("ALTER TABLE app_store_transactions ALTER COLUMN user_id SET NOT NULL").run()
        }
    }

    enum ReversionError: Error, Equatable {
        case deletedAccountsCannotBeRepresented
    }

    private static let statements = [
        "ALTER TABLE users ADD COLUMN deleting_at TIMESTAMPTZ",
        "ALTER TABLE stores ADD COLUMN name_redacted BOOLEAN NOT NULL DEFAULT false",
        """
        ALTER TABLE groups ALTER COLUMN creator_user_id DROP NOT NULL,
            ADD COLUMN pending_administration BOOLEAN NOT NULL DEFAULT false,
            DROP CONSTRAINT groups_active_administrator_check,
            ADD CONSTRAINT groups_active_administrator_check CHECK(
                (closed_at IS NOT NULL AND administrator_user_id IS NULL AND NOT pending_administration)
                OR (closed_at IS NULL AND (
                    (administrator_user_id IS NOT NULL AND NOT pending_administration)
                    OR (administrator_user_id IS NULL AND pending_administration))))
        """,
        """
        ALTER TABLE items ALTER COLUMN created_by DROP NOT NULL, DROP CONSTRAINT items_check,
            ADD COLUMN name_redacted BOOLEAN NOT NULL DEFAULT false,
            ADD CONSTRAINT items_purchase_state_check CHECK(
                (status = 'purchased' AND purchased_at IS NOT NULL)
                OR (status <> 'purchased' AND purchased_by IS NULL AND purchased_at IS NULL))
        """,
        """
        ALTER TABLE mutation_receipts ALTER COLUMN fingerprint DROP NOT NULL,
            ADD COLUMN result_removed BOOLEAN NOT NULL DEFAULT false,
            ADD CONSTRAINT receipts_removed_content_check CHECK(
                (result_removed AND fingerprint IS NULL AND body IS NULL AND status IS NULL AND group_id IS NULL)
                OR (NOT result_removed AND fingerprint IS NOT NULL))
        """,
        """
        ALTER TABLE app_store_subscriptions ALTER COLUMN user_id DROP NOT NULL, ADD COLUMN detached_at TIMESTAMPTZ
        """,
        "ALTER TABLE app_store_transactions ALTER COLUMN user_id DROP NOT NULL"
    ]
}
