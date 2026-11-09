import Foundation
import FluentKit
import FluentSQL
import Vapor
import Logging

/// PostgreSQL is the queue and the checkpoint. A lease can expire after a process crash without losing the work.
actor AccountDeletionWorker {
    let service: AccountDeletionService
    private var task: Task<Void, Never>?
    private let logger: Logger

    init(service: AccountDeletionService, logger: Logger = Logger(label: "account-deletion")) {
        self.service = service
        self.logger = logger
    }

    func start() {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                do {
                    _ = try await runNext()
                } catch is CancellationError {
                    break
                } catch {
                    logger.error("Account deletion worker failed; durable work will retry. Check queue health.")
                }
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
            }
        }
    }

    func stop() async {
        task?.cancel()
        await task?.value
        task = nil
    }

    @discardableResult
    func runNext() async throws -> Bool {
        let lease = UUID()
        let work: Work? = try await service.databases.database().accountTransaction(exclusive: true) { database in
            let sql = try shoppingSQL(database)
            try await sql.raw("""
                UPDATE account_deletion_jobs SET state = 'cancelled',completed_at = clock_timestamp(),user_id = NULL,
                    expires_at = LEAST(expires_at,clock_timestamp() + INTERVAL '7 days')
                WHERE state = 'prepared' AND created_at <= clock_timestamp() - INTERVAL '30 minutes'
                """).run()
            try await sql.raw("DELETE FROM account_deletion_challenges WHERE expires_at <= clock_timestamp()").run()
            try await sql.raw("""
                UPDATE account_deletion_jobs SET subject = NULL WHERE state = 'completed'
                    AND completed_at <= clock_timestamp() - INTERVAL '5 minutes'
                """).run()
            try await sql.raw("DELETE FROM deleted_session_receipts WHERE expires_at <= clock_timestamp()").run()
            try await sql.raw("""
                DELETE FROM account_deletion_jobs WHERE expires_at <= clock_timestamp()
                    AND (state = 'cancelled' OR (state = 'completed'
                        AND completed_at <= clock_timestamp() - INTERVAL '5 minutes'))
                """).run()
            guard let row = try await sql.raw("""
                SELECT * FROM account_deletion_jobs
                WHERE state IN ('accepted','purging','data_deleted') AND next_attempt_at <= clock_timestamp()
                    AND (lease_until IS NULL OR lease_until <= clock_timestamp())
                ORDER BY accepted_at,id LIMIT 1 FOR UPDATE SKIP LOCKED
                """).first() else { return nil }
            let id = try row.decode(column: "id", as: UUID.self)
            try await sql.raw("""
                UPDATE account_deletion_jobs SET lease_id = \(bind: lease),lease_until = clock_timestamp() + INTERVAL '2 minutes'
                WHERE id = \(bind: id)
                """).run()
            return Work(
                id: id,
                user: try row.decode(column: "user_id", as: UUID?.self),
                acceptedAt: try row.decode(column: "accepted_at", as: Date.self)
            )
        }
        guard let work else { return false }
        let service = service
        // Copy revocation material and purge data in a single recoverable commit, before retrying external Apple work.
        let dataDeleted = try await service.databases.database().accountTransaction(exclusive: true) { database in
            let sql = try shoppingSQL(database)
            guard try await owns(work.id, lease: lease, on: sql) else { return false }
            if let user = work.user {
                // A response that can rotate an Apple token must settle before copying its revocation material.
                if try await sql.raw("""
                    SELECT 1 FROM apple_grants WHERE user_id = \(bind: user)
                        AND validation_id IS NOT NULL AND validation_deadline > clock_timestamp()
                    UNION ALL SELECT 1 FROM auth_challenges WHERE login_deletion_job_id = \(bind: work.id)
                        AND login_exchange_pending AND login_exchange_deadline > clock_timestamp() LIMIT 1
                    """).first() != nil {
                    try await sql.raw("""
                        UPDATE account_deletion_jobs SET next_attempt_at = clock_timestamp() + INTERVAL '5 seconds',
                            lease_id = NULL,lease_until = NULL WHERE id = \(bind: work.id)
                        """).run()
                    return false
                }
                // A crash or lost response may hide a rotated token; later 200s cannot erase that uncertainty.
                try await sql.raw("""
                    UPDATE account_deletion_jobs SET apple_requires_manual = TRUE WHERE id = \(bind: work.id)
                        AND (EXISTS(SELECT 1 FROM apple_grants WHERE user_id = \(bind: user)
                            AND (validation_uncertain OR validation_id IS NOT NULL))
                            OR EXISTS(SELECT 1 FROM auth_challenges WHERE login_deletion_job_id = \(bind: work.id)
                                AND login_exchange_pending))
                    """).run()
                try await sql.raw("DELETE FROM auth_challenges WHERE login_deletion_job_id = \(bind: work.id)").run()
                try await sql.raw("""
                    INSERT INTO account_deletion_tokens(job_id,grant_id,ciphertext,key_version)
                    SELECT \(bind: work.id),id,encrypted_refresh_token,key_version FROM apple_grants WHERE user_id = \(bind: user)
                    ON CONFLICT DO NOTHING
                    """).run()
                try await sql.raw("""
                    INSERT INTO deleted_session_receipts(token_hash,expires_at)
                    SELECT token_hash,clock_timestamp() + INTERVAL '30 days' FROM app_sessions WHERE user_id = \(bind: user)
                    ON CONFLICT(token_hash) DO UPDATE SET expires_at = EXCLUDED.expires_at
                    """).run()
                try await AccountDataPurger.purge(user: user, on: sql)
            }
            try await sql.raw("""
                UPDATE account_deletion_jobs SET state = 'data_deleted',user_id = NULL,
                    data_deleted_at = COALESCE(data_deleted_at,clock_timestamp()) WHERE id = \(bind: work.id)
                """).run()
            return true
        }
        guard dataDeleted else { return true }
        let sql = try shoppingSQL(service.databases.database())
        let rows = try await sql.raw("SELECT * FROM account_deletion_tokens WHERE job_id = \(bind: work.id)").all()
        let checkpoint = try await sql.raw("SELECT apple_outcome,apple_requires_manual FROM account_deletion_jobs WHERE id = \(bind: work.id)").first()
        let previousOutcome = try checkpoint?.decode(column: "apple_outcome", as: String?.self)
        let requiresManual = try checkpoint?.decode(column: "apple_requires_manual", as: Bool.self) ?? true
        let retryWindowOpen = try await databaseClock(sql).timeIntervalSince(work.acceptedAt) < 7 * 86_400
        var allConfirmed = !requiresManual && (rows.isEmpty ? previousOutcome == "confirmed" : retryWindowOpen)
        let missingMaterial = rows.isEmpty && previousOutcome != "confirmed"
        for row in rows where retryWindowOpen {
            try Task.checkCancellation()
            let stillOwned = try await service.databases.database().accountTransaction { database in
                let sql = try shoppingSQL(database)
                guard try await owns(work.id, lease: lease, on: sql) else { return false }
                try await sql.raw("UPDATE account_deletion_jobs SET lease_until = clock_timestamp() + INTERVAL '2 minutes' WHERE id = \(bind: work.id)").run()
                return true
            }
            guard stillOwned else { return true }
            let grant = try row.decode(column: "grant_id", as: UUID.self)
            do {
                guard let vault = service.vault else { throw AppleGatewayError.unavailable }
                let token = try vault.open(
                    row.decode(column: "ciphertext", as: Data.self),
                    keyVersion: row.decode(column: "key_version", as: String.self),
                    grantID: grant
                )
                try await service.gateway.revoke(refreshToken: token)
                try await service.databases.database().accountTransaction { database in
                    let sql = try shoppingSQL(database)
                    guard try await owns(work.id, lease: lease, on: sql) else { return }
                    try await sql.raw("DELETE FROM account_deletion_tokens WHERE job_id = \(bind: work.id) AND grant_id = \(bind: grant)").run()
                    try await sql.raw("""
                        UPDATE account_deletion_jobs SET apple_outcome = 'confirmed'
                        WHERE id = \(bind: work.id) AND NOT apple_requires_manual AND NOT EXISTS (
                            SELECT 1 FROM account_deletion_tokens WHERE job_id = \(bind: work.id))
                        """).run()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                allConfirmed = false
            }
        }
        let confirmed = allConfirmed
        try await service.databases.database().accountTransaction(exclusive: true) { database in
            let sql = try shoppingSQL(database)
            guard try await owns(work.id, lease: lease, on: sql) else { return }
            let now = try await databaseClock(sql)
            if confirmed || requiresManual || missingMaterial || now.timeIntervalSince(work.acceptedAt) >= 7 * 86_400 {
                try await sql.raw("DELETE FROM account_deletion_tokens WHERE job_id = \(bind: work.id)").run()
                try await sql.raw("DELETE FROM account_deletion_challenges WHERE job_id = \(bind: work.id)").run()
                let outcome = confirmed ? "confirmed" : "manual_action_required"
                try await sql.raw("""
                    UPDATE account_deletion_jobs SET state = 'completed',apple_outcome = \(bind: outcome),
                        completed_at = clock_timestamp(),lease_id = NULL,lease_until = NULL,
                        expires_at = clock_timestamp() + INTERVAL '7 days' WHERE id = \(bind: work.id)
                    """).run()
            } else {
                try await sql.raw("""
                    UPDATE account_deletion_jobs SET next_attempt_at = clock_timestamp() + INTERVAL '5 minutes',
                        lease_id = NULL,lease_until = NULL WHERE id = \(bind: work.id)
                    """).run()
            }
        }
        return true
    }

    private struct Work: Sendable {
        let id: UUID
        let user: UUID?
        let acceptedAt: Date
    }
}

private func owns(_ job: UUID, lease: UUID, on sql: any SQLDatabase) async throws -> Bool {
    try await sql.raw("SELECT id FROM account_deletion_jobs WHERE id = \(bind: job) AND lease_id = \(bind: lease) FOR UPDATE").first() != nil
}

struct AccountDeletionLifecycle: LifecycleHandler {
    let worker: AccountDeletionWorker

    func didBootAsync(_ application: Application) async throws {
        await worker.start()
    }

    func shutdownAsync(_ application: Application) async {
        await worker.stop()
    }
}
