import Foundation
import FluentKit
import FluentSQL
import Vapor

/// Apple verification and network calls finish before acquiring any shopping or account locks.
struct SubscriptionService: Sendable {
    let databases: Databases
    let gateway: any AppStoreGateway
    var accountCapacity = AccountCapacityPolicy()

    func submit(user: UUID, signed: String) async throws -> APIJSON {
        let claim = try await verifiedTransaction(signed)
        guard claim.appAccountToken == user else { throw Self.problem("transaction_account_mismatch") }
        let snapshots = try await currentSnapshots(original: claim.originalTransactionId, user: user)
        try await ingest(user: user, snapshots: snapshots, claim: claim, notification: nil)
        let current = try await storedStatus(user: user)
        return .object([
            "subscription": current.json,
            "acknowledgedTransactionId": .string(claim.transactionId)
        ])
    }

    /// Unavailability retains the last verified entitlement only until its already verified deadline.
    func status(user: UUID) async throws -> SubscriptionStatus {
        if let configuration = gateway.configuration {
            let sql = try shoppingSQL(databases.database())
            let rows = try await sql.raw("""
                SELECT original_transaction_id FROM app_store_subscriptions
                WHERE user_id = \(bind: user) AND environment = \(bind: configuration.environment.rawValue)
                ORDER BY original_transaction_id LIMIT 64
                """).all()
            for row in rows {
                let original = try row.decode(column: "original_transaction_id", as: String.self)
                do {
                    let snapshots = try await currentSnapshots(original: original, user: user)
                    try await ingest(user: user, snapshots: snapshots, claim: nil, notification: nil)
                } catch let problem as APIProblem where problem.code == "subscription_unavailable" {
                    // Do not invent a new deadline or change the already verified access on an outage.
                    break
                }
            }
        }
        return try await storedStatus(user: user)
    }

    func notification(signed: String) async throws {
        let event: AppStoreNotification
        do {
            event = try await gateway.verifyNotification(signed)
        } catch {
            throw Self.gatewayProblem(error, invalid: "invalid_app_store_notification")
        }
        guard let configuration = gateway.configuration, let data = event.data,
            data.environment == configuration.environment
        else {
            throw Self.problem("invalid_app_store_notification")
        }
        let receipt = NotificationReceipt(
            id: event.notificationUUID,
            environment: data.environment,
            hash: SHA256.hash(data: Data(signed.utf8)).map { String(format: "%02x", $0) }.joined()
        )
        let sql = try shoppingSQL(databases.database())
        if try await existingNotification(receipt, on: sql) {
            return
        }
        guard event.notificationType != "TEST", let transaction = data.signedTransactionInfo else {
            try await recordNotification(receipt)
            return
        }
        let claim: AppStoreTransaction
        do {
            claim = try await verifiedTransaction(transaction)
        } catch let problem as APIProblem where problem.code == "invalid_app_store_transaction" {
            throw Self.problem("invalid_app_store_notification")
        }
        guard let user = claim.appAccountToken else { throw Self.problem("invalid_app_store_notification") }
        // A valid event for an account this service has never created is acknowledged without granting access.
        guard try await sql.raw("SELECT id FROM users WHERE id = \(bind: user)").first() != nil else {
            try await recordNotification(receipt)
            return
        }
        do {
            let snapshots = try await currentSnapshots(original: claim.originalTransactionId, user: user)
            try await ingest(user: user, snapshots: snapshots, claim: claim, notification: receipt)
        } catch let problem as APIProblem where problem.code == "invalid_app_store_transaction"
            || problem.code == "transaction_already_bound" {
            throw Self.problem("invalid_app_store_notification")
        }
    }

    private func verifiedTransaction(_ signed: String) async throws -> AppStoreTransaction {
        guard !signed.isEmpty, signed.utf8.count <= 65_536 else {
            throw Self.problem("invalid_app_store_transaction")
        }
        do {
            let transaction = try await gateway.verifyTransaction(signed)
            guard let configuration = gateway.configuration,
                transaction.environment == configuration.environment,
                configuration.productIDs.contains(transaction.productId), transaction.appAccountToken != nil
            else {
                throw AppStoreGatewayError.rejected
            }
            return transaction
        } catch {
            throw Self.gatewayProblem(error, invalid: "invalid_app_store_transaction")
        }
    }

