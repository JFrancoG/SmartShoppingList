import Foundation
import FluentKit
import FluentSQL
import Vapor

struct AccountDeletionService: Sendable {
    let databases: Databases
    let gateway: any AppleGateway
    let vault: RefreshTokenVault?

    func preview(user: UUID) async throws -> AccountDeletionImpact {
        try await databases.database().accountTransaction(exclusive: true) { database in
            let sql = try shoppingSQL(database)
            try await requireActiveAccount(user, on: sql)
            return try await AccountDataPurger.preview(user: user, on: sql)
        }
    }

    func prepare(user: UUID, operation: UUID, secret: String, revision: String) async throws -> APIJSON {
        try validateSecret(secret)
        return try await databases.database().accountTransaction(exclusive: true) { database in
            let sql = try shoppingSQL(database)
            try await requireActiveAccount(user, on: sql)
            let impact = try await AccountDataPurger.preview(user: user, on: sql)
            guard impact.revision == revision else { throw Self.impactChanged }
            // Cancelling an older preparation is safe: acceptance rechecks its state after Apple returns.
            try await sql.raw("""
                UPDATE account_deletion_jobs SET state = 'cancelled',completed_at = clock_timestamp(),user_id = NULL,
                    expires_at = LEAST(expires_at,clock_timestamp() + INTERVAL '7 days')
                WHERE user_id = \(bind: user) AND id <> \(bind: operation) AND state = 'prepared'
                """).run()
            // A new preview can replace a cancelled operation, never an uncertain accepted one.
            try await sql.raw("""
                INSERT INTO account_deletion_jobs(id,user_id,secret_hash,revision,state)
                VALUES(\(bind: operation),\(bind: user),\(bind: IdentitySecrets.hash(secret)),\(bind: revision),'prepared')
                ON CONFLICT(id) DO NOTHING
                """).run()
            let row = try await job(operation, secret: secret, on: sql)
            guard try row.decode(column: "user_id", as: UUID?.self) == user,
                  try row.decode(column: "state", as: String.self) == "prepared" else { throw Self.inProgress }
            try await sql.raw("UPDATE account_deletion_jobs SET revision = \(bind: revision) WHERE id = \(bind: operation)").run()
            try await sql.raw("DELETE FROM account_deletion_challenges WHERE job_id = \(bind: operation)").run()
            let challenge = UUID()
            let nonce = IdentitySecrets.generate()
            let expires = try await databaseClock(sql).addingTimeInterval(300)
            try await sql.raw("""
                INSERT INTO account_deletion_challenges(id,job_id,nonce,expires_at)
                VALUES(\(bind: challenge),\(bind: operation),\(bind: nonce),\(bind: expires))
                """).run()
            return .object([
                "id": .string(challenge.uuidString.lowercased()), "nonce": .string(nonce),
                "expiresAt": .string(APIEncoding.timestamp(expires))
            ])
        }
    }

