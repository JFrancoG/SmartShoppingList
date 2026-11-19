import Foundation
import FluentSQL

/// Login and deletion reauthentication share the same durable record for an Apple exchange in flight.
enum IdentityExchangeLedger {
    enum Retention: Sendable {
        case stored
        case queued
        case late
    }

    static func beginReauthentication(user: UUID, subject: String, on sql: any SQLDatabase) async throws -> UUID {
        try await requireActiveAccount(user, on: sql)
        let id = UUID()
        // claimed_at and a missing nonce make this technical ledger row unusable as a login challenge.
        try await sql.raw("""
            INSERT INTO auth_challenges(id,nonce,expires_at,claimed_at,login_subject,
                login_exchange_pending,login_exchange_deadline)
            VALUES(\(bind: id),NULL,clock_timestamp() + INTERVAL '5 minutes',clock_timestamp(),\(bind: subject),
                TRUE,clock_timestamp() + INTERVAL '1 minute')
            """).run()
        return id
    }

    static func retainReauthentication(
        exchange: UUID,
        user: UUID,
        refreshToken: String?,
        vault: RefreshTokenVault?,
        on sql: any SQLDatabase
    ) async throws -> Retention {
        guard let row = try await sql.raw("SELECT * FROM auth_challenges WHERE id = \(bind: exchange) FOR UPDATE").first() else {
            return .late
        }
        let deadline = try row.decode(column: "login_exchange_deadline", as: Date?.self)
        let now = try await databaseClock(sql)
        let timely = try row.decode(column: "login_exchange_pending", as: Bool.self) && deadline.map { $0 > now } == true
        let grant = UUID()
        let encrypted: RefreshTokenVault.SealedToken?
        if let refreshToken, !refreshToken.isEmpty, let vault {
            encrypted = try vault.seal(refreshToken, grantID: grant)
        } else {
            encrypted = nil
        }
        if let job = try row.decode(column: "login_deletion_job_id", as: UUID?.self),
           try await sql.raw("""
            SELECT 1 FROM account_deletion_jobs WHERE id = \(bind: job)
                AND state IN ('accepted','purging','data_deleted') FOR UPDATE
            """).first() != nil {
            if let encrypted {
                try await sql.raw("""
                    INSERT INTO account_deletion_tokens(job_id,grant_id,ciphertext,key_version)
                    VALUES(\(bind: job),\(bind: grant),\(bind: encrypted.ciphertext),\(bind: encrypted.keyVersion))
                    """).run()
            }
            try await sql.raw("""
                UPDATE account_deletion_jobs SET apple_requires_manual = apple_requires_manual OR \(bind: !timely || encrypted == nil),
                    next_attempt_at = clock_timestamp() WHERE id = \(bind: job)
                """).run()
            try await end(exchange, on: sql)
            return .queued
        }
        guard timely, try await sql.raw("""
            SELECT 1 FROM users WHERE id = \(bind: user) AND deleting_at IS NULL
            """).first() != nil else {
            try await fail(exchange, on: sql)
            return .late
        }
        if let encrypted {
            // A cancelled preparation does not discard a verified refresh token. It remains revocable with this account.
            try await sql.raw("""
                INSERT INTO apple_grants(id,user_id,encrypted_refresh_token,key_version,last_validated_at)
                VALUES(\(bind: grant),\(bind: user),\(bind: encrypted.ciphertext),\(bind: encrypted.keyVersion),clock_timestamp())
                """).run()
        } else {
            try await sql.raw("UPDATE apple_grants SET validation_uncertain = TRUE WHERE user_id = \(bind: user)").run()
        }
        try await end(exchange, on: sql)
        return .stored
    }

    static func end(_ exchange: UUID, on sql: any SQLDatabase) async throws {
        try await sql.raw("""
            UPDATE auth_challenges SET login_subject = NULL,login_exchange_pending = FALSE,
                login_exchange_deadline = NULL,consumed_at = clock_timestamp() WHERE id = \(bind: exchange)
            """).run()
    }

    static func fail(_ exchange: UUID, on sql: any SQLDatabase) async throws {
        guard let row = try await sql.raw("""
            SELECT * FROM auth_challenges WHERE id = \(bind: exchange) AND login_exchange_pending FOR UPDATE
            """).first() else { return }
        if let job = try row.decode(column: "login_deletion_job_id", as: UUID?.self) {
            try await sql.raw("""
                UPDATE account_deletion_jobs SET apple_requires_manual = TRUE,next_attempt_at = clock_timestamp()
                WHERE id = \(bind: job) AND state IN ('accepted','purging','data_deleted')
                """).run()
        } else if let subject = try row.decode(column: "login_subject", as: String?.self) {
            try await sql.raw("""
                UPDATE apple_grants SET validation_uncertain = TRUE WHERE user_id IN (
                    SELECT id FROM users WHERE apple_subject = \(bind: subject))
                """).run()
        }
        try await end(exchange, on: sql)
    }
}
