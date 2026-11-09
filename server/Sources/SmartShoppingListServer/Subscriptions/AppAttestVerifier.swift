import Foundation
import JWTKit
import X509
import SwiftASN1
import Vapor

struct AppAttestConfiguration: Sendable {
    let appID: String
    let minimumBuild: Int
    var allowDevelopment = false

    static func load(environment: (String) -> String? = Environment.get) throws -> Self? {
        let appID = environment("APP_ATTEST_APP_ID")
        let build = environment("APP_ATTEST_MIN_BUILD")
        let development = environment("APP_ATTEST_ALLOW_DEVELOPMENT")
        guard appID != nil || build != nil || development != nil else { return nil }
        guard let appID, let build, let minimum = Int(build), minimum > 0,
              appID.hasSuffix(".com.plusprojects.SmartShoppingList"),
              appID.utf8.count == 10 + ".com.plusprojects.SmartShoppingList".utf8.count,
              appID.prefix(10).utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
              development == nil || development == "true" || development == "false"
        else {
            throw AppStoreGatewayError.invalidConfiguration
        }
        return Self(appID: appID, minimumBuild: minimum, allowDevelopment: development == "true")
    }
}

protocol AppAttestVerifying: Sendable {
    func verify(_ attestation: Data, keyID: String, clientDataHash: Data, environment: AppStoreEnvironment) async throws
}

/// One attestation is bound to one explicit recovery request; it is not accepted as an Apple-account identity.
struct LiveAppAttestVerifier: AppAttestVerifying {
    let configuration: AppAttestConfiguration
    private let roots: CertificateStore
    private let receiptVerifier: AppAttestReceiptVerifier


    static func live(configuration: AppAttestConfiguration) throws -> Self {
        guard let path = Bundle.module.url(forResource: "Apple_App_Attestation_Root_CA", withExtension: "pem"),
              let receiptPath = Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer")
        else {
            throw AppStoreGatewayError.invalidConfiguration
        }
        let root = try Certificate(pemEncoded: String(contentsOf: path, encoding: .utf8))
        return try Self(
            configuration: configuration,
            rootCertificates: [Data(root.serializeAsPEM().derBytes)],
            receiptRootCertificates: [Data(contentsOf: receiptPath)]
        )
    }

    func verify(_ attestation: Data, keyID: String, clientDataHash: Data, environment: AppStoreEnvironment) async throws {
        do {
            guard let keyBytes = Data(base64Encoded: keyID), keyBytes.count == 32, clientDataHash.count == 32 else {
                throw AppStoreGatewayError.rejected
            }
            var reader = try AppAttestCBOR.Reader(attestation)
            let object = try reader.read()
            guard reader.isAtEnd, object["fmt"]?.text == "apple-appattest",
                  let certificates = object["attStmt"]?["x5c"]?.array, certificates.count == 2,
                  let leafBytes = certificates[0].bytes, let intermediateBytes = certificates[1].bytes,
                  let authData = object["authData"]?.bytes, authData.count >= 87,
                  let receipt = object["attStmt"]?["receipt"]?.bytes, !receipt.isEmpty
            else {
                throw AppStoreGatewayError.rejected
            }
            let leaf = try Certificate(derEncoded: Array(leafBytes))
            let intermediate = try Certificate(derEncoded: Array(intermediateBytes))
            var verifier = Verifier(rootCertificates: roots) { RFC5280Policy() }
            guard case .validCertificate = await verifier.validate(
                leaf: leaf,
                intermediates: CertificateStore([intermediate])
            ) else {
                throw AppStoreGatewayError.rejected
            }
            let nonce = Data(SHA256.hash(data: authData + clientDataHash))
            let nonceOID: ASN1ObjectIdentifier = [1, 2, 840, 113635, 100, 8, 2]
            guard let extensionValue = leaf.extensions.first(where: { $0.oid == nonceOID }),
                  Data(extensionValue.value) == Data([0x30, 0x24, 0xA1, 0x22, 0x04, 0x20]) + nonce,
                  let key = P256.Signing.PublicKey(leaf.publicKey),
                  Data(SHA256.hash(data: key.x963Representation)) == keyBytes
            else {
                throw AppStoreGatewayError.rejected
            }
            try verifyAuthenticator(authData, key: key, keyID: keyBytes, environment: environment)
            try await receiptVerifier.verify(receipt, appID: configuration.appID, attestedKey: key)
        } catch {
            throw AppStoreGatewayError.rejected
        }
    }

    private func verifyAuthenticator(
        _ data: Data,
        key: P256.Signing.PublicKey,
        keyID: Data,
        environment: AppStoreEnvironment
    ) throws {
        let bytes = Array(data)
        let production = Array("appattest".utf8) + Array(repeating: UInt8(0), count: 7)
        let development = Array("appattestdevelop".utf8)
        let aaguid = Array(bytes[37..<53])
        let permitsDevelopment = configuration.allowDevelopment && environment == .sandbox
        guard Data(bytes[0..<32]) == Data(SHA256.hash(data: Data(configuration.appID.utf8))),
              bytes[32] & 0x40 != 0, bytes[33..<37].allSatisfy({ $0 == 0 }),
              aaguid == production || permitsDevelopment && aaguid == development,
              bytes[53] == 0, bytes[54] == 32, Data(bytes[55..<87]) == keyID
        else {
            throw AppStoreGatewayError.rejected
        }
        var reader = try AppAttestCBOR.Reader(Data(bytes.dropFirst(87)))
        let cose = try reader.read()
        guard cose[1]?.integer == 2, cose[3]?.integer == -7, cose[-1]?.integer == 1,
              let x = cose[-2]?.bytes, let y = cose[-3]?.bytes, x.count == 32, y.count == 32,
              Data([4]) + x + y == key.x963Representation, !reader.isAtEnd
        else {
            throw AppStoreGatewayError.rejected
        }
        let extensions = try reader.read()
        guard reader.isAtEnd, let category = extensions["apple_validation_category_01"]?.bytes,
              category.count == 4, category.dropFirst().allSatisfy({ $0 == 0 }),
              let buildText = extensions["apple_bundle_version_01"]?.text, let build = Int(buildText),
              build >= configuration.minimumBuild,
              category[0] == 4 || environment == .sandbox && category[0] == 2
                  || permitsDevelopment && aaguid == development && category[0] == 3
        else {
            throw AppStoreGatewayError.rejected
        }
    }
}

extension LiveAppAttestVerifier {
    init(configuration: AppAttestConfiguration, rootCertificates: [Data], receiptRootCertificates: [Data]) throws {
        self.configuration = configuration
        self.roots = CertificateStore(try rootCertificates.map { try Certificate(derEncoded: Array($0)) })
        receiptVerifier = AppAttestReceiptVerifier(
            roots: CertificateStore(try receiptRootCertificates.map { try Certificate(derEncoded: Array($0)) })
        )
    }
}
