@testable import SmartShoppingListServer
import Foundation
import Testing
import Vapor

struct AppleSignInConfigurationTests {
    @Test
    func `a multiline environment key signs an Apple client secret`() async throws {
        let configuration = try #require(AppleSignInConfiguration.load { AppleSigningFixture.environment[$0] })
        try await verifyClientSecret(configuration)
    }

    @Test
    func `a mounted private key still signs an Apple client secret`() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("AuthKey.p8")
        try AppleSigningFixture.privateKey.write(to: file, atomically: true, encoding: .utf8)
        var environment = AppleSigningFixture.environment
        environment.removeValue(forKey: "APPLE_PRIVATE_KEY_PEM")
        environment["APPLE_PRIVATE_KEY_PATH"] = file.path

        let configuration = try #require(AppleSignInConfiguration.load { environment[$0] })
        try await verifyClientSecret(configuration)
    }

    @Test
    func `absent Apple credentials preserve unconfigured local bootstrap`() throws {
        let configuration = try AppleSignInConfiguration.load { _ in nil }
        #expect(configuration == nil)
    }

    @Test(arguments: ["APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_PEM"])
    func `a partial signing configuration cannot start`(missing: String) {
        var environment = AppleSigningFixture.environment
        environment.removeValue(forKey: missing)
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { environment[$0] }
        }
    }

    @Test(arguments: ["APPLE_CLIENT_ID", "APPLE_TEAM_ID", "APPLE_KEY_ID", "APPLE_PRIVATE_KEY_PEM"])
    func `empty signing values cannot start`(empty: String) {
        var environment = AppleSigningFixture.environment
        environment[empty] = ""
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { environment[$0] }
        }
    }

    @Test(arguments: [
        " \n\t",
        "not a private key",
        AppleSigningFixture.privateKey.replacingOccurrences(of: "\n", with: "\\n")
    ])
    func `invalid environment PEM is rejected without interpreting escaped newlines`(pem: String) {
        var environment = AppleSigningFixture.environment
        environment["APPLE_PRIVATE_KEY_PEM"] = pem
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { environment[$0] }
        }
    }

    @Test
    func `a lone PEM variable is partial configuration rather than local bootstrap`() {
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { name in
                name == "APPLE_PRIVATE_KEY_PEM" ? AppleSigningFixture.privateKey : nil
            }
        }
    }

    @Test(arguments: ["", AppleSigningFixture.privateKey])
    func `two configured key sources are rejected even when one is empty`(pem: String) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("AuthKey.p8")
        try AppleSigningFixture.privateKey.write(to: file, atomically: true, encoding: .utf8)
        var environment = AppleSigningFixture.environment
        environment["APPLE_PRIVATE_KEY_PATH"] = file.path
        environment["APPLE_PRIVATE_KEY_PEM"] = pem

        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { environment[$0] }
        }
    }

    @Test
    func `an empty file variable cannot coexist with a valid inline key`() {
        var environment = AppleSigningFixture.environment
        environment["APPLE_PRIVATE_KEY_PATH"] = ""
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { environment[$0] }
        }
    }

    @Test(arguments: ["", " \n\t", "/nonexistent-smart-shopping-fixture/AuthKey.p8"])
    func `an unusable mounted key path exposes only a configuration error`(path: String) {
        var environment = AppleSigningFixture.environment
        environment.removeValue(forKey: "APPLE_PRIVATE_KEY_PEM")
        environment["APPLE_PRIVATE_KEY_PATH"] = path
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try AppleSignInConfiguration.load { environment[$0] }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Crypto verifies the signature independently of JWTKit; claims follow Apple's client-secret requirements.
    private func verifyClientSecret(_ configuration: AppleSignInConfiguration) async throws {
        let secret = try await configuration.clientSecret(now: Date(timeIntervalSince1970: 1_800_000_000))
        let parts = secret.split(separator: ".")
        try #require(parts.count == 3)
        let publicKey = try P256.Signing.PublicKey(pemRepresentation: AppleSigningFixture.publicKey)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: decodeBase64URL(parts[2]))
        #expect(publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))

        let header = try JSONDecoder().decode([String: String].self, from: decodeBase64URL(parts[0]))
        let claims = try JSONDecoder().decode(AppleClientClaims.self, from: decodeBase64URL(parts[1]))
        #expect(header["alg"] == "ES256")
        #expect(header["kid"] == "KEY1234567")
        #expect(claims.iss == "TEAM123456")
        #expect(claims.sub == "com.plusprojects.SmartShoppingList")
        #expect(claims.aud == "https://appleid.apple.com")
        #expect(claims.iat == 1_800_000_000)
        #expect(claims.exp == 1_800_000_300)
    }

    private func decodeBase64URL(_ input: Substring) throws -> Data {
        var value = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return try #require(Data(base64Encoded: value))
    }

    private struct AppleClientClaims: Decodable {
        let iss: String
        let sub: String
        let aud: String
        let iat: Int
        let exp: Int
    }
}

/// Synthetic, publicly committed key pair used only by this suite; never an Apple credential.
private enum AppleSigningFixture {
    static let privateKey = """
        -----BEGIN PRIVATE KEY-----
        MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgZ27f6rv2/ySkYpb7
        1lyZc7/K1lgQHjpbnY2uZ8LzBHehRANCAARZqQntIjypzx52SaKielIQeQ1i6RZZ
        079Bb4H5MZdO7ofVmpNNqe1cinTec9QZLVQ9zDo0CwwyB/gTe4+cL812
        -----END PRIVATE KEY-----
        """

    static let publicKey = """
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEWakJ7SI8qc8edkmionpSEHkNYukW
        WdO/QW+B+TGXTu6H1ZqTTantXIp03nPUGS1UPcw6NAsMMgf4E3uPnC/Ndg==
        -----END PUBLIC KEY-----
        """

    static let environment = [
        "APPLE_CLIENT_ID": "com.plusprojects.SmartShoppingList",
        "APPLE_TEAM_ID": "TEAM123456",
        "APPLE_KEY_ID": "KEY1234567",
        "APPLE_PRIVATE_KEY_PEM": privateKey
    ]
}
