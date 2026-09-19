import Foundation
import Vapor

struct RefreshTokenVault: Sendable {
    struct SealedToken: Sendable {
        let ciphertext: Data
        let keyVersion: String
    }

    private let activeVersion: String
    private let keys: [String: SymmetricKey]

    init(activeVersion: String, keyData: [String: Data]) throws {
        guard !activeVersion.isEmpty, keyData[activeVersion] != nil,
            keyData.allSatisfy({ !$0.key.isEmpty && $0.value.count == 32 })
        else {
            throw AppleGatewayError.invalidConfiguration
        }
        self.activeVersion = activeVersion
        self.keys = keyData.mapValues { SymmetricKey(data: $0) }
    }

    static func load(environment: (String) -> String? = Environment.get) throws -> Self? {
        guard let version = environment("APPLE_REFRESH_ACTIVE_KEY_VERSION") else {
            guard environment("APPLE_REFRESH_KEYS_JSON") == nil else { throw AppleGatewayError.invalidConfiguration }
            return nil
        }
        guard let json = environment("APPLE_REFRESH_KEYS_JSON"),
            let encodedKeys = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        else {
            throw AppleGatewayError.invalidConfiguration
        }
        var decoded: [String: Data] = [:]
        for (version, encoded) in encodedKeys {
            guard let bytes = Data(base64Encoded: encoded) else { throw AppleGatewayError.invalidConfiguration }
            decoded[version] = bytes
        }
        return try Self(activeVersion: version, keyData: decoded)
    }

    /// Bind ciphertext to its grant as well as its version, preventing database-row substitution.
    func seal(_ token: String, grantID: UUID) throws -> SealedToken {
        guard let key = keys[activeVersion] else { throw AppleGatewayError.unavailable }
        let sealed = try AES.GCM.seal(
            Data(token.utf8),
            using: key,
            authenticating: associatedData(grantID: grantID, version: activeVersion)
        )
        guard let combined = sealed.combined else { throw AppleGatewayError.unavailable }
        return SealedToken(ciphertext: combined, keyVersion: activeVersion)
    }

    func open(_ ciphertext: Data, keyVersion: String, grantID: UUID) throws -> String {
        guard let key = keys[keyVersion] else { throw AppleGatewayError.unavailable }
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            let cleartext = try AES.GCM.open(
                box,
                using: key,
                authenticating: associatedData(grantID: grantID, version: keyVersion)
            )
            guard let token = String(data: cleartext, encoding: .utf8), !token.isEmpty else {
                throw AppleGatewayError.unavailable
            }
            return token
        } catch {
            throw AppleGatewayError.unavailable
        }
    }

    private func associatedData(grantID: UUID, version: String) -> Data {
        Data("SmartShoppingList.apple-refresh.\(grantID.uuidString.lowercased()).\(version)".utf8)
    }
}

enum IdentitySecrets {
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func isValid(_ value: String) -> Bool {
        value.utf8.count == 43 && value.last.map { "AEIMQUYcgkosw048".contains($0) } == true
            && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}
