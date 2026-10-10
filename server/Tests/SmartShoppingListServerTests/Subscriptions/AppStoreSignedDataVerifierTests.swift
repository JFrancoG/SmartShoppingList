import Foundation
import JWTKit
import X509
import SwiftASN1
import Testing
@testable import SmartShoppingListServer

struct AppStoreSignedDataVerifierTests {
    @Test("Receipt certificate chain validates a signed transaction and rejects an altered signed body")
    func signedBodyIntegrity() async throws {
        let certificates = try AppStoreCertificateFixture()
        let verifier = try certificates.verifier()
        let signed = try await certificates.sign()
        _ = try await verifier.verify(signed, as: AppStoreTransaction.self, online: false)
        var parts = signed.split(separator: ".").map(String.init)
        var encoded = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.utf8.count % 4) % 4)
        let original = try #require(Data(base64Encoded: encoded))
        let altered = String(decoding: original, as: UTF8.self).replacingOccurrences(of: "2000001", with: "9999999")
        parts[1] = Data(altered.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let alteredSigned = parts.joined(separator: ".")
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(alteredSigned, as: AppStoreTransaction.self, online: false)
        }
    }

    @Test("Both receipt and intermediate purposes are required independently", arguments: [true, false])
    func receiptPurposeIsRequired(missingLeafPurpose: Bool) async throws {
        let certificates = try AppStoreCertificateFixture(
            receiptPurpose: !missingLeafPurpose,
            intermediatePurpose: missingLeafPurpose
        )
        let verifier = try certificates.verifier()
        let signed = try await certificates.sign()
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(signed, as: AppStoreTransaction.self, online: false)
        }
    }

    @Test("Client-supplied roots do not become trusted production roots")
    func productionAnchorRejectsSyntheticChain() async throws {
        let certificates = try AppStoreCertificateFixture()
        let verifier = try AppStoreSignedDataVerifier.live(transport: FixtureAppStoreTransport())
        let signed = try await certificates.sign()
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(signed, as: AppStoreTransaction.self, online: false)
        }
    }

    @Test("OCSP network failure remains retryable instead of rejecting a paid transaction")
    func ocspFailureIsRetryable() async throws {
        let certificates = try AppStoreCertificateFixture(includeOCSP: true)
        let verifier = try certificates.verifier()
        let signed = try await certificates.sign()
        await #expect(throws: AppStoreGatewayError.unavailable) {
            try await verifier.verify(signed, as: AppStoreTransaction.self, online: true)
        }
    }

    @Test("A signed certificate chain rejects family-shared ownership for a personal subscription")
    func rejectsFamilySharing() async throws {
        let certificates = try AppStoreCertificateFixture()
        let verifier = try certificates.verifier()
        let signed = try await certificates.sign(overrides: ["inAppOwnershipType": .string("FAMILY_SHARED")])
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(signed, as: AppStoreTransaction.self, online: false)
        }
    }

    @Test("Apple API lookup must independently match the transaction being acknowledged")
    func authoritativeLookupCannotChangePurchase() async throws {
        let certificates = try AppStoreCertificateFixture()
        let requested = try await certificates.sign()
        let other = try await certificates.sign(overrides: ["transactionId": .string("2000002")])
        let transport = FixtureAppStoreTransport(transaction: other)
        let gateway = try LiveAppStoreGateway(
            configuration: certificates.configuration,
            transport: transport,
            verifier: certificates.verifier(transport: transport)
        )
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await gateway.verifyTransaction(requested)
        }
    }

    @Test("A restored historical purchase is located through Apple's API and cannot trust a different bundle or environment")
    func authoritativeLookupValidatesApplication() async throws {
        let certificates = try AppStoreCertificateFixture()
        let requested = try await certificates.sign()
        let wrongBundle = try await certificates.sign(overrides: ["bundleId": .string("com.other.application")])
        let transport = FixtureAppStoreTransport(transaction: wrongBundle)
        let gateway = try LiveAppStoreGateway(
            configuration: certificates.configuration,
            transport: transport,
            verifier: certificates.verifier(transport: transport)
        )
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await gateway.verifyTransaction(requested)
        }
    }
}

/// Independent test PKI: none of these keys or certificates are Apple credentials or production trust roots.
private struct AppStoreCertificateFixture {
    let root: Certificate
    let chain: [Certificate]
    let key: ES256PrivateKey
    let configuration: AppStoreConfiguration

