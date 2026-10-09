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

extension SharedAPIClientTests {
    @Test
    func `Member pagination retains distinct people with missing or duplicate names`() async throws {
        let transport = FixtureSharedTransport { request in
            let cursor = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cursor" })?.value
            let body = cursor == nil ? """
            {"data":[{"id":"00000000-0000-4000-8000-000000000001","displayName":null},
            {"id":"00000000-0000-4000-8000-000000000002","displayName":"Alex"}],"nextCursor":"members-next"}
            """ : """
            {"data":[{"id":"00000000-0000-4000-8000-000000000003","displayName":"Alex"}],"nextCursor":null}
            """
            return try Self.response(request, status: 200, body: body)
        }
        let api = try client(transport)

        let members = try await api.groupMembers(groupID: Self.groupID, token: Self.token)

        #expect(members.count == 3)
        #expect(Set(members.map(\.id)).count == 3)
        #expect(members.map(\.displayName) == [nil, "Alex", "Alex"])
        #expect(await transport.requestCount == 2)
    }

    @Test(arguments: [true, false])
    func `A transfer receipt from another group or with an omitted state field stays uncertain`(
        wrongGroup: Bool
    ) async throws {
        let body = Self.groupTransferBody(
            groupID: wrongGroup ? "00000000-0000-4000-8000-000000000099" : Self.groupID.uuidString.lowercased(),
            includesResolution: wrongGroup
        )
        let transport = FixtureSharedTransport { request in
            try Self.response(request, status: 201, body: body)
        }
        let api = try client(transport)
        let request = ProposeGroupTransferRequest(
            operationId: UUID(),
            recipientUserId: UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 2))
        )

        await #expect(throws: SharedAPIError.invalidResponse) {
            try await api.proposeTransfer(request, groupID: Self.groupID, token: Self.token)
        }
    }

    @Test(arguments: ["transfer_pending", "transfer_required", "closure_confirmation_required"])
    func `A contract lifecycle refusal is terminal rather than a transport retry`(_ code: String) async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 409,
                body: """
                {"code":"\(code)","message":"Rejected without changes",\
                "requestId":"00000000-0000-4000-8000-000000000900"}
                """
            )
        }
        let api = try client(transport)
        do {
            _ = try await api.leaveGroup(
                LeaveGroupRequest(operationId: UUID(), confirmClosure: false),
                groupID: Self.groupID,
                token: Self.token
            )
            Issue.record("The server rejection must not become a successful departure")
        } catch let error as SharedAPIError {
            #expect(!error.isUncertain)
        }
    }

    private static func groupTransferBody(groupID: String, includesResolution: Bool) -> String {
        let resolution = includesResolution ? ",\"resolvedAt\":null" : ""
        return """
        {"group":{"id":"\(groupID)","name":"Casa",\
        "creatorUserId":"00000000-0000-4000-8000-000000000001",\
        "administratorUserId":"00000000-0000-4000-8000-000000000001","createdAt":"2026-09-19T10:10:00Z"},\
        "transfer":{"id":"00000000-0000-4000-8000-000000000080","groupId":"\(groupID)",\
        "proposerUserId":"00000000-0000-4000-8000-000000000001",\
        "recipientUserId":"00000000-0000-4000-8000-000000000002",\
        "status":"pending","createdAt":"2026-10-09T12:00:00Z","expiresAt":"2026-10-16T12:00:00Z"\(resolution)}}
        """
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

extension SharedAPIClientTests {
    @Test
    func `Membership pagination completes before returning distinct groups`() async throws {
        let transport = FixtureSharedTransport { request in
            let url = try #require(request.url)
            guard url.path == "/v1/groups" else { throw FixtureFailure.unexpectedRequest }
            let cursor = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "cursor" }?.value
            let body: String
            if cursor == nil {
                body = "{\"data\":[\(Self.membership(id: 16, name: "Casa"))],\"nextCursor\":\"second/page+\"}"
            } else {
                guard cursor == "second/page+" else { throw FixtureFailure.unexpectedRequest }
                body = "{\"data\":[\(Self.membership(id: 16, name: "Casa actualizada")),\(Self.membership(id: 17, name: "Viaje"))],\"nextCursor\":null}"
            }
            return try Self.response(request, status: 200, body: body)
        }

        let groups = try await client(transport).groups(token: Self.token)
        #expect(groups.map(\.name) == ["Casa actualizada", "Viaje"])
        #expect(await transport.requestCount == 2)
    }

    @Test(arguments: ["missing", "repeated", "failure"])
    func `An incomplete membership download is never returned as a usable group list`(_ fault: String) async throws {
        let transport = FixtureSharedTransport { request in
            let cursor = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "cursor" }?.value
            if fault == "failure", cursor != nil {
                throw URLError(.networkConnectionLost)
            }
            let suffix = fault == "missing" ? "" : ",\"nextCursor\":\"loop\""
            return try Self.response(
                request,
                status: 200,
                body: "{\"data\":[\(Self.membership(id: 16, name: "Casa"))]\(suffix)}"
            )
        }
        let api = try client(transport)
        await #expect(throws: fault == "failure" ? SharedAPIError.transport : .invalidResponse) {
            try await api.groups(token: Self.token)
        }
    }

    @Test(arguments: ["negativeCount", "zeroMaximum", "missingMaximum", "contradictoryCapability"])
    func `Malformed account capabilities cannot authorize a client workflow`(_ fault: String) async throws {
        let transport = FixtureSharedTransport { request in
            let count = fault == "negativeCount" ? -1 : 1
            let maximum = fault == "missingMaximum" ? "null" : fault == "zeroMaximum" ? "0" : "1"
            let canCreate = fault == "contradictoryCapability" ? "true" : "false"
            return try Self.response(
                request,
                status: 200,
                body: """
                {"id":"00000000-0000-4000-8000-000000000002","displayName":null,"group":null,
                "accountCapabilities":{"membershipCount":\(count),"canCreateGroup":\(canCreate),"canJoinGroup":false,
                "limits":{"groupsPerAccount":{"maximum":\(maximum),"enforced":true}}}}
                """
            )
        }
        let api = try client(transport)
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await api.currentUser(token: Self.token)
        }
    }

    private static func membership(id: Int, name: String) -> String {
        """
        {"id":"00000000-0000-4000-8000-0000000000\(id)","name":"\(name)",
        "creatorUserId":"00000000-0000-4000-8000-000000000002","createdAt":"2026-09-19T10:10:00Z",
        "administratorUserId":"00000000-0000-4000-8000-000000000002"}
        """
    }
}

