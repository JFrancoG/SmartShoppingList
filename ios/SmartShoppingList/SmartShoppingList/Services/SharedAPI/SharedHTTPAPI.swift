import Foundation

protocol SharedHTTPTransport: Sendable {
    func response(to request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

actor URLSessionSharedTransport: SharedHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func response(to request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await session.data(for: request, delegate: RejectSharedAPIRedirects())
        guard let response = result.1 as? HTTPURLResponse else { throw SharedAPIError.invalidResponse }
        return (result.0, response)
    }
}

/// Neither bearer credentials nor one-use Apple credentials may follow a redirect.
final class RejectSharedAPIRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Swift 6.4 crashes generating the async delegate's Objective-C thunk (Xcode 27A266a).
        // Keep this stateless SDK callback behind URLSession's async data API, without concurrency escapes.
        completionHandler(nil)
    }
}

actor SharedHTTPAPI: SharedShoppingAPI {
    private let configuration: SharedAPIConfiguration
    private let transport: any SharedHTTPTransport

    init(configuration: SharedAPIConfiguration, transport: any SharedHTTPTransport = URLSessionSharedTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    func createChallenge() async throws -> SharedChallenge {
        let challenge: SharedChallenge = try await send(
            path: "v1/auth/challenges",
            method: "POST",
            body: EmptySharedRequest(),
            token: nil,
            status: 201
        )
        guard SharedAPIConfiguration.isCanonicalSecret(challenge.nonce) else { throw SharedAPIError.invalidResponse }
        return challenge
    }

    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession {
        let session: SharedSession = try await send(
            path: "v1/auth/apple",
            method: "POST",
            body: request,
            token: nil,
            status: 200
        )
        guard session.tokenType == "Bearer", SharedAPIConfiguration.isCanonicalSecret(session.accessToken) else {
            throw SharedAPIError.invalidResponse
        }
        return session
    }

    func currentUser(token: String) async throws -> SharedUser {
        try await get(path: "v1/me", token: token)
    }

    func logout(token: String) async throws {
        _ = try await exchange(
            path: "v1/session",
            method: "DELETE",
            body: nil,
            token: token,
            status: 204
        )
    }

    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup {
        try await send(
            path: "v1/groups",
            method: "POST",
            body: request,
            token: token,
            status: 201
        )
    }

    func stores(groupID: UUID, token: String) async throws -> [SharedStore] {
        let stores = try await pages(StorePage.self, path: "v1/groups/\(id(groupID))/stores", token: token)
        guard stores.allSatisfy({ $0.groupId == groupID }) else { throw SharedAPIError.invalidResponse }
        return stores
    }

    func createInvitation(groupID: UUID, token: String) async throws -> CreatedInvitation {
        let created: CreatedInvitation = try await send(
            path: "v1/groups/\(id(groupID))/invitations",
            method: "POST",
            body: EmptySharedRequest(),
            token: token,
            status: 201
        )
        let link = try configuration.invitation(from: created.url)
        guard link.id == created.invitation.id, created.invitation.groupId == groupID else {
            throw SharedAPIError.invalidResponse
        }
        return created
    }

    func invitations(groupID: UUID, token: String) async throws -> [SharedInvitation] {
        let invitations = try await pages(
            InvitationPage.self,
            path: "v1/groups/\(id(groupID))/invitations",
            token: token
        )
        guard invitations.allSatisfy({ $0.groupId == groupID }) else { throw SharedAPIError.invalidResponse }
        return invitations
    }

    func revokeInvitation(groupID: UUID, invitationID: UUID, token: String) async throws {
        _ = try await exchange(
            path: "v1/groups/\(id(groupID))/invitations/\(id(invitationID))",
            method: "DELETE",
            body: nil,
            token: token,
            status: 204
        )
    }

    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview {
        try await send(
            path: "v1/invitations/\(id(invitation.id))/preview",
            method: "POST",
            body: InvitationSecret(token: invitation.token),
            token: token,
            status: 200
        )
    }

    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup {
        try await send(
            path: "v1/invitations/\(id(invitation.id))/accept",
            method: "POST",
            body: InvitationSecret(token: invitation.token),
            token: token,
            status: 200
        )
    }

    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem] {
        let response: AddedItemList = try await send(
            path: "v1/groups/\(id(groupID))/item-batches",
            method: "POST",
            body: request,
            token: token,
            status: 201
        )
        guard response.items.count == request.items.count,
              Set(response.items.map(\.id)).count == response.items.count,
              response.items.allSatisfy({ $0.groupId == groupID && Self.isPending($0) }) else {
            throw SharedAPIError.invalidResponse
        }
        return response.items
    }

    func finalizePurchase(
        _ request: FinalizePurchaseRequest,
        groupID: UUID,
        token: String
    ) async throws -> PurchaseResult {
        guard (1...50).contains(request.items.count),
              Set(request.items.map(\.id)).count == request.items.count else { throw SharedAPIError.invalidResponse }
        let response: PurchaseResult = try await send(
            path: "v1/groups/\(id(groupID))/purchases",
            method: "POST",
            body: request,
            token: token,
            status: 200,
            purchaseContext: PurchaseConflictContext(groupID: groupID, request: request)
        )
        let versions = Dictionary(uniqueKeysWithValues: request.items.map { ($0.id, $0.expectedVersion) })
        guard response.items.count == request.items.count,
              Set(response.items.map(\.id)) == Set(versions.keys),
              response.items.allSatisfy({ item in
                  guard let version = versions[item.id], version < 9_007_199_254_740_991 else { return false }
                  return item.groupId == groupID && item.storeId == request.storeId && item.status == "purchased"
                      && item.version == version + 1 && item.purchasedBy != nil
                      && item.purchasedAt == response.confirmedAt
              }) else { throw SharedAPIError.invalidResponse }
        return response
    }

    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem] {
        let items = try await pages(
            PendingItemPage.self,
            path: "v1/groups/\(id(groupID))/stores/\(id(storeID))/items",
            token: token
        )
        guard items.allSatisfy({ $0.groupId == groupID && $0.storeId == storeID && Self.isPending($0) }) else {
            throw SharedAPIError.invalidResponse
        }
        return items
    }

    private func pages<Page: SharedAPIPage>(
        _ type: Page.Type,
        path: String,
        token: String
    ) async throws -> [Page.Element] {
        var result: [Page.Element] = []
        var indices: [UUID: Int] = [:]
        var seenCursors: Set<String> = []
        var cursor: String?
        repeat {
            try Task.checkCancellation()
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor {
                guard !cursor.isEmpty, cursor.utf8.count <= 512, seenCursors.insert(cursor).inserted,
                      seenCursors.count < 100 else {
                    throw SharedAPIError.invalidResponse
                }
                query.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let page: Page = try await get(path: path, token: token, query: query)
            guard page.entries.count <= 100 else { throw SharedAPIError.invalidResponse }
            for entry in page.entries {
                if let index = indices[entry.id] {
                    if Page.version(of: entry) >= Page.version(of: result[index]) {
                        result[index] = entry
                    }
                } else {
                    indices[entry.id] = result.count
                    result.append(entry)
                }
            }
            cursor = page.nextCursor
        } while cursor != nil
        return result
    }

    private func get<Response: Decodable & Sendable>(
        path: String,
        token: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        let data = try await exchange(
            path: path,
            method: "GET",
            body: nil,
            token: token,
            status: 200,
            query: query
        )
        return try decode(Response.self, from: data)
    }

    private func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        method: String,
        body: Body,
        token: String?,
        status: Int,
        purchaseContext: PurchaseConflictContext? = nil
    ) async throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(body)
        guard encoded.count <= 128 * 1_024 else { throw SharedAPIError.requestTooLarge }
        let data = try await exchange(
            path: path,
            method: method,
            body: encoded,
            token: token,
            status: status,
            purchaseContext: purchaseContext
        )
        return try decode(Response.self, from: data)
    }

    private func exchange(
        path: String,
        method: String,
        body: Data?,
        token: String?,
        status: Int,
        query: [URLQueryItem] = [],
        purchaseContext: PurchaseConflictContext? = nil
    ) async throws -> Data {
        try Task.checkCancellation()
        let endpoint = configuration.baseURL.appending(path: path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SharedAPIError.configuration
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw SharedAPIError.configuration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            guard SharedAPIConfiguration.isCanonicalSecret(token) else {
                throw SharedAPIError.server(
                    status: 401,
                    code: "invalid_session",
                    requestID: nil,
                    retryAfter: nil
                )
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.response(to: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SharedAPIError.transport
        }
        guard response.url == request.url, data.count <= 1_024 * 1_024 else { throw SharedAPIError.invalidResponse }
        guard response.statusCode == status else {
            let failure = try? SharedJSON.decoder().decode(ServerFailure.self, from: data)
            if failure?.code == "item_conflict", let purchaseContext {
                guard response.statusCode == 409 else { throw SharedAPIError.invalidResponse }
                try purchaseContext.validate(data)
            }
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw SharedAPIError.server(
                status: response.statusCode,
                code: failure?.code ?? "invalid_response",
                requestID: failure?.requestId,
                retryAfter: retryAfter.flatMap { $0 >= 0 ? $0 : nil }
            )
        }
        if status != 204 {
            let contentType = response.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first
            guard contentType?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
                throw SharedAPIError.invalidResponse
            }
        }
        return data
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try SharedJSON.decoder().decode(type, from: data)
        } catch {
            throw SharedAPIError.invalidResponse
        }
    }

    private func id(_ value: UUID) -> String { value.uuidString.lowercased() }

    private static func isPending(_ item: SharedItem) -> Bool {
        item.status == "pending" && (1...9_007_199_254_740_991).contains(item.version)
            && item.purchasedBy == nil && item.purchasedAt == nil
    }
}