    init(receiptPurpose: Bool = true, intermediatePurpose: Bool = true, includeOCSP: Bool = false) throws {
        let key = ES256PrivateKey()
        let signer = try Certificate.PrivateKey(pemEncoded: key.pemRepresentation)
        let rootName = try DistinguishedName { CommonName("Issue 39 test root") }
        let intermediateName = try DistinguishedName { CommonName("Issue 39 test intermediate") }
        let start = Date(timeIntervalSince1970: 946_684_800)
        let end = Date(timeIntervalSince1970: 4_102_444_800)
        let ca = try Certificate.Extensions { Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil)) }
        root = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: signer.publicKey,
            notValidBefore: start,
            notValidAfter: end,
            issuer: rootName,
            subject: rootName,
            extensions: ca,
            issuerPrivateKey: signer
        )
        var intermediateExtensions = ca
        var leafExtensions = Certificate.Extensions()
        if intermediatePurpose {
            try intermediateExtensions.append(.init(
                oid: [1, 2, 840, 113635, 100, 6, 2, 1],
                critical: false,
                value: [5, 0]
            ))
        }
        if receiptPurpose {
            try leafExtensions.append(.init(oid: [1, 2, 840, 113635, 100, 6, 11, 1], critical: false, value: [5, 0]))
        }
        if includeOCSP {
            try leafExtensions.append(.init(AuthorityInformationAccess([
                .init(method: .ocspServer, location: .uniformResourceIdentifier("http://ocsp.apple.com/fixture"))
            ]), critical: false))
        }
        let intermediate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: signer.publicKey,
            notValidBefore: start,
            notValidAfter: end,
            issuer: rootName,
            subject: intermediateName,
            extensions: intermediateExtensions,
            issuerPrivateKey: signer
        )
        let leaf = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: signer.publicKey,
            notValidBefore: start,
            notValidAfter: end,
            issuer: intermediateName,
            subject: try DistinguishedName { CommonName("Issue 39 test receipt signer") },
            extensions: leafExtensions,
            issuerPrivateKey: signer
        )
        chain = [leaf, intermediate, root]
        self.key = key
        configuration = AppStoreConfiguration(
            bundleID: "com.plusprojects.SmartShoppingList",
            appAppleID: 1234,
            subscriptionGroupID: "90001",
            issuerID: "c1c9b8ab-f86c-4b72-8892-758643795fcf",
            keyID: "TESTKEY001",
            privateKeyPEM: key.pemRepresentation,
            monthlyProductID: "fixture.premium.monthly",
            annualProductID: "fixture.premium.annual",
            environment: .sandbox
        )
    }

    func verifier(
        transport: any AppStoreHTTPTransport = FixtureAppStoreTransport()
    ) throws -> AppStoreSignedDataVerifier {
        try AppStoreSignedDataVerifier(rootCertificates: [Data(root.serializeAsPEM().derBytes)], transport: transport)
    }

    func sign(overrides: [String: APIJSON] = [:]) async throws -> String {
        var fields: [String: APIJSON] = [
            "transactionId": .string("2000001"), "originalTransactionId": .string("1000001"),
            "bundleId": .string("com.plusprojects.SmartShoppingList"), "productId": .string("fixture.premium.monthly"),
            "environment": .string("Sandbox"), "appAccountToken": .string("29a03870-3aa3-4993-a8a2-af9b1effba9b"),
            "subscriptionGroupIdentifier": .string("90001"),
            "type": .string("Auto-Renewable Subscription"), "inAppOwnershipType": .string("PURCHASED"),
            "purchaseDate": .integer(1_728_000_000_000), "expiresDate": .integer(1_730_592_000_000),
            "signedDate": .integer(1_728_000_060_000)
        ]
        fields.merge(overrides) { _, replacement in replacement }
        let keys = await JWTKeyCollection().add(ecdsa: key)
        let certificates = try chain.map { try $0.serializeAsPEM().pemString }
        return try await keys.sign(
            FixturePayload(fields: fields),
            header: ["x5c": .array(certificates.map(JWTHeaderField.string))]
        )
    }

    private struct FixturePayload: JWTPayload {
        let fields: [String: APIJSON]

        init(fields: [String: APIJSON]) { self.fields = fields }

        init(from decoder: any Decoder) throws { fields = [:] }

        func encode(to encoder: any Encoder) throws {
            try APIJSON.object(fields).encode(to: encoder)
        }

        func verify(using algorithm: some JWTAlgorithm) throws {}
    }
}

private struct FixtureAppStoreTransport: AppStoreHTTPTransport {
    var transaction: String? = nil

    func get(path: String, authorization: String, environment: AppStoreEnvironment) async throws -> AppleHTTPResponse {
        guard let transaction else { throw AppStoreGatewayError.unavailable }
        return AppleHTTPResponse(
            status: 200,
            body: try APIEncoding.data(APIJSON.object(["signedTransactionInfo": .string(transaction)]))
        )
    }

    func ocsp(request: Data, uri: String) async throws -> AppleHTTPResponse {
        throw AppStoreGatewayError.unavailable
    }
}
