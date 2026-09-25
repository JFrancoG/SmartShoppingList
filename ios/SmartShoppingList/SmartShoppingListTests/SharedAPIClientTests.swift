import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
struct SharedAPIClientTests {
    @Test
    func `Pending pages merge by identity and retain the latest version`() async throws {
        let transport = FixtureSharedTransport { request in
            let cursor = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cursor" })?.value
            let body: String
            if cursor == nil {
                body = "{\"items\":[\(Self.item(id: 30, version: 3, name: "Jabón corregido"))],\"nextCursor\":\"after+first/row=\"}"
            } else {
                guard cursor == "after+first/row=" else { throw FixtureFailure.unexpectedRequest }
                body = "{\"items\":[\(Self.item(id: 30, version: 1, name: "Jabón")),\(Self.item(id: 31, version: 1, name: "Pan"))],\"nextCursor\":null}"
            }
            return try Self.response(request, status: 200, body: body)
        }
        let client = try client(transport)

        let items = try await client.pendingItems(groupID: Self.groupID, storeID: Self.storeID, token: Self.token)

        #expect(items.map(\.name) == ["Jabón corregido", "Pan"])
        #expect(items.map(\.version) == [3, 1])
        #expect(await transport.requestCount == 2)
    }

    @Test
    func `Repeating cursors fail without announcing a partial list`() async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(request, status: 200, body: "{\"stores\":[],\"nextCursor\":\"stuck\"}")
        }
        let client = try client(transport)

        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client.stores(groupID: Self.groupID, token: Self.token)
        }
        #expect(await transport.requestCount == 2)
    }

    @Test
    func `An omitted page cursor fails instead of presenting an incomplete list as complete`() async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(request, status: 200, body: "{\"stores\":[]}")
        }
        let client = try client(transport)
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client.stores(groupID: Self.groupID, token: Self.token)
        }
    }

    @Test
    func `A retry after lost response resends the reviewed operation unchanged`() async throws {
        let transport = LostResponseSharedTransport()
        let client = try client(transport)
        let operationID = try #require(UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000111"))
        let batch = AddItemsRequest(
            operationId: operationID,
            items: [SharedNewItem(name: "Jabón", quantity: nil, store: .existing(Self.storeID))]
        )

        await #expect(throws: SharedAPIError.transport) {
            try await client.addItems(batch, groupID: Self.groupID, token: Self.token)
        }
        #expect(await transport.requestCount == 1)
        let confirmed = try await client.addItems(batch, groupID: Self.groupID, token: Self.token)

        #expect(confirmed.map(\.name) == ["Jabón"])
        #expect(await transport.requestCount == 2)
        #expect(await transport.payloadWasIdentical)
    }

    @Test(arguments: [401, 409, 429, 503])
    func `Server failures retain stable codes and retry guidance without retrying writes`(_ status: Int) async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: status,
                body: "{\"code\":\"service_unavailable\",\"message\":\"Diagnostic only\",\"requestId\":\"00000000-0000-4000-8000-000000000900\"}",
                headers: ["Retry-After": "15"]
            )
        }
        let client = try client(transport)
        let requestID = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000900"))
        await #expect(throws: SharedAPIError.server(
            status: status,
            code: "service_unavailable",
            requestID: requestID,
            retryAfter: 15
        )) {
            try await client.createChallenge()
        }
        #expect(await transport.requestCount == 1)
    }

    @Test(arguments: [Optional<String>.none, .some(""), .some(String(repeating: "x", count: 501))])
    func `An incomplete contract error cannot establish a terminal mutation rejection`(_ message: String?) async throws {
        let transport = FixtureSharedTransport { request in
            let messageField = message.map { ",\"message\":\"\($0)\"" } ?? ""
            return try Self.response(
                request,
                status: 409,
                body: "{\"code\":\"idempotency_key_reused\",\"requestId\":\"00000000-0000-4000-8000-000000000900\"\(messageField)}"
            )
        }
        let client = try client(transport)
        let operation = CreateGroupRequest(operationId: UUID(), name: "Casa")
        await #expect(throws: SharedAPIError.server(
            status: 409,
            code: "invalid_response",
            requestID: nil,
            retryAfter: nil
        )) {
            try await client.createGroup(operation, token: Self.token)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `Cancellation remains cancellation rather than a session or server failure`() async throws {
        let transport = FixtureSharedTransport { _ in throw CancellationError() }
        let client = try client(transport)
        await #expect(throws: CancellationError.self) {
            try await client.currentUser(token: Self.token)
        }
    }

    @Test
    func `An unexpected redirect cannot become a successful authenticated response`() async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 302,
                body: "",
                headers: ["Location": "https://other.test/me"]
            )
        }
        let client = try client(transport)
        await #expect(throws: SharedAPIError.server(
            status: 302,
            code: "invalid_response",
            requestID: nil,
            retryAfter: nil
        )) {
            try await client.currentUser(token: Self.token)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test
    func `Challenge POST sends the required empty object and accepts fractional UTC expiry`() async throws {
        let transport = FixtureSharedTransport { request in
            guard request.httpMethod == "POST", request.httpBody == Data("{}".utf8),
                  request.value(forHTTPHeaderField: "Authorization") == nil else {
                throw FixtureFailure.unexpectedRequest
            }
            return try Self.response(
                request,
                status: 201,
                body: "{\"id\":\"00000000-0000-4000-8000-000000000050\",\"nonce\":\"NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNM\",\"expiresAt\":\"2026-09-19T10:05:00.125Z\"}"
            )
        }
        let client = try client(transport)

        let challenge = try await client.createChallenge()

        #expect(challenge.expiresAt.timeIntervalSince1970 == 1_789_812_300.125)
    }

    @Test
    func `Oversized reviewed batches never leave the process`() async throws {
        let transport = FixtureSharedTransport { _ in throw FixtureFailure.unexpectedRequest }
        let client = try client(transport)
        let batch = AddItemsRequest(
            operationId: UUID(),
            items: [SharedNewItem(
                name: String(repeating: "a", count: 128 * 1_024),
                quantity: nil,
                store: .newName("Día")
            )]
        )
        await #expect(throws: SharedAPIError.requestTooLarge) {
            try await client.addItems(batch, groupID: Self.groupID, token: Self.token)
        }
        #expect(await transport.requestCount == 0)
    }

    @Test
    func `A response from another group is never exposed as this group stores`() async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 200,
                body: "{\"stores\":[{\"id\":\"00000000-0000-4000-8000-000000000020\",\"groupId\":\"00000000-0000-4000-8000-000000000099\",\"name\":\"Día\"}],\"nextCursor\":null}"
            )
        }
        let client = try client(transport)
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client.stores(groupID: Self.groupID, token: Self.token)
        }
    }

    private func client(_ transport: any SharedHTTPTransport) throws -> SharedHTTPAPI {
        let config = try SharedAPIConfiguration(baseURL: "https://api.test", invitationOrigin: "https://links.test")
        return SharedHTTPAPI(configuration: config, transport: transport)
    }

    static let groupID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 16))
    static let storeID = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 32))
    static let token = "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSQ"

    static func item(id: Int, version: Int, name: String) -> String {
        """
        {"id":"00000000-0000-4000-8000-0000000000\(id)","groupId":"00000000-0000-4000-8000-000000000010",
        "storeId":"00000000-0000-4000-8000-000000000020","name":"\(name)","quantity":null,"status":"pending",
        "version":\(version),"createdBy":"00000000-0000-4000-8000-000000000002",
        "createdAt":"2026-09-19T10:10:00Z","purchasedBy":null,"purchasedAt":null}
        """
    }

    static func response(
        _ request: URLRequest,
        status: Int,
        body: String,
        headers: [String: String] = [:]
    ) throws -> (Data, HTTPURLResponse) {
        var fields = headers
        fields["Content-Type"] = "application/json"
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: fields
        ))
        return (Data(body.utf8), response)
    }
}

