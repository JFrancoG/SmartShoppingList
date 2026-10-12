@testable import SmartShoppingListServer
import Foundation
import Logging
import Testing

struct RefreshTokenVaultTests {
    @Test
    func `a stored grant survives key rotation without accepting another grant or tampered bytes`() throws {
        let firstKey = Data(repeating: 0x34, count: 32)
        let secondKey = Data(repeating: 0x75, count: 32)
        let oldVault = try RefreshTokenVault(activeVersion: "2026-a", keyData: ["2026-a": firstKey])
        let rotatedVault = try RefreshTokenVault(
            activeVersion: "2026-b",
            keyData: ["2026-a": firstKey, "2026-b": secondKey]
        )
        let grant = UUID()
        let encrypted = try oldVault.seal("apple-fixture-refresh-grant", grantID: grant)
        #expect(try rotatedVault.open(encrypted.ciphertext, keyVersion: "2026-a", grantID: grant)
            == "apple-fixture-refresh-grant")
        #expect(throws: AppleGatewayError.unavailable) {
            try rotatedVault.open(encrypted.ciphertext, keyVersion: "2026-a", grantID: UUID())
        }
        var tampered = encrypted.ciphertext
        tampered[tampered.count - 1] ^= 0x01
        #expect(throws: AppleGatewayError.unavailable) {
            try rotatedVault.open(tampered, keyVersion: "2026-a", grantID: grant)
        }
        #expect(throws: AppleGatewayError.unavailable) {
            try rotatedVault.open(encrypted.ciphertext, keyVersion: "2026-b", grantID: grant)
        }
    }

    @Test(arguments: [
        (
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            nil as String?,
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "is required when APPLE_REFRESH_KEYS_JSON is present."
        ),
        (
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "",
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "must not be empty."
        ),
        (
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "DIAGNOSTIC_SENTINEL_SECRET",
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "must identify a key present in APPLE_REFRESH_KEYS_JSON."
        ),
        (
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            " v1",
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "must identify a key present in APPLE_REFRESH_KEYS_JSON."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            nil,
            "APPLE_REFRESH_KEYS_JSON",
            "is required when APPLE_REFRESH_ACTIVE_KEY_VERSION is present."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "[\"DIAGNOSTIC_SENTINEL_SECRET\"]",
            "APPLE_REFRESH_KEYS_JSON",
            "must be a JSON object mapping key versions to Base64 strings."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "{\"v1\":42}",
            "APPLE_REFRESH_KEYS_JSON",
            "must be a JSON object mapping key versions to Base64 strings."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "{\"v1\":\"DIAGNOSTIC_SENTINEL_SECRET\"}",
            "APPLE_REFRESH_KEYS_JSON",
            "must contain only valid Base64-encoded keys."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "{}",
            "APPLE_REFRESH_ACTIVE_KEY_VERSION",
            "must identify a key present in APPLE_REFRESH_KEYS_JSON."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "{\"v1\":\"\(VaultDiagnosticFixture.encodedKey)\",\"\":\"\(VaultDiagnosticFixture.encodedKey)\"}",
            "APPLE_REFRESH_KEYS_JSON",
            "key versions must not be empty."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "{\"v1\":\"Zg==\"}",
            "APPLE_REFRESH_KEYS_JSON",
            "each decoded key must contain exactly 32 bytes."
        ),
        (
            "APPLE_REFRESH_KEYS_JSON",
            "{\"v1\":\"\(Data(repeating: 0x34, count: 33).base64EncodedString())\"}",
            "APPLE_REFRESH_KEYS_JSON",
            "each decoded key must contain exactly 32 bytes."
        )
    ])
    func `rejected vault configuration logs only the variable and fixed validation rule`(
        changedField: String,
        value: String?,
        diagnosticField: String,
        rule: String
    ) throws {
        var environment = VaultDiagnosticFixture.environment
        environment[changedField] = value
        let capture = AppleStartupDiagnosticLogCapture()
        #expect(throws: AppleGatewayError.invalidConfiguration) {
            _ = try RefreshTokenVault.load(logger: capture.logger) { environment[$0] }
        }
        try capture.expectSingleDiagnostic(field: diagnosticField, rule: rule)
    }

    @Test
    func `loaded vault encrypts and opens a grant without logging its key or token`() throws {
        let capture = AppleStartupDiagnosticLogCapture()
        let vault = try #require(RefreshTokenVault.load(logger: capture.logger) {
            VaultDiagnosticFixture.environment[$0]
        })
        let grant = UUID()
        let token = "DIAGNOSTIC_SENTINEL_SECRET-refresh-token"
        let sealed = try vault.seal(token, grantID: grant)
        #expect(sealed.ciphertext.range(of: Data(token.utf8)) == nil)
        #expect(try vault.open(sealed.ciphertext, keyVersion: "v1", grantID: grant) == token)
        #expect(capture.isEmpty)
    }

    @Test
    func `absent vault variables remain unconfigured without a diagnostic`() throws {
        let capture = AppleStartupDiagnosticLogCapture()
        let vault = try RefreshTokenVault.load(logger: capture.logger) { _ in nil }
        #expect(vault == nil)
        #expect(capture.isEmpty)
    }
}

private enum VaultDiagnosticFixture {
    static let encodedKey = Data(repeating: 0x34, count: 32).base64EncodedString()
    static let environment = [
        "APPLE_REFRESH_ACTIVE_KEY_VERSION": "v1",
        "APPLE_REFRESH_KEYS_JSON": "{\"v1\":\"\(encodedKey)\"}"
    ]
}
