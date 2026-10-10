@testable import SmartShoppingListServer
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("Submitting an expired historical purchase acknowledges it while Apple's current state controls access")
    func historicalPurchaseUsesCurrentAppleState() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let historical = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: -10 * 86_400)
        let expired = SubscriptionServiceFixture.snapshot(historical, status: 2)
        let gateway = SubscriptionServiceGateway(transaction: historical, snapshots: [expired])
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            let response = try await SubscriptionServiceFixture.submit(user)
            try #require(response.status == .ok)
            #expect(try ShoppingFixture.object(response)["acknowledgedTransactionId"] == .string("1001"))
            let status = try StoreQuotaFixture.fields(ShoppingFixture.object(response)["subscription"])
            #expect(status["state"] == .string("expired"))
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(false))
            let ledger = try await SubscriptionServiceFixture.ledger(user)
            #expect(ledger.count == 1)
            #expect(ledger[0]["transaction_id"] == "1001")
            let storedExpiry = try #require(status["expiresAt"]?.string)
            #expect(storedExpiry == APIEncoding.timestamp(try #require(historical.expiresDate)))
        }
    }

    @Test("A paid grace snapshot grants full premium and a verification outage keeps only its existing deadline")
    func paidGraceAndVerificationOutage() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let transaction = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: -86_400)
        let snapshot = SubscriptionServiceFixture.snapshot(
            transaction,
            status: 4,
            grace: now.addingTimeInterval(5 * 86_400)
        )
        let gateway = SubscriptionServiceGateway(transaction: transaction, snapshots: [snapshot])
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            let submitted = try await SubscriptionServiceFixture.submit(user)
            try #require(submitted.status == .ok)
            let before = try StoreQuotaFixture.fields(ShoppingFixture.object(submitted)["subscription"])
            #expect(before["state"] == .string("in_grace_period"))
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(true))
            _ = try await ShoppingFixture.group(user)
            _ = try await ShoppingFixture.group(user)
            await gateway.failStatus(.unavailable)
            let read = try await ShoppingFixture.request(.GET, "/v1/account/subscription", user)
            #expect(read.status == .ok)
            #expect(try ShoppingFixture.object(read)["verifiedAt"] == before["verifiedAt"])
            #expect(try ShoppingFixture.object(read)["gracePeriodExpiresAt"] == before["gracePeriodExpiresAt"])
            let sql = try shoppingSQL(database)
            try await sql.raw("""
                UPDATE app_store_subscriptions SET grace_expires_at = clock_timestamp() - INTERVAL '1 second'
                WHERE user_id = \(bind: user.id)
                """).run()
            try await sql.raw("""
                UPDATE account_premium_access SET premium_until = clock_timestamp() - INTERVAL '1 second',
                    transition_started_at = clock_timestamp() - INTERVAL '1 second'
                WHERE user_id = \(bind: user.id)
                """).run()
            let expired = try await ShoppingFixture.request(.GET, "/v1/account/subscription", user)
            #expect(try ShoppingFixture.object(expired)["state"] == .string("expired"))
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(false))
        }
    }

    @Test("Expiry after paid grace starts courtesy at the retained grace end even if Apple's later renewal omits that field")
    func expiredGraceKeepsItsCourtesyAnchor() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let transaction = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: -10 * 86_400)
        let graceEnd = now.addingTimeInterval(-86_400)
        let oldGrace = SubscriptionServiceFixture.snapshot(transaction, status: 4, grace: graceEnd)
        let gateway = SubscriptionServiceGateway(transaction: transaction, snapshots: [oldGrace])
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            try #require(try await SubscriptionServiceFixture.submit(user).status == .ok)
            let before = try await PremiumAccessFixture.capabilities(user)
            let expired = SubscriptionServiceFixture.snapshot(transaction, status: 2)
            await gateway.replace(transaction: transaction, snapshots: [expired])
            #expect(try await SubscriptionServiceFixture.submit(user).status == .ok)
            let after = try await PremiumAccessFixture.capabilities(user)
            #expect(after["premiumActive"] == .bool(false))
            #expect(after["transitionEndsAt"] == before["transitionEndsAt"])
            let expectedEnd = APIEncoding.timestamp(graceEnd.addingTimeInterval(604_800))
            #expect(after["transitionEndsAt"] == .string(expectedEnd))
        }
    }

    @Test("Out-of-order verified states and equal-revision active retries cannot undo a revocation")
    func revokedStateRejectsStaleAndEqualRevisionActivation() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let active = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: 86_400)
        let gateway = SubscriptionServiceGateway(
            transaction: active,
            snapshots: [SubscriptionServiceFixture.snapshot(active)]
        )
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            try #require(try await SubscriptionServiceFixture.submit(user).status == .ok)
            let revoked = SubscriptionServiceFixture.transaction(
                user: user.id,
                now: now,
                expiry: 86_400,
                revoked: true
            )
            await gateway.replace(
                transaction: revoked,
                snapshots: [SubscriptionServiceFixture.snapshot(revoked, status: 5)]
            )
            #expect(try await SubscriptionServiceFixture.submit(user).status == .ok)
            #expect(try await PremiumAccessFixture.capabilities(user)["transitionEndsAt"] == .null)
            let revokedLedger = try await SubscriptionServiceFixture.ledger(user)
            await gateway.replace(transaction: active, snapshots: [SubscriptionServiceFixture.snapshot(active)])
            #expect(try await SubscriptionServiceFixture.submit(user).status == .ok)
            #expect(try await SubscriptionServiceFixture.ledger(user) == revokedLedger)
            let stale = SubscriptionServiceFixture.transaction(
                user: user.id,
                now: now.addingTimeInterval(-60),
                expiry: 86_400
            )
            await gateway.replace(transaction: stale, snapshots: [SubscriptionServiceFixture.snapshot(stale)])
            #expect(try await SubscriptionServiceFixture.submit(user).status == .ok)
            #expect(try await SubscriptionServiceFixture.ledger(user) == revokedLedger)
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(false))
        }
    }

    @Test("Purchase ownership cannot be reassigned and neither rejected nor unavailable verification grants access")
    func subscriptionOwnershipAndVerificationFailures() async throws {
        let owner = try await ShoppingFixture.user()
        let attacker = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let value = SubscriptionServiceFixture.transaction(user: owner.id, now: now, expiry: 86_400)
        let gateway = SubscriptionServiceGateway(
            transaction: value,
            snapshots: [SubscriptionServiceFixture.snapshot(value)]
        )
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            let mismatch = try await SubscriptionServiceFixture.submit(attacker)
            #expect(
                try SubscriptionServiceFixture.errorCode(mismatch, status: .forbidden) == "transaction_account_mismatch"
            )
            #expect(try await SubscriptionServiceFixture.ledger(attacker).isEmpty)
            try #require(try await SubscriptionServiceFixture.submit(owner).status == .ok)
            let rebound = SubscriptionServiceFixture.transaction(user: attacker.id, now: now, expiry: 86_400)
            await gateway.replace(transaction: rebound, snapshots: [SubscriptionServiceFixture.snapshot(rebound)])
            let conflict = try await SubscriptionServiceFixture.submit(attacker)
            #expect(
                try SubscriptionServiceFixture.errorCode(conflict, status: .conflict) == "transaction_already_bound"
            )
            #expect(try await PremiumAccessFixture.capabilities(attacker)["premiumActive"] == .bool(false))
            await gateway.failTransaction(.rejected)
            let rejected = try await SubscriptionServiceFixture.submit(attacker)
            #expect(
                try SubscriptionServiceFixture.errorCode(rejected, status: .badRequest) == "invalid_app_store_transaction"
            )
            await gateway.failTransaction(.unavailable)
            let unavailable = try await SubscriptionServiceFixture.submit(attacker)
            #expect(
                try SubscriptionServiceFixture.errorCode(unavailable, status: .serviceUnavailable)
                    == "subscription_unavailable"
            )
            #expect(try await SubscriptionServiceFixture.ledger(owner).count == 1)
        }
    }

    @Test("Verified notifications bind a known account durably, deduplicate retries and ignore unknown accounts without granting")
    func appStoreNotificationDurabilityAndUnknownAccount() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let transaction = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: 86_400)
        let event = SubscriptionServiceFixture.notification(transaction: transaction)
        let gateway = SubscriptionServiceGateway(
            transaction: transaction,
            snapshots: [SubscriptionServiceFixture.snapshot(transaction)],
            notification: event
        )
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            let first = try await SubscriptionServiceFixture.notify()
            #expect(first.status == .noContent)
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(true))
            let after = try await SubscriptionServiceFixture.ledger(user)
            await gateway.failStatus(.unavailable)
            let duplicate = try await SubscriptionServiceFixture.notify()
            #expect(duplicate.status == .noContent)
            #expect(try await SubscriptionServiceFixture.ledger(user) == after)
            let unknown = SubscriptionServiceFixture.transaction(
                user: UUID(),
                now: now,
                expiry: 86_400,
                original: "2000"
            )
            await gateway.replace(transaction: unknown, snapshots: [SubscriptionServiceFixture.snapshot(unknown)])
            await gateway.replaceNotification(SubscriptionServiceFixture.notification(transaction: unknown))
            #expect(try await SubscriptionServiceFixture.notify().status == .noContent)
            let sql = try shoppingSQL(database)
            #expect(try await sql.raw("SELECT user_id FROM account_premium_access").all().count == 1)
            #expect(try await sql.raw("SELECT notification_id FROM app_store_notifications").all().count == 2)
            #expect(try await sql.raw("SELECT user_id FROM app_store_subscriptions").all().count == 1)
        }
    }

    @Test("Revoking one original chain preserves a separately verified active chain for the same account")
    func aggregateKeepsOtherVerifiedPaidChain() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let first = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: 86_400)
        let second = SubscriptionServiceFixture.transaction(
            user: user.id,
            now: now,
            expiry: 2 * 86_400,
            original: "2000"
        )
        let gateway = SubscriptionServiceGateway(
            transaction: first,
            snapshots: [SubscriptionServiceFixture.snapshot(first), SubscriptionServiceFixture.snapshot(second)]
        )
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            try #require(try await SubscriptionServiceFixture.submit(user).status == .ok)
            let revoked = SubscriptionServiceFixture.transaction(
                user: user.id,
                now: now,
                expiry: 86_400,
                revoked: true
            )
            await gateway.replace(
                transaction: revoked,
                snapshots: [
                    SubscriptionServiceFixture.snapshot(revoked, status: 5),
                    SubscriptionServiceFixture.snapshot(second)
                ]
            )
            let response = try await SubscriptionServiceFixture.submit(user)
            #expect(response.status == .ok)
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(true))
            let status = try StoreQuotaFixture.fields(ShoppingFixture.object(response)["subscription"])
            #expect(status["expiresAt"] == .string(APIEncoding.timestamp(try #require(second.expiresDate))))
            #expect(try await SubscriptionServiceFixture.ledger(user).count == 2)
        }
    }

    @Test(
        "Verified revocation and pending growth serialize using the same group quota owner",
        .timeLimit(.minutes(1)),
        arguments: [true, false]
    )
    func subscriptionRevocationRacesPendingGrowth(revokeFirst: Bool) async throws {
        let user = try await ShoppingFixture.user()
        let member = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let value = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: 86_400)
        let gateway = SubscriptionServiceGateway(
            transaction: value,
            snapshots: [SubscriptionServiceFixture.snapshot(value)]
        )
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            try #require(try await SubscriptionServiceFixture.submit(user).status == .ok)
            let group = try await ShoppingFixture.group(user)
            try await ShoppingFixture.join(member, group: group)
            _ = try await StoreQuotaFixture.add(user, group: group, store: "Casa", count: 20)
            let revoked = SubscriptionServiceFixture.transaction(
                user: user.id,
                now: now,
                expiry: 86_400,
                revoked: true
            )
            await gateway.replace(
                transaction: revoked,
                snapshots: [SubscriptionServiceFixture.snapshot(revoked, status: 5)]
            )
            let revoke: @Sendable () async throws -> TestingHTTPResponse = {
                try await SubscriptionServiceFixture.submit(user)
            }
            let add: @Sendable () async throws -> TestingHTTPResponse = {
                try await ShoppingFixture.request(
                    .POST,
                    "/v1/groups/\(group)/item-batches",
                    member,
                    ShoppingFixture.batch(names: ["Último"], stores: ["Casa"])
                )
            }
            let results = try await ShoppingFixture.overlappingRequests(
                lockedBy: "SELECT id FROM groups WHERE id = \(bind: group)::uuid FOR UPDATE",
                waitingQuery: "%FROM groups%FOR UPDATE%",
                first: revokeFirst ? revoke : add,
                second: revokeFirst ? add : revoke
            )
            #expect(results.0.status == (revokeFirst ? .ok : .created))
            #expect(results.1.status == (revokeFirst ? .conflict : .ok))
            if revokeFirst {
                #expect(try StoreQuotaFixture.code(results.1) == "pending_item_limit_reached")
            }
            #expect(try await ShoppingFixture.allPending(group: group, user: member).count == (revokeFirst ? 20 : 21))
            let capacity = try await StoreQuotaFixture.capacity(member, group: group)
            #expect(capacity["limits"] == StoreQuotaFixture.freeLimits)
        }
    }

    @Test("Notification outages are retryable and a valid TEST event creates no paid rights")
    func appStoreNotificationOutageAndTestEvent() async throws {
        let user = try await ShoppingFixture.user()
        let now = try await databaseClock(shoppingSQL(database))
        let value = SubscriptionServiceFixture.transaction(user: user.id, now: now, expiry: 86_400)
        let gateway = SubscriptionServiceGateway(
            transaction: value,
            snapshots: [SubscriptionServiceFixture.snapshot(value)],
            notification: SubscriptionServiceFixture.notification(transaction: value)
        )
        try await SubscriptionServiceFixture.withRoutes(gateway) {
            await gateway.failStatus(.unavailable)
            let outage = try await SubscriptionServiceFixture.notify()
            #expect(
                try SubscriptionServiceFixture.errorCode(outage, status: .serviceUnavailable) == "subscription_unavailable"
            )
            let sql = try shoppingSQL(database)
            #expect(try await sql.raw("SELECT notification_id FROM app_store_notifications").all().isEmpty)
            #expect(try await PremiumAccessFixture.capabilities(user)["premiumActive"] == .bool(false))
            await gateway.replaceNotification(SubscriptionServiceFixture.notification(transaction: value, type: "TEST"))
            #expect(try await SubscriptionServiceFixture.notify().status == .noContent)
            #expect(try await sql.raw("SELECT notification_id FROM app_store_notifications").all().count == 1)
            #expect(try await sql.raw("SELECT user_id FROM app_store_subscriptions").all().isEmpty)
        }
    }
}