    private func currentSnapshots(original: String, user: UUID) async throws -> [VerifiedAppStoreSubscription] {
        do {
            guard let configuration = gateway.configuration else { throw AppStoreGatewayError.unavailable }
            let values = try await gateway.subscriptionStates(originalTransactionID: original)
            let matching = values.filter {
                $0.transaction.appAccountToken == user && $0.transaction.environment == configuration.environment
                    && configuration.productIDs.contains($0.transaction.productId)
            }
            guard !matching.isEmpty, matching.count <= 64,
                matching.contains(where: { $0.transaction.originalTransactionId == original })
            else {
                throw AppStoreGatewayError.unavailable
            }
            return matching.sorted { $0.transaction.originalTransactionId < $1.transaction.originalTransactionId }
        } catch {
            throw Self.gatewayProblem(error, invalid: "invalid_app_store_transaction")
        }
    }
}

extension SubscriptionService {
    private struct NotificationReceipt: Sendable {
        let id: UUID
        let environment: AppStoreEnvironment
        let hash: String
    }

    private enum LockRetry: Error {
        case administratorSetChanged
    }

    /// The stable group set protects shared quotas while the account lock protects admissions and selection.
    private func ingest(
        user: UUID,
        snapshots: [VerifiedAppStoreSubscription],
        claim: AppStoreTransaction?,
        notification: NotificationReceipt?
    ) async throws {
        guard let environment = gateway.configuration?.environment else {
            throw Self.problem("subscription_unavailable")
        }
        let database = try databases.database()
        for _ in 0..<8 {
            do {
                try await database.transaction { transaction in
                    let sql = try shoppingSQL(transaction)
                    let groups = try await administeredGroups(user: user, on: sql)
                    for group in groups {
                        // The administrator may change while this transaction waits for a group lock.
                        _ = try await sql.raw("SELECT id FROM groups WHERE id = \(bind: group) FOR UPDATE").first()
                    }
                    let shopping = ShoppingService(
                        database: transaction,
                        invitationOrigin: nil,
                        cursorKey: SymmetricKey(size: .bits256),
                        accountCapacity: accountCapacity
                    )
                    try await shopping.lockUser(user, on: sql)
                    guard try await administeredGroups(user: user, on: sql) == groups else {
                        throw LockRetry.administratorSetChanged
                    }
                    if let notification, try await existingNotification(notification, on: sql) {
                        return
                    }
                    let now = try await databaseClock(sql)
                    for snapshot in snapshots {
                        try await persist(snapshot, user: user, now: now, on: sql)
                    }
                    if let claim {
                        try await bindTransaction(claim, user: user, now: now, on: sql)
                    }
                    let stored = try await storedSubscriptions(user: user, environment: environment, on: sql)
                    let effective = effectiveSubscription(stored, now: now)
                    let deadline: Date?
                    let courtesy: Bool
                    if let effective, effective.state != .revoked {
                        if (effective.state == .subscribed || effective.state == .inGracePeriod),
                            effective.accessDeadline > now {
                            deadline = effective.accessDeadline
                            courtesy = true
                        } else if effective.courtesyDeadline <= now {
                            deadline = effective.courtesyDeadline
                            courtesy = true
                        } else {
                            deadline = nil
                            courtesy = false
                        }
                    } else {
                        deadline = nil
                        courtesy = false
                    }
                    try await persistTrustedPremiumAccess(
                        user: user,
                        premiumUntil: deadline,
                        transitionStartedAt: deadline,
                        transitionAllowed: courtesy,
                        verificationEnvironment: environment,
                        on: sql
                    )
                    if let notification {
                        try await insertNotification(notification, now: now, on: sql)
                    }
                }
                return
            } catch LockRetry.administratorSetChanged {
                // Release every old lock and start again; never lock another group after the account.
                continue
            }
        }
        throw Self.problem("subscription_unavailable")
    }

    private func administeredGroups(user: UUID, on sql: any SQLDatabase) async throws -> [UUID] {
        let rows = try await sql.raw("""
            SELECT id FROM groups WHERE administrator_user_id = \(bind: user) AND closed_at IS NULL ORDER BY id
            """).all()
        return try rows.map { try $0.decode(column: "id", as: UUID.self) }
    }

