@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Crypto
import JWTKit
import Testing
import Vapor

extension SmartShoppingListServerTests {
    @Test("Attested recovery restores only the paid period to the new account and survives a duplicate request")
    func recoveryRestoresRemainingPeriodOnce() async throws {
        let user = try await ShoppingFixture.user()
        let fixture = try await RecoveryFixture.make()
        let challenge = try await fixture.challenge(user.id)
        let first = try await fixture.recover(user.id, challenge)
        #expect(try RecoveryFixture.fields(first)["acknowledgedTransactionId"] == .string("700002"))
        let status = try RecoveryFixture.fields(RecoveryFixture.fields(first)["subscription"])
        #expect(status["state"] == .string("subscribed"))
        #expect(status["expiresAt"] == .string(APIEncoding.timestamp(fixture.expiry)))
        #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(true))
        _ = try await fixture.recover(user.id, challenge)
        let sql = try shoppingSQL(database)
        let chain = try #require(try await sql.raw("SELECT * FROM app_store_subscriptions").first())
        #expect(try chain.decode(column: "user_id", as: UUID?.self) == user.id)
        #expect(try chain.decode(column: "detached_at", as: Date?.self) == nil)
        #expect(try await sql.raw("SELECT 1 FROM app_store_subscriptions").all().count == 1)
        #expect(try await sql.raw("SELECT 1 FROM groups").all().isEmpty)
        #expect(try await sql.raw("SELECT 1 FROM items").all().isEmpty)
        let transactions = try await sql.raw("SELECT user_id FROM app_store_transactions").all()
        #expect(transactions.count == 2)
        for row in transactions {
            #expect(try row.decode(column: "user_id", as: UUID?.self) == user.id)
        }
        #expect(await fixture.gateway.tokens == [user.id])
    }

