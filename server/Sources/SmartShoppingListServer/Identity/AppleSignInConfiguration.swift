import Foundation
import JWTKit
import Logging
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
        privateKeyPEM: String,
        privateKeyField: StaticString = "APPLE_PRIVATE_KEY_PEM",
        logger: Logger? = nil
    ) throws {
        guard clientID == "com.plusprojects.SmartShoppingList" else {
            throw AppleStartupDiagnostics.invalidConfiguration(
                logger,
                field: "APPLE_CLIENT_ID",
                rule: "must equal the app bundle identifier."
            )
        }
        guard Self.isAppleIdentifier(teamID) else {
            throw AppleStartupDiagnostics.invalidConfiguration(
                logger,
                field: "APPLE_TEAM_ID",
                rule: "must contain exactly 10 uppercase ASCII letters or digits."
            )
        }
        guard Self.isAppleIdentifier(keyID) else {
            throw AppleStartupDiagnostics.invalidConfiguration(
                logger,
                field: "APPLE_KEY_ID",
                rule: "must contain exactly 10 uppercase ASCII letters or digits."
            )
        }
        self.clientID = clientID
        self.teamID = teamID
        self.keyID = keyID
        do {
            signingKey = try ES256PrivateKey(pem: privateKeyPEM)
        } catch {
            throw AppleStartupDiagnostics.invalidConfiguration(
                logger,
                field: privateKeyField,
                rule: "must contain a readable P-256 private key in PEM format."
            )
        }
    }

    static func load(
        logger: Logger? = nil,
        environment: (String) -> String? = Environment.get
    ) throws -> Self? {
        let names = [
            "APPLE_CLIENT_ID",
            "APPLE_TEAM_ID",
            "APPLE_KEY_ID",
            "APPLE_PRIVATE_KEY_PATH",
            "APPLE_PRIVATE_KEY_PEM"
        ]
        let values = names.map(environment)
        guard values.contains(where: { $0 != nil }) else { return nil }
        guard let clientID = values[0] else {
            throw AppleStartupDiagnostics.invalidConfiguration(logger, field: "APPLE_CLIENT_ID", rule: "is required.")
        }
        guard let teamID = values[1] else {
            throw AppleStartupDiagnostics.invalidConfiguration(logger, field: "APPLE_TEAM_ID", rule: "is required.")
        }
        guard let keyID = values[2] else {
            throw AppleStartupDiagnostics.invalidConfiguration(logger, field: "APPLE_KEY_ID", rule: "is required.")
        }
        let key: String
        let privateKeyField: StaticString
        switch (values[3], values[4]) {
        case (let path?, nil):
            privateKeyField = "APPLE_PRIVATE_KEY_PATH"
            guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppleStartupDiagnostics.invalidConfiguration(
                    logger,
                    field: "APPLE_PRIVATE_KEY_PATH",
                    rule: "must not be empty."
                )
            }
            do {
                key = try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                throw AppleStartupDiagnostics.invalidConfiguration(
                    logger,
                    field: "APPLE_PRIVATE_KEY_PATH",
                    rule: "must refer to a readable UTF-8 private-key file."
                )
            }
        case (nil, let pem?):
            privateKeyField = "APPLE_PRIVATE_KEY_PEM"
            guard !pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppleStartupDiagnostics.invalidConfiguration(
                    logger,
                    field: "APPLE_PRIVATE_KEY_PEM",
                    rule: "must not be empty."
                )
            }
            key = pem
        case (nil, nil):
            throw AppleStartupDiagnostics.invalidConfiguration(
                logger,
                field: "APPLE_PRIVATE_KEY_PEM",
                rule: "is required when APPLE_PRIVATE_KEY_PATH is absent."
            )
        case (.some, .some):
            throw AppleStartupDiagnostics.invalidConfiguration(
                logger,
                field: "APPLE_PRIVATE_KEY_PEM",
                rule: "must not coexist with APPLE_PRIVATE_KEY_PATH."
            )
        }
        return try Self(
            clientID: clientID,
            teamID: teamID,
            keyID: keyID,
            privateKeyPEM: key,
            privateKeyField: privateKeyField,
            logger: logger
        )
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
