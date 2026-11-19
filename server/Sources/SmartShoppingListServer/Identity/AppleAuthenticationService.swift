import Foundation
import FluentKit
import FluentSQL
import Vapor

protocol SessionAuthenticating: Sendable {
    func authenticate(_ request: Request) async throws -> UUID
}

/// PostgreSQL owns sessions and one-time challenge transitions; no database transaction spans an Apple request.
struct AppleAuthenticationService: SessionAuthenticating, Sendable {
    let databases: Databases
    let gateway: any AppleGateway
    let vault: RefreshTokenVault?
    let accountCapacity: AccountCapacityPolicy
    private let validation = GrantValidationCoordinator()

    init(
        databases: Databases,
        gateway: any AppleGateway,
        vault: RefreshTokenVault?,
        accountCapacity: AccountCapacityPolicy = .init()
    ) {
        self.databases = databases
        self.gateway = gateway
        self.vault = vault
        self.accountCapacity = accountCapacity
    }

    func createChallenge() async throws -> APIJSON {
        try await databases.database().accountTransaction { database in
            let sql = try shoppingSQL(database)
            // Expired exchanges may have created a token even when their response was lost.
            try await sql.raw("""
                UPDATE apple_grants SET validation_uncertain = TRUE WHERE user_id IN (
                    SELECT users.id FROM users JOIN auth_challenges ON users.apple_subject = auth_challenges.login_subject
                    WHERE auth_challenges.expires_at <= clock_timestamp() AND login_exchange_pending)
                """).run()
            // A deletion worker owns its linked exchanges until their uncertainty has been checkpointed.
            try await sql.raw("""
                DELETE FROM auth_challenges WHERE expires_at <= clock_timestamp() AND login_deletion_job_id IS NULL
                """).run()
            let id = UUID()
            let nonce = IdentitySecrets.generate()
            guard let row = try await sql.raw("""
                INSERT INTO auth_challenges (id, nonce, expires_at)
                VALUES (\(bind: id), \(bind: nonce), clock_timestamp() + INTERVAL '5 minutes')
                RETURNING expires_at
                """).first() else { throw APIProblem.unavailable }
            let expires = try row.decode(column: "expires_at", as: Date.self)
            return .object([
                "id": .string(id.uuidString.lowercased()), "nonce": .string(nonce),
                "expiresAt": .string(APIEncoding.timestamp(expires))
            ])
        }
    }

