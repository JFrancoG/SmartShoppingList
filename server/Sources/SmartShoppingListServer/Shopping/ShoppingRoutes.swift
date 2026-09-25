import Foundation
import FluentKit
import Vapor

struct ShoppingRoutes: RouteCollection {
    let databases: Databases
    let authentication: any SessionAuthenticating
    let invitationOrigin: String?
    private let cursorKey = SymmetricKey(size: .bits256)

    func boot(routes: any RoutesBuilder) throws {
        let api = routes.grouped("v1").grouped(APIErrorMiddleware())
        api.post("groups", use: createGroup)
        api.get("groups", ":groupId", "stores", use: listStores)
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
        ShoppingService(database: try databases.database(), invitationOrigin: invitationOrigin, cursorKey: cursorKey)
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

    private func listStores(_ request: Request) async throws -> Response {
        try await page(request, resource: .stores)
    }

    private func listInvitations(_ request: Request) async throws -> Response {
        try await page(request, resource: .invitations)
    }

    private func listItems(_ request: Request) async throws -> Response {
        try await page(request, resource: .items)
    }

    private func page(_ request: Request, resource: ShoppingService.Resource) async throws -> Response {
        let user = try await authentication.authenticate(request)
        let query = URLComponents(string: request.url.string)?.queryItems ?? []
        guard query.allSatisfy({ ["limit", "cursor"].contains($0.name) }),
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
        return try await service().page(
            user: user,
            group: parameter("groupId", request: request),
            resource: resource,
            store: resource == .items ? parameter("storeId", request: request) : nil,
            limit: limit,
            cursor: cursorParameter?.value
        ).response()
    }
}
