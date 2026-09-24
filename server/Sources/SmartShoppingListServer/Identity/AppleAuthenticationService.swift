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
    private let validation = GrantValidationCoordinator()

    init(databases: Databases, gateway: any AppleGateway, vault: RefreshTokenVault?) {
        self.databases = databases
        self.gateway = gateway
        self.vault = vault
    }

    func createChallenge() async throws -> APIJSON {
        let sql = try shoppingSQL(databases.database())
        // Delete expired nonce material on every challenge request, including abandoned exchanges.
        try await sql.raw("DELETE FROM auth_challenges WHERE expires_at <= clock_timestamp()").run()
        let id = UUID()
        let nonce = IdentitySecrets.generate()
        guard let row = try await sql.raw("""
            INSERT INTO auth_challenges (id, nonce, expires_at)
            VALUES (\(bind: id), \(bind: nonce), clock_timestamp() + INTERVAL '5 minutes')
            RETURNING expires_at
            """).first()
        else {
            throw APIProblem.unavailable
        }
        let expires = try row.decode(column: "expires_at", as: Date.self)
        return .object([
            "id": .string(id.uuidString.lowercased()), "nonce": .string(nonce),
            "expiresAt": .string(APIEncoding.timestamp(expires))
        ])
    }

    func login(_ request: Request) async throws -> APIJSON {
        let input = try AppleLoginInput(request)
        let database = try databases.database()
        let sql = try shoppingSQL(database)
        let nonce = try await claimChallenge(input.challengeID, sql: sql)
        // Claim removes nonce from storage immediately; a crash or failed exchange cannot make it reusable.
        do {
            guard let vault else { throw APIProblem.unavailable }
            let subject = try await gateway.verifyIdentityToken(input.identityToken, nonce: nonce)
            let tokens = try await gateway.exchange(code: input.authorizationCode)
            guard let exchangeToken = tokens.identityToken, let refresh = tokens.refreshToken, !refresh.isEmpty else {
                throw AppleGatewayError.rejected
            }
            let exchangedSubject = try await gateway.verifyIdentityToken(exchangeToken, nonce: nonce)
            guard exchangedSubject == subject else { throw AppleGatewayError.rejected }
            let grantID = UUID()
            let encrypted = try vault.seal(refresh, grantID: grantID)
            let bearer = IdentitySecrets.generate()
            let hash = IdentitySecrets.hash(bearer)
            let result = try await database.transaction { database -> APIJSON in
                let sql = try shoppingSQL(database)
                let newUserID = UUID()
                guard let userRow = try await sql.raw("""
                    INSERT INTO users (id, apple_subject, display_name)
                    VALUES (\(bind: newUserID), \(bind: subject), \(bind: input.displayName))
                    ON CONFLICT (apple_subject) DO UPDATE
                    SET display_name = COALESCE(EXCLUDED.display_name, users.display_name)
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
                let user = try await loadShoppingUser(id: userID, on: database)
                let userJSON = try JSONDecoder().decode(APIJSON.self, from: APIEncoding.data(user))
                return .object([
                    "accessToken": .string(bearer), "tokenType": .string("Bearer"),
                    "expiresAt": .string(APIEncoding.timestamp(expires)), "user": userJSON
                ])
            }
            try await consumeChallenge(input.challengeID, sql: sql)
            return result
        } catch {
            // This is best-effort bookkeeping only: claimed_at already makes the challenge unusable.
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
            UPDATE auth_challenges SET consumed_at = clock_timestamp(), nonce = NULL WHERE id = \(bind: id)
            """).run()
    }

    private func activeSession(hash: String, sql: any SQLDatabase) async throws -> ActiveSession {
        guard let row = try await sql.raw("""
            SELECT session.user_id, session.apple_grant_id,
                concession.last_validated_at <= clock_timestamp() - INTERVAL '24 hours' AS requires_validation
            FROM app_sessions AS session JOIN apple_grants AS concession ON session.apple_grant_id = concession.id
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
        let database = try databases.database()
        let sql = try shoppingSQL(database)
        guard let row = try await sql.raw("""
            SELECT encrypted_refresh_token, key_version,
                last_validated_at > clock_timestamp() - INTERVAL '24 hours' AS fresh
            FROM apple_grants WHERE id = \(bind: grantID) AND revoked_at IS NULL
            """).first()
        else {
            throw Self.unauthorized
        }
        if try row.decode(column: "fresh", as: Bool.self) {
            return
        }
        guard let vault else { throw APIProblem.unavailable }
        do {
            let ciphertext = try row.decode(column: "encrypted_refresh_token", as: Data.self)
            let version = try row.decode(column: "key_version", as: String.self)
            let token = try vault.open(ciphertext, keyVersion: version, grantID: grantID)
            let response = try await gateway.validate(refreshToken: token)
            let rotated = try vault.seal(response.refreshToken ?? token, grantID: grantID)
            try await sql.raw("""
                UPDATE apple_grants
                SET encrypted_refresh_token = \(bind: rotated.ciphertext), key_version = \(bind: rotated.keyVersion),
                    last_validated_at = clock_timestamp()
                WHERE id = \(bind: grantID) AND revoked_at IS NULL
                """).run()
        } catch AppleGatewayError.invalidGrant {
            try await database.transaction { database in
                let sql = try shoppingSQL(database)
                try await sql.raw("""
                    UPDATE apple_grants SET revoked_at = COALESCE(revoked_at, clock_timestamp())
                    WHERE id = \(bind: grantID)
                    """).run()
                try await sql.raw("""
                    UPDATE app_sessions SET revoked_at = COALESCE(revoked_at, clock_timestamp())
                    WHERE apple_grant_id = \(bind: grantID)
                    """).run()
            }
            throw Self.unauthorized
        } catch {
            throw APIProblem.unavailable
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