    func login(_ request: Request) async throws -> APIJSON {
        let input = try AppleLoginInput(request)
        let database = try databases.database()
        let sql = try shoppingSQL(database)
        let nonce = try await claimChallenge(input.challengeID, sql: sql)
        // Claim removes nonce from storage immediately; a crash or failed exchange cannot make it reusable.
        let completion: LoginCompletion
        var verifiedRefresh: String?
        do {
            guard let vault else { throw APIProblem.unavailable }
            let subject = try await gateway.verifyIdentityToken(input.identityToken, nonce: nonce)
            let existingUser = try await bindLoginExchange(challenge: input.challengeID, subject: subject)
            let tokens = try await gateway.exchange(code: input.authorizationCode)
            guard let exchangeToken = tokens.identityToken, let refresh = tokens.refreshToken, !refresh.isEmpty else {
                throw AppleGatewayError.rejected
            }
            let exchangedSubject = try await gateway.verifyIdentityToken(exchangeToken, nonce: nonce)
            guard exchangedSubject == subject else { throw AppleGatewayError.rejected }
            verifiedRefresh = refresh
            let grantID = UUID()
            let encrypted = try vault.seal(refresh, grantID: grantID)
            let bearer = IdentitySecrets.generate()
            let hash = IdentitySecrets.hash(bearer)
            completion = try await database.accountTransaction { database -> LoginCompletion in
                let sql = try shoppingSQL(database)
                let disposition = try await authorizeLoginCompletion(
                    challenge: input.challengeID,
                    subject: subject,
                    existingUser: existingUser,
                    grant: grantID,
                    encrypted: encrypted,
                    on: sql
                )
                switch disposition {
                case .deleting: return .deleting
                case .late: return .late
                case .active: break
                }
                let newUserID = UUID()
                guard let userRow = try await sql.raw("""
                    INSERT INTO users (id, apple_subject, display_name)
                    VALUES (\(bind: newUserID), \(bind: subject), \(bind: input.displayName))
                    ON CONFLICT (apple_subject) DO UPDATE
                    SET display_name = COALESCE(EXCLUDED.display_name, users.display_name)
                    WHERE users.deleting_at IS NULL
                    RETURNING id
                    """).first()
                else {
                    throw APIProblem.unavailable
                }
                let userID = try userRow.decode(column: "id", as: UUID.self)
                try await sql.raw("""
                    INSERT INTO apple_grants
                        (id, user_id, encrypted_refresh_token, key_version, last_validated_at)
                    VALUES
                        (\(bind: grantID), \(bind: userID), \(bind: encrypted.ciphertext),
                         \(bind: encrypted.keyVersion), clock_timestamp())
                    """).run()
                guard let sessionRow = try await sql.raw("""
                    INSERT INTO app_sessions (id, user_id, apple_grant_id, token_hash, expires_at)
                    VALUES (\(bind: UUID()), \(bind: userID), \(bind: grantID), \(bind: hash),
                            clock_timestamp() + INTERVAL '30 days')
                    RETURNING expires_at
                    """).first()
                else {
                    throw APIProblem.unavailable
                }
                let expires = try sessionRow.decode(column: "expires_at", as: Date.self)
                let user = try await loadShoppingUser(id: userID, on: database, capacity: accountCapacity)
                let userJSON = try JSONDecoder().decode(APIJSON.self, from: APIEncoding.data(user))
                try await sql.raw("""
                    UPDATE auth_challenges SET consumed_at = clock_timestamp(),nonce = NULL,login_subject = NULL,
                        login_exchange_pending = FALSE,login_exchange_deadline = NULL WHERE id = \(bind: input.challengeID)
                    """).run()
                return .authenticated(.object([
                    "accessToken": .string(bearer), "tokenType": .string("Bearer"),
                    "expiresAt": .string(APIEncoding.timestamp(expires)), "user": userJSON
                ]))
            }
        } catch {
            // A failed final commit retains uncertainty; never silently discard an exchange that may have issued a token.
            try? await failLoginExchange(input.challengeID)
            try? await consumeChallenge(input.challengeID, sql: sql)
            if let problem = error as? APIProblem {
                throw problem
            }
            if let error = error as? AppleGatewayError, error == .rejected || error == .invalidGrant {
                throw APIProblem(
                    status: .unauthorized,
                    code: "invalid_apple_credentials",
                    message: "No se ha podido verificar el acceso con Apple."
                )
            }
            throw APIProblem.unavailable
        }
        switch completion {
        case .authenticated(let result):
            return result
        case .deleting:
            throw AccountDeletionService.inProgress
        case .late:
            if let verifiedRefresh {
                try? await gateway.revoke(refreshToken: verifiedRefresh)
            }
            throw AccountDeletionService.inProgress
        }
    }

    private func bindLoginExchange(challenge: UUID, subject: String) async throws -> UUID? {
        try await databases.database().accountTransaction { database in
            let sql = try shoppingSQL(database)
            guard try await sql.raw("""
                SELECT 1 FROM account_deletion_jobs JOIN auth_challenges ON auth_challenges.id = \(bind: challenge)
                WHERE subject = \(bind: subject) AND (state IN ('accepted','purging','data_deleted')
                    OR (state = 'completed' AND completed_at >= auth_challenges.created_at)) LIMIT 1
                """).first() == nil else { throw AccountDeletionService.inProgress }
            let user = try await sql.raw("SELECT id,deleting_at FROM users WHERE apple_subject = \(bind: subject)").first()
            guard try user?.decode(column: "deleting_at", as: Date?.self) == nil else {
                throw AccountDeletionService.inProgress
            }
            guard try await sql.raw("""
                UPDATE auth_challenges SET login_subject = \(bind: subject),login_exchange_pending = TRUE,
                    login_exchange_deadline = clock_timestamp() + INTERVAL '1 minute'
                WHERE id = \(bind: challenge) AND claimed_at IS NOT NULL AND consumed_at IS NULL
                    AND expires_at > clock_timestamp() AND NOT login_exchange_pending RETURNING id
                """).first() != nil else { throw AppleGatewayError.rejected }
            return try user?.decode(column: "id", as: UUID.self)
        }
    }

