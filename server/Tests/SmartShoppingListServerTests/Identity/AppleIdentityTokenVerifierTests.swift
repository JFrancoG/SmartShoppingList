@testable import SmartShoppingListServer
import Foundation
import JWTKit
import Testing

@Suite("Apple identity token verification")
struct AppleIdentityTokenVerifierTests {
    @Test
    func `a valid signature and bound claims authenticate the stable Apple subject`() async throws {
        let verifier = try await makeVerifier(currentDate: Date(timeIntervalSince1970: 1_999_999_999))

        let subject = try await verifier.verify(
            AppleIdentityTokenFixtures.valid,
            expectedNonce: "one-time-fixture-nonce"
        )

        #expect(subject == "apple-fixture-user-001")
    }

    @Test(arguments: [
        AppleIdentityTokenFixtures.InvalidToken.wrongIssuer,
        .wrongAudience,
        .missingNonce,
        .emptySubject,
        .unknownKey,
        .missingKey,
        .unsupportedAlgorithm,
        .tamperedPayload,
        .tamperedSignature,
        .unsigned,
    ])
    func `invalid signatures headers and identity claims never authenticate`(
        _ invalidToken: AppleIdentityTokenFixtures.InvalidToken
    ) async throws {
        let verifier = try await makeVerifier()

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify(invalidToken.token, expectedNonce: "one-time-fixture-nonce")
        }
    }

    @Test(arguments: [2_000_000_000.0, 2_000_000_001.0])
    func `a token is rejected at its expiration instant and afterwards`(_ timestamp: TimeInterval) async throws {
        let verifier = try await makeVerifier(currentDate: Date(timeIntervalSince1970: timestamp))

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify(AppleIdentityTokenFixtures.valid, expectedNonce: "one-time-fixture-nonce")
        }
    }

    @Test(arguments: ["another-authentication-attempt", ""])
    func `a valid token cannot authenticate an unrelated or missing nonce`(_ nonce: String) async throws {
        let verifier = try await makeVerifier()

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify(AppleIdentityTokenFixtures.valid, expectedNonce: nonce)
        }
    }

    @Test
    func `malformed input fails without exposing a parser error or identity claims`() async throws {
        let verifier = try await makeVerifier()

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify("not-a-jwt", expectedNonce: "one-time-fixture-nonce")
        }
    }

    @Test(arguments: ["[]", "{}", "42", "null", "true"])
    func `an unsigned audience with a malformed type is rejected without trapping`(
        _ audienceJSON: String
    ) async throws {
        let verifier = try await makeVerifier()
        let originalParts = AppleIdentityTokenFixtures.valid.split(separator: ".")
        let payload = """
        {"iss":"https://appleid.apple.com","aud":\(audienceJSON),"exp":2000000000,
        "sub":"apple-fixture-user-001","nonce":"one-time-fixture-nonce"}
        """
        let encodedPayload = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "\(originalParts[0]).\(encodedPayload).\(originalParts[2])"

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify(token, expectedNonce: "one-time-fixture-nonce")
        }
    }

    @Test
    func `an empty audience is rejected even with a valid trusted signature`() async throws {
        let verifier = try await makeVerifier(jwksJSON: AppleIdentityTokenFixtures.signedEdgeCasesJWKSJSON)

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify(
                AppleIdentityTokenFixtures.signedEmptyAudience,
                expectedNonce: "one-time-fixture-nonce"
            )
        }
    }

    @Test
    func `a misleading algorithm header is rejected even when the RSA SHA256 signature is valid`() async throws {
        let verifier = try await makeVerifier(jwksJSON: AppleIdentityTokenFixtures.signedEdgeCasesJWKSJSON)

        await #expect(throws: AppleIdentityTokenVerifier.VerificationError.rejected) {
            try await verifier.verify(
                AppleIdentityTokenFixtures.signedMismatchedAlgorithm,
                expectedNonce: "one-time-fixture-nonce"
            )
        }
    }

    private func makeVerifier(
        jwksJSON: String = AppleIdentityTokenFixtures.jwksJSON,
        currentDate: Date = Date(timeIntervalSince1970: 1_999_999_900)
    ) async throws -> AppleIdentityTokenVerifier {
        let jwks = try JSONDecoder().decode(JWKS.self, from: Data(jwksJSON.utf8))
        return try await AppleIdentityTokenVerifier(
            audience: "com.example.smartshoppinglist.fixture",
            trustedJWKS: jwks,
            now: { currentDate }
        )
    }
}
