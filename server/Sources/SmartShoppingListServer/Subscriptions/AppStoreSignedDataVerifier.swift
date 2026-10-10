import Foundation
import JWTKit
import X509
import SwiftASN1

/// Trust is anchored to the bundled Apple certificate, never to roots supplied by a client or configuration.
struct AppStoreSignedDataVerifier: Sendable {
    private let verifier: X5CVerifier
    private let transport: any AppStoreHTTPTransport

    init(rootCertificates: [Data], transport: any AppStoreHTTPTransport) throws {
        verifier = try X5CVerifier(rootCertificates: rootCertificates)
        self.transport = transport
    }

    static func live(transport: any AppStoreHTTPTransport) throws -> Self {
        guard let url = Bundle.module.url(forResource: "AppleRootCA-G3", withExtension: "cer") else {
            throw AppStoreGatewayError.invalidConfiguration
        }
        return try Self(rootCertificates: [Data(contentsOf: url)], transport: transport)
    }

    func verify<Payload: ValidationTimePayload>(
        _ signed: String,
        as type: Payload.Type,
        online: Bool
    ) async throws -> Payload {
        let requester = AppStoreOCSPRequester(transport: transport)
        do {
            let parts = signed.split(separator: ".", omittingEmptySubsequences: false)
            guard signed.utf8.count <= 65_536, parts.count == 3, parts.allSatisfy({ !$0.isEmpty }),
                  let headerData = Self.base64URL(String(parts[0]))
            else {
                throw AppStoreGatewayError.rejected
            }
            let header = try JSONDecoder().decode(Header.self, from: headerData)
            guard header.alg == "ES256", header.x5c.count == 3,
                  header.x5c.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 16_384 })
            else {
                throw AppStoreGatewayError.rejected
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try await verifier.verifyJWS(Data(signed.utf8), as: type, jsonDecoder: decoder) {
                AppStoreCertificatePolicy()
                if online {
                    RFC5280Policy()
                    OCSPVerifierPolicy(failureMode: .hard, requester: requester)
                }
            }
        } catch {
            // A failed OCSP request must remain retryable; it cannot be treated as a rejected purchase.
            if await requester.networkFailed {
                throw AppStoreGatewayError.unavailable
            }
            throw AppStoreGatewayError.rejected
        }
    }

    private static func base64URL(_ value: String) -> Data? {
        var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.utf8.count % 4) % 4)
        return Data(base64Encoded: encoded)
    }

    private struct Header: Decodable {
        let alg: String
        let x5c: [String]
    }
}

/// A generally valid Apple certificate is insufficient: the verified chain must be for receipt signing.
private struct AppStoreCertificatePolicy: VerifierPolicy {
    var verifyingCriticalExtensions: [ASN1ObjectIdentifier] { [] }

    mutating func chainMeetsPolicyRequirements(chain: UnverifiedCertificateChain) async -> PolicyEvaluationResult {
        let receipt: ASN1ObjectIdentifier = [1, 2, 840, 113635, 100, 6, 11, 1]
        let intermediate: ASN1ObjectIdentifier = [1, 2, 840, 113635, 100, 6, 2, 1]
        guard chain.count == 3, chain[0].extensions.contains(where: { $0.oid == receipt }),
              chain[1].extensions.contains(where: { $0.oid == intermediate })
        else {
            return .failsToMeetPolicy(reason: "Not an App Store receipt certificate chain")
        }
        return .meetsPolicy
    }
}

private actor AppStoreOCSPRequester: OCSPRequester {
    let transport: any AppStoreHTTPTransport
    private(set) var networkFailed = false

    init(transport: any AppStoreHTTPTransport) { self.transport = transport }

    func query(request: [UInt8], uri: String) async -> OCSPRequesterQueryResult {
        do {
            let response = try await transport.ocsp(request: Data(request), uri: uri)
            guard response.status == 200, !response.body.isEmpty else { throw AppStoreGatewayError.unavailable }
            return .response(Array(response.body))
        } catch {
            networkFailed = true
            return .terminalError(AppStoreGatewayError.unavailable)
        }
    }
}