    private func authorizeLoginCompletion(
        challenge: UUID,
        subject: String,
        existingUser: UUID?,
        grant: UUID,
        encrypted: RefreshTokenVault.SealedToken,
        on sql: any SQLDatabase
    ) async throws -> ValidationOutcome {
        guard let row = try await sql.raw("SELECT * FROM auth_challenges WHERE id = \(bind: challenge) FOR UPDATE").first() else {
            return .late
        }
        let deadline = try row.decode(column: "login_exchange_deadline", as: Date?.self)
        let now = try await databaseClock(sql)
        let pending = try row.decode(column: "login_exchange_pending", as: Bool.self)
        let timely = pending && deadline.map { $0 > now } == true
        if let jobID = try row.decode(column: "login_deletion_job_id", as: UUID?.self),
           try await sql.raw("""
            SELECT 1 FROM account_deletion_jobs WHERE id = \(bind: jobID)
                AND state IN ('accepted','purging','data_deleted') FOR UPDATE
            """).first() != nil {
            try await sql.raw("""
                INSERT INTO account_deletion_tokens(job_id,grant_id,ciphertext,key_version)
                VALUES(\(bind: jobID),\(bind: grant),\(bind: encrypted.ciphertext),\(bind: encrypted.keyVersion))
                """).run()
            try await sql.raw("""
                UPDATE account_deletion_jobs SET apple_requires_manual = apple_requires_manual OR \(bind: !timely),
                    next_attempt_at = clock_timestamp() WHERE id = \(bind: jobID)
                """).run()
            try await endLoginExchange(challenge, on: sql)
            return .deleting
        }
        let currentUser = try await sql.raw("""
            SELECT id FROM users WHERE apple_subject = \(bind: subject) AND deleting_at IS NULL
            """).first()?.decode(column: "id", as: UUID.self)
        if timely, try row.decode(column: "login_subject", as: String?.self) == subject,
           try row.decode(column: "consumed_at", as: Date?.self) == nil,
           try row.decode(column: "expires_at", as: Date.self) > now,
           existingUser == nil || existingUser == currentUser {
            return .active
        }
        try await sql.raw("""
            UPDATE apple_grants SET validation_uncertain = TRUE WHERE user_id IN (
                SELECT id FROM users WHERE apple_subject = \(bind: subject))
            """).run()
        try await endLoginExchange(challenge, on: sql)
        return .late
    }

    private func endLoginExchange(_ challenge: UUID, on sql: any SQLDatabase) async throws {
        try await IdentityExchangeLedger.end(challenge, on: sql)
    }

    private func failLoginExchange(_ challenge: UUID) async throws {
        try await databases.database().accountTransaction { database in
            try await IdentityExchangeLedger.fail(challenge, on: shoppingSQL(database))
        }
    }

    func authenticate(_ request: Request) async throws -> UUID {
        let hash = IdentitySecrets.hash(try Self.bearer(in: request))
        let sql = try shoppingSQL(databases.database())
        let session = try await activeSession(hash: hash, sql: sql)
        if session.requiresValidation {
            try await validation.check(grantID: session.grantID) {
                try await revalidate(grantID: session.grantID)
            }
        }
        // Re-read after external work: a concurrent logout or invalid_grant must take effect immediately.
        return try await activeSession(hash: hash, sql: sql).userID
    }

    func logout(_ request: Request) async throws {
        let hash = IdentitySecrets.hash(try Self.bearer(in: request))
        let sql = try shoppingSQL(databases.database())
        try await sql.raw("""
            UPDATE app_sessions SET revoked_at = COALESCE(revoked_at, clock_timestamp())
            WHERE token_hash = \(bind: hash)
            """).run()
    }