private actor SubscriptionServiceGateway: AppStoreGateway {
    nonisolated let configuration: AppStoreConfiguration? = SubscriptionServiceFixture.configuration
    private var transaction: AppStoreTransaction
    private var snapshots: [VerifiedAppStoreSubscription]
    private var event: AppStoreNotification?
    private var transactionError: AppStoreGatewayError?
    private var statusError: AppStoreGatewayError?

    init(
        transaction: AppStoreTransaction,
        snapshots: [VerifiedAppStoreSubscription],
        notification: AppStoreNotification? = nil
    ) {
        self.transaction = transaction
        self.snapshots = snapshots
        event = notification
    }

    func verifyTransaction(_ signed: String) throws -> AppStoreTransaction {
        if let transactionError {
            throw transactionError
        }
        return transaction
    }

    func subscriptionStates(originalTransactionID: String) throws -> [VerifiedAppStoreSubscription] {
        if let statusError {
            throw statusError
        }
        return snapshots
    }

    func verifyNotification(_ signed: String) throws -> AppStoreNotification {
        guard let event else { throw AppStoreGatewayError.rejected }
        return event
    }

    func replace(transaction: AppStoreTransaction, snapshots: [VerifiedAppStoreSubscription]) {
        self.transaction = transaction
        self.snapshots = snapshots
        transactionError = nil
        statusError = nil
    }

    func failTransaction(_ error: AppStoreGatewayError) {
        transactionError = error
    }

    func failStatus(_ error: AppStoreGatewayError) {
        statusError = error
    }

    func replaceNotification(_ value: AppStoreNotification) {
        event = value
    }
}

