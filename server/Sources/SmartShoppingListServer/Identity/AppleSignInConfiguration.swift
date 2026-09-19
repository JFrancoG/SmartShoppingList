import Foundation
import JWTKit
import Vapor

struct AppleSignInConfiguration: Sendable {
    let clientID: String
    let teamID: String
    let keyID: String
    private let signingKey: ES256PrivateKey

    init(
        clientID: String,
        teamID: String,
        keyID: String,
        privateKeyPEM: String
    ) throws {
        guard clientID == "com.plusprojects.SmartShoppingList", Self.isAppleIdentifier(teamID),
            Self.isAppleIdentifier(keyID)
        else {
            throw AppleGatewayError.invalidConfiguration
        }
        self.clientID = clientID
        self.teamID = teamID
        self.keyID = keyID
        do {
            signingKey = try ES256PrivateKey(pem: privateKeyPEM)
        } catch {
            throw AppleGatewayError.invalidConfiguration
        }
    }

    static func load(environment: (String) -> String? = Environment.get) throws -> Self? {
        let names = ["APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_PATH"]
        let values = names.map(environment)
        guard values.contains(where: { $0 != nil }) else { return nil }
        guard let clientID = values[0], let teamID = values[1], let keyID = values[2], let path = values[3] else {
            throw AppleGatewayError.invalidConfiguration
        }
        do {
            let key = try String(contentsOfFile: path, encoding: .utf8)
            return try Self(
                clientID: clientID,
                teamID: teamID,
                keyID: keyID,
                privateKeyPEM: key
            )
        } catch {
            throw AppleGatewayError.invalidConfiguration
        }
    }

    func clientSecret(now: Date) async throws -> String {
        let keys = await JWTKeyCollection().add(ecdsa: signingKey, kid: JWKIdentifier(string: keyID))
        let claims = ClientSecretClaims(
            issuer: teamID,
            issuedAt: Int(now.timeIntervalSince1970),
            expiration: Int(now.addingTimeInterval(300).timeIntervalSince1970),
            audience: "https://appleid.apple.com",
            subject: clientID
        )
        return try await keys.sign(claims, kid: JWKIdentifier(string: keyID))
    }

    private static func isAppleIdentifier(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
    }

    private struct ClientSecretClaims: JWTPayload {
        let issuer: String
        let issuedAt: Int
        let expiration: Int
        let audience: String
        let subject: String

        enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case issuedAt = "iat"
            case expiration = "exp"
            case audience = "aud"
            case subject = "sub"
        }

        func verify(using algorithm: some JWTAlgorithm) throws {
            guard algorithm.name == "ES256" else { throw AppleGatewayError.invalidConfiguration }
        }
    }
}

/// Fail closed when local bootstrap has no credentials; never synthesizes an Apple identity.
struct UnconfiguredAppleGateway: AppleGateway {
    func verifyIdentityToken(_ token: String, nonce: String) async throws -> String {
        throw AppleGatewayError.unavailable
    }

    func exchange(code: String) async throws -> AppleTokenResponse {
        throw AppleGatewayError.unavailable
    }

    func validate(refreshToken: String) async throws -> AppleTokenResponse {
        throw AppleGatewayError.unavailable
    }
}
