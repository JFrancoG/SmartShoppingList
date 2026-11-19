import FluentKit
import FluentSQL

struct AddSubscriptionRecovery: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                CREATE TABLE subscription_recovery_challenges (
                    id UUID PRIMARY KEY, user_id UUID NOT NULL REFERENCES users(id),
                    environment TEXT NOT NULL CHECK(environment IN ('Sandbox','Production')),
                    original_transaction_id TEXT NOT NULL, transaction_hash TEXT NOT NULL,
                    key_id TEXT UNIQUE NOT NULL, nonce TEXT NOT NULL, expires_at TIMESTAMPTZ NOT NULL,
                    verified_at TIMESTAMPTZ, attestation_hash TEXT
                )
                """).run()
            try await sql.raw("CREATE INDEX subscription_recovery_challenges_user ON subscription_recovery_challenges(user_id)").run()
            try await sql.raw("""
                CREATE TABLE subscription_recovery_jobs (
                    environment TEXT NOT NULL, original_transaction_id TEXT NOT NULL,
                    user_id UUID REFERENCES users(id),
                    challenge_id UUID UNIQUE REFERENCES subscription_recovery_challenges(id),
                    state TEXT NOT NULL CHECK(state IN ('reserved','completed','quarantined')),
                    request_in_flight BOOLEAN NOT NULL DEFAULT false,
                    has_uncertain_update BOOLEAN NOT NULL DEFAULT false,
                    attempt_started_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
                    reserved_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), completed_at TIMESTAMPTZ,
                    PRIMARY KEY(environment,original_transaction_id)
                )
                """).run()
            try await sql.raw("CREATE INDEX subscription_recovery_jobs_user ON subscription_recovery_jobs(user_id)").run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("""
                LOCK TABLE subscription_recovery_jobs, subscription_recovery_challenges IN ACCESS EXCLUSIVE MODE
                """).run()
            guard try await sql.raw("SELECT 1 FROM subscription_recovery_jobs LIMIT 1").first() == nil else {
                throw AppStoreGatewayError.unavailable
            }
            try await sql.raw("DROP TABLE subscription_recovery_jobs, subscription_recovery_challenges").run()
        }
    }
}