    @Test("A copied transaction, changed challenge binding or unverified app never starts reassignment")
    func recoveryRejectsCopiedOrChangedEvidence() async throws {
        let user = try await ShoppingFixture.user()
        let other = try await ShoppingFixture.user()
        let fixture = try await RecoveryFixture.make()
        let challenge = try await fixture.challenge(user.id)
        await #expect(throws: APIProblem.self) {
            try await fixture.recover(other.id, challenge)
        }
        await #expect(throws: APIProblem.self) {
            try await fixture.service.recover(
                user: user.id,
                challengeID: challenge.id,
                keyID: challenge.key,
                attestation: challenge.hash,
                signed: "different-signed-transaction"
            )
        }
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await fixture.service.recover(
                user: user.id,
                challengeID: challenge.id,
                keyID: challenge.key,
                attestation: Data(repeating: 0, count: 32),
                signed: RecoveryFixture.signed
            )
        }
        #expect(await fixture.gateway.tokens.isEmpty)
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT 1 FROM subscription_recovery_jobs").all().isEmpty)
        #expect(try await sql.raw("SELECT 1 FROM account_premium_access").all().isEmpty)
    }

    @Test("An uncertain Apple update reserves one owner, returns retryable V2 failure and completes on retry")
    func recoveryResumesUncertainAppleUpdateWithoutDoubleAssignment() async throws {
        let user = try await ShoppingFixture.user()
        let competitor = try await ShoppingFixture.user()
        let fixture = try await RecoveryFixture.make()
        let challenge = try await fixture.challenge(user.id)
        let competingChallenge = try await fixture.challenge(competitor.id)
        await fixture.gateway.failAfterApplyingOnce()
        await #expect(throws: AppStoreGatewayError.unavailable) {
            try await fixture.recover(user.id, challenge)
        }
        await #expect(throws: APIProblem.self) {
            try await fixture.recover(competitor.id, competingChallenge)
        }
        let subscription = SubscriptionService(databases: try testDatabases, gateway: fixture.gateway)
        do {
            try await subscription.notification(signed: "notification-during-recovery")
            Issue.record("A pending reassignment must be retryable, not acknowledged or granted")
        } catch let error as APIProblem {
            #expect(error.code == "subscription_unavailable")
            #expect(error.status.code == 503)
        }
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT 1 FROM account_premium_access").all().isEmpty)
        #expect(try await sql.raw("SELECT 1 FROM app_store_notifications").all().isEmpty)
        _ = try await fixture.recover(user.id, challenge)
        try await subscription.notification(signed: "notification-during-recovery")
        #expect(try await sql.raw("SELECT 1 FROM app_store_notifications").all().count == 1)
        #expect(await fixture.gateway.tokens == [user.id, user.id])
        #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(true))
        #expect(try await PremiumAccessFixture.capabilities(competitor)["premiumActive"] == .bool(false))
    }

    @Test("An owned chain, expired challenge and deleting account cannot be recovered")
    func recoveryCannotStealOrReviveAnAccount() async throws {
        let user = try await ShoppingFixture.user()
        let owner = try await ShoppingFixture.user()
        let fixture = try await RecoveryFixture.make()
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE app_store_subscriptions SET user_id = \(bind: owner.id), detached_at = NULL").run()
        await #expect(throws: APIProblem.self) {
            try await fixture.challenge(user.id)
        }
        try await sql.raw("UPDATE app_store_subscriptions SET user_id = NULL, detached_at = clock_timestamp()").run()
        let expired = try await fixture.challenge(user.id)
        try await sql.raw("""
            UPDATE subscription_recovery_challenges SET expires_at = clock_timestamp() - INTERVAL '1 second'
            WHERE id = \(bind: expired.id)
            """).run()
        await #expect(throws: APIProblem.self) {
            try await fixture.recover(user.id, expired)
        }
        let fresh = try await fixture.challenge(user.id)
        await fixture.gateway.onUpdate {
            try await database.accountTransaction(exclusive: true) { transaction in
                let sql = try shoppingSQL(transaction)
                try await sql.raw("UPDATE users SET deleting_at = clock_timestamp() WHERE id = \(bind: user.id)").run()
                try await AccountDataPurger.purge(user: user.id, on: sql)
            }
        }
        await #expect(throws: APIProblem.self) {
            try await fixture.recover(user.id, fresh)
        }
        #expect(try await sql.raw("SELECT 1 FROM app_store_subscriptions WHERE user_id IS NOT NULL").all().isEmpty)
        #expect(try await sql.raw("SELECT 1 FROM account_premium_access").all().isEmpty)
        #expect(await fixture.gateway.tokens == [user.id])
        do {
            _ = try await fixture.challenge(owner.id)
            Issue.record("A late Apple update must quarantine the chain before another account can reserve it")
        } catch let error as APIProblem {
            #expect(error.code == "subscription_recovery_pending_review")
        }
        let quarantine = try #require(try await sql.raw("SELECT * FROM subscription_recovery_jobs").first())
        #expect(try quarantine.decode(column: "state", as: String.self) == "quarantined")
        #expect(try quarantine.decode(column: "user_id", as: UUID?.self) == nil)
        #expect(try quarantine.decode(column: "challenge_id", as: UUID?.self) == nil)
    }
}

private struct RecoveryFixture: Sendable {
    static let signed = "storekit-verified-current-transaction"
    let service: SubscriptionRecoveryService
    let gateway: RecoveryGateway
    let expiry: Date

    struct Challenge: Sendable {
        let id: UUID
        let key: String
        let hash: Data
    }

    static func make() async throws -> Self {
        let sql = try shoppingSQL(database)
        let now = try await databaseClock(sql)
        let expiry = now.addingTimeInterval(3_600)
        try await sql.raw("""
            INSERT INTO app_store_subscriptions(environment,original_transaction_id,user_id,transaction_id,
                product_id,state,purchase_date,expires_at,auto_renew_enabled,revision,verified_at,detached_at)
            VALUES ('Production','700000',NULL,'700002','recovery.monthly','subscribed',
                \(bind: now),\(bind: expiry),true,\(bind: now),\(bind: now),\(bind: now))
            """).run()
        for id in ["700001", "700002"] {
            try await sql.raw("""
                INSERT INTO app_store_transactions(environment,transaction_id,user_id,original_transaction_id,verified_at)
                VALUES ('Production',\(bind: id),NULL,'700000',\(bind: now))
                """).run()
        }
        let gateway = RecoveryGateway(expiry: expiry, now: now)
        return Self(
            service: SubscriptionRecoveryService(
                databases: try testDatabases,
                gateway: gateway,
                attestation: RecoveryAttestationOracle()
            ),
            gateway: gateway,
            expiry: expiry
        )
    }

