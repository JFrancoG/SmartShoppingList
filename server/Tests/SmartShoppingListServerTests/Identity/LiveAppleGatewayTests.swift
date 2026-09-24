@testable import SmartShoppingListServer
import Foundation
import Testing
import Vapor

struct LiveAppleGatewayTests {
    @Test
    func `Apple exchange signs a valid bounded client secret and sends the grant without a nonce`() async throws {
        let key = P256.Signing.PrivateKey()
        let configuration = try AppleSignInConfiguration(
            clientID: "com.plusprojects.SmartShoppingList",
            teamID: "TEAM123456",
            keyID: "KEY1234567",
            privateKeyPEM: key.pemRepresentation
        )
        let transport = AppleTokenOracle(publicKey: key.publicKey)
        let gateway = LiveAppleGateway(
            configuration: configuration,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let grant = try await gateway.exchange(code: "single-use-fixture-code")
        #expect(grant.refreshToken == "fixture-authorized-refresh")
        #expect(await transport.acceptedRequests == 1)
    }

    @Test(arguments: ["invalid_grant", "invalid_client", "malformed_success"])
    func `Apple failures never become a successful grant`(_ response: String) async throws {
        let key = P256.Signing.PrivateKey()
        let configuration = try AppleSignInConfiguration(
            clientID: "com.plusprojects.SmartShoppingList",
            teamID: "TEAM123456",
            keyID: "KEY1234567",
            privateKeyPEM: key.pemRepresentation
        )
        let gateway = LiveAppleGateway(
            configuration: configuration,
            transport: AppleFailureTransport(response: response)
        )
        await #expect {
            try await gateway.validate(refreshToken: "fixture-refresh")
        } throws: { error in
            let expected: AppleGatewayError = response == "invalid_grant" ? .invalidGrant : .unavailable
            return error as? AppleGatewayError == expected
        }
    }
}

/// Independently verifies the JWT signature with Crypto and the public Apple claim/form requirements.
private actor AppleTokenOracle: AppleHTTPTransport {
    let publicKey: P256.Signing.PublicKey
    private(set) var acceptedRequests = 0

    init(publicKey: P256.Signing.PublicKey) { self.publicKey = publicKey }

    func fetchKeys() async throws -> AppleHTTPResponse { throw AppleGatewayError.unavailable }

    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        guard fields["grant_type"] == "authorization_code", fields["code"] == "single-use-fixture-code",
            fields["nonce"] == nil, fields["client_id"] == "com.plusprojects.SmartShoppingList",
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
        let claims = try JSONDecoder().decode(AppleClientClaims.self, from: decodeBase64URL(parts[1]))
        guard header["alg"] == "ES256", header["kid"] == "KEY1234567", claims.iss == "TEAM123456",
            claims.sub == "com.plusprojects.SmartShoppingList", claims.aud == "https://appleid.apple.com",
            claims.iat == 1_800_000_000, claims.exp > claims.iat, claims.exp <= claims.iat + 300
        else {
            throw AppleGatewayError.rejected
        }
        acceptedRequests += 1
        return AppleHTTPResponse(
            status: 200,
            body: Data(#"{"access_token":"fixture-access","token_type":"Bearer","expires_in":3600,"id_token":"fixture-identity","refresh_token":"fixture-authorized-refresh"}"#.utf8)
        )
    }

    private func decodeBase64URL(_ input: Substring) throws -> Data {
        var value = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { throw AppleGatewayError.rejected }
        return data
    }

    private struct AppleClientClaims: Decodable {
        let iss: String
        let sub: String
        let aud: String
        let iat: Int
        let exp: Int
    }
}

private struct AppleFailureTransport: AppleHTTPTransport {
    let response: String

    func fetchKeys() async throws -> AppleHTTPResponse { throw AppleGatewayError.unavailable }

    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        if response == "malformed_success" {
            return AppleHTTPResponse(status: 200, body: Data("{}".utf8))
        }
        return AppleHTTPResponse(status: 400, body: Data("{\"error\":\"\(response)\"}".utf8))
    }
}