private enum FixtureFailure: Error {
    case unexpectedRequest
}

private actor FixtureSharedTransport: SharedHTTPTransport {
    private let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)
    private(set) var requestCount = 0

    init(_ handler: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func response(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        return try handler(request)
    }
}

private actor LostResponseSharedTransport: SharedHTTPTransport {
    private var firstPayload: Data?
    private(set) var requestCount = 0
    private(set) var payloadWasIdentical = false

    func response(to request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let body = try #require(request.httpBody)
        // Contract-derived wire requirements are enforced by the remote boundary, not inspected as DTO construction.
        let payload = String(decoding: body, as: UTF8.self)
        guard payload.contains("\"quantity\":null"),
              payload.contains("\"operationId\":\"abcdef01-0000-4000-8000-000000000111\""),
              payload.contains("\"store\":{\"id\":\"00000000-0000-4000-8000-000000000020\"}") else {
            throw FixtureFailure.unexpectedRequest
        }
        if firstPayload == nil {
            firstPayload = body
            throw URLError(.networkConnectionLost)
        }
        payloadWasIdentical = body == firstPayload
        return try SharedAPIClientTests.response(
            request,
            status: 201,
            body: "{\"items\":[\(SharedAPIClientTests.item(id: 30, version: 1, name: "Jabón"))]}"
        )
    }
}

