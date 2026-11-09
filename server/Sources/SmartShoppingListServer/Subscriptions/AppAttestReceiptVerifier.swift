import Foundation
import Crypto
import SwiftASN1
// Swift Certificates exposes CMS verification through this SPI in the pinned version.
// Keep the use isolated here; signature and path validation remain Apple's library implementation.
@_spi(CMS) import X509

struct AppAttestReceiptVerifier: Sendable {
    let roots: CertificateStore

    func verify(_ receipt: Data, appID: String, attestedKey: P256.Signing.PublicKey) async throws {
        let payload = try Self.payload(receipt)
        guard case .success = await CMS.isValidSignature(
            dataBytes: payload,
            signatureBytes: receipt,
            trustRoots: roots,
            allowAttachedContent: true,
            policy: { RFC5280Policy() }
        ) else {
            throw AppStoreGatewayError.rejected
        }
        let attributes = try Self.attributes(payload)
        guard let application = attributes[2], String(data: application, encoding: .utf8) == appID,
              let created = attributes[12], let text = String(data: created, encoding: .utf8),
              let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text),
              date >= Date().addingTimeInterval(-300), date <= Date().addingTimeInterval(60),
              attributes[6] == Data("ATTEST".utf8), let encodedKey = attributes[3]
        else {
            throw AppStoreGatewayError.rejected
        }
        // Apple's receipt can carry the DER attestation certificate; the documented identity is its public key.
        let key: P256.Signing.PublicKey
        if let certificate = try? Certificate(derEncoded: Array(encodedKey)),
           let publicKey = P256.Signing.PublicKey(certificate.publicKey) {
            key = publicKey
        } else {
            key = try P256.Signing.PublicKey(derRepresentation: encodedKey)
        }
        guard key.x963Representation == attestedKey.x963Representation else { throw AppStoreGatewayError.rejected }
    }

    private static func payload(_ receipt: Data) throws -> Data {
        guard !receipt.isEmpty, receipt.count <= 65_536 else { throw AppStoreGatewayError.rejected }
        let content = try children(BER.parse(Array(receipt)), identifier: .sequence)
        guard content.count == 2,
              try ASN1ObjectIdentifier(derEncoded: content[0]) == [1, 2, 840, 113549, 1, 7, 2]
        else {
            throw AppStoreGatewayError.rejected
        }
        let explicit = try children(content[1], identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific))
        guard explicit.count == 1 else { throw AppStoreGatewayError.rejected }
        let signed = try children(explicit[0], identifier: .sequence)
        guard signed.count >= 4 else { throw AppStoreGatewayError.rejected }
        let encapsulated = try children(signed[2], identifier: .sequence)
        guard encapsulated.count == 2,
              try ASN1ObjectIdentifier(derEncoded: encapsulated[0]) == [1, 2, 840, 113549, 1, 7, 1]
        else {
            throw AppStoreGatewayError.rejected
        }
        let octets = try children(encapsulated[1], identifier: .init(tagWithNumber: 0, tagClass: .contextSpecific))
        guard octets.count == 1 else { throw AppStoreGatewayError.rejected }
        return try Data(ASN1OctetString(berEncoded: octets[0]).bytes)
    }

    private static func attributes(_ payload: Data) throws -> [Int: Data] {
        let fields = try children(BER.parse(Array(payload)), identifier: .set)
        var values: [Int: Data] = [:]
        for field in fields {
            let parts = try children(field, identifier: .sequence)
            guard parts.count == 3, try Int(derEncoded: parts[1]) == 1 else { throw AppStoreGatewayError.rejected }
            let id = try Int(derEncoded: parts[0])
            guard values[id] == nil else { throw AppStoreGatewayError.rejected }
            values[id] = try Data(ASN1OctetString(berEncoded: parts[2]).bytes)
        }
        return values
    }

    private static func children(_ node: ASN1Node, identifier: ASN1Identifier) throws -> [ASN1Node] {
        guard node.identifier == identifier, case .constructed(let nodes) = node.content else {
            throw AppStoreGatewayError.rejected
        }
        let values = Array(nodes)
        guard values.count <= 64 else { throw AppStoreGatewayError.rejected }
        return values
    }
}
