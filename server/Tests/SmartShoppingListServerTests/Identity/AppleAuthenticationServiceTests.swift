@testable import SmartShoppingListServer
import FluentKit
import FluentSQL
import Foundation
import Testing
import Vapor
import VaporTesting

extension SmartShoppingListServerTests {
    @Test
    func `only one caller can exchange a challenge and its nonce is erased before Apple responds`() async throws {
        let gateway = ControlledAppleGateway(suspendExchange: true)
        let service = try makeIdentityService(gateway)
        let challenge = try await service.createChallenge()
        let input = try loginRequest(challenge: challenge)
        let first = Task {
            try await service.login(input)
        }
        await gateway.waitForExchange()
        await #expect {
            try await service.login(input)
        } throws: { ($0 as? APIProblem)?.code == "challenge_consumed" }
        let sql = try shoppingSQL(database)
        let row = try #require(try await sql.raw("SELECT nonce FROM auth_challenges").first())
        #expect(try row.decode(column: "nonce", as: String?.self) == nil)
        await gateway.releaseExchange()
        let response = try await first.value
        #expect(try APIObject(response, allowed: ["accessToken", "tokenType", "expiresAt", "user"], required: [])
            .string("tokenType") == "Bearer")
        #expect(await gateway.exchangeCount == 1)
        let sessions = try await sql.raw("SELECT id FROM app_sessions").all()
        #expect(sessions.count == 1)
    }

    @Test
    func `a mismatched exchange subject cannot create a user and consumes the attempt`() async throws {
        let service = try makeIdentityService(ControlledAppleGateway(exchangeSubject: "another-apple-subject"))
        let challenge = try await service.createChallenge()
        let input = try loginRequest(challenge: challenge)
        await #expect {
            try await service.login(input)
        } throws: { ($0 as? APIProblem)?.status == .unauthorized }
        let sql = try shoppingSQL(database)
        #expect(try await sql.raw("SELECT id FROM users").all().isEmpty)
        #expect(try await sql.raw("SELECT id FROM app_sessions").all().isEmpty)
        await #expect {
            try await service.login(input)
        } throws: { ($0 as? APIProblem)?.code == "challenge_consumed" }
    }

    @Test
    func `a fresh session survives Apple outage and logout is idempotent without validating Apple`() async throws {
        let gateway = ControlledAppleGateway(refreshError: .unavailable)
        let service = try makeIdentityService(gateway)
        let bearer = try await loginBearer(service)
        let request = try authenticatedRequest(bearer)
        _ = try await service.authenticate(request)
        try await service.logout(request)
        try await service.logout(request)
        await #expect {
            try await service.authenticate(request)
        } throws: { ($0 as? APIProblem)?.status == .unauthorized }
        #expect(await gateway.refreshCount == 0)
        try await service.logout(authenticatedRequest(String(repeating: "A", count: 43)))
    }

    @Test
    func `required Apple revalidation fails closed and preserves the session for a later retry`() async throws {
        let gateway = ControlledAppleGateway(refreshError: .unavailable)
        let service = try makeIdentityService(gateway)
        let bearer = try await loginBearer(service)
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE apple_grants SET last_validated_at = clock_timestamp() - INTERVAL '25 hours'").run()
        await #expect {
            try await service.authenticate(authenticatedRequest(bearer))
        } throws: { ($0 as? APIProblem)?.status == .serviceUnavailable }
        let row = try #require(try await sql.raw("SELECT revoked_at FROM app_sessions").first())
        #expect(try row.decode(column: "revoked_at", as: Date?.self) == nil)
        await gateway.setRefreshError(nil)
        _ = try await service.authenticate(authenticatedRequest(bearer))
        #expect(await gateway.refreshCount == 2)
    }

    @Test
    func `invalid grant revokes its sessions while a different grant of the same user remains usable`() async throws {
        let gateway = ControlledAppleGateway(refreshError: .invalidGrant)
        let service = try makeIdentityService(gateway)
        let firstBearer = try await loginBearer(service)
        let secondBearer = try await loginBearer(service)
        let sql = try shoppingSQL(database)
        try await sql.raw("""
            UPDATE apple_grants SET last_validated_at = clock_timestamp() - INTERVAL '25 hours'
            WHERE id = (SELECT apple_grant_id FROM app_sessions WHERE token_hash = \(bind: IdentitySecrets.hash(firstBearer)))
            """).run()
        await #expect {
            try await service.authenticate(authenticatedRequest(firstBearer))
        } throws: { ($0 as? APIProblem)?.status == .unauthorized }
        let secondUser = try await service.authenticate(authenticatedRequest(secondBearer))
        let users = try await sql.raw("SELECT id FROM users").all()
        #expect(users.count == 1)
        #expect(try users.first?.decode(column: "id", as: UUID.self) == secondUser)
        #expect(await gateway.refreshCount == 1)
    }

    @Test
    func `concurrent expired grant checks share one Apple validation and retain absolute session expiry`() async throws {
        let gateway = ControlledAppleGateway(suspendRefresh: true)
        let service = try makeIdentityService(gateway)
        let bearer = try await loginBearer(service)
        let sql = try shoppingSQL(database)
        try await sql.raw("UPDATE apple_grants SET last_validated_at = clock_timestamp() - INTERVAL '25 hours'").run()
        let original = try #require(try await sql.raw("SELECT expires_at FROM app_sessions").first())
        let expiresAt = try original.decode(column: "expires_at", as: Date.self)
        let first = Task {
            try await service.authenticate(authenticatedRequest(bearer))
        }
        await gateway.waitForRefresh()
        let second = Task {
            try await service.authenticate(authenticatedRequest(bearer))
        }
        await gateway.releaseRefresh()
        let firstUser = try await first.value
        #expect(try await second.value == firstUser)
        #expect(await gateway.refreshCount == 1)
        let persisted = try #require(try await sql.raw("SELECT expires_at FROM app_sessions").first())
        #expect(try persisted.decode(column: "expires_at", as: Date.self) == expiresAt)
    }

    private func makeIdentityService(_ gateway: any AppleGateway) throws -> AppleAuthenticationService {
        try AppleAuthenticationService(
            databases: testDatabases,
            gateway: gateway,
            vault: RefreshTokenVault(activeVersion: "fixture", keyData: ["fixture": Data(repeating: 0x42, count: 32)])
        )
    }

    private func loginRequest(challenge: APIJSON) throws -> Request {
        let fields = try APIObject(challenge, allowed: ["id", "nonce", "expiresAt"], required: ["id"])
        let body: APIJSON = .object([
            "challengeId": .string(try fields.string("id")),
            "identityToken": .string("native-fixture"), "authorizationCode": .string("fixture-code")
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

    private func loginBearer(_ service: AppleAuthenticationService) async throws -> String {
        let response = try await service.login(loginRequest(challenge: service.createChallenge()))
        return try APIObject(
            response,
            allowed: ["accessToken", "tokenType", "expiresAt", "user"],
            required: ["accessToken"]
        ).string("accessToken")
    }

    private func authenticatedRequest(_ token: String) throws -> Request {
        try Request(
            application: app,
            method: .GET,
            url: "/v1/me",
            headers: ["Authorization": "Bearer \(token)"],
            on: app.eventLoopGroup.any()
        )
    }
}

/// Explicit test oracle: two native credentials belong to one stable Apple identity, except the injected mismatch.
private actor ControlledAppleGateway: AppleGateway {
    let exchangeSubject: String
    let suspendExchange: Bool
    let suspendRefresh: Bool
    var refreshError: AppleGatewayError?
    private(set) var exchangeCount = 0
    private(set) var refreshCount = 0
    private var exchangeWaiting: CheckedContinuation<Void, Never>?
    private var exchangeStarted: CheckedContinuation<Void, Never>?
    private var refreshWaiting: CheckedContinuation<Void, Never>?
    private var refreshStarted: CheckedContinuation<Void, Never>?

    init(
        exchangeSubject: String = "apple-fixture-subject",
        refreshError: AppleGatewayError? = nil,
        suspendExchange: Bool = false,
        suspendRefresh: Bool = false
    ) {
        self.exchangeSubject = exchangeSubject
        self.refreshError = refreshError
        self.suspendExchange = suspendExchange
        self.suspendRefresh = suspendRefresh
    }

    func verifyIdentityToken(_ token: String, nonce: String) async throws -> String {
        guard IdentitySecrets.isValid(nonce) else { throw AppleGatewayError.rejected }
        return token == "exchanged-fixture" ? exchangeSubject : "apple-fixture-subject"
    }

    func exchange(code: String) async throws -> AppleTokenResponse {
        exchangeCount += 1
        if suspendExchange {
            await withCheckedContinuation { continuation in
                exchangeWaiting = continuation
                exchangeStarted?.resume()
                exchangeStarted = nil
            }
        }
        return AppleTokenResponse(identityToken: "exchanged-fixture", refreshToken: "fixture-refresh")
    }

    func validate(refreshToken: String) async throws -> AppleTokenResponse {
        refreshCount += 1
        if suspendRefresh {
            await withCheckedContinuation { continuation in
                refreshWaiting = continuation
                refreshStarted?.resume()
                refreshStarted = nil
            }
        }
        if let refreshError {
            throw refreshError
        }
        return AppleTokenResponse(identityToken: nil, refreshToken: "rotated-fixture-refresh")
    }

    func setRefreshError(_ error: AppleGatewayError?) {
        refreshError = error
    }

    func waitForExchange() async {
        if exchangeWaiting != nil {
            return
        }
        await withCheckedContinuation {
            exchangeStarted = $0
        }
    }

    func releaseExchange() {
        exchangeWaiting?.resume()
        exchangeWaiting = nil
    }

    func waitForRefresh() async {
        if refreshWaiting != nil {
            return
        }
        await withCheckedContinuation {
            refreshStarted = $0
        }
    }

    func releaseRefresh() {
        refreshWaiting?.resume()
        refreshWaiting = nil
    }
}
