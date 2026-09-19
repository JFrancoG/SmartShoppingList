import Foundation
import JWTKit

/// Verifies an Apple identity token against a trusted snapshot of Apple's public signing keys.
///
/// The caller supplies keys fetched from `https://appleid.apple.com/auth/keys`, never keys supplied
/// by a login request. Key retrieval/rotation and issuing or consuming a one-time nonce belong to
/// the eventual authentication flow. `expectedNonce` must be the exact value sent to Apple.
struct AppleIdentityTokenVerifier: Sendable {
    enum VerificationError: Error, Equatable {
        case invalidConfiguration
        case rejected
    }

    private let audience: String
    private let keys: JWTKeyCollection
    private let keyIdentifiers: Set<String>
    private let now: @Sendable () -> Date

    init(
        audience: String,
        trustedJWKS: JWKS,
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws {
        guard !audience.isEmpty else { throw VerificationError.invalidConfiguration }

        let keys = JWTKeyCollection()
        var identifiers: Set<String> = []
        for key in trustedJWKS.keys where key.keyType == .rsa && key.algorithm == .rs256 {
            guard let identifier = key.keyIdentifier?.string, !identifier.isEmpty,
                identifiers.insert(identifier).inserted, key.privateExponent == nil
            else {
                throw VerificationError.invalidConfiguration
            }
            try await keys.add(jwk: key)
        }
        guard !identifiers.isEmpty else { throw VerificationError.invalidConfiguration }

        self.audience = audience
        self.keys = keys
        self.keyIdentifiers = identifiers
        self.now = now
    }

    /// Returns the stable Apple subject only after signature and all required claims are verified.
    func verify(_ token: String, expectedNonce: String) async throws -> String {
        do {
            guard !expectedNonce.isEmpty else { throw VerificationError.rejected }

            // These untrusted fields only restrict key selection; they never establish identity.
            // JWTKit otherwise falls back to a default key for an unknown or absent `kid`.
            let header = try unverifiedHeader(in: token)
            guard header.alg == "RS256", keyIdentifiers.contains(header.kid) else { throw VerificationError.rejected }

            let claims = try await keys.verify(token, as: Claims.self)
            guard claims.audience == audience else { throw VerificationError.rejected }
            try claims.expires.verifyNotExpired(currentDate: now())
            guard claims.nonce == expectedNonce else { throw VerificationError.rejected }
            return claims.subject.value
        } catch {
            // Do not propagate errors containing token claims into logs or an eventual HTTP response.
            throw VerificationError.rejected
        }
    }

    private func unverifiedHeader(in token: String) throws -> Header {
        let parts = try DefaultJWTParser().getTokenParts(Data(token.utf8))
        var encoded = String(decoding: parts.header, as: UTF8.self)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw VerificationError.rejected }
        return try JSONDecoder().decode(Header.self, from: data)
    }

    private struct Header: Decodable {
        let alg: String
        let kid: String
    }

    private struct Claims: JWTPayload {
        let issuer: IssuerClaim
        // Apple documents `aud` as the client_id string. Decode untrusted values with throwing
        // String decoding; JWTKit's AudienceClaim traps on an empty array rather than throwing.
        let audience: String
        let expires: ExpirationClaim
        let subject: SubjectClaim
        let nonce: String

        enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case audience = "aud"
            case expires = "exp"
            case subject = "sub"
            case nonce
        }

        func verify(using algorithm: some JWTAlgorithm) throws {
            guard algorithm.name == "RS256", issuer.value == "https://appleid.apple.com", !subject.value.isEmpty else {
                throw VerificationError.rejected
            }
        }
    }
}
