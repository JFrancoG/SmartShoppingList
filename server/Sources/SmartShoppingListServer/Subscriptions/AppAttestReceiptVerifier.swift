import Foundation
import Crypto
import SwiftASN1
// Swift Certificates exposes CMS verification through this SPI in the pinned version.
// Keep the use isolated here; signature and path validation remain Apple's library implementation.
@_spi(CMS) @_spi(FixedExpiryValidationTime) import X509

struct AppAttestReceiptVerifier: Sendable {
    let roots: CertificateStore

    static func appleRootCertificate() throws -> Data {
        guard let url = Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer") else {
            throw AppStoreGatewayError.invalidConfiguration
        }
        return try Data(contentsOf: url)
    }

    func verify(_ receipt: Data, appID: String, attestedKey: P256.Signing.PublicKey, at verificationTime: Date = .now) async throws {
        let (payload, signature) = try Self.receiptForVerification(receipt)
        guard case .success = await CMS.isValidSignature(
            dataBytes: payload,
            signatureBytes: signature,
            trustRoots: roots,
            allowAttachedContent: true,
            policy: { RFC5280Policy(fixedExpiryValidationTime: verificationTime) }
        ) else {
            throw AppStoreGatewayError.rejected
        }
        let attributes = try Self.attributes(payload)
        guard let application = attributes[2], String(data: application, encoding: .utf8) == appID,
              let created = attributes[12], let text = String(data: created, encoding: .utf8),
              let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text),
              date >= verificationTime.addingTimeInterval(-300), date <= verificationTime.addingTimeInterval(60),
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

    private static func receiptForVerification(_ receipt: Data) throws -> (payload: Data, signature: Data) {
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
        let payload = try ASN1OctetString(berEncoded: octets[0])

        // swift-certificates 1.20 parses the attached OCTET STRING as DER in its CMS decoder.
        // Give it the same content octets in primitive form. Preserve every signed attribute,
        // certificate and signature verbatim from Apple's BER message.
        var primitive = DER.Serializer()
        try primitive.serialize(payload)
        let explicitTag = ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific)
        let attachment = encoding(explicitTag, [primitive.serializedBytes[...]])
        var fields = signed.map(\.encodedBytes)
        fields[2] = encoding(.sequence, [encapsulated[0].encodedBytes, attachment])

        // RFC 5754 §2 requires SHA-256 digest parameters NULL and absent to be equivalent.
        // Only these two unsigned AlgorithmIdentifiers need the spelling expected by X509.
        let algorithms = try children(signed[1], identifier: .set)
        fields[1] = try setEncoding(.set, algorithms.map(canonicalDigest))
        // RFC 5652 permits BER ordering for CertificateSet. X509 reads this set as DER.
        if signed[3].identifier == explicitTag {
            let certificates = try children(signed[3], identifier: explicitTag)
            fields[3] = setEncoding(explicitTag, certificates.map(\.encodedBytes))
        }
        let signers = try children(signed[signed.count - 1], identifier: .set)
        guard signers.count == 1 else { throw AppStoreGatewayError.rejected }
        let signer = try children(signers[0], identifier: .sequence)
        guard signer.count >= 5 else { throw AppStoreGatewayError.rejected }
        var signerFields = signer.map(\.encodedBytes)
        signerFields[2] = try canonicalDigest(signer[2])
        fields[fields.count - 1] = encoding(.set, [encoding(.sequence, signerFields)])
        let signedData = encoding(explicitTag, [encoding(.sequence, fields)])
        let signature = encoding(.sequence, [content[0].encodedBytes, signedData])
        return (Data(payload.bytes), Data(signature))
    }

    private static func canonicalDigest(_ algorithm: ASN1Node) throws -> ArraySlice<UInt8> {
        let parts = try children(algorithm, identifier: .sequence)
        guard parts.count == 2, try ASN1ObjectIdentifier(derEncoded: parts[0]) == [2, 16, 840, 1, 101, 3, 4, 2, 1],
              parts[1].encodedBytes.elementsEqual([0x05, 0x00]) else { return algorithm.encodedBytes }
        return encoding(.sequence, [parts[0].encodedBytes])
    }

    private static func setEncoding(_ identifier: ASN1Identifier, _ elements: [ArraySlice<UInt8>]) -> ArraySlice<UInt8> {
        encoding(identifier, elements.sorted { $0.lexicographicallyPrecedes($1) })
    }

    private static func encoding(_ identifier: ASN1Identifier, _ children: [ArraySlice<UInt8>]) -> ArraySlice<UInt8> {
        var writer = DER.Serializer()
        writer.appendConstructedNode(identifier: identifier) { writer in
            for child in children { writer.serializeRawBytes(child) }
        }
        return writer.serializedBytes[...]
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
