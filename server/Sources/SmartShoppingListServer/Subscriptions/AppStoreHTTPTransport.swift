import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol AppStoreHTTPTransport: Sendable {
    func get(path: String, authorization: String, environment: AppStoreEnvironment) async throws -> AppleHTTPResponse
    func ocsp(request: Data, uri: String) async throws -> AppleHTTPResponse
}

/// API credentials stay on the fixed StoreKit origin; OCSP requests never receive them.
final class AppStoreURLSessionTransport: NSObject, AppStoreHTTPTransport, URLSessionTaskDelegate, Sendable {
    func get(path: String, authorization: String, environment: AppStoreEnvironment) async throws -> AppleHTTPResponse {
        guard path.hasPrefix("/inApps/v1/"), !path.contains("?"), !path.contains("#"),
              let url = URL(string: environment.origin + path)
        else {
            throw AppStoreGatewayError.unavailable
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + authorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    func ocsp(request body: Data, uri: String) async throws -> AppleHTTPResponse {
        guard uri.utf8.count <= 2_048, let url = URL(string: uri),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), host.hasSuffix(".apple.com"),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 80 || url.port == 443
        else {
            throw AppStoreGatewayError.unavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/ocsp-request", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> AppleHTTPResponse {
        do {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (body, response) = try await session.data(for: request)
            guard body.count <= 1_048_576, let response = response as? HTTPURLResponse else {
                throw AppStoreGatewayError.unavailable
            }
            return AppleHTTPResponse(status: response.statusCode, body: body)
        } catch {
            throw AppStoreGatewayError.unavailable
        }
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