    func accept(user: UUID, body: APIObject) async throws -> APIJSON {
        let operation = try body.uuid("operationId")
        let secret = try body.string("statusSecret")
        let revision = try body.string("revision")
        let challenge = try body.uuid("challengeId")
        let token = try body.string("identityToken")
        let code = try body.string("authorizationCode")
        try validateSecret(secret)
        guard (1...16_384).contains(token.utf8.count), (1...4_096).contains(code.utf8.count) else {
            throw APIProblem.invalidRequest
        }
        let evidence: (String, String) = try await databases.database().accountTransaction { database in
            let sql = try shoppingSQL(database)
            try await requireActiveAccount(user, on: sql)
            let row = try await job(operation, secret: secret, on: sql)
            guard try row.decode(column: "state", as: String.self) == "prepared",
                  try row.decode(column: "user_id", as: UUID?.self) == user else { throw Self.inProgress }
            guard let proof = try await sql.raw("""
                WITH candidate AS (
                    SELECT id,nonce FROM account_deletion_challenges
                    WHERE id = \(bind: challenge) AND job_id = \(bind: operation)
                        AND claimed_at IS NULL AND expires_at > clock_timestamp() FOR UPDATE
                )
                UPDATE account_deletion_challenges AS challenge SET claimed_at = clock_timestamp(),nonce = NULL
                FROM candidate WHERE challenge.id = candidate.id RETURNING candidate.nonce
                """).first(),
                let nonce = try proof.decode(column: "nonce", as: String?.self),
                let owner = try await sql.raw("SELECT apple_subject FROM users WHERE id = \(bind: user)").first()
            else { throw Self.invalidProof }
            return (nonce, try owner.decode(column: "apple_subject", as: String.self))
        }
        // No SQL locks are held across an Apple request. An in-flight cancellation wins at the commit below.
        do {
            guard try await gateway.verifyIdentityToken(token, nonce: evidence.0) == evidence.1 else {
                throw Self.invalidProof
            }
        } catch let error as AppleGatewayError where error == .rejected || error == .invalidGrant {
            throw Self.invalidProof
        }
        let exchange = try await databases.database().accountTransaction { database in
            try await IdentityExchangeLedger.beginReauthentication(user: user, subject: evidence.1, on: shoppingSQL(database))
        }
        let response: AppleTokenResponse
        do {
            response = try await gateway.exchange(code: code)
            guard let identity = response.identityToken,
                  try await gateway.verifyIdentityToken(identity, nonce: evidence.0) == evidence.1 else {
                throw Self.invalidProof
            }
        } catch {
            try? await databases.database().accountTransaction { database in
                try await IdentityExchangeLedger.fail(exchange, on: shoppingSQL(database))
            }
            if let error = error as? AppleGatewayError, error == .rejected || error == .invalidGrant {
                throw Self.invalidProof
            }
            throw error
        }
        let retained = try await databases.database().accountTransaction { database in
            try await IdentityExchangeLedger.retainReauthentication(
                exchange: exchange,
                user: user,
                refreshToken: response.refreshToken,
                vault: vault,
                on: shoppingSQL(database)
            )
        }
        if case .late = retained {
            if let refresh = response.refreshToken {
                try? await gateway.revoke(refreshToken: refresh)
            }
            throw Self.inProgress
        }
        return try await databases.database().accountTransaction(exclusive: true) { database in
            let sql = try shoppingSQL(database)
            try await requireActiveAccount(user, on: sql)
            let row = try await job(operation, secret: secret, on: sql)
            guard try row.decode(column: "state", as: String.self) == "prepared",
                  try row.decode(column: "user_id", as: UUID?.self) == user else { throw Self.inProgress }
            let impact = try await AccountDataPurger.preview(user: user, on: sql)
            guard impact.revision == revision, try row.decode(column: "revision", as: String.self) == revision else {
                throw Self.impactChanged
            }
            try await sql.raw("UPDATE users SET deleting_at = clock_timestamp() WHERE id = \(bind: user)").run()
            try await sql.raw("""
                UPDATE account_deletion_jobs SET state = 'accepted',subject = \(bind: evidence.1),
                    accepted_at = clock_timestamp(),next_attempt_at = clock_timestamp() WHERE id = \(bind: operation)
                """).run()
            // Cancel exchanges already bound to this identity, retaining only their temporary link to this job.
            try await sql.raw("""
                UPDATE auth_challenges SET login_deletion_job_id = \(bind: operation),login_subject = NULL,
                    consumed_at = clock_timestamp()
                WHERE login_subject = \(bind: evidence.1) AND login_exchange_pending
                """).run()
            // Acceptance is irreversible: another device can now clear this account without mistaking a generic 401 for deletion.
            try await sql.raw("""
                INSERT INTO deleted_session_receipts(token_hash,expires_at)
                SELECT token_hash,clock_timestamp() + INTERVAL '30 days' FROM app_sessions WHERE user_id = \(bind: user)
                ON CONFLICT DO NOTHING
                """).run()
            try await sql.raw("UPDATE app_sessions SET revoked_at = COALESCE(revoked_at,clock_timestamp()) WHERE user_id = \(bind: user)").run()
            return try await status(operation: operation, secret: secret, cancelPrepared: false, on: sql)
        }
    }