extension SharedAPIClientTests {
    @Test(arguments: [
        "",
        ",\"conflicts\":[]",
        ",\"conflicts\":[{\"itemId\":\"00000000-0000-4000-8000-000000000030\",\"reason\":\"not_found\"}]",
        ",\"conflicts\":[{\"itemId\":\"00000000-0000-4000-8000-000000000099\",\"reason\":\"not_found\",\"current\":null}]"
    ])
    func `Incomplete purchase conflicts cannot resolve an uncertain operation`(_ conflicts: String) async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 409,
                body: "{\"code\":\"item_conflict\",\"message\":\"Changed\",\"requestId\":\"00000000-0000-4000-8000-000000000900\"\(conflicts)}"
            )
        }
        let client = try client(transport)
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client.finalizePurchase(Self.purchaseRequest(), groupID: Self.groupID, token: Self.token)
        }
    }

    @Test
    func `A complete purchase conflict is a definitive rejection for the selected item`() async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 409,
                body: """
                {"code":"item_conflict","message":"Changed","requestId":"00000000-0000-4000-8000-000000000900",
                "conflicts":[{"itemId":"00000000-0000-4000-8000-000000000030","reason":"version_mismatch",
                "current":\(Self.item(id: 30, version: 2, name: "Pan corregido"))}]}
                """
            )
        }
        let client = try client(transport)
        do {
            _ = try await client.finalizePurchase(Self.purchaseRequest(), groupID: Self.groupID, token: Self.token)
            Issue.record("An item conflict must reject the purchase")
        } catch let error as SharedAPIError {
            #expect(!error.isUncertain)
            guard case .server(409, "item_conflict", _, _) = error else {
                Issue.record("A valid conflict was not recognized")
                return
            }
        }
    }

    @Test(arguments: [true, false])
    func `Purchase wire response must confirm exactly the selected ids`(_ matchingID: Bool) async throws {
        let transport = FixtureSharedTransport { request in
            let body = try #require(request.httpBody)
            let payload = String(decoding: body, as: UTF8.self)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/groups/00000000-0000-4000-8000-000000000010/purchases")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)")
            #expect(payload.contains("\"operationId\":\"abcdef01-0000-4000-8000-000000000111\""))
            #expect(payload.contains("\"items\":[{\"expectedVersion\":1,\"id\":\"00000000-0000-4000-8000-000000000030\"}]"))
            let id = matchingID ? "30" : "99"
            return try Self.response(
                request,
                status: 200,
                body: """
                {"confirmedAt":"2026-09-22T10:00:00Z","items":[{
                "id":"00000000-0000-4000-8000-0000000000\(id)",
                "groupId":"00000000-0000-4000-8000-000000000010","storeId":"00000000-0000-4000-8000-000000000020",
                "name":"Pan","quantity":null,"status":"purchased","version":2,
                "createdBy":"00000000-0000-4000-8000-000000000002","createdAt":"2026-09-19T10:10:00Z",
                "purchasedBy":"00000000-0000-4000-8000-000000000003","purchasedAt":"2026-09-22T10:00:00Z"}]}
                """
            )
        }
        let client = try client(transport)
        if matchingID {
            let result = try await client.finalizePurchase(Self.purchaseRequest(), groupID: Self.groupID, token: Self.token)
            #expect(result.items.map(\.name) == ["Pan"])
        } else {
            await #expect(throws: SharedAPIError.invalidResponse) {
                try await client.finalizePurchase(Self.purchaseRequest(), groupID: Self.groupID, token: Self.token)
            }
        }
        #expect(await transport.requestCount == 1)
    }

    private static func purchaseRequest() throws -> FinalizePurchaseRequest {
        FinalizePurchaseRequest(
            operationId: try #require(UUID(uuidString: "ABCDEF01-0000-4000-8000-000000000111")),
            storeId: storeID,
            items: [SelectedPurchaseItem(
                id: try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000030")),
                expectedVersion: 1
            )]
        )
    }
}