extension SharedAPIClientTests {
    @Test
    func `Archived pagination retains its state filter and never leaks archived stores into active selectors`() async throws {
        let transport = FixtureSharedTransport { request in
            let components = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)
            guard components?.queryItems?.contains(URLQueryItem(name: "state", value: "archived")) == true else {
                throw FixtureFailure.unexpectedRequest
            }
            let cursor = components?.queryItems?.first { $0.name == "cursor" }?.value
            let body = cursor == nil
                ? "{\"stores\":[\(Self.managedStore(archived: true))],\"nextCursor\":\"archived/page+\"}"
                : "{\"stores\":[],\"nextCursor\":null}"
            return try Self.response(request, status: 200, body: body)
        }
        let stores = try await client(transport).archivedStores(groupID: Self.groupID, token: Self.token)
        #expect(stores.map(\.id) == [Self.storeID])
        #expect(stores.first?.capabilities?.canRestore == true)
        #expect(await transport.requestCount == 2)
        let mixedTransport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 200,
                body: "{\"stores\":[\(Self.managedStore(archived: true))],\"nextCursor\":null}"
            )
        }
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client(mixedTransport).stores(groupID: Self.groupID, token: Self.token)
        }
    }

    @Test(arguments: [SharedStoreAction.archive, .restore])
    func `Store lifecycle requests bind the route and operation to the intended store`(
        action: SharedStoreAction
    ) async throws {
        let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 64, 0, 128, 0, 0, 0, 0, 0, 0, 90))
        let transport = FixtureSharedTransport { request in
            let path = "/v1/groups/\(Self.groupID.uuidString.lowercased())/stores/\(Self.storeID.uuidString.lowercased())"
            guard request.url?.path == "\(path)/\(action.rawValue)", request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)",
                  request.httpBody == Data("{\"operationId\":\"\(id.uuidString.lowercased())\"}".utf8) else {
                throw FixtureFailure.unexpectedRequest
            }
            return try Self.response(request, status: 200, body: Self.managedStore(archived: action == .archive))
        }
        let store = try await client(transport).changeStoreState(
            ChangeStoreStateRequest(operationId: id),
            groupID: Self.groupID,
            storeID: Self.storeID,
            action: action,
            token: Self.token
        )
        #expect(store.id == Self.storeID)
        #expect((store.archivedAt != nil) == (action == .archive))
        #expect(await transport.requestCount == 1)
    }

    @Test(arguments: ["store_limit_reached", "pending_item_limit_reached", "store_archived", "store_not_empty"])
    func `Contract quota errors establish a definitive refusal without automatic retry`(_ code: String) async throws {
        let transport = FixtureSharedTransport { request in
            try Self.response(
                request,
                status: 409,
                body: """
                {"code":"\(code)","message":"Refused","requestId":"00000000-0000-4000-8000-000000000900"}
                """
            )
        }
        do {
            _ = try await client(transport).changeStoreState(
                ChangeStoreStateRequest(operationId: UUID()),
                groupID: Self.groupID,
                storeID: Self.storeID,
                action: .archive,
                token: Self.token
            )
            Issue.record("A quota refusal was accepted as a successful store change")
        } catch let error as SharedAPIError {
            #expect(!error.isUncertain)
        }
        #expect(await transport.requestCount == 1)
    }

    @Test(arguments: ["negative", "partial", "archivedPending", "wrongStore"])
    func `Malformed lifecycle receipts cannot resolve an uncertain store action`(_ fault: String) async throws {
        let transport = FixtureSharedTransport { request in
            var body = Self.managedStore(archived: true)
            switch fault {
            case "negative":
                body = body.replacingOccurrences(of: "\"pendingItemCount\":0", with: "\"pendingItemCount\":-1")
            case "partial":
                body = body.replacingOccurrences(of: "\"pendingItemCount\":0,", with: "")
            case "archivedPending":
                body = body.replacingOccurrences(of: "\"pendingItemCount\":0", with: "\"pendingItemCount\":1")
            default:
                body = body.replacingOccurrences(
                    of: Self.storeID.uuidString.lowercased(),
                    with: Self.groupID.uuidString
                )
            }
            return try Self.response(request, status: 200, body: body)
        }
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client(transport).changeStoreState(
                ChangeStoreStateRequest(operationId: UUID()),
                groupID: Self.groupID,
                storeID: Self.storeID,
                action: .archive,
                token: Self.token
            )
        }
    }

    @Test(arguments: ["wrongGroup", "negativeCount", "zeroMaximum", "unenforced", "contradiction"])
    func `Invalid capacity responses cannot authorize store creation`(_ fault: String) async throws {
        let transport = FixtureSharedTransport { request in
            let group = fault == "wrongGroup" ? Self.storeID : Self.groupID
            let count = fault == "negativeCount" ? -1 : 2
            let maximum = fault == "zeroMaximum" ? 0 : 3
            let enforced = fault == "unenforced" ? "false" : "true"
            let canCreate = fault == "contradiction" ? "false" : "true"
            return try Self.response(
                request,
                status: 200,
                body: """
                {"groupId":"\(group.uuidString)","capacityOwnerUserId":"00000000-0000-4000-8000-000000000002",
                "activeStoreCount":\(count),"limits":{"storesPerGroup":{"maximum":\(maximum),"enforced":\(enforced)},
                "pendingItemsPerStore":{"maximum":20,"enforced":true}},"canCreateStore":\(canCreate)}
                """
            )
        }
        await #expect(throws: SharedAPIError.invalidResponse) {
            try await client(transport).groupCapacity(groupID: Self.groupID, token: Self.token)
        }
    }

    private static func managedStore(archived: Bool) -> String {
        let date = archived ? "\"2026-09-19T10:10:00Z\"" : "null"
        return """
        {"id":"\(storeID.uuidString.lowercased())","groupId":"\(groupID.uuidString.lowercased())","name":"Aldi",
        "archivedAt":\(date),"pendingItemCount":0,"capabilities":{
        "canAddItems":\(!archived),"canArchive":\(!archived),"canRestore":\(archived)}}
        """
    }
}
