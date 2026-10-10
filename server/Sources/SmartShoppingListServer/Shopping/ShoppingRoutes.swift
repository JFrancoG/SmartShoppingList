import Foundation
import FluentKit
import Vapor

struct ShoppingRoutes: RouteCollection {
    let databases: Databases
    let authentication: any SessionAuthenticating
    let invitationOrigin: String?
    var accountCapacity = AccountCapacityPolicy()
    private let cursorKey = SymmetricKey(size: .bits256)

    func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("v1").grouped(APIErrorMiddleware())
        api.post("groups", use: createGroup)
        api.get("groups", use: listGroups)
        api.post("account", "free-group", use: selectFreeGroup)
        api.get("groups", ":groupId", "stores", use: listStores)
        api.get(
            "groups",
            ":groupId",
            "capacity",
            use: capacity
        )
        api.post(
            "groups",
            ":groupId",
            "stores",
            ":storeId",
            "archive",
            use: archiveStore
        )
        api.post(
            "groups",
            ":groupId",
            "stores",
            ":storeId",
            "restore",
            use: restoreStore
        )
        api.get(
            "groups",
            ":groupId",
            "members",
            use: listMembers
        )
        api.get(
            "groups",
            ":groupId",
            "administration",
            use: administration
        )
        api.post(
            "groups",
            ":groupId",
            "administration-transfers",
            use: proposeTransfer
        )
        api.post(
            "groups",
            ":groupId",
            "administration-transfers",
            ":transferId",
            "accept",
            use: acceptTransfer
        )
        api.post(
            "groups",
            ":groupId",
            "administration-transfers",
            ":transferId",
            "reject",
            use: rejectTransfer
        )
        api.post(
            "groups",
            ":groupId",
            "administration-transfers",
            ":transferId",
            "withdraw",
            use: withdrawTransfer
        )
        api.post(
            "groups",
            ":groupId",
            "departure",
            use: departGroup
        )
        api.post("groups", ":groupId", "invitations", use: createInvitation)
        api.get("groups", ":groupId", "invitations", use: listInvitations)
        api.delete("groups", ":groupId", "invitations", ":invitationId", use: revokeInvitation)
        api.post("invitations", ":invitationId", "preview", use: previewInvitation)
        api.post("invitations", ":invitationId", "accept", use: acceptInvitation)
        api.post("groups", ":groupId", "item-batches", use: addItems)
        api.post("groups", ":groupId", "purchases", use: finalizePurchase)
        api.patch("groups", ":groupId", "items", ":itemId", use: editItem)
        api.post("groups", ":groupId", "items", ":itemId", "cancellation", use: cancelItem)
        api.get("groups", ":groupId", "stores", ":storeId", "items", use: listItems)
    }

    private func service() throws -> ShoppingService {
        ShoppingService(
            database: try databases.database(),
            invitationOrigin: invitationOrigin,
            cursorKey: cursorKey,
            accountCapacity: accountCapacity
        )
    }

    private func parameter(_ name: String, request: Request) throws -> UUID {
        guard let value = request.parameters.get(name) else { throw APIProblem.invalidRequest }
        return try APIObject.uuid(value)
    }

    private func createGroup(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(request, allowed: ["operationId", "name"], required: ["operationId", "name"])
        return try await service().createGroup(
            user: user, operation: body.uuid("operationId"), name: body.string("name")
        ).response()
    }

    private func selectFreeGroup(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(
            request,
            allowed: ["operationId", "groupId"],
            required: ["operationId", "groupId"]
        )
        return try await service().selectFreeGroup(
            user: user,
            group: body.uuid("groupId"),
            operation: body.uuid("operationId")
        ).response()
    }

    private func addItems(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let group = try parameter("groupId", request: request)
        let body = try APIObject.body(request, allowed: ["operationId", "items"], required: ["operationId", "items"])
        guard case .array(let values) = body.values["items"], (1...50).contains(values.count) else {
            throw APIProblem.invalidRequest
        }
        let items = try values.map(ShoppingNewItem.init)
        return try await service().addItems(
            user: user,
            group: group,
            operation: body.uuid("operationId"),
            items: items
        ).response()
    }

    private func finalizePurchase(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let group = try parameter("groupId", request: request)
        let body = try APIObject.body(
            request, allowed: ["operationId", "storeId", "items"], required: ["operationId", "storeId", "items"]
        )
        guard case .array(let values) = body.values["items"] else { throw APIProblem.invalidRequest }
        return try await service().finalizePurchase(
            user: user,
            group: group,
            operation: body.uuid("operationId"),
            store: body.uuid("storeId"),
            items: values.map(ShoppingSelectedItem.init)
        ).response()
    }

    private func editItem(_ request: Request) async throws -> Response {
        try await changeItem(request, editing: true)
    }

    private func cancelItem(_ request: Request) async throws -> Response {
        try await changeItem(request, editing: false)
    }

    private func changeItem(_ request: Request, editing: Bool) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let group = try parameter("groupId", request: request)
        let item = try parameter("itemId", request: request)
        let keys: Set<String> = editing
            ? ["operationId", "expectedVersion", "name", "quantity", "store"]
            : ["operationId", "expectedVersion"]
        let body = try APIObject.body(request, allowed: keys, required: keys)
        let selected = try ShoppingSelectedItem(.object([
            "id": .string(item.uuidString.lowercased()),
            "expectedVersion": body.values["expectedVersion"] ?? .null
        ]))
        let replacement = try editing ? ShoppingNewItem(.object([
            "name": body.values["name"] ?? .null,
            "quantity": body.values["quantity"] ?? .null,
            "store": body.values["store"] ?? .null
        ])) : nil
        return try await service().changeItem(
            user: user,
            group: group,
            operation: body.uuid("operationId"),
            item: selected,
            replacement: replacement
        ).response()
    }

    private func createInvitation(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        _ = try APIObject.body(request, allowed: [], required: [])
        let group = try parameter("groupId", request: request)
        return try await service().createInvitation(user: user, group: group).response()
    }

    private func revokeInvitation(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        try await service().revokeInvitation(
            user: user,
            group: parameter("groupId", request: request),
            id: parameter("invitationId", request: request)
        )
        return Response(status: .noContent)
    }

    private func previewInvitation(_ request: Request) async throws -> Response {
        try await invitation(request, accepting: false)
    }

    private func acceptInvitation(_ request: Request) async throws -> Response {
        try await invitation(request, accepting: true)
    }

    private func invitation(_ request: Request, accepting: Bool) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(request, allowed: ["token"], required: ["token"])
        return try await service().invitation(
            user: user,
            id: parameter("invitationId", request: request),
            secret: body.string("token"),
            accepting: accepting
        ).response()
    }

    private func listGroups(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let (limit, cursor) = try pagination(request)
        return try await service().groups(user: user, limit: limit, cursor: cursor).response()
    }

    private func capacity(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        return try await service().capacity(user: user, group: parameter("groupId", request: request)).response()
    }

    private func archiveStore(_ request: Request) async throws -> Response {
        try await changeStoreState(request, state: .archived)
    }

    private func restoreStore(_ request: Request) async throws -> Response {
        try await changeStoreState(request, state: .active)
    }

    private func changeStoreState(_ request: Request, state: ShoppingService.StoreState) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(request, allowed: ["operationId"], required: ["operationId"])
        return try await service().changeStoreState(
            user: user,
            group: parameter("groupId", request: request),
            store: parameter("storeId", request: request),
            operation: body.uuid("operationId"),
            state: state
        ).response()
    }

    private func listStores(_ request: Request) async throws -> Response {
        try await page(request, resource: .stores)
    }

    private func listMembers(_ request: Request) async throws -> Response {
        try await page(request, resource: .members)
    }

    private func administration(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        return try await service().administration(user: user, group: parameter("groupId", request: request)).response()
    }

    private func proposeTransfer(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(
            request,
            allowed: ["operationId", "recipientUserId"],
            required: ["operationId", "recipientUserId"]
        )
        return try await service().proposeTransfer(
            user: user,
            group: parameter("groupId", request: request),
            operation: body.uuid("operationId"),
            recipient: body.uuid("recipientUserId")
        ).response()
    }

    private func acceptTransfer(_ request: Request) async throws -> Response {
        try await resolveTransfer(request, action: .accept)
    }

    private func rejectTransfer(_ request: Request) async throws -> Response {
        try await resolveTransfer(request, action: .reject)
    }

    private func withdrawTransfer(_ request: Request) async throws -> Response {
        try await resolveTransfer(request, action: .withdraw)
    }

    private func resolveTransfer(_ request: Request, action: ShoppingService.TransferAction) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(request, allowed: ["operationId"], required: ["operationId"])
        return try await service().resolveTransfer(
            user: user,
            group: parameter("groupId", request: request),
            operation: body.uuid("operationId"),
            transferID: parameter("transferId", request: request),
            action: action
        ).response()
    }

    private func departGroup(_ request: Request) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let body = try APIObject.body(
            request,
            allowed: ["operationId", "confirmClosure"],
            required: ["operationId", "confirmClosure"]
        )
        guard case .bool(let confirmed) = body.values["confirmClosure"] else { throw APIProblem.invalidRequest }
        return try await service().departGroup(
            user: user,
            group: parameter("groupId", request: request),
            operation: body.uuid("operationId"),
            confirmClosure: confirmed
        ).response()
    }

    private func listInvitations(_ request: Request) async throws -> Response {
        try await page(request, resource: .invitations)
    }

    private func listItems(_ request: Request) async throws -> Response {
        try await page(request, resource: .items)
    }

    private func page(_ request: Request, resource: ShoppingService.Resource) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let (limit, cursor) = try pagination(request, allowStoreState: resource == .stores)
        let query = URLComponents(string: request.url.string)?.queryItems ?? []
        let state: ShoppingService.StoreState
        if let parameter = query.first(where: { $0.name == "state" }) {
            guard let value = parameter.value, let parsed = ShoppingService.StoreState(rawValue: value) else {
                throw APIProblem.invalidRequest
            }
            state = parsed
        } else {
            state = .active
        }
        return try await service().page(
            user: user,
            group: parameter("groupId", request: request),
            resource: resource,
            store: resource == .items ? parameter("storeId", request: request) : nil,
            limit: limit,
            cursor: cursor,
            state: state
        ).response()
    }

    private func pagination(_ request: Request, allowStoreState: Bool = false) throws -> (limit: Int, cursor: String?) {
        let query = URLComponents(string: request.url.string)?.queryItems ?? []
        let allowed = allowStoreState ? ["limit", "cursor", "state"] : ["limit", "cursor"]
        guard query.allSatisfy({ allowed.contains($0.name) }),
            Set(query.map(\.name)).count == query.count
        else {
            throw APIProblem.invalidRequest
        }
        let limit: Int
        if let parameter = query.first(where: { $0.name == "limit" }) {
            guard let value = parameter.value, let parsed = Int(value), (1...100).contains(parsed),
                value == String(parsed)
            else {
                throw APIProblem.invalidRequest
            }
            limit = parsed
        } else {
            limit = 50
        }
        let cursorParameter = query.first(where: { $0.name == "cursor" })
        if let cursorParameter, cursorParameter.value?.isEmpty != false {
            throw APIProblem.invalidRequest
        }
        return (limit, cursorParameter?.value)
    }
}