extension SharedAPIClientTests {
    @Test("Item-change responses cannot confirm an unrelated or stale result", arguments: [false, true], [false, true])
    func validatesItemChange(cancelling: Bool, malformed: Bool) async throws {
        let original = try SharedJSON.decoder().decode(SharedItem.self, from: Data(Self.item(id: 30, version: 1, name: "Pan").utf8))
        let transport = FixtureSharedTransport { request in
            let expectedPath = "/v1/groups/00000000-0000-4000-8000-000000000010/items/00000000-0000-4000-8000-000000000030" + (cancelling ? "/cancellation" : "")
            guard request.url?.path == expectedPath, request.httpMethod == (cancelling ? "POST" : "PATCH") else {
                throw FixtureFailure.unexpectedRequest
            }
            let payload = try #require(request.httpBody)
            let fields = try JSONDecoder().decode(ItemChangeWireFixture.self, from: payload)
            #expect(fields.expectedVersion == 1)
            if !cancelling {
                #expect(fields.hasExplicitNullQuantity)
            }
            var body = Self.item(id: 30, version: malformed ? 1 : 2, name: cancelling ? "Pan" : "Pan integral")
            if cancelling {
                body = body.replacingOccurrences(of: "\"pending\"", with: "\"cancelled\"")
            }
            return try Self.response(request, status: 200, body: body)
        }
        let api = try client(transport)
        let request = SharedItemChangeRequest(
            operationId: UUID(),
            expectedVersion: 1,
            replacement: cancelling ? nil : SharedNewItem(name: "Pan integral", quantity: nil, store: .existing(Self.storeID))
        )
        if malformed {
            await #expect(throws: SharedAPIError.invalidResponse) {
                try await api.changeItem(request, item: original, token: Self.token)
            }
        } else {
            let changed = try await api.changeItem(request, item: original, token: Self.token)
            #expect(changed.status == (cancelling ? "cancelled" : "pending"))
            #expect(changed.name == (cancelling ? "Pan" : "Pan integral"))
        }
    }
}


private struct ItemChangeWireFixture: Decodable {
    let expectedVersion: Int
    let hasExplicitNullQuantity: Bool

    private enum CodingKeys: String, CodingKey {
        case expectedVersion, quantity
    }
}

private extension ItemChangeWireFixture {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        expectedVersion = try values.decode(Int.self, forKey: .expectedVersion)
        hasExplicitNullQuantity = try values.contains(.quantity) && values.decodeNil(forKey: .quantity)
    }
}