private enum SubscriptionServiceFixture {
    static let configuration = AppStoreConfiguration(
        bundleID: "app.test",
        appAppleID: 123,
        subscriptionGroupID: "90001",
        issuerID: "00000000-0000-0000-0000-000000000001",
        keyID: "TEST_KEY",
        privateKeyPEM: "unused-trusted-gateway-test-credential",
        monthlyProductID: "app.test.premium.monthly",
        annualProductID: "app.test.premium.annual",
        environment: .production
    )

    static func transaction(
        user: UUID,
        now: Date,
        expiry: TimeInterval,
        revoked: Bool = false,
        original: String = "1000"
    ) -> AppStoreTransaction {
        AppStoreTransaction(
            transactionId: original == "1000" ? "1001" : "2001",
            originalTransactionId: original,
            bundleId: configuration.bundleID,
            productId: configuration.monthlyProductID,
            environment: .production,
            appAccountToken: user,
            type: "Auto-Renewable Subscription",
            inAppOwnershipType: "PURCHASED",
            purchaseDate: now.addingTimeInterval(-30 * 86_400),
            expiresDate: now.addingTimeInterval(expiry),
            revocationDate: revoked ? now : nil,
            signedDate: now
        )
    }

    static func snapshot(
        _ transaction: AppStoreTransaction,
        status: Int = 1,
        grace: Date? = nil
    ) -> VerifiedAppStoreSubscription {
        VerifiedAppStoreSubscription(
            transaction: transaction,
            renewal: AppStoreRenewal(
                originalTransactionId: transaction.originalTransactionId,
                appAccountToken: transaction.appAccountToken,
                productId: transaction.productId,
                environment: transaction.environment,
                autoRenewStatus: 1,
                gracePeriodExpiresDate: grace,
                signedDate: transaction.signedDate
            ),
            status: status
        )
    }

