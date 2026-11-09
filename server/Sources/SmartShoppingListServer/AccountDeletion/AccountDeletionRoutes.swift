import Vapor

struct AccountDeletionRoutes: RouteCollection, Sendable {
    let service: AccountDeletionService
    let authentication: any SessionAuthenticating

    func boot(routes: any RoutesBuilder) throws {
        let account = routes.grouped("v1", "account")
        account.get("deletion-preview") { request async throws -> Response in
            try await APIEncoding.response(service.preview(user: authentication.authenticate(request)))
        }
        account.post("deletion-challenges") { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            let body = try APIObject.body(request, allowed: ["operationId", "statusSecret", "revision"], required: ["operationId", "statusSecret", "revision"])
            return try await APIEncoding.response(service.prepare(
                user: user,
                operation: body.uuid("operationId"),
                secret: body.string("statusSecret"),
                revision: body.string("revision")
            ), status: .created)
        }
        account.post("deletions") { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            let fields: Set<String> = ["operationId", "statusSecret", "revision", "challengeId", "identityToken", "authorizationCode"]
            let body = try APIObject.body(request, allowed: fields, required: fields)
            return try await APIEncoding.response(service.accept(user: user, body: body), status: .accepted)
        }
        for action in ["status", "cancel"] {
            account.post("deletions", PathComponent(stringLiteral: action)) { request async throws -> Response in
                let body = try APIObject.body(request, allowed: ["operationId", "statusSecret"], required: ["operationId", "statusSecret"])
                return try await APIEncoding.response(service.status(
                    operation: body.uuid("operationId"),
                    secret: body.string("statusSecret"),
                    cancelPrepared: action == "cancel"
                ))
            }
        }
        account.post("deletion-session-status") { request async throws -> Response in
            _ = try APIObject.body(request, allowed: [], required: [])
            guard request.headers[.authorization].count == 1,
                  let token = request.headers.bearerAuthorization?.token else { throw APIProblem.invalidRequest }
            return try await APIEncoding.response(APIJSON.object(["deletionAccepted": .bool(service.deletionAcceptedForSession(token))]))
        }
    }
}
