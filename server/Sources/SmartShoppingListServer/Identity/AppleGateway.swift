import Foundation
import JWTKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The only boundary that contacts Apple. Test implementations cannot be selected by a request or environment flag.
protocol AppleGateway: Sendable {
    func verifyIdentityToken(_ token: String, nonce: String) async throws -> String
    func exchange(code: String) async throws -> AppleTokenResponse
    func validate(refreshToken: String) async throws -> AppleTokenResponse
}

struct AppleTokenResponse: Decodable, Sendable {
    let identityToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "id_token"
        case refreshToken = "refresh_token"
    }
}

enum AppleGatewayError: Error, Equatable {
    case rejected
    case invalidGrant
    case unavailable
    case invalidConfiguration
}

struct AppleHTTPResponse: Sendable {
    let status: Int
    let body: Data
}

protocol AppleHTTPTransport: Sendable {
    func fetchKeys() async throws -> AppleHTTPResponse
    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse
}

/// Apple's endpoints are fixed; credentials never follow a redirect to another origin.
final class AppleURLSessionTransport: NSObject, AppleHTTPTransport, URLSessionTaskDelegate, Sendable {
    func fetchKeys() async throws -> AppleHTTPResponse {
        try await send(URLRequest(url: URL(string: "https://appleid.apple.com/auth/keys")!))
    }

    func sendTokenForm(_ fields: [String: String]) async throws -> AppleHTTPResponse {
        var request = URLRequest(url: URL(string: "https://appleid.apple.com/auth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")="
                + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&").utf8)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> AppleHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (body, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, body.count <= 131_072 else {
            throw AppleGatewayError.unavailable
        }
        return AppleHTTPResponse(status: response.statusCode, body: body)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

actor LiveAppleGateway: AppleGateway {
    private let configuration: AppleSignInConfiguration
    private let transport: any AppleHTTPTransport
    private let now: @Sendable () -> Date
    private var cachedVerifier: AppleIdentityTokenVerifier?
    private var cachedKeyIDs: Set<String> = []
    private var fetchedAt: Date?
    private var keyFetch: Task<(AppleIdentityTokenVerifier, Set<String>), any Error>?

    init(
        configuration: AppleSignInConfiguration,
        transport: any AppleHTTPTransport = AppleURLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
    }

    func verifyIdentityToken(_ token: String, nonce: String) async throws -> String {
        let keyID = try tokenKeyID(token)
        let expired = fetchedAt.map { now().timeIntervalSince($0) >= 3_600 } ?? true
        if expired || !cachedKeyIDs.contains(keyID) {
            // Bound unknown-kid refreshes; a rotated key can be retried after this short cooldown.
            if !expired, let fetchedAt, now().timeIntervalSince(fetchedAt) < 30 {
                throw AppleGatewayError.rejected
            }
            try await refreshKeys()
        }
        guard let verifier = cachedVerifier else { throw AppleGatewayError.unavailable }
        do {
            return try await verifier.verify(token, expectedNonce: nonce)
        } catch {
            throw AppleGatewayError.rejected
        }
    }

    func exchange(code: String) async throws -> AppleTokenResponse {
        try await tokenRequest(fields: ["grant_type": "authorization_code", "code": code])
    }

    func validate(refreshToken: String) async throws -> AppleTokenResponse {
        try await tokenRequest(fields: ["grant_type": "refresh_token", "refresh_token": refreshToken])
    }

    private func tokenRequest(fields: [String: String]) async throws -> AppleTokenResponse {
        do {
            var fields = fields
            fields["client_id"] = configuration.clientID
            fields["client_secret"] = try await configuration.clientSecret(now: now())
            let response = try await transport.sendTokenForm(fields)
            if response.status == 400 {
                let body = try? JSONDecoder().decode(AppleErrorResponse.self, from: response.body)
                if body?.error == "invalid_grant" {
                    throw AppleGatewayError.invalidGrant
                }
                throw AppleGatewayError.unavailable
            }
            guard response.status == 200 else { throw AppleGatewayError.unavailable }
            let tokens = try JSONDecoder().decode(TokenResponseBody.self, from: response.body)
            guard !tokens.accessToken.isEmpty, tokens.tokenType == "Bearer", tokens.expiresIn > 0 else {
                throw AppleGatewayError.unavailable
            }
            return AppleTokenResponse(identityToken: tokens.identityToken, refreshToken: tokens.refreshToken)
        } catch let error as AppleGatewayError {
            throw error
        } catch {
            throw AppleGatewayError.unavailable
        }
    }

    private func refreshKeys() async throws {
        if let keyFetch {
            let (verifier, identifiers) = try await keyFetch.value
            cachedVerifier = verifier
            cachedKeyIDs = identifiers
            return
        }
        let transport = transport
        let audience = configuration.clientID
        let now = now
        let task = Task {
            let response = try await transport.fetchKeys()
            guard response.status == 200 else { throw AppleGatewayError.unavailable }
            let keys = try JSONDecoder().decode(JWKS.self, from: response.body)
            let verifier = try await AppleIdentityTokenVerifier(audience: audience, trustedJWKS: keys, now: now)
            return (verifier, Set(keys.keys.compactMap { $0.keyIdentifier?.string }))
        }
        keyFetch = task
        defer { keyFetch = nil }
        do {
            let (verifier, identifiers) = try await task.value
            cachedVerifier = verifier
            cachedKeyIDs = identifiers
            fetchedAt = now()
        } catch {
            throw AppleGatewayError.unavailable
        }
    }

    private func tokenKeyID(_ token: String) throws -> String {
        guard let header = token.split(separator: ".").first else { throw AppleGatewayError.rejected }
        var encoded = header.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["alg"] as? String == "RS256", let keyID = json["kid"] as? String, !keyID.isEmpty
        else {
            throw AppleGatewayError.rejected
        }
        return keyID
    }

    private struct TokenResponseBody: Decodable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
        let identityToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case identityToken = "id_token"
            case refreshToken = "refresh_token"
        }
    }

    private struct AppleErrorResponse: Decodable {
        let error: String
    }
}