private struct EmptySharedRequest: Encodable {}

private struct InvitationSecret: Encodable {
    let token: String
}

private struct ServerFailure: Decodable {
    private let errorCode: String
    private let correlationID: UUID

    var code: String { errorCode }
    var requestId: UUID { correlationID }
}

extension ServerFailure {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let message = try values.decode(String.self, forKey: .message)
        guard (1...500).contains(message.unicodeScalars.count) else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: values,
                debugDescription: "The API error message must contain 1 to 500 Unicode scalars"
            )
        }
        errorCode = try values.decode(String.self, forKey: .code)
        correlationID = try values.decode(UUID.self, forKey: .requestId)
    }

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestId
    }
}

private struct AddedItemList: Decodable {
    let items: [SharedItem]
}

private protocol SharedAPIPage: Decodable, Sendable {
    associatedtype Element: Identifiable & Sendable where Element.ID == UUID
    var entries: [Element] { get }
    var nextCursor: String? { get }
    static func version(of element: Element) -> Int
}

private extension SharedAPIPage {
    static func version(of element: Element) -> Int { 0 }
}

private struct StorePage: SharedAPIPage {
    let stores: [SharedStore]
    let nextCursor: String?
    var entries: [SharedStore] { stores }
}

private struct InvitationPage: SharedAPIPage {
    let invitations: [SharedInvitation]
    let nextCursor: String?
    var entries: [SharedInvitation] { invitations }
}