    static func notification(transaction: AppStoreTransaction, type: String = "SUBSCRIBED") -> AppStoreNotification {
        AppStoreNotification(
            notificationUUID: UUID(),
            notificationType: type,
            signedDate: transaction.signedDate,
            data: .init(
                bundleId: configuration.bundleID,
                appAppleId: configuration.appAppleID,
                environment: .production,
                signedTransactionInfo: type == "TEST" ? nil : "verified-notification-transaction",
                signedRenewalInfo: nil
            )
        )
    }

    static func withRoutes(
        _ gateway: any AppStoreGateway,
        perform: @Sendable () async throws -> Void
    ) async throws {
        let suppliedDatabases = try testDatabases
        let application = try await Application.make(.testing)
        application.middleware.use(APIErrorMiddleware(), at: .end)
        let authentication = AppleAuthenticationService(
            databases: suppliedDatabases,
            gateway: UnconfiguredAppleGateway(),
            vault: nil
        )
        let service = SubscriptionService(databases: suppliedDatabases, gateway: gateway)
        do {
            try application.register(collection: AppStoreRoutes(service: service, authentication: authentication))
            try application.register(collection: AppleAuthenticationRoutes(service: authentication))
            try application.register(collection: ShoppingRoutes(
                databases: suppliedDatabases,
                authentication: authentication,
                invitationOrigin: "https://links.test"
            ))
            try await application.asyncBoot()
            try await $_application.withValue(application) {
                try await perform()
            }
            try await application.asyncShutdown()
        } catch {
            try await application.asyncShutdown()
            throw error
        }
    }