    func challenge(_ user: UUID) async throws -> Challenge {
        let key = Data(SHA256.hash(data: Data(UUID().uuidString.utf8))).base64EncodedString()
        let response = try Self.fields(await service.challenge(user: user, signed: Self.signed, keyID: key))
        let idText = try #require(response["id"]?.string)
        let id = try #require(UUID(uuidString: idText))
        let nonce = try #require(response["nonce"]?.string)
        // Independent wire-contract calculation: no production hash or context helper is reused.
        let transaction = SHA256.hash(data: Data(Self.signed.utf8)).map { String(format: "%02x", $0) }.joined()
        let bytes = "smartlist.subscription-recovery.v1\n\(idText)\n\(user.uuidString.lowercased())\n"
            + "Production\n\(key)\n\(nonce)\n\(transaction)"
        let expected = Data(SHA256.hash(data: Data(bytes.utf8)))
        #expect(response["clientDataHash"] == .string(expected.base64EncodedString()))
        #expect(response["appAccountToken"] == .string(user.uuidString.lowercased()))
        return Challenge(id: id, key: key, hash: expected)
    }

    func recover(_ user: UUID, _ challenge: Challenge) async throws -> APIJSON {
        try await service.recover(
            user: user,
            challengeID: challenge.id,
            keyID: challenge.key,
            attestation: challenge.hash,
            signed: Self.signed
        )
    }

    static func fields(_ json: APIJSON?) throws -> [String: APIJSON] {
        guard case .object(let values) = json else {
            Issue.record("Expected JSON object")
            throw APIProblem.invalidRequest
        }
        return values
    }
}

/// This oracle tests service binding; real certificate and WebAuthn validation has its own independent fixtures.
private struct RecoveryAttestationOracle: AppAttestVerifying {
    func verify(_ attestation: Data, keyID: String, clientDataHash: Data, environment: AppStoreEnvironment) throws {
        guard attestation == clientDataHash else { throw AppStoreGatewayError.rejected }
    }
}

private actor RecoveryGateway: AppStoreGateway {
    nonisolated let configuration: AppStoreConfiguration? = .init(
        bundleID: "app.recovery.test",
        appAppleID: 1,
        subscriptionGroupID: "700",
        issuerID: UUID().uuidString,
        keyID: "unused",
        privateKeyPEM: "unused",
        monthlyProductID: "recovery.monthly",
        annualProductID: "recovery.annual",
        environment: .production
    )
    let expiry: Date
    let now: Date
    private var token = UUID()
    private var failsAfterUpdate = false
    private var updated: (@Sendable () async throws -> Void)?
    private let notificationID = UUID()
    private(set) var tokens: [UUID] = []

    init(expiry: Date, now: Date) {
        self.expiry = expiry
        self.now = now
    }

    func verifyTransaction(_ signed: String) -> AppStoreTransaction { transaction() }

    func subscriptionStates(originalTransactionID: String) -> [VerifiedAppStoreSubscription] {
        [.init(
            transaction: transaction(),
            renewal: .init(
                originalTransactionId: "700000", appAccountToken: token, productId: "recovery.monthly",
                environment: .production, autoRenewStatus: 1, gracePeriodExpiresDate: nil, signedDate: now
            ),
            status: 1
        )]
    }

    func verifyNotification(_ signed: String) -> AppStoreNotification {
        .init(
            notificationUUID: notificationID,
            notificationType: "DID_RENEW",
            signedDate: now,
            data: .init(
                bundleId: "app.recovery.test", appAppleId: 1, environment: .production,
                signedTransactionInfo: RecoveryFixture.signed, signedRenewalInfo: nil
            )
        )
    }

    func setAppAccountToken(originalTransactionID: String, token: UUID) async throws {
        self.token = token
        tokens.append(token)
        if let updated {
            try await updated()
        }
        if failsAfterUpdate {
            failsAfterUpdate = false
            throw AppStoreGatewayError.unavailable
        }
    }

    func failAfterApplyingOnce() { failsAfterUpdate = true }
    func onUpdate(_ action: @escaping @Sendable () async throws -> Void) { updated = action }

    private func transaction() -> AppStoreTransaction {
        .init(
            transactionId: "700002", originalTransactionId: "700000", bundleId: "app.recovery.test",
            productId: "recovery.monthly", environment: .production, appAccountToken: token,
            type: "Auto-Renewable Subscription", inAppOwnershipType: "PURCHASED",
            purchaseDate: now.addingTimeInterval(-1_800), expiresDate: expiry, revocationDate: nil, signedDate: now
        )
    }
}