    private func persist(
        _ snapshot: VerifiedAppStoreSubscription,
        user: UUID,
        now: Date,
        on sql: any SQLDatabase
    ) async throws {
        let value = snapshot.transaction
        let environment = value.environment.rawValue
        if let owner = try await sql.raw("""
            SELECT user_id FROM app_store_subscriptions
            WHERE environment = \(bind: environment) AND original_transaction_id = \(bind: value.originalTransactionId)
            """).first(), try owner.decode(column: "user_id", as: UUID.self) != user {
            throw Self.problem("transaction_already_bound")
        }
        guard let expiry = value.expiresDate else { throw Self.problem("invalid_app_store_transaction") }
        // An equal revision may strengthen a revocation; it may never undo one.
        let bound = try await sql.raw("""
            INSERT INTO app_store_subscriptions
                (environment,original_transaction_id,user_id,transaction_id,product_id,state,purchase_date,
                    expires_at,grace_expires_at,auto_renew_enabled,revision,verified_at)
            VALUES (\(bind: environment),\(bind: value.originalTransactionId),\(bind: user),\(bind: value.transactionId),
                \(bind: value.productId),\(bind: snapshot.state.rawValue),\(bind: value.purchaseDate),\(bind: expiry),
                \(bind: snapshot.renewal.gracePeriodExpiresDate),\(bind: snapshot.renewal.autoRenewStatus == 1),
                \(bind: snapshot.revision),\(bind: now))
            ON CONFLICT(environment,original_transaction_id) DO UPDATE SET
                transaction_id = EXCLUDED.transaction_id, product_id = EXCLUDED.product_id,
                state = EXCLUDED.state, purchase_date = EXCLUDED.purchase_date, expires_at = EXCLUDED.expires_at,
                grace_expires_at = CASE
                    WHEN EXCLUDED.grace_expires_at IS NOT NULL THEN EXCLUDED.grace_expires_at
                    WHEN app_store_subscriptions.transaction_id = EXCLUDED.transaction_id
                        THEN app_store_subscriptions.grace_expires_at
                    ELSE NULL END,
                auto_renew_enabled = EXCLUDED.auto_renew_enabled,
                revision = EXCLUDED.revision, verified_at = EXCLUDED.verified_at
            WHERE app_store_subscriptions.user_id = EXCLUDED.user_id
                AND (EXCLUDED.revision > app_store_subscriptions.revision
                    OR (EXCLUDED.revision = app_store_subscriptions.revision
                        AND (app_store_subscriptions.state <> 'revoked' OR EXCLUDED.state = 'revoked')))
            RETURNING user_id
            """).first()
        if bound == nil {
            guard let existing = try await sql.raw("""
                SELECT user_id FROM app_store_subscriptions
                WHERE environment = \(bind: environment) AND original_transaction_id = \(bind: value.originalTransactionId)
                """).first(), try existing.decode(column: "user_id", as: UUID.self) == user
            else {
                throw Self.problem("transaction_already_bound")
            }
        }
        try await bindTransaction(value, user: user, now: now, on: sql)
    }

    private func bindTransaction(
        _ value: AppStoreTransaction,
        user: UUID,
        now: Date,
        on sql: any SQLDatabase
    ) async throws {
        let row = try await sql.raw("""
            INSERT INTO app_store_transactions(environment,transaction_id,user_id,original_transaction_id,verified_at)
            VALUES (\(bind: value.environment.rawValue),\(bind: value.transactionId),\(bind: user),
                \(bind: value.originalTransactionId),\(bind: now))
            ON CONFLICT(environment,transaction_id) DO NOTHING RETURNING user_id
            """).first()
        guard row == nil else { return }
        guard let existing = try await sql.raw("""
            SELECT user_id,original_transaction_id FROM app_store_transactions
            WHERE environment = \(bind: value.environment.rawValue) AND transaction_id = \(bind: value.transactionId)
            """).first(), try existing.decode(column: "user_id", as: UUID.self) == user,
            try existing.decode(column: "original_transaction_id", as: String.self) == value.originalTransactionId
        else {
            throw Self.problem("transaction_already_bound")
        }
    }
}

extension SubscriptionService {
    private struct StoredSubscription: Sendable {
        let product: String
        let state: SubscriptionState
        let purchaseDate: Date
        let expiry: Date
        let graceExpiry: Date?
        let autoRenew: Bool
        let verifiedAt: Date

        var accessDeadline: Date {
            state == .inGracePeriod ? (graceExpiry ?? expiry) : expiry
        }
        var courtesyDeadline: Date { max(expiry, graceExpiry ?? .distantPast) }
    }