    static func submit(_ user: ShoppingFixture.User) async throws -> TestingHTTPResponse {
        try await ShoppingFixture.request(
            .POST,
            "/v1/account/subscription/transactions",
            user,
            .object(["signedTransaction": .string("verified-purchase")])
        )
    }

    static func notify() async throws -> TestingHTTPResponse {
        try await app.sendRequest(
            .POST,
            "/v1/app-store/notifications",
            headers: ["Content-Type": "application/json"],
            body: ByteBuffer(bytes: try APIEncoding.data(APIJSON.object([
                "signedPayload": .string("verified-notification")
            ])))
        )
    }

    static func errorCode(_ response: TestingHTTPResponse, status: HTTPStatus) throws -> String {
        try #require(response.status == status)
        return try #require(try ShoppingFixture.object(response)["code"]?.string)
    }

    static func ledger(_ user: ShoppingFixture.User) async throws -> [[String: String]] {
        let sql = try shoppingSQL(database)
        let rows = try await sql.raw("""
            SELECT transaction_id,state,revision::text,verified_at::text FROM app_store_subscriptions
            WHERE user_id = \(bind: user.id) ORDER BY original_transaction_id
            """).all()
        return try rows.map { row in
            [
                "transaction_id": try row.decode(column: "transaction_id", as: String.self),
                "state": try row.decode(column: "state", as: String.self),
                "revision": try row.decode(column: "revision", as: String.self),
                "verified_at": try row.decode(column: "verified_at", as: String.self)
            ]
        }
    }
}
