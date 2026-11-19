import Crypto
import Foundation
import SwiftASN1
import Testing
import X509
@testable import SmartShoppingListServer

struct AppAttestReceiptVerifierTests {
    // The PKCS #7 receipt and this public key come from Apple's signed example at
    // https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide
    // Evaluate the historical fixture at its documented issuance date.
    private let appID = "1234567890.com.example.myapp"
    private let issued = Date(timeIntervalSince1970: 1_776_795_192.153)
    private let publicKey = """
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEQzJUSs8yPbd0RDyq8zn1bn6VxyT6
        wsFCWfNl4kRWULK1+yhbz1Sby2BZRBLnaCokJ+6tqftS3+0LGrF+0J+pvQ==
        -----END PUBLIC KEY-----
        """

    @Test func `Apple guide receipt validates the attested key and rejects altered signed content`() async throws {
        let url = try #require(Bundle.module.url(forResource: "AppleAppAttestGuideReceipt", withExtension: "p7"))
        var receipt = try Data(contentsOf: url)
        let key = try P256.Signing.PublicKey(pemRepresentation: publicKey)
        let root = try Certificate(derEncoded: Array(AppAttestReceiptVerifier.appleRootCertificate()))
        let verifier = AppAttestReceiptVerifier(roots: CertificateStore([root]))
        try await verifier.verify(receipt, appID: appID, attestedKey: key, at: issued)

        let challenge = try #require(receipt.range(of: Data("example_server_challenge".utf8)))
        receipt[challenge.lowerBound] ^= 1
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(receipt, appID: appID, attestedKey: key, at: issued)
        }
    }
}
