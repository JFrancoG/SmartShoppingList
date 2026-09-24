import FluentKit
import FluentSQL

struct CreateAppleAuthentication: AsyncMigration {
    func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { throw AppleGatewayError.invalidConfiguration }
        try await sql.raw("""
            CREATE TABLE auth_challenges (
                id UUID PRIMARY KEY,
                nonce TEXT,
                created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
                expires_at TIMESTAMPTZ NOT NULL,
                claimed_at TIMESTAMPTZ,
                consumed_at TIMESTAMPTZ
            )
            """).run()
        try await sql.raw("""
            CREATE INDEX auth_challenges_expiry ON auth_challenges (expires_at)
            """).run()
        try await sql.raw("""
            CREATE TABLE apple_grants (
                id UUID PRIMARY KEY,
                user_id UUID NOT NULL REFERENCES users(id),
                encrypted_refresh_token BYTEA NOT NULL,
                key_version TEXT NOT NULL,
                last_validated_at TIMESTAMPTZ NOT NULL,
                revoked_at TIMESTAMPTZ
            )
            """).run()
        try await sql.raw("CREATE INDEX apple_grants_user ON apple_grants (user_id)").run()
        try await sql.raw("""
            CREATE TABLE app_sessions (
                id UUID PRIMARY KEY,
                user_id UUID NOT NULL REFERENCES users(id),
                apple_grant_id UUID NOT NULL REFERENCES apple_grants(id),
                token_hash TEXT NOT NULL UNIQUE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
                expires_at TIMESTAMPTZ NOT NULL,
                revoked_at TIMESTAMPTZ
            )
            """).run()
        try await sql.raw("CREATE INDEX app_sessions_grant ON app_sessions (apple_grant_id)").run()
        try await sql.raw("CREATE INDEX app_sessions_user ON app_sessions (user_id)").run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else { throw AppleGatewayError.invalidConfiguration }
        try await sql.raw("DROP TABLE app_sessions").run()
        try await sql.raw("DROP TABLE apple_grants").run()
        try await sql.raw("DROP TABLE auth_challenges").run()
    }
}