private struct PendingItemPage: SharedAPIPage {
    let items: [SharedItem]
    let nextCursor: String?
    var entries: [SharedItem] { items }
    static func version(of element: SharedItem) -> Int { element.version }
}

/// Both canonical UTC timestamps accepted by the contract are decoded explicitly.
enum SharedJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard value.hasSuffix("Z") else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a UTC timestamp")
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid UTC timestamp")
            }
            return date
        }
        return decoder
    }
}

extension StorePage {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stores = try values.decode([SharedStore].self, forKey: .stores)
        nextCursor = try values.decode(String?.self, forKey: .nextCursor)
    }

    enum CodingKeys: String, CodingKey {
        case stores
        case nextCursor
    }
}

extension InvitationPage {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        invitations = try values.decode([SharedInvitation].self, forKey: .invitations)
        nextCursor = try values.decode(String?.self, forKey: .nextCursor)
    }

    enum CodingKeys: String, CodingKey {
        case invitations
        case nextCursor
    }
}

extension PendingItemPage {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decode([SharedItem].self, forKey: .items)
        nextCursor = try values.decode(String?.self, forKey: .nextCursor)
    }

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor
    }
}


private struct PurchaseConflictContext {
    let groupID: UUID
    let request: FinalizePurchaseRequest

    func validate(_ data: Data) throws {
        guard let payload = try? SharedJSON.decoder().decode(PurchaseConflictPayload.self, from: data),
              (1...request.items.count).contains(payload.conflicts.count),
              Set(payload.conflicts.map(\.itemId)).count == payload.conflicts.count else {
            throw SharedAPIError.invalidResponse
        }
        for conflict in payload.conflicts {
            guard let selected = request.items.first(where: { $0.id == conflict.itemId }) else {
                throw SharedAPIError.invalidResponse
            }
            if conflict.reason == "not_found" {
                guard conflict.current == nil else { throw SharedAPIError.invalidResponse }
                continue
            }
            guard let item = conflict.current, item.id == conflict.itemId, item.groupId == groupID,
                  (1...9_007_199_254_740_991).contains(item.version) else {
                throw SharedAPIError.invalidResponse
            }
            let valid: Bool
            switch conflict.reason {
            case "store_mismatch":
                valid = item.storeId != request.storeId
            case "not_pending":
                valid = item.storeId == request.storeId && ["purchased", "cancelled"].contains(item.status)
            case "version_mismatch":
                valid = item.storeId == request.storeId && item.status == "pending"
                    && item.version != selected.expectedVersion
            default:
                valid = false
            }
            guard valid else { throw SharedAPIError.invalidResponse }
        }
    }
}

private struct PurchaseConflictPayload: Decodable {
    let conflicts: [PurchaseConflict]
}

private struct PurchaseConflict: Decodable {
    let itemId: UUID
    let reason: String
    let current: SharedItem?
}

private extension PurchaseConflict {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try values.decode(UUID.self, forKey: .itemId)
        reason = try values.decode(String.self, forKey: .reason)
        current = try values.decode(SharedItem?.self, forKey: .current)
    }

    enum CodingKeys: String, CodingKey {
        case itemId, reason, current
    }
}
