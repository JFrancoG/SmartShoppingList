@testable import SmartShoppingListServer
import Foundation
import Testing
import Vapor

struct AppleRevocationTests {
    @Test
    func `Revocation signs the client request and can be repeated after the grant is invalidated`() async throws {
        let key = P256.Signing.PrivateKey()
        let transport = AppleRevocationOracle(publicKey: key.publicKey)
        let gateway = try makeGateway(key: key, transport: transport)

        try await gateway.revoke(refreshToken: "fixture-refresh+/=&")
        #expect(await transport.isRevoked)
        try await gateway.revoke(refreshToken: "fixture-refresh+/=&")
        #expect(await transport.acceptedRequests == 2)
    }

    @Test(arguments: [
        AppleHTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)),
        AppleHTTPResponse(status: 400, body: Data(#"{"error":"invalid_client"}"#.utf8)),
        AppleHTTPResponse(status: 429, body: Data()),
        AppleHTTPResponse(status: 503, body: Data()),
        AppleHTTPResponse(status: 200, body: Data(#"{"error":"invalid_request"}"#.utf8)),
        AppleHTTPResponse(status: 204, body: Data()),
        AppleHTTPResponse(status: 302, body: Data())
    ])
    func `An unconfirmed response never becomes successful revocation`(_ response: AppleHTTPResponse) async throws {
        let transport = RevocationResponseTransport(response: response)
        let gateway = try makeGateway(key: P256.Signing.PrivateKey(), transport: transport)

        await #expect(throws: AppleGatewayError.unavailable) {
            try await gateway.revoke(refreshToken: "fixture-refresh")
        }
    }

    @Test
    func `A transport failure remains unconfirmed without exposing the underlying error`() async throws {
        let gateway = try makeGateway(key: P256.Signing.PrivateKey(), transport: FailingRevocationTransport())

        await #expect(throws: AppleGatewayError.unavailable) {
            try await gateway.revoke(refreshToken: "fixture-refresh")
        }
    }

    @Test
    func `An absent token is not sent or treated as an already revoked grant`() async throws {
        let key = P256.Signing.PrivateKey()
        let transport = AppleRevocationOracle(publicKey: key.publicKey)
        let gateway = try makeGateway(key: key, transport: transport)

        await #expect(throws: AppleGatewayError.rejected) {
            try await gateway.revoke(refreshToken: "")
        }
        #expect(await transport.attemptedRequests == 0)
    }

    @Test
    func `A server without Apple credentials cannot confirm revocation`() async {
        let gateway: any AppleGateway = UnconfiguredAppleGateway()

        await #expect(throws: AppleGatewayError.unavailable) {
            try await gateway.revoke(refreshToken: "fixture-refresh")
        }
    }

    private func makeGateway(
        key: P256.Signing.PrivateKey,
        transport: any AppleHTTPTransport
    ) throws -> LiveAppleGateway {
        let configuration = try AppleSignInConfiguration(
            clientID: "com.plusprojects.SmartShoppingList",
            teamID: "TEAM123456",
            keyID: "KEY1234567",
            privateKeyPEM: key.pemRepresentation
        )
        return LiveAppleGateway(
            configuration: configuration,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}

/// Models Apple's published revocation contract, including an independently verified client signature.
private actor AppleRevocationOracle: AppleHTTPTransport {
    let publicKey: P256.Signing.PublicKey
    private(set) var attemptedRequests = 0
    private(set) var acceptedRequests = 0
    private(set) var isRevoked = false

    init(publicKey: P256.Signing.PublicKey) { self.publicKey = publicKey }

    func fetchKeys() async throws -> AppleHTTPResponse { throw AppleGatewayError.unavailable }

    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        throw AppleGatewayError.rejected
    }

    func sendRevocationForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        attemptedRequests += 1
        guard fields.count == 4, fields["token"] == "fixture-refresh+/=&",
            fields["token_type_hint"] == "refresh_token", fields["client_id"] == "com.plusprojects.SmartShoppingList",
            let secret = fields["client_secret"]
        else {
            throw AppleGatewayError.rejected
        }
        let parts = secret.split(separator: ".")
        guard parts.count == 3 else { throw AppleGatewayError.rejected }
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: decodeBase64URL(parts[2]))
        guard publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)) else {
            throw AppleGatewayError.rejected
        }
        let header = try JSONDecoder().decode([String: String].self, from: decodeBase64URL(parts[0]))
        let claims = try JSONDecoder().decode(ClientClaims.self, from: decodeBase64URL(parts[1]))
        guard header["alg"] == "ES256", header["kid"] == "KEY1234567", claims.iss == "TEAM123456",
            claims.sub == "com.plusprojects.SmartShoppingList", claims.aud == "https://appleid.apple.com",
            claims.iat == 1_800_000_000, claims.exp > claims.iat, claims.exp <= claims.iat + 300
        else {
            throw AppleGatewayError.rejected
        }
        isRevoked = true
        acceptedRequests += 1
        return AppleHTTPResponse(status: 200, body: Data())
    }

    private func decodeBase64URL(_ input: Substring) throws -> Data {
        var value = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { throw AppleGatewayError.rejected }
        return data
    }

    private struct ClientClaims: Decodable {
        let iss: String
        let sub: String
        let aud: String
        let iat: Int
        let exp: Int
    }
}

private struct RevocationResponseTransport: AppleHTTPTransport {
    let response: AppleHTTPResponse

    func fetchKeys() async throws -> AppleHTTPResponse { throw AppleGatewayError.unavailable }

    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        throw AppleGatewayError.rejected
    }

    func sendRevocationForm(_ fields: [String: String]) async throws -> AppleHTTPResponse { response }
}

private struct FailingRevocationTransport: AppleHTTPTransport {
    func fetchKeys() async throws -> AppleHTTPResponse { throw AppleGatewayError.unavailable }

    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        throw AppleGatewayError.rejected
    }

    func sendRevocationForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        throw URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://fixture.invalid/private")!])
    }
}
