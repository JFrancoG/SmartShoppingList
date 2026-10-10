import FluentKit
import FluentSQL

struct AddAppStoreSubscriptions: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                CREATE TABLE app_store_subscriptions (
                    environment TEXT NOT NULL CHECK(environment IN ('Production','Sandbox')),
                    original_transaction_id TEXT NOT NULL, user_id UUID NOT NULL REFERENCES users(id),
                    transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, state TEXT NOT NULL,
                    purchase_date TIMESTAMPTZ NOT NULL, expires_at TIMESTAMPTZ NOT NULL,
                    grace_expires_at TIMESTAMPTZ, auto_renew_enabled BOOLEAN NOT NULL,
                    revision TIMESTAMPTZ NOT NULL, verified_at TIMESTAMPTZ NOT NULL,
                    PRIMARY KEY(environment,original_transaction_id)
                )
                """).run()
            try await sql.raw("CREATE INDEX app_store_subscriptions_user ON app_store_subscriptions(user_id)").run()
            try await sql.raw("""
                CREATE TABLE app_store_transactions (
                    environment TEXT NOT NULL, transaction_id TEXT NOT NULL, user_id UUID NOT NULL REFERENCES users(id),
                    original_transaction_id TEXT NOT NULL, verified_at TIMESTAMPTZ NOT NULL,
                    PRIMARY KEY(environment,transaction_id),
                    FOREIGN KEY(environment,original_transaction_id)
                        REFERENCES app_store_subscriptions(environment,original_transaction_id)
                )
                """).run()
            try await sql.raw("""
                CREATE TABLE app_store_notifications (
                    environment TEXT NOT NULL CHECK(environment IN ('Production','Sandbox')),
                    notification_id UUID NOT NULL, payload_hash TEXT NOT NULL, received_at TIMESTAMPTZ NOT NULL,
                    PRIMARY KEY(environment,notification_id)
                )
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                LOCK TABLE app_store_subscriptions, app_store_transactions, app_store_notifications IN ACCESS EXCLUSIVE MODE
                """).run()
            guard try await sql.raw("""
                SELECT 1 FROM app_store_subscriptions UNION ALL SELECT 1 FROM app_store_transactions
                UNION ALL SELECT 1 FROM app_store_notifications LIMIT 1
                """).first() == nil else { throw ReversionError.verifiedSubscriptionsCannotBeDiscarded }
            try await sql.raw("DROP TABLE app_store_transactions, app_store_subscriptions, app_store_notifications").run()
        }
    }

    enum ReversionError: Error, Equatable {
        case verifiedSubscriptionsCannotBeDiscarded
    }
}