    func status(operation: UUID, secret: String, cancelPrepared: Bool = false) async throws -> APIJSON {
        try validateSecret(secret)
        return try await databases.database().accountTransaction(exclusive: cancelPrepared) { database in
            try await status(operation: operation, secret: secret, cancelPrepared: cancelPrepared, on: shoppingSQL(database))
        }
    }

    func deletionAcceptedForSession(_ bearer: String) async throws -> Bool {
        guard IdentitySecrets.isValid(bearer) else { throw APIProblem.invalidRequest }
        let sql = try shoppingSQL(databases.database())
        return try await sql.raw("""
            SELECT 1 FROM deleted_session_receipts WHERE token_hash = \(bind: IdentitySecrets.hash(bearer))
                AND expires_at > clock_timestamp()
            """).first() != nil
    }

    private func status(operation: UUID, secret: String, cancelPrepared: Bool, on sql: any SQLDatabase) async throws -> APIJSON {
        if cancelPrepared {
            // The prepare request may never have arrived. Its private cancellation marker fences a delayed retry.
            try await sql.raw("""
                INSERT INTO account_deletion_jobs(id,secret_hash,revision,state,completed_at,expires_at)
                VALUES(\(bind: operation),\(bind: IdentitySecrets.hash(secret)),'','cancelled',
                    clock_timestamp(),clock_timestamp() + INTERVAL '7 days')
                ON CONFLICT(id) DO NOTHING
                """).run()
        }
        var row = try await job(operation, secret: secret, on: sql)
        if cancelPrepared, try row.decode(column: "state", as: String.self) == "prepared" {
            try await sql.raw("""
                UPDATE account_deletion_jobs SET state = 'cancelled',completed_at = clock_timestamp(),user_id = NULL,
                    expires_at = LEAST(expires_at,clock_timestamp() + INTERVAL '7 days') WHERE id = \(bind: operation)
                """).run()
            try await sql.raw("DELETE FROM account_deletion_challenges WHERE job_id = \(bind: operation)").run()
            row = try await job(operation, secret: secret, on: sql)
        }
        return .object([
            "operationId": .string(operation.uuidString.lowercased()),
            "status": .string(try row.decode(column: "state", as: String.self)),
            "appleRevocationOutcome": .optional(try row.decode(column: "apple_outcome", as: String?.self))
        ])
    }

    private func job(_ id: UUID, secret: String, on sql: any SQLDatabase) async throws -> any SQLRow {
        guard let row = try await sql.raw("""
            SELECT * FROM account_deletion_jobs WHERE id = \(bind: id) AND secret_hash = \(bind: IdentitySecrets.hash(secret))
                AND (expires_at > clock_timestamp() OR state IN ('accepted','purging','data_deleted')) FOR UPDATE
            """).first() else { throw APIProblem.notFound }
        return row
    }

    private func validateSecret(_ secret: String) throws {
        guard IdentitySecrets.isValid(secret) else { throw APIProblem.invalidRequest }
    }

    static let impactChanged = APIProblem(status: .conflict, code: "deletion_impact_changed", message: "Los datos han cambiado. Revisa de nuevo la eliminación.")
    static let inProgress = APIProblem(status: .conflict, code: "deletion_in_progress", message: "Consulta la solicitud de eliminación existente.")
    static let invalidProof = APIProblem(status: .unauthorized, code: "invalid_deletion_proof", message: "Confirma de nuevo tu identidad con Apple.")
}
