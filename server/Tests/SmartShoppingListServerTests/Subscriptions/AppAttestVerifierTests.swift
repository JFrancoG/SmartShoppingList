import Foundation
import Crypto
import JWTKit
import SwiftASN1
@_spi(CMS) import X509
import Testing
@testable import SmartShoppingListServer

struct AppAttestVerifierTests {
    @Test
    func `A CBOR map consumes entries beyond the first byte without reusing slice offsets`() throws {
        // { "a": 1, "b": [2, 3] }, encoded independently from the production reader.
        var reader = try AppAttestCBOR.Reader(Data([0xA2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03]))
        let decoded = try reader.read()
        #expect(decoded["a"]?.integer == 1)
        #expect(decoded["b"]?.array?.compactMap(\.integer) == [2, 3])
        #expect(reader.isAtEnd)
    }

    @Test
    func `Truncated CBOR maps and every possible single-byte prefix are bounded failures or complete values`() throws {
        let map = Data([0xA2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x82, 0x02, 0x03])
        for length in 1..<map.count {
            var reader = try AppAttestCBOR.Reader(Data(map.prefix(length)))
            #expect(throws: AppStoreGatewayError.rejected) { try reader.read() }
        }
        for byte in UInt8.min...UInt8.max {
            var reader = try AppAttestCBOR.Reader(Data([byte]))
            do {
                _ = try reader.read()
                #expect(reader.isAtEnd)
            } catch let error as AppStoreGatewayError {
                #expect(error == .rejected)
            }
        }
    }

    @Test
    func `A distributed Sandbox app attests the exact recovery digest with a production key`() async throws {
        let fixture = try RecoveryAttestationFixture()
        let verifier = try fixture.verifier()
        try await verifier.verify(
            fixture.object,
            keyID: fixture.keyID,
            clientDataHash: fixture.digest,
            environment: .sandbox
        )
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(
                fixture.object,
                keyID: fixture.keyID,
                clientDataHash: Data(repeating: 0xEE, count: 32),
                environment: .sandbox
            )
        }
    }

    @Test(arguments: [
        "app", "counter", "credential", "cose", "category", "build", "nonce", "root", "expired",
        "receipt-app", "receipt-key", "receipt-time", "receipt-signature"
    ])
    func `Signed but incompatible attestation evidence is rejected`(_ defect: String) async throws {
        let fixture = try RecoveryAttestationFixture(defect: defect)
        let verifier = try fixture.verifier()
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await verifier.verify(
                fixture.object,
                keyID: fixture.keyID,
                clientDataHash: fixture.digest,
                environment: .sandbox
            )
        }
    }

    @Test
    func `Development evidence needs an explicit Sandbox allowance and never grants production recovery`() async throws {
        let fixture = try RecoveryAttestationFixture(development: true)
        let denied = try fixture.verifier()
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await denied.verify(fixture.object, keyID: fixture.keyID, clientDataHash: fixture.digest, environment: .sandbox)
        }
        let allowed = try fixture.verifier(allowDevelopment: true)
        try await allowed.verify(fixture.object, keyID: fixture.keyID, clientDataHash: fixture.digest, environment: .sandbox)
        await #expect(throws: AppStoreGatewayError.rejected) {
            try await allowed.verify(
                fixture.object,
                keyID: fixture.keyID,
                clientDataHash: fixture.digest,
                environment: .production
            )
        }
    }

    @Test(arguments: [Data([0xBF, 0xFF]), Data([0xA2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02]), Data([0x5A, 0xFF, 0xFF, 0xFF, 0xFF])])
    func `Malformed CBOR cannot bypass the bounded attestation decoder`(_ data: Data) throws {
        var reader = try AppAttestCBOR.Reader(data)
        #expect(throws: AppStoreGatewayError.rejected) { try reader.read() }
    }
}

/// Independent WebAuthn/COSE encoder and certificate issuer, not the production parser or trust root.
private struct RecoveryAttestationFixture {
    static let appID = "TEAM123456.com.plusprojects.SmartShoppingList"
    let object: Data
    let root: Certificate
    let keyID: String
    let digest = Data(repeating: UInt8(0x43), count: 32)

