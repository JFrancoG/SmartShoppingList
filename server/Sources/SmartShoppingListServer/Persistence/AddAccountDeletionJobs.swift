import FluentKit
import FluentSQL

struct AddAccountDeletionJobs: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.transaction { database in
            let sql = try shoppingSQL(database)
            try await sql.raw("""
                ALTER TABLE apple_grants ADD COLUMN validation_id UUID, ADD COLUMN validation_deadline TIMESTAMPTZ,
                    ADD COLUMN validation_uncertain BOOLEAN NOT NULL DEFAULT FALSE,
                    ADD CONSTRAINT apple_validation_lease_check
                        CHECK((validation_id IS NULL) = (validation_deadline IS NULL))
                """).run()
            try await sql.raw("""
                CREATE TABLE account_deletion_jobs (
                    id UUID PRIMARY KEY, user_id UUID REFERENCES users(id) ON DELETE SET NULL,
                    subject TEXT, secret_hash TEXT NOT NULL, revision TEXT NOT NULL,
                    state TEXT NOT NULL CHECK(state IN ('prepared','accepted','purging','data_deleted','completed','cancelled')),
                    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), accepted_at TIMESTAMPTZ,
                    data_deleted_at TIMESTAMPTZ, completed_at TIMESTAMPTZ,
                    expires_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp() + INTERVAL '30 days',
                    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
                    lease_until TIMESTAMPTZ, lease_id UUID, apple_requires_manual BOOLEAN NOT NULL DEFAULT FALSE,
                    apple_outcome TEXT CHECK(apple_outcome IN ('confirmed','manual_action_required'))
                )
                """).run()
            try await sql.raw("""
                CREATE UNIQUE INDEX deletion_one_per_user ON account_deletion_jobs(user_id)
                WHERE state IN ('prepared','accepted','purging','data_deleted')
                """).run()
            try await sql.raw("CREATE INDEX deletion_subject ON account_deletion_jobs(subject) WHERE subject IS NOT NULL").run()
            try await sql.raw("""
                ALTER TABLE auth_challenges ADD COLUMN login_subject TEXT,
                    ADD COLUMN login_exchange_pending BOOLEAN NOT NULL DEFAULT FALSE,
                    ADD COLUMN login_exchange_deadline TIMESTAMPTZ,
                    ADD COLUMN login_deletion_job_id UUID REFERENCES account_deletion_jobs(id) ON DELETE CASCADE
                """).run()
            try await sql.raw("""
                CREATE TABLE account_deletion_challenges (
                    id UUID PRIMARY KEY, job_id UUID NOT NULL REFERENCES account_deletion_jobs(id) ON DELETE CASCADE,
                    nonce TEXT, expires_at TIMESTAMPTZ NOT NULL, claimed_at TIMESTAMPTZ
                )
                """).run()
            try await sql.raw("""
                CREATE TABLE account_deletion_tokens (
                    job_id UUID NOT NULL REFERENCES account_deletion_jobs(id) ON DELETE CASCADE,
                    grant_id UUID NOT NULL, ciphertext BYTEA NOT NULL, key_version TEXT NOT NULL,
                    PRIMARY KEY(job_id,grant_id)
                )
                """).run()
            // Hashes authorize a bounded, explicit remote-deletion signal; a generic 401 never proves deletion.
            try await sql.raw("""
                CREATE TABLE deleted_session_receipts (
                    token_hash TEXT PRIMARY KEY, expires_at TIMESTAMPTZ NOT NULL
                )
                """).run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { database in
            let sql = try shoppingSQL(database)
            guard try await sql.raw("""
                SELECT 1 FROM account_deletion_jobs
                UNION ALL SELECT 1 FROM apple_grants WHERE validation_id IS NOT NULL OR validation_uncertain LIMIT 1
                """).first() == nil else {
                throw APIProblem.unavailable
            }
            try await sql.raw("""
                ALTER TABLE auth_challenges DROP COLUMN login_subject,DROP COLUMN login_exchange_pending,
                    DROP COLUMN login_exchange_deadline,DROP COLUMN login_deletion_job_id
                """).run()
            try await sql.raw("DROP TABLE deleted_session_receipts, account_deletion_tokens, account_deletion_challenges, account_deletion_jobs").run()
            try await sql.raw("""
                ALTER TABLE apple_grants DROP CONSTRAINT apple_validation_lease_check,
                    DROP COLUMN validation_id, DROP COLUMN validation_deadline, DROP COLUMN validation_uncertain
                """).run()
        }
    }
}