    private func claimChallenge(_ id: UUID, sql: any SQLDatabase) async throws -> String {
        // Return the old nonce through a CTE while deleting it in the same atomic transition.
        if let row = try await sql.raw("""
            WITH candidate AS (
                SELECT id, nonce FROM auth_challenges
                WHERE id = \(bind: id) FOR UPDATE
            )
            UPDATE auth_challenges AS challenge
            SET claimed_at = clock_timestamp(), nonce = NULL
            FROM candidate
            WHERE challenge.id = candidate.id AND challenge.claimed_at IS NULL
                AND challenge.expires_at > clock_timestamp() AND candidate.nonce IS NOT NULL
            RETURNING candidate.nonce
            """).first()
        {
            return try row.decode(column: "nonce", as: String.self)
        }
        if let row = try await sql.raw("""
            SELECT claimed_at IS NOT NULL AS claimed FROM auth_challenges WHERE id = \(bind: id)
            """).first(), try row.decode(column: "claimed", as: Bool.self)
        {
            throw APIProblem(status: .conflict, code: "challenge_consumed", message: "Inicia otro acceso con Apple.")
        }
        throw APIProblem(status: .unauthorized, code: "challenge_expired", message: "Inicia otro acceso con Apple.")
    }

    private func consumeChallenge(_ id: UUID, sql: any SQLDatabase) async throws {
        try await sql.raw("""
            UPDATE auth_challenges SET consumed_at = clock_timestamp(),nonce = NULL,
                login_subject = CASE WHEN login_exchange_pending THEN login_subject ELSE NULL END WHERE id = \(bind: id)
            """).run()
    }

    private func activeSession(hash: String, sql: any SQLDatabase) async throws -> ActiveSession {
        guard let row = try await sql.raw("""
            SELECT session.user_id, session.apple_grant_id,
                concession.last_validated_at <= clock_timestamp() - INTERVAL '24 hours' AS requires_validation
            FROM app_sessions AS session JOIN apple_grants AS concession ON session.apple_grant_id = concession.id
            JOIN users ON users.id = session.user_id AND users.deleting_at IS NULL
            WHERE session.token_hash = \(bind: hash) AND session.revoked_at IS NULL
                AND session.expires_at > clock_timestamp() AND concession.revoked_at IS NULL
                AND session.user_id = concession.user_id
            """).first()
        else {
            throw Self.unauthorized
        }
        return try ActiveSession(
            userID: row.decode(column: "user_id", as: UUID.self),
            grantID: row.decode(column: "apple_grant_id", as: UUID.self),
            requiresValidation: row.decode(column: "requires_validation", as: Bool.self)
        )
    }

    private func revalidate(grantID: UUID) async throws {
        guard let vault else { throw APIProblem.unavailable }
        guard let attempt = try await beginValidation(grantID: grantID) else { return }
        let refreshed: String
        do {
            let token = try vault.open(attempt.ciphertext, keyVersion: attempt.keyVersion, grantID: grantID)
            let response = try await gateway.validate(refreshToken: token)
            refreshed = response.refreshToken ?? token
        } catch AppleGatewayError.invalidGrant {
            try await finishFailedValidation(attempt, invalidGrant: true)
            throw Self.unauthorized
        } catch {
            try await finishFailedValidation(attempt, invalidGrant: false)
            throw APIProblem.unavailable
        }
        guard !refreshed.isEmpty else {
            try await finishFailedValidation(attempt, invalidGrant: false)
            throw APIProblem.unavailable
        }
        switch try await finishValidation(attempt, refreshToken: refreshed, vault: vault) {
        case .active:
            return
        case .deleting:
            throw Self.unauthorized
        case .late:
            // Its durable marker already requires manual action. A late response cannot reopen the job or account.
            try? await gateway.revoke(refreshToken: refreshed)
            throw Self.unauthorized
        }
    }

