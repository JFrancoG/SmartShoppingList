import Foundation
import FluentKit
import FluentSQL
import Vapor

/// Request logs contain only the failed check. The signed transaction, proof and account identifiers stay private.
enum RecoveryRejectionStage: String {
    case recoveryRequest, challengeContext, storedProof, subscriptionRecord, acknowledgedTransaction
    case attestationObject, certificateChain, certificateNonce, attestedKey, authenticatorData
    case credentialPublicKey, authenticatorExtensions, distributionCategory, bundleVersion, receipt

    func log(to logger: Logger?) {
        logger?.notice("Subscription recovery verification rejected", metadata: ["stage": .string(rawValue)])
    }
}

/// A recovery reservation survives an uncertain Apple response; repeated attempts set the same new account token.
struct SubscriptionRecoveryService: Sendable {
    let databases: Databases
    let gateway: any AppStoreGateway
    let attestation: any AppAttestVerifying

    func challenge(user: UUID, signed: String, keyID: String) async throws -> APIJSON {
        guard let key = Data(base64Encoded: keyID), key.count == 32, key.base64EncodedString() == keyID,
              !signed.isEmpty, signed.utf8.count <= 65_536
        else {
            throw Self.rejected
        }
        let claim = try await gateway.verifyTransaction(signed)
        try validate(claim)
        let states = try await gateway.subscriptionStates(originalTransactionID: claim.originalTransactionId)
        guard try active(states, original: claim.originalTransactionId) else { throw Self.expired }
        let database = try databases.database()
        try await database.accountTransaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await requireActiveAccount(user, on: sql)
            try await cleanup(on: sql)
        }
        return try await database.accountTransaction { transaction in
            let sql = try shoppingSQL(transaction)
            _ = try await sql.raw("SELECT id FROM users WHERE id = \(bind: user) FOR UPDATE").first()
            try await requireActiveAccount(user, on: sql)
            let challenges = try await sql.raw("""
                SELECT id FROM subscription_recovery_challenges
                WHERE user_id = \(bind: user) AND expires_at > clock_timestamp() LIMIT 5
                """).all()
            guard challenges.count < 5 else {
                throw APIProblem(
                    status: .tooManyRequests,
                    code: "recovery_attempt_limit",
                    message: "Espera unos minutos antes de volver a intentar la recuperación."
                )
            }
            let existing = try await sql.raw("""
                SELECT user_id,detached_at FROM app_store_subscriptions
                WHERE environment = \(bind: claim.environment.rawValue)
                    AND original_transaction_id = \(bind: claim.originalTransactionId) FOR UPDATE
                """).first()
            guard let existing, try existing.decode(column: "user_id", as: UUID?.self) == nil,
                  try existing.decode(column: "detached_at", as: Date?.self) != nil
            else {
                throw SubscriptionService.problem("transaction_already_bound")
            }
            if let job = try await recoveryJob(claim.environment, original: claim.originalTransactionId, on: sql) {
                if try job.decode(column: "state", as: String.self) == "quarantined" {
                    throw Self.pendingReview
                }
                guard try job.decode(column: "user_id", as: UUID?.self) == user else {
                    throw SubscriptionService.problem("transaction_already_bound")
                }
            }
            let id = UUID()
            let nonce = IdentitySecrets.generate()
            let digest = Self.transactionHash(signed)
            guard let row = try await sql.raw("""
                INSERT INTO subscription_recovery_challenges
                    (id,user_id,environment,original_transaction_id,transaction_hash,key_id,nonce,expires_at)
                VALUES (\(bind: id),\(bind: user),\(bind: claim.environment.rawValue),
                    \(bind: claim.originalTransactionId),\(bind: digest),\(bind: keyID),\(bind: nonce),
                    clock_timestamp() + INTERVAL '5 minutes')
                ON CONFLICT(key_id) DO NOTHING RETURNING expires_at
                """).first() else { throw Self.rejected }
            let context = RecoveryContext(
                id: id,
                user: user,
                environment: claim.environment,
                original: claim.originalTransactionId,
                transactionHash: digest,
                keyID: keyID,
                nonce: nonce
            )
            return .object([
                "id": .string(id.uuidString.lowercased()), "nonce": .string(nonce),
                "expiresAt": .string(APIEncoding.timestamp(try row.decode(column: "expires_at", as: Date.self))),
                "clientDataHash": .string(context.clientDataHash.base64EncodedString()),
                "appAccountToken": .string(user.uuidString.lowercased()),
                "environment": .string(claim.environment.rawValue)
            ])
        }
    }

    func recover(
        user: UUID,
        challengeID: UUID,
        keyID: String,
        attestation proof: Data,
        signed: String,
        logger: Logger? = nil
    ) async throws -> APIJSON {
        guard proof.count <= 65_536, !proof.isEmpty, signed.utf8.count <= 65_536 else {
            throw Self.rejected(at: .recoveryRequest, logger: logger)
        }
        let database = try databases.database()
        let context = try await database.accountTransaction { transaction -> RecoveryContext in
            let sql = try shoppingSQL(transaction)
            try await requireActiveAccount(user, on: sql)
            return try await loadContext(user: user, id: challengeID, keyID: keyID, signed: signed, on: sql, logger: logger)
        }
        // The signed JWS is not sufficient. The genuine app attests only after local StoreKit device verification.
        let proofHash = Self.dataHash(proof)
        if let verifiedProof = context.attestationHash {
            guard verifiedProof == proofHash else { throw Self.rejected(at: .storedProof, logger: logger) }
        } else {
            try await attestation.verify(
                proof,
                keyID: keyID,
                clientDataHash: context.clientDataHash,
                environment: context.environment,
                logger: logger
            )
        }
        let completed = try await database.accountTransaction { transaction -> Bool in
            let sql = try shoppingSQL(transaction)
            try await requireActiveAccount(user, on: sql)
            _ = try await loadContext(user: user, id: challengeID, keyID: keyID, signed: signed, on: sql, logger: logger)
            guard let subscription = try await sql.raw("""
                SELECT user_id,detached_at FROM app_store_subscriptions
                WHERE environment = \(bind: context.environment.rawValue)
                    AND original_transaction_id = \(bind: context.original) FOR UPDATE
                """).first() else { throw Self.rejected(at: .subscriptionRecord, logger: logger) }
            let owner = try subscription.decode(column: "user_id", as: UUID?.self)
            let job = try await recoveryJob(context.environment, original: context.original, on: sql)
            if let job {
                if try job.decode(column: "state", as: String.self) == "quarantined" {
                    throw Self.pendingReview
                }
                guard try job.decode(column: "user_id", as: UUID?.self) == user else {
                    throw SubscriptionService.problem("transaction_already_bound")
                }
                guard owner == nil || owner == user else { throw Self.rejected(at: .subscriptionRecord, logger: logger) }
                if try job.decode(column: "state", as: String.self) == "completed" {
                    return true
                }
                let inFlight = try job.decode(column: "request_in_flight", as: Bool.self)
                let started = try job.decode(column: "attempt_started_at", as: Date.self)
                let now = try await databaseClock(sql)
                guard !inFlight || started.addingTimeInterval(60) < now else {
                    throw SubscriptionService.problem("subscription_unavailable")
                }
                // A new attested attempt by the same account may resume a reservation after losing local state.
                try await sql.raw("""
                    UPDATE subscription_recovery_jobs SET challenge_id = \(bind: challengeID),
                        has_uncertain_update = has_uncertain_update OR request_in_flight,
                        request_in_flight = true, attempt_started_at = clock_timestamp()
                    WHERE environment = \(bind: context.environment.rawValue)
                        AND original_transaction_id = \(bind: context.original)
                    """).run()
            } else {
                guard owner == nil, try subscription.decode(column: "detached_at", as: Date?.self) != nil else {
                    throw SubscriptionService.problem("transaction_already_bound")
                }
                try await sql.raw("""
                    INSERT INTO subscription_recovery_jobs
                        (environment,original_transaction_id,user_id,challenge_id,state,request_in_flight)
                    VALUES (\(bind: context.environment.rawValue),\(bind: context.original),\(bind: user),
                        \(bind: challengeID),'reserved',true)
                    """).run()
            }
            try await sql.raw("""
                UPDATE subscription_recovery_challenges SET verified_at = COALESCE(verified_at,clock_timestamp()),
                    attestation_hash = \(bind: proofHash)
                WHERE id = \(bind: challengeID)
                """).run()
            return false
        }
        // No SQL transaction or shared deletion barrier spans Apple's network call.
        let service = SubscriptionService(databases: databases, gateway: gateway)
        let status: SubscriptionStatus
        if completed {
            status = try await service.status(user: user)
        } else {
            var updateAcknowledged = false
            do {
                try await gateway.setAppAccountToken(originalTransactionID: context.original, token: user)
                updateAcknowledged = true
                let states = try await gateway.subscriptionStates(originalTransactionID: context.original)
                guard try active(states, original: context.original),
                      states.filter({ $0.transaction.originalTransactionId == context.original })
                          .allSatisfy({ $0.transaction.appAccountToken == user })
                else {
                    throw SubscriptionService.problem("subscription_unavailable")
                }
                status = try await service.completeRecovery(user: user, original: context.original, snapshots: states)
            } catch {
                let uncertain = !updateAcknowledged
                try await database.accountTransaction { transaction in
                    let sql = try shoppingSQL(transaction)
                    try await sql.raw("""
                        UPDATE subscription_recovery_jobs SET request_in_flight = false,
                            has_uncertain_update = has_uncertain_update OR \(bind: uncertain)
                        WHERE environment = \(bind: context.environment.rawValue)
                            AND original_transaction_id = \(bind: context.original) AND user_id = \(bind: user)
                            AND state = 'reserved'
                        """).run()
                }
                throw error
            }
        }
        let claim = try await gateway.verifyTransaction(signed)
        try validate(claim)
        guard claim.originalTransactionId == context.original else {
            throw Self.rejected(at: .acknowledgedTransaction, logger: logger)
        }
        return .object([
            "subscription": status.json, "acknowledgedTransactionId": .string(claim.transactionId)
        ])
    }

    private func validate(_ claim: AppStoreTransaction) throws {
        guard let configuration = gateway.configuration, claim.environment == configuration.environment,
              configuration.productIDs.contains(claim.productId), claim.inAppOwnershipType == "PURCHASED"
        else {
            throw Self.rejected
        }
    }

    private func active(_ states: [VerifiedAppStoreSubscription], original: String) throws -> Bool {
        guard let configuration = gateway.configuration else { throw AppStoreGatewayError.unavailable }
        let matching = states.filter { $0.transaction.originalTransactionId == original }
        guard !matching.isEmpty, matching.count <= 64 else { throw Self.rejected }
        return matching.contains {
            $0.transaction.environment == configuration.environment
                && configuration.productIDs.contains($0.transaction.productId)
                && $0.transaction.inAppOwnershipType == "PURCHASED" && !$0.isRevoked
                && ($0.premiumUntil ?? .distantPast) > Date()
        }
    }

    private func loadContext(
        user: UUID,
        id: UUID,
        keyID: String,
        signed: String,
        on sql: any SQLDatabase,
        logger: Logger?
    ) async throws -> RecoveryContext {
        guard let row = try await sql.raw("""
            SELECT * FROM subscription_recovery_challenges
            WHERE id = \(bind: id) AND user_id = \(bind: user)
                AND (expires_at > clock_timestamp() OR verified_at IS NOT NULL)
            """).first(),
              try row.decode(column: "key_id", as: String.self) == keyID,
              try row.decode(column: "transaction_hash", as: String.self) == Self.transactionHash(signed),
              let environment = try AppStoreEnvironment(rawValue: row.decode(column: "environment", as: String.self)),
              gateway.configuration?.environment == environment
        else {
            throw Self.rejected(at: .challengeContext, logger: logger)
        }
        return try RecoveryContext(
            id: id,
            user: user,
            environment: environment,
            original: row.decode(column: "original_transaction_id", as: String.self),
            transactionHash: row.decode(column: "transaction_hash", as: String.self),
            keyID: keyID,
            nonce: row.decode(column: "nonce", as: String.self),
            attestationHash: row.decode(column: "attestation_hash", as: String?.self)
        )
    }

    private func recoveryJob(
        _ environment: AppStoreEnvironment,
        original: String,
        on sql: any SQLDatabase
    ) async throws -> (any SQLRow)? {
        try await sql.raw("""
            SELECT * FROM subscription_recovery_jobs
            WHERE environment = \(bind: environment.rawValue) AND original_transaction_id = \(bind: original)
            """).first()
    }

    private func cleanup(on sql: any SQLDatabase) async throws {
        try await sql.raw("""
            DELETE FROM subscription_recovery_jobs
            WHERE state = 'completed' AND NOT request_in_flight AND NOT has_uncertain_update
                AND completed_at < clock_timestamp() - INTERVAL '7 days'
            """).run()
        try await sql.raw("""
            DELETE FROM subscription_recovery_challenges
            WHERE expires_at < clock_timestamp()
                AND NOT EXISTS (SELECT 1 FROM subscription_recovery_jobs
                    WHERE challenge_id = subscription_recovery_challenges.id)
            """).run()
    }

    static func transactionHash(_ signed: String) -> String {
        dataHash(Data(signed.utf8))
    }

    private static func dataHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static var rejected: APIProblem {
        .init(status: .forbidden, code: "invalid_subscription_recovery", message: "No se ha podido verificar la recuperación.")
    }

    static func rejected(at stage: RecoveryRejectionStage, logger: Logger?) -> APIProblem {
        stage.log(to: logger)
        return rejected
    }

    private static var expired: APIProblem {
        .init(status: .conflict, code: "subscription_expired", message: "La suscripción ya no tiene un periodo vigente.")
    }

    private static var pendingReview: APIProblem {
        .init(
            status: .serviceUnavailable,
            code: "subscription_recovery_pending_review",
            message: "La recuperación necesita revisión. Contacta con soporte@jesusfranco.dev."
        )
    }
}

private struct RecoveryContext: Sendable {
    let id: UUID
    let user: UUID
    let environment: AppStoreEnvironment
    let original: String
    let transactionHash: String
    let keyID: String
    let nonce: String
    var attestationHash: String? = nil

    var clientDataHash: Data {
        let value = [
            "smartlist.subscription-recovery.v1", id.uuidString.lowercased(), user.uuidString.lowercased(),
            environment.rawValue, keyID, nonce, transactionHash
        ].joined(separator: "\n")
        return Data(SHA256.hash(data: Data(value.utf8)))
    }
}