    init(defect: String = "", development: Bool = false) throws {
        let key = P256.Signing.PrivateKey()
        let credential = Data(SHA256.hash(data: key.publicKey.x963Representation))
        keyID = credential.base64EncodedString()
        let app = defect == "app" ? "TEAM999999.com.another.app" : Self.appID
        var auth = Data(SHA256.hash(data: Data(app.utf8)))
        auth.append(contentsOf: [0xC0, 0, 0, 0, defect == "counter" ? 1 : 0])
        auth.append(Data(development ? Array("appattestdevelop".utf8) : Array("appattest".utf8) + [0, 0, 0, 0, 0, 0, 0]))
        auth.append(contentsOf: [0, 32])
        auth.append(defect == "credential" ? Data(repeating: 7, count: 32) : credential)
        let x963 = key.publicKey.x963Representation
        auth.append(Self.map([
            (Self.integer(1), Self.integer(2)), (Self.integer(3), Self.integer(-7)),
            (Self.integer(-1), Self.integer(1)),
            (Self.integer(-2), Self.bytes(defect == "cose" ? Data(repeating: 8, count: 32) : x963.subdata(in: 1..<33))),
            (Self.integer(-3), Self.bytes(x963.subdata(in: 33..<65)))
        ]))
        auth.append(Self.map([
            (Self.text("apple_validation_category_01"), Self.bytes(Data([defect == "category" ? 5 : development ? 3 : 2, 0, 0, 0]))),
            (Self.text("apple_bundle_version_01"), Self.text(defect == "build" ? "5" : "6"))
        ]))
        let nonce = defect == "nonce" ? Data(repeating: 3, count: 32) : Data(SHA256.hash(data: auth + digest))
        let signer = try Certificate.PrivateKey(pemEncoded: key.pemRepresentation)
        let rootName = try DistinguishedName { CommonName("Recovery test root") }
        let intermediateName = try DistinguishedName { CommonName("Recovery test intermediate") }
        let start = Date().addingTimeInterval(-86_400)
        let end = Date().addingTimeInterval(defect == "expired" ? -3_600 : 86_400)
        let ca = try Certificate.Extensions { Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil)) }
        let issuedRoot = try Certificate(
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
        if defect == "root" {
            let other = try Certificate.PrivateKey(pemEncoded: P256.Signing.PrivateKey().pemRepresentation)
            root = try Certificate(
                version: .v3,
                serialNumber: .init(),
                publicKey: other.publicKey,
                notValidBefore: start,
                notValidAfter: end,
                issuer: rootName,
                subject: rootName,
                extensions: ca,
                issuerPrivateKey: other
            )
        } else {
            root = issuedRoot
        }
        let intermediate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: signer.publicKey,
            notValidBefore: start,
            notValidAfter: end,
            issuer: rootName,
            subject: intermediateName,
            extensions: ca,
            issuerPrivateKey: signer
        )
        var extensions = Certificate.Extensions()
        try extensions.append(.init(
            oid: [1, 2, 840, 113635, 100, 8, 2],
            critical: false,
            value: ArraySlice([0x30, 0x24, 0xA1, 0x22, 0x04, 0x20] + Array(nonce))
        ))
        let leaf = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: signer.publicKey,
            notValidBefore: start,
            notValidAfter: end,
            issuer: intermediateName,
            subject: try DistinguishedName { CommonName("Attested device key") },
            extensions: extensions,
            issuerPrivateKey: signer
        )
        let chain = Data([0x82]) + Self.bytes(Data(try leaf.serializeAsPEM().derBytes))
            + Self.bytes(Data(try intermediate.serializeAsPEM().derBytes))
        let receiptTime = Date().addingTimeInterval(defect == "receipt-time" ? -600 : 0)
        let created = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(receiptTime)
        let receiptFields: [(Int, Data)] = [
            (2, Data((defect == "receipt-app" ? "OTHER.app" : Self.appID).utf8)),
            (3, defect == "receipt-key" ? P256.Signing.PrivateKey().publicKey.derRepresentation
                : Data(try leaf.serializeAsPEM().derBytes)),
            (6, Data("ATTEST".utf8)), (12, Data(created.utf8))
        ]
        var payload = DER.Serializer()
        try payload.appendConstructedNode(identifier: .set) { set in
            for (id, bytes) in receiptFields {
                try set.appendConstructedNode(identifier: .sequence) { sequence in
                    try sequence.serialize(id)
                    try sequence.serialize(1)
                    try sequence.serialize(ASN1OctetString(contentBytes: ArraySlice(bytes)))
                }
            }
        }
        var receipt = try Data(CMS.sign(
            Data(payload.serializedBytes),
            additionalIntermediateCertificates: [intermediate],
            certificate: leaf,
            privateKey: signer,
            detached: false
        ))
        if defect == "receipt-signature" {
            receipt[receipt.count - 1] ^= 1
        }
        object = Self.map([
            (Self.text("fmt"), Self.text("apple-appattest")),
            (Self.text("authData"), Self.bytes(auth)),
            (Self.text("attStmt"), Self.map([
                (Self.text("x5c"), chain), (Self.text("receipt"), Self.bytes(receipt))
            ]))
        ])
    }

    func verifier(allowDevelopment: Bool = false) throws -> LiveAppAttestVerifier {
        try LiveAppAttestVerifier(
            configuration: .init(appID: Self.appID, minimumBuild: 6, allowDevelopment: allowDevelopment),
            rootCertificates: [Data(root.serializeAsPEM().derBytes)],
            receiptRootCertificates: [Data(root.serializeAsPEM().derBytes)]
        )
    }

    private static func header(_ major: UInt8, _ count: Int) -> Data {
        if count < 24 { return Data([major << 5 | UInt8(count)]) }
        if count < 256 { return Data([major << 5 | 24, UInt8(count)]) }
        return Data([major << 5 | 25, UInt8(count >> 8), UInt8(count & 255)])
    }

    private static func bytes(_ data: Data) -> Data { header(2, data.count) + data }
    private static func text(_ text: String) -> Data { header(3, text.utf8.count) + Data(text.utf8) }
    private static func integer(_ value: Int) -> Data { value < 0 ? header(1, -1 - value) : header(0, value) }
    private static func map(_ pairs: [(Data, Data)]) -> Data {
        pairs.reduce(header(5, pairs.count)) { $0 + $1.0 + $1.1 }
    }
}