    private func beginValidation(grantID: UUID) async throws -> ValidationAttempt? {
        try await databases.database().accountTransaction { database in
            let sql = try shoppingSQL(database)
            guard let row = try await sql.raw("""
                SELECT concession.*,concession.last_validated_at > clock_timestamp() - INTERVAL '24 hours' AS fresh
                FROM apple_grants AS concession JOIN users ON users.id = concession.user_id
                WHERE concession.id = \(bind: grantID) AND concession.revoked_at IS NULL AND users.deleting_at IS NULL
                FOR UPDATE OF concession
                """).first() else { throw Self.unauthorized }
            if try row.decode(column: "fresh", as: Bool.self) {
                return nil
            }
            let now = try await databaseClock(sql)
            if let deadline = try row.decode(column: "validation_deadline", as: Date?.self), deadline > now {
                // Another process owns this grant's validation. Do not overwrite its marker or send a second request.
                throw APIProblem.unavailable
            }
            let id = UUID()
            try await sql.raw("""
                UPDATE apple_grants SET validation_uncertain = validation_uncertain OR validation_id IS NOT NULL,
                    validation_id = \(bind: id),validation_deadline = clock_timestamp() + INTERVAL '1 minute'
                WHERE id = \(bind: grantID)
                """).run()
            return try ValidationAttempt(
                id: id,
                grant: grantID,
                ciphertext: row.decode(column: "encrypted_refresh_token", as: Data.self),
                keyVersion: row.decode(column: "key_version", as: String.self)
            )
        }
    }

    private func finishValidation(
        _ attempt: ValidationAttempt,
        refreshToken: String,
        vault: RefreshTokenVault
    ) async throws -> ValidationOutcome {
        let currentGrantToken = try vault.seal(refreshToken, grantID: attempt.grant)
        let revocationGrant = UUID()
        let revocationToken = try vault.seal(refreshToken, grantID: revocationGrant)
        return try await databases.database().accountTransaction { database in
            let sql = try shoppingSQL(database)
            guard let row = try await sql.raw("""
                SELECT concession.*,users.deleting_at FROM apple_grants AS concession
                JOIN users ON users.id = concession.user_id WHERE concession.id = \(bind: attempt.grant)
                FOR UPDATE OF concession
                """).first() else { return .late }
            let user = try row.decode(column: "user_id", as: UUID.self)
            let sameLease = try row.decode(column: "validation_id", as: UUID?.self) == attempt.id
            let deadline = try row.decode(column: "validation_deadline", as: Date?.self)
            let now = try await databaseClock(sql)
            let timely = sameLease && deadline.map { $0 > now } == true
            let deleting = try row.decode(column: "deleting_at", as: Date?.self) != nil
            let revoked = try row.decode(column: "revoked_at", as: Date?.self) != nil
            if timely && !deleting && !revoked {
                try await sql.raw("""
                    UPDATE apple_grants SET encrypted_refresh_token = \(bind: currentGrantToken.ciphertext),
                        key_version = \(bind: currentGrantToken.keyVersion),last_validated_at = clock_timestamp(),
                        validation_id = NULL,validation_deadline = NULL WHERE id = \(bind: attempt.grant)
                    """).run()
                return .active
            }
            if deleting, let job = try await sql.raw("""
                SELECT id FROM account_deletion_jobs WHERE user_id = \(bind: user)
                    AND state IN ('accepted','purging','data_deleted') FOR UPDATE
                """).first() {
                let jobID = try job.decode(column: "id", as: UUID.self)
                try await sql.raw("""
                    INSERT INTO account_deletion_tokens(job_id,grant_id,ciphertext,key_version)
                    VALUES(\(bind: jobID),\(bind: revocationGrant),\(bind: revocationToken.ciphertext),
                        \(bind: revocationToken.keyVersion))
                    """).run()
                let uncertain = try row.decode(column: "validation_uncertain", as: Bool.self) || !timely
                try await sql.raw("""
                    UPDATE account_deletion_jobs SET apple_requires_manual = apple_requires_manual OR \(bind: uncertain),
                        next_attempt_at = clock_timestamp() WHERE id = \(bind: jobID)
                    """).run()
                if sameLease {
                    try await sql.raw("""
                        UPDATE apple_grants SET validation_id = NULL,validation_deadline = NULL
                        WHERE id = \(bind: attempt.grant)
                        """).run()
                }
                return .deleting
            }
            // An expired/stolen lease cannot update usable credentials, even if the account still exists.
            try await sql.raw("""
                UPDATE apple_grants SET validation_uncertain = TRUE,revoked_at = COALESCE(revoked_at,clock_timestamp()),
                    validation_id = CASE WHEN validation_id = \(bind: attempt.id) THEN NULL ELSE validation_id END,
                    validation_deadline = CASE WHEN validation_id = \(bind: attempt.id) THEN NULL ELSE validation_deadline END
                WHERE id = \(bind: attempt.grant)
                """).run()
            try await sql.raw("""
                UPDATE app_sessions SET revoked_at = COALESCE(revoked_at,clock_timestamp())
                WHERE apple_grant_id = \(bind: attempt.grant)
                """).run()
            return .late
        }
    }