    private func storedSubscriptions(
        user: UUID,
        environment: AppStoreEnvironment,
        on sql: any SQLDatabase
    ) async throws -> [StoredSubscription] {
        let rows = try await sql.raw("""
            SELECT * FROM app_store_subscriptions
            WHERE user_id = \(bind: user) AND environment = \(bind: environment.rawValue)
            ORDER BY purchase_date DESC,original_transaction_id DESC
            """).all()
        return try rows.map { row in
            guard let state = SubscriptionState(rawValue: try row.decode(column: "state", as: String.self)) else {
                throw Self.problem("subscription_unavailable")
            }
            return try StoredSubscription(
                product: row.decode(column: "product_id", as: String.self),
                state: state,
                purchaseDate: row.decode(column: "purchase_date", as: Date.self),
                expiry: row.decode(column: "expires_at", as: Date.self),
                graceExpiry: row.decode(column: "grace_expires_at", as: Date?.self),
                autoRenew: row.decode(column: "auto_renew_enabled", as: Bool.self),
                verifiedAt: row.decode(column: "verified_at", as: Date.self)
            )
        }
    }

    private func effectiveSubscription(_ rows: [StoredSubscription], now: Date) -> StoredSubscription? {
        let active = rows.filter { ($0.state == .subscribed || $0.state == .inGracePeriod) && $0.accessDeadline > now }
        return active.max { $0.accessDeadline < $1.accessDeadline } ?? rows.first
    }

    private func storedStatus(user: UUID) async throws -> SubscriptionStatus {
        let sql = try shoppingSQL(databases.database())
        let environment = gateway.configuration?.environment ?? accountCapacity.verificationEnvironment
        let now = try await databaseClock(sql)
        let rows = try await storedSubscriptions(user: user, environment: environment, on: sql)
        let effective = effectiveSubscription(rows, now: now)
        let state: SubscriptionState
        if let effective {
            if effective.state == .revoked {
                state = .revoked
            } else {
                state = effective.accessDeadline > now ? effective.state : .expired
            }
        } else {
            state = .free
        }
        return SubscriptionStatus(
            appAccountToken: user,
            isConfigured: gateway.configuration != nil,
            productIDs: gateway.configuration?.productIDs ?? [],
            state: state,
            expiresAt: effective.map { APIEncoding.timestamp($0.expiry) },
            gracePeriodExpiresAt: effective?.graceExpiry.map(APIEncoding.timestamp),
            autoRenewEnabled: effective?.autoRenew,
            verifiedAt: effective.map { APIEncoding.timestamp($0.verifiedAt) }
        )
    }

    private func existingNotification(_ receipt: NotificationReceipt, on sql: any SQLDatabase) async throws -> Bool {
        guard let row = try await sql.raw("""
            SELECT payload_hash FROM app_store_notifications
            WHERE environment = \(bind: receipt.environment.rawValue) AND notification_id = \(bind: receipt.id)
            """).first() else { return false }
        guard try row.decode(column: "payload_hash", as: String.self) == receipt.hash else {
            throw Self.problem("invalid_app_store_notification")
        }
        return true
    }

    private func recordNotification(_ receipt: NotificationReceipt) async throws {
        let database = try databases.database()
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            let now = try await databaseClock(sql)
            try await insertNotification(receipt, now: now, on: sql)
        }
    }

    private func insertNotification(_ receipt: NotificationReceipt, now: Date, on sql: any SQLDatabase) async throws {
        try await sql.raw("""
            INSERT INTO app_store_notifications(environment,notification_id,payload_hash,received_at)
            VALUES (\(bind: receipt.environment.rawValue),\(bind: receipt.id),\(bind: receipt.hash),\(bind: now))
            ON CONFLICT(environment,notification_id) DO NOTHING
            """).run()
        // Verify a racing insertion has the same signed evidence before acknowledging it.
        _ = try await existingNotification(receipt, on: sql)
    }

    static func gatewayProblem(_ error: any Error, invalid: String) -> APIProblem {
        if let error = error as? AppStoreGatewayError, error == .rejected {
            return problem(invalid)
        }
        return problem("subscription_unavailable")
    }

    static func problem(_ code: String) -> APIProblem {
        let status: HTTPStatus
        let message: String
        switch code {
        case "invalid_app_store_transaction", "invalid_app_store_notification":
            status = .badRequest
            message = "No se ha podido verificar la evidencia de App Store."
        case "transaction_account_mismatch":
            status = .forbidden
            message = "La compra pertenece a otra cuenta de la aplicación."
        case "transaction_already_bound":
            status = .conflict
            message = "La compra ya está vinculada a otra cuenta."
        default:
            status = .serviceUnavailable
            message = "La verificación de suscripciones no está disponible temporalmente."
        }
        return APIProblem(status: status, code: code, message: message)
    }
}
