@testable import SmartShoppingListServer
import Foundation
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
}