    private func finishFailedValidation(_ attempt: ValidationAttempt, invalidGrant: Bool) async throws {
        try await databases.database().accountTransaction { database in
            let sql = try shoppingSQL(database)
            guard let row = try await sql.raw("""
                UPDATE apple_grants SET validation_uncertain = validation_uncertain OR \(bind: !invalidGrant)
                        OR validation_deadline <= clock_timestamp(),validation_id = NULL,validation_deadline = NULL,
                    revoked_at = CASE WHEN \(bind: invalidGrant) THEN COALESCE(revoked_at,clock_timestamp()) ELSE revoked_at END
                WHERE id = \(bind: attempt.grant) AND validation_id = \(bind: attempt.id)
                RETURNING user_id,validation_uncertain
                """).first() else { return }
            let user = try row.decode(column: "user_id", as: UUID.self)
            let uncertain = try row.decode(column: "validation_uncertain", as: Bool.self)
            try await sql.raw("""
                UPDATE account_deletion_jobs SET apple_requires_manual = apple_requires_manual OR \(bind: uncertain),
                    next_attempt_at = clock_timestamp()
                WHERE user_id = \(bind: user) AND state IN ('accepted','purging','data_deleted')
                """).run()
            if invalidGrant {
                try await sql.raw("""
                    UPDATE app_sessions SET revoked_at = COALESCE(revoked_at,clock_timestamp())
                    WHERE apple_grant_id = \(bind: attempt.grant)
                    """).run()
            }
        }
    }

    private static func bearer(in request: Request) throws -> String {
        guard request.headers[.authorization].count == 1,
            let bearer = request.headers.bearerAuthorization?.token, IdentitySecrets.isValid(bearer)
        else {
            throw unauthorized
        }
        return bearer
    }

    static let unauthorized = APIProblem(
        status: .unauthorized,
        code: "invalid_session",
        message: "Inicia sesión con Apple para continuar."
    )

    private struct ActiveSession {
        let userID: UUID
        let grantID: UUID
        let requiresValidation: Bool
    }

    private struct ValidationAttempt: Sendable {
        let id: UUID
        let grant: UUID
        let ciphertext: Data
        let keyVersion: String
    }

    private enum ValidationOutcome: Sendable {
        case active
        case deleting
        case late
    }

    private enum LoginCompletion: Sendable {
        case authenticated(APIJSON)
        case deleting
        case late
    }
}

private actor GrantValidationCoordinator {
    private var checks: [UUID: Task<Void, any Error>] = [:]

    func check(grantID: UUID, operation: @escaping @Sendable () async throws -> Void) async throws {
        if let task = checks[grantID] {
            try await task.value
            return
        }
        let task = Task {
            try await operation()
        }
        checks[grantID] = task
        defer { checks[grantID] = nil }
        try await task.value
    }
}

private struct AppleLoginInput: Sendable {
    let challengeID: UUID
    let identityToken: String
    let authorizationCode: String
    let displayName: String?

    init(_ request: Request) throws {
        let body = try APIObject.body(
            request,
            allowed: ["challengeId", "identityToken", "authorizationCode", "displayName"],
            required: ["challengeId", "identityToken", "authorizationCode"]
        )
        challengeID = try body.uuid("challengeId")
        identityToken = try body.string("identityToken")
        authorizationCode = try body.string("authorizationCode")
        guard (1...16_384).contains(identityToken.unicodeScalars.count),
            (1...4_096).contains(authorizationCode.unicodeScalars.count)
        else {
            throw APIProblem.invalidRequest
        }
        if body.values["displayName"] != nil, let name = try body.optionalString("displayName") {
            displayName = try ShoppingText.normalize(name, maximum: 160)
        } else {
            displayName = nil
        }
    }
}
