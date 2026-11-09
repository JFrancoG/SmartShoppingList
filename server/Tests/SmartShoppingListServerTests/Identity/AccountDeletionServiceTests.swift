@testable import SmartShoppingListServer
import Foundation
import FluentKit
import FluentSQL
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test("An accepted deletion survives response loss and signals irreversible deletion to the other devices")
    func deletionCompletesAndRetainsPrivateStatusReceipt() async throws {
        let fixture = try await DeletionServiceFixture.make()
        _ = try await ShoppingFixture.group(fixture.user)
        let preparation = try await fixture.prepare()
        let accepted = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        #expect(try DeletionServiceFixture.fields(accepted)["status"] == .string("accepted"))
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token))
        let rejectedSession = try await ShoppingFixture.request(.GET, "/v1/me", fixture.user)
        #expect(rejectedSession.status == .unauthorized)

        // A new worker models a restarted process; the request and its secret are the only client recovery state.
        let worker = AccountDeletionWorker(service: fixture.service)
        #expect(try await worker.runNext())
        let recovered = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        let status = try DeletionServiceFixture.fields(recovered)
        #expect(status["status"] == .string("completed"))
        #expect(status["appleRevocationOutcome"] == .string("confirmed"))
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token))
        #expect(try await fixture.userExists() == false)
        #expect(await fixture.gateway.revokedTokens() == Set(["existing-refresh", "reauthenticated-refresh"]))
        let sql = try shoppingSQL(database)
        let job = try #require(try await sql.raw("SELECT * FROM account_deletion_jobs").first())
        #expect(try job.decode(column: "subject", as: String?.self) == fixture.user.id.uuidString)
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() == nil)
        try await sql.raw("UPDATE account_deletion_jobs SET completed_at = clock_timestamp() - INTERVAL '6 minutes'").run()
        #expect(try await worker.runNext() == false)
        let cleaned = try #require(try await sql.raw("SELECT subject FROM account_deletion_jobs").first())
        #expect(try cleaned.decode(column: "subject", as: String?.self) == nil)
        await #expect(throws: APIProblem.self) {
            try await fixture.service.status(operation: preparation.operation, secret: IdentitySecrets.generate())
        }
    }

    @Test("Cancelling during Apple reauthentication wins before deletion becomes irreversible")
    func deletionCancellationWinsAgainstInFlightReauthentication() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let preparation = try await fixture.prepare()
        await fixture.gateway.suspendExchange()
        let accepting = Task {
            try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        }
        await fixture.gateway.waitUntilExchangeStarts()
        let cancellation = try await fixture.service.status(
            operation: preparation.operation,
            secret: preparation.secret,
            cancelPrepared: true
        )
        await fixture.gateway.resumeExchange()
        #expect(try DeletionServiceFixture.fields(cancellation)["status"] == .string("cancelled"))
        await #expect(throws: APIProblem.self) { try await accepting.value }
        #expect(try await fixture.userExists())
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token) == false)
        let sql = try shoppingSQL(database)
        let user = try #require(try await sql.raw("""
            SELECT deleting_at FROM users WHERE id = \(bind: fixture.user.id)
            """).first())
        #expect(try user.decode(column: "deleting_at", as: Date?.self) == nil)
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() == nil)
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext() == false)
        let session = try await ShoppingFixture.request(.GET, "/v1/me", fixture.user)
        #expect(session.status == .ok)
    }

    @Test("Cancelling before preparation reaches the server prevents a late preparation from becoming actionable")
    func deletionCancellationBeforePreparationIsDurable() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let operation = UUID()
        let secret = IdentitySecrets.generate()
        let cancelled = try await fixture.service.status(operation: operation, secret: secret, cancelPrepared: true)
        #expect(try DeletionServiceFixture.fields(cancelled)["status"] == .string("cancelled"))
        let impact = try await fixture.service.preview(user: fixture.user.id)
        await #expect {
            try await fixture.service.prepare(user: fixture.user.id, operation: operation, secret: secret, revision: impact.revision)
        } throws: { ($0 as? APIProblem)?.code == "deletion_in_progress" }
        await #expect {
            try await fixture.service.status(operation: operation, secret: IdentitySecrets.generate(), cancelPrepared: true)
        } throws: { ($0 as? APIProblem)?.status == .notFound }
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token) == false)
        #expect(try await fixture.userExists())
        let newPreparation = try await fixture.prepare()
        #expect(newPreparation.operation != operation)
    }

    @Test("An identity from another account consumes the challenge and cannot be replayed with a valid identity")
    func deletionRejectsWrongIdentityAndChallengeReplay() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let preparation = try await fixture.prepare()
        do {
            _ = try await fixture.service.accept(
                user: fixture.user.id,
                body: preparation.body(subject: "another-account")
            )
            Issue.record("A different Apple identity must not authorize deletion")
        } catch let problem as APIProblem {
            #expect(problem.code == "invalid_deletion_proof")
        }
        do {
            _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
            Issue.record("The consumed challenge must not authorize a second request")
        } catch let problem as APIProblem {
            #expect(problem.code == "invalid_deletion_proof")
        }
        #expect(await fixture.gateway.numberOfExchanges() == 0)
        #expect(try await fixture.userExists())
        let replacement = try await fixture.prepare()
        let prior = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(prior)["status"] == .string("cancelled"))
        let accepted = try await fixture.service.accept(user: fixture.user.id, body: replacement.body())
        #expect(try DeletionServiceFixture.fields(accepted)["status"] == .string("accepted"))
    }

    @Test("A changed group invalidates the confirmed impact before any account data is deleted")
    func deletionRejectsChangedImpact() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let group = try await ShoppingFixture.group(fixture.user)
        let preparation = try await fixture.prepare()
        let member = try await ShoppingFixture.user()
        try await ShoppingFixture.join(member, group: group)
        do {
            _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
            Issue.record("Changed group membership must require a new impact confirmation")
        } catch let problem as APIProblem {
            #expect(problem.code == "deletion_impact_changed")
        }
        #expect(try await fixture.userExists())
        let sql = try shoppingSQL(database)
        let user = try #require(try await sql.raw("""
            SELECT deleting_at FROM users WHERE id = \(bind: fixture.user.id)
            """).first())
        #expect(try user.decode(column: "deleting_at", as: Date?.self) == nil)
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() == nil)
    }

    @Test("A failed purge preserves the accepted deletion signal and another worker retries after lease expiry")
    func deletionRetriesFailedPurgeWithoutPartialErasure() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let group = try await ShoppingFixture.group(fixture.user)
        let member = try await ShoppingFixture.user()
        try await ShoppingFixture.join(member, group: group)
        let created = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            fixture.user,
            ShoppingFixture.batch(names: ["Pan"], stores: ["Aldi"])
        )
        try #require(created.status == .created)
        let sql = try shoppingSQL(database)
        // Preserve the other member's quantity, making the production purge redact the owner's name.
        try await sql.raw("""
            UPDATE items SET quantity = '2',quantity_author_user_id = \(bind: member.id)
            WHERE group_id = \(bind: group)::uuid
            """).run()
        try await sql.raw("ALTER TABLE items ADD CONSTRAINT deletion_test_failure CHECK(name <> 'Producto sin nombre')").run()
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        await #expect {
            try await AccountDeletionWorker(service: fixture.service).runNext()
        } throws: { ($0 as? any DatabaseError)?.isConstraintFailure == true }
        #expect(try await fixture.userExists())
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token))
        let row = try #require(try await sql.raw("SELECT name FROM items WHERE group_id = \(bind: group)::uuid").first())
        #expect(try row.decode(column: "name", as: String.self) == "Pan")
        #expect(await fixture.gateway.revokedTokens().isEmpty)
        try await sql.raw("ALTER TABLE items DROP CONSTRAINT deletion_test_failure").run()
        try await sql.raw("UPDATE account_deletion_jobs SET lease_until = clock_timestamp() - INTERVAL '1 second'").run()
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        #expect(try await fixture.userExists() == false)
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token))
        let recovered = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(recovered)["status"] == .string("completed"))
    }

    @Test("Apple outages leave data deleted and retry revocation from durable encrypted material")
    func deletionRetriesAppleRevocationAfterDataErasure() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        await fixture.gateway.setRevocationFailure(true)
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        #expect(try await fixture.userExists() == false)
        #expect(try await fixture.service.deletionAcceptedForSession(fixture.user.token))
        let status = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(status)["status"] == .string("data_deleted"))
        #expect(try DeletionServiceFixture.fields(status)["appleRevocationOutcome"] == .null)
        let sql = try shoppingSQL(database)
        let pending = try #require(try await sql.raw("SELECT subject FROM account_deletion_jobs").first())
        #expect(try pending.decode(column: "subject", as: String?.self) == fixture.user.id.uuidString)
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() != nil)

        await fixture.gateway.setRevocationFailure(false)
        try await sql.raw("UPDATE account_deletion_jobs SET next_attempt_at = clock_timestamp() - INTERVAL '1 second'").run()
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        let retried = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(retried)["status"] == .string("completed"))
        #expect(try DeletionServiceFixture.fields(retried)["appleRevocationOutcome"] == .string("confirmed"))
        #expect(await fixture.gateway.revokedTokens() == Set(["existing-refresh", "reauthenticated-refresh"]))
    }

    @Test("Revocation that remains unavailable after seven days ends with explicit manual action and no identity material")
    func deletionBoundsFailedRevocationRetention() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        await fixture.gateway.setRevocationFailure(true)
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE account_deletion_jobs SET accepted_at = clock_timestamp() - INTERVAL '8 days'").run()
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        let result = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(result)["status"] == .string("completed"))
        #expect(try DeletionServiceFixture.fields(result)["appleRevocationOutcome"] == .string("manual_action_required"))
        #expect(try await fixture.userExists() == false)
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() == nil)
        try await sql.raw("UPDATE account_deletion_jobs SET completed_at = clock_timestamp() - INTERVAL '6 minutes'").run()
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext() == false)
        let job = try #require(try await sql.raw("SELECT subject FROM account_deletion_jobs").first())
        #expect(try job.decode(column: "subject", as: String?.self) == nil)
        #expect(await fixture.gateway.revokedTokens().isEmpty)
    }

    @Test("A crash after the final Apple confirmation preserves the successful revocation checkpoint")
    func deletionResumesFinalRevocationCheckpoint() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        await fixture.gateway.setRevocationFailure(true)
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        let sql = try shoppingSQL(database)
        // This is the durable state after the last revocation commits, before the final job update.
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("DELETE FROM account_deletion_tokens").run()
            try await sql.raw("""
                UPDATE account_deletion_jobs SET apple_outcome = 'confirmed',
                    next_attempt_at = clock_timestamp() - INTERVAL '1 second'
                """).run()
        }
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        let result = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(result)["status"] == .string("completed"))
        #expect(try DeletionServiceFixture.fields(result)["appleRevocationOutcome"] == .string("confirmed"))
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() == nil)
    }

    @Test("A pending group remains readable and purchasable, and only one concurrent member claims administration")
    func deletionPendingGroupAccessAndConcurrentAdministrationClaim() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let first = try await ShoppingFixture.user()
        let second = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(fixture.user)
        try await ShoppingFixture.join(first, group: group)
        try await ShoppingFixture.join(second, group: group)
        let created = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            first,
            ShoppingFixture.batch(names: ["Leche"], stores: ["Aldi"])
        )
        try #require(created.status == .created)
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        let listed = try await ShoppingFixture.request(.GET, "/v1/groups", first)
        try #require(listed.status == .ok)
        guard case .array(let groups) = try ShoppingFixture.object(listed)["data"],
              case .object(let pendingGroup) = groups.first else { throw APIProblem.invalidRequest }
        #expect(pendingGroup["state"] == .string("pending_administration"))
        #expect(pendingGroup["creatorUserId"] == .null)
        #expect(pendingGroup["administratorUserId"] == .null)
        let account = try await ShoppingFixture.request(.GET, "/v1/me", first)
        try #require(account.status == .ok)
        guard case .object(let projected) = try ShoppingFixture.object(account)["group"] else {
            throw APIProblem.invalidRequest
        }
        #expect(projected["state"] == .string("pending_administration"))
        let administration = try await AdministrationFixture.snapshot(first, group: group)
        guard case .object(let capabilities) = administration["capabilities"] else { throw APIProblem.invalidRequest }
        #expect(capabilities["canClaimAdministration"] == .bool(true))
        let addition = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            first,
            ShoppingFixture.batch(names: ["Pan"], stores: ["Aldi"])
        )
        #expect(addition.status == .conflict)
        #expect(try ShoppingFixture.object(addition)["code"] == .string("administration_pending"))
        let sql = try shoppingSQL(database)
        let item = try #require(try await sql.raw("SELECT id,store_id FROM items WHERE group_id = \(bind: group)::uuid").first())
        let itemID = try item.decode(column: "id", as: UUID.self).uuidString.lowercased()
        let storeID = try item.decode(column: "store_id", as: UUID.self).uuidString.lowercased()
        let purchase = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/purchases",
            first,
            PurchaseFixture.body(store: storeID, ids: [itemID])
        )
        #expect(purchase.status == .ok)

        async let firstClaim = ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-claim",
            first,
            AdministrationFixture.operation()
        )
        async let secondClaim = ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/administration-claim",
            second,
            AdministrationFixture.operation()
        )
        let claims = try await [firstClaim, secondClaim]
        #expect(claims.filter { $0.status == .ok }.count == 1)
        #expect(claims.filter { $0.status == .conflict }.count == 1)
        let denied = try #require(claims.first { $0.status == .conflict })
        #expect(try ShoppingFixture.object(denied)["code"] == .string("administration_already_assigned"))
        let groupRow = try #require(try await sql.raw("SELECT * FROM groups WHERE id = \(bind: group)::uuid").first())
        let administrator = try groupRow.decode(column: "administrator_user_id", as: UUID.self)
        #expect([first.id, second.id].contains(administrator))
        #expect(try groupRow.decode(column: "pending_administration", as: Bool.self) == false)
    }

    @Test("The last member's departure purges a pending group and an exact retry returns its committed result")
    func deletionPendingGroupFinalDepartureIsRecoverable() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let remaining = try await ShoppingFixture.user()
        let group = try await ShoppingFixture.group(fixture.user)
        try await ShoppingFixture.join(remaining, group: group)
        let addition = try await ShoppingFixture.request(
            .POST,
            "/v1/groups/\(group)/item-batches",
            remaining,
            ShoppingFixture.batch(names: ["Leche"], stores: ["Aldi"])
        )
        try #require(addition.status == .created)
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        let departure = AdministrationFixture.departureBody(confirmClosure: true)
        let path = "/v1/groups/\(group)/departure"
        let first = try await ShoppingFixture.request(.POST, path, remaining, departure)
        try #require(first.status == .ok)
        let retry = try await ShoppingFixture.request(.POST, path, remaining, departure)
        #expect(retry.status == .ok)
        #expect(retry.body.string == first.body.string)
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT 1 FROM groups WHERE id = \(bind: group)::uuid").first() == nil)
        #expect(try await sql.raw("SELECT 1 FROM items WHERE group_id = \(bind: group)::uuid").first() == nil)
        #expect(try await sql.raw("SELECT 1 FROM stores WHERE group_id = \(bind: group)::uuid").first() == nil)
        let active = try await ShoppingFixture.request(.GET, "/v1/me", remaining)
        #expect(active.status == .ok)
    }

    @Test("A concurrent Apple refresh cannot outrun deletion or restore an active grant", arguments: [false, true])
    func deletionWaitsForTokenRotationOrReportsAnExpiredValidation(expireLease: Bool) async throws {
        let fixture = try await DeletionServiceFixture.make()
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE apple_grants SET last_validated_at = clock_timestamp() - INTERVAL '25 hours'").run()
        let authentication = try AppleAuthenticationService(
            databases: testDatabases,
            gateway: fixture.gateway,
            vault: fixture.service.vault
        )
        await fixture.gateway.suspendValidation()
        let revalidating = Task { try await authentication.authenticate(fixture.authenticatedRequest()) }
        await fixture.gateway.waitUntilValidationStarts()
        // A second service models another server process, bypassing the in-process coordinator.
        let otherProcess = try AppleAuthenticationService(
            databases: testDatabases,
            gateway: fixture.gateway,
            vault: fixture.service.vault
        )
        await #expect {
            try await otherProcess.authenticate(fixture.authenticatedRequest())
        } throws: { ($0 as? APIProblem)?.status == .serviceUnavailable }
        #expect(await fixture.gateway.numberOfValidations() == 1)

        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        #expect(try await fixture.userExists())
        #expect(await fixture.gateway.revokedTokens().isEmpty)
        if expireLease {
            try await sql.raw("""
                UPDATE apple_grants SET validation_deadline = clock_timestamp() - INTERVAL '1 second'
                WHERE validation_id IS NOT NULL
                """).run()
            try await sql.raw("UPDATE account_deletion_jobs SET next_attempt_at = clock_timestamp() - INTERVAL '1 second'").run()
            #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
            #expect(try await fixture.userExists() == false)
        }
        await fixture.gateway.resumeValidation()
        await #expect {
            try await revalidating.value
        } throws: { ($0 as? APIProblem)?.status == .unauthorized }
        if !expireLease {
            #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        }
        let result = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        #expect(try DeletionServiceFixture.fields(result)["status"] == .string("completed"))
        let expected = expireLease ? "manual_action_required" : "confirmed"
        #expect(try DeletionServiceFixture.fields(result)["appleRevocationOutcome"] == .string(expected))
        #expect(try await fixture.userExists() == false)
        #expect(try await sql.raw("SELECT 1 FROM apple_grants").first() == nil)
        #expect(try await sql.raw("SELECT 1 FROM account_deletion_tokens").first() == nil)
        #expect(await fixture.gateway.revokedTokens().contains("rotated-refresh"))
    }

    @Test("An in-flight login cannot recreate the deleted account", arguments: [false, true])
    func deletionCoordinatesAnExistingLoginExchange(expireLease: Bool) async throws {
        let fixture = try await DeletionServiceFixture.make()
        let authentication = try fixture.authentication()
        let challenge = try await authentication.createChallenge()
        await fixture.gateway.suspendExchange()
        let login = Task { try await authentication.login(fixture.loginRequest(challenge)) }
        await fixture.gateway.waitUntilExchangeStarts()
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        #expect(try await fixture.userExists())
        let sql = try shoppingSQL(database)
        if expireLease {
            try await sql.raw("""
                UPDATE auth_challenges SET login_exchange_deadline = clock_timestamp() - INTERVAL '1 second'
                WHERE login_exchange_pending
                """).run()
            try await sql.raw("UPDATE account_deletion_jobs SET next_attempt_at = clock_timestamp() - INTERVAL '1 second'").run()
            #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        }
        await fixture.gateway.resumeExchange()
        await #expect {
            try await login.value
        } throws: { ($0 as? APIProblem)?.code == "deletion_in_progress" }
        if !expireLease {
            #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        }
        #expect(try await sql.raw("SELECT 1 FROM users").first() == nil)
        #expect(try await sql.raw("SELECT 1 FROM apple_grants").first() == nil)
        #expect(await fixture.gateway.revokedTokens().contains("login-refresh"))
        let result = try await fixture.service.status(operation: preparation.operation, secret: preparation.secret)
        let expected = expireLease ? "manual_action_required" : "confirmed"
        #expect(try DeletionServiceFixture.fields(result)["status"] == .string("completed"))
        #expect(try DeletionServiceFixture.fields(result)["appleRevocationOutcome"] == .string(expected))
    }

    @Test("An old login awaiting identity verification is fenced, while a new explicit signup is allowed")
    func deletionFencesLoginBeforeItsIdentityWasVerified() async throws {
        let fixture = try await DeletionServiceFixture.make()
        let authentication = try fixture.authentication()
        let oldChallenge = try await authentication.createChallenge()
        await fixture.gateway.suspendVerification()
        let login = Task { try await authentication.login(fixture.loginRequest(oldChallenge)) }
        await fixture.gateway.waitUntilVerificationStarts()
        let preparation = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: preparation.body())
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        await fixture.gateway.resumeVerification()
        await #expect {
            try await login.value
        } throws: { ($0 as? APIProblem)?.code == "deletion_in_progress" }
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT 1 FROM users").first() == nil)
        #expect(await fixture.gateway.numberOfExchanges() == 1)
        let newChallenge = try await authentication.createChallenge()
        _ = try await authentication.login(fixture.loginRequest(newChallenge))
        let newUser = try #require(try await sql.raw("SELECT id FROM users").first())
        #expect(try newUser.decode(column: "id", as: UUID.self) != fixture.user.id)
    }

    @Test("A cancelled reauthentication remains part of a later accepted deletion", arguments: [false, true])
    func deletionCapturesRefreshFromCancelledPreparation(expireLease: Bool) async throws {
        let fixture = try await DeletionServiceFixture.make()
        let first = try await fixture.prepare()
        await fixture.gateway.suspendExchange()
        let cancelledAccept = Task { try await fixture.service.accept(user: fixture.user.id, body: first.body()) }
        await fixture.gateway.waitUntilExchangeStarts()
        _ = try await fixture.service.status(operation: first.operation, secret: first.secret, cancelPrepared: true)
        let replacement = try await fixture.prepare()
        _ = try await fixture.service.accept(user: fixture.user.id, body: replacement.body())
        #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        #expect(try await fixture.userExists())
        let sql = try shoppingSQL(database)
        if expireLease {
            try await sql.raw("""
                UPDATE auth_challenges SET login_exchange_deadline = clock_timestamp() - INTERVAL '1 second'
                WHERE login_exchange_pending
                """).run()
            try await sql.raw("UPDATE account_deletion_jobs SET next_attempt_at = clock_timestamp() - INTERVAL '1 second'").run()
            #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        }
        await fixture.gateway.resumeExchange()
        await #expect(throws: APIProblem.self) { try await cancelledAccept.value }
        if !expireLease {
            #expect(try await AccountDeletionWorker(service: fixture.service).runNext())
        }
        #expect(try await fixture.userExists() == false)
        #expect(await fixture.gateway.numberOfRevocations() == 3)
        let result = try await fixture.service.status(operation: replacement.operation, secret: replacement.secret)
        let expected = expireLease ? "manual_action_required" : "confirmed"
        #expect(try DeletionServiceFixture.fields(result)["status"] == .string("completed"))
        #expect(try DeletionServiceFixture.fields(result)["appleRevocationOutcome"] == .string(expected))
    }
}

struct AccountDeletionClientContractTests {
    @Test("Clients must explicitly support the deletion contract; Apple notifications remain independent")
    func enforcesClientContractWithoutBlockingAppleNotifications() async throws {
        let application = try await Application.make(.testing)
        application.middleware.use(ClientContractMiddleware())
        application.get("v1", "fixture") { _ in "compatible client" }
        application.post("v1", "app-store", "notifications") { _ in "notification reached handler" }
        do {
            try await application.asyncBoot()
            for header in [nil, "0.5", "0.6, 0.5"] as [String?] {
                let headers: HTTPHeaders = header.map { ["X-SmartList-Contract": $0] } ?? [:]
                let response = try await application.sendRequest(.GET, "/v1/fixture", headers: headers)
                #expect(response.status == .upgradeRequired)
                #expect(try ShoppingFixture.object(response)["code"] == .string("client_update_required"))
            }
            let current = try await application.sendRequest(
                .GET,
                "/v1/fixture",
                headers: ["X-SmartList-Contract": "0.6"]
            )
            #expect(current.status == .ok)
            #expect(current.body.string == "compatible client")
            let notification = try await application.sendRequest(.POST, "/v1/app-store/notifications")
            #expect(notification.status == .ok)
            #expect(notification.body.string == "notification reached handler")
        } catch {
            try await application.asyncShutdown()
            throw error
        }
        try await application.asyncShutdown()
    }
}

private struct DeletionServiceFixture: Sendable {
    let user: ShoppingFixture.User
    let service: AccountDeletionService
    let gateway: DeletionAppleGateway

    struct Preparation: Sendable {
        let operation: UUID
        let secret: String
        let revision: String
        let challenge: String
        let nonce: String
        let subject: String

        func body(subject override: String? = nil) throws -> APIObject {
            let token = "\(override ?? subject)|\(nonce)"
            let fields: [String: APIJSON] = [
                "operationId": .string(operation.uuidString.lowercased()), "statusSecret": .string(secret),
                "revision": .string(revision), "challengeId": .string(challenge),
                "identityToken": .string(token), "authorizationCode": .string(token)
            ]
            return try APIObject(.object(fields), allowed: Set(fields.keys), required: Set(fields.keys))
        }
    }

    static func make() async throws -> Self {
        let user = try await ShoppingFixture.user()
        let gateway = DeletionAppleGateway()
        let vault = try RefreshTokenVault(activeVersion: "test", keyData: ["test": Data(repeating: 7, count: 32)])
        let sql = try shoppingSQL(database)
        let grants = try await sql.raw("SELECT id FROM apple_grants WHERE user_id = \(bind: user.id)").all()
        for row in grants {
            let grant = try row.decode(column: "id", as: UUID.self)
            let token = try vault.seal("existing-refresh", grantID: grant)
            try await sql.raw("""
                UPDATE apple_grants SET encrypted_refresh_token = \(bind: token.ciphertext),key_version = \(bind: token.keyVersion)
                WHERE id = \(bind: grant)
                """).run()
        }
        let service = try AccountDeletionService(databases: testDatabases, gateway: gateway, vault: vault)
        return Self(user: user, service: service, gateway: gateway)
    }

    func prepare() async throws -> Preparation {
        let impact = try await service.preview(user: user.id)
        let operation = UUID()
        let secret = IdentitySecrets.generate()
        let challenge = try await service.prepare(
            user: user.id,
            operation: operation,
            secret: secret,
            revision: impact.revision
        )
        let result = try Self.fields(challenge)
        return Preparation(
            operation: operation,
            secret: secret,
            revision: impact.revision,
            challenge: try #require(result["id"]?.string),
            nonce: try #require(result["nonce"]?.string),
            subject: user.id.uuidString
        )
    }

    func userExists() async throws -> Bool {
        let sql = try shoppingSQL(database)
        return try await sql.raw("SELECT 1 FROM users WHERE id = \(bind: user.id)").first() != nil
    }

    func authenticatedRequest() throws -> Request {
        try Request(
            application: app,
            method: .GET,
            url: "/v1/me",
            headers: ["Authorization": "Bearer \(user.token)"],
            on: app.eventLoopGroup.any()
        )
    }

    func authentication() throws -> AppleAuthenticationService {
        try AppleAuthenticationService(databases: testDatabases, gateway: gateway, vault: service.vault)
    }

    func loginRequest(_ challenge: APIJSON) throws -> Request {
        let fields = try Self.fields(challenge)
        let nonce = try #require(fields["nonce"]?.string)
        let token = "\(user.id.uuidString)|\(nonce)"
        let body: APIJSON = .object([
            "challengeId": try #require(fields["id"]), "identityToken": .string(token),
            "authorizationCode": .string("login:" + token)
        ])
        return try Request(
            application: app,
            method: .POST,
            url: "/v1/auth/apple",
            headers: ["Content-Type": "application/json"],
            collectedBody: ByteBuffer(bytes: APIEncoding.data(body)),
            on: app.eventLoopGroup.any()
        )
    }

    static func fields(_ json: APIJSON) throws -> [String: APIJSON] {
        guard case .object(let fields) = json else { throw APIProblem.invalidRequest }
        return fields
    }
}

private actor DeletionAppleGateway: AppleGateway {
    private var exchangeSuspended = false
    private var exchangeStarted = false
    private var exchangeWaiters: [CheckedContinuation<Void, Never>] = []
    private var exchangeContinuation: CheckedContinuation<Void, Never>?
    private var exchanges = 0
    private var revocationFails = false
    private var revoked: Set<String> = []
    private var validationStarted = false
    private var validationSuspended = false
    private var validationWaiters: [CheckedContinuation<Void, Never>] = []
    private var validationContinuation: CheckedContinuation<Void, Never>?
    private var validations = 0
    private var revocations = 0
    private var verificationStarted = false
    private var verificationSuspended = false
    private var verificationWaiters: [CheckedContinuation<Void, Never>] = []
    private var verificationContinuation: CheckedContinuation<Void, Never>?

    func verifyIdentityToken(_ token: String, nonce: String) async throws -> String {
        if verificationSuspended {
            verificationSuspended = false
            verificationStarted = true
            for waiter in verificationWaiters {
                waiter.resume()
            }
            verificationWaiters.removeAll()
            await withCheckedContinuation { verificationContinuation = $0 }
        }
        let parts = token.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == nonce else { throw AppleGatewayError.rejected }
        return String(parts[0])
    }

    func exchange(code: String) async throws -> AppleTokenResponse {
        exchanges += 1
        exchangeStarted = true
        for waiter in exchangeWaiters {
            waiter.resume()
        }
        exchangeWaiters.removeAll()
        if exchangeSuspended {
            exchangeSuspended = false
            await withCheckedContinuation { exchangeContinuation = $0 }
        }
        let login = code.hasPrefix("login:")
        return AppleTokenResponse(
            identityToken: login ? String(code.dropFirst(6)) : code,
            refreshToken: login ? "login-refresh" : "reauthenticated-refresh"
        )
    }

    func validate(refreshToken: String) async throws -> AppleTokenResponse {
        validations += 1
        validationStarted = true
        for waiter in validationWaiters {
            waiter.resume()
        }
        validationWaiters.removeAll()
        if validationSuspended {
            await withCheckedContinuation { validationContinuation = $0 }
        }
        return AppleTokenResponse(identityToken: nil, refreshToken: "rotated-refresh")
    }

    func revoke(refreshToken: String) async throws {
        revocations += 1
        guard !revocationFails else { throw AppleGatewayError.unavailable }
        revoked.insert(refreshToken)
    }

    func suspendExchange() { exchangeSuspended = true }

    func waitUntilExchangeStarts() async {
        guard !exchangeStarted else { return }
        await withCheckedContinuation { exchangeWaiters.append($0) }
    }

    func resumeExchange() {
        exchangeSuspended = false
        exchangeContinuation?.resume()
        exchangeContinuation = nil
    }

    func setRevocationFailure(_ fails: Bool) { revocationFails = fails }
    func numberOfExchanges() -> Int { exchanges }
    func revokedTokens() -> Set<String> { revoked }
    func numberOfValidations() -> Int { validations }
    func numberOfRevocations() -> Int { revocations }
    func suspendValidation() { validationSuspended = true }
    func suspendVerification() { verificationSuspended = true }

    func waitUntilVerificationStarts() async {
        guard !verificationStarted else { return }
        await withCheckedContinuation { verificationWaiters.append($0) }
    }

    func resumeVerification() {
        verificationContinuation?.resume()
        verificationContinuation = nil
    }

    func waitUntilValidationStarts() async {
        guard !validationStarted else { return }
        await withCheckedContinuation { validationWaiters.append($0) }
    }

    func resumeValidation() {
        validationSuspended = false
        validationContinuation?.resume()
        validationContinuation = nil
    }
}
