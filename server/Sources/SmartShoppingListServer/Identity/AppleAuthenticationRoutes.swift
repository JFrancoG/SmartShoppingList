import FluentKit
import Vapor

struct AppleAuthenticationRoutes: RouteCollection, Sendable {
    let service: AppleAuthenticationService

    func boot(routes: any RoutesBuilder) throws {
        let version = routes.grouped("v1")
        version.post("auth", "challenges") { request async throws -> Response in
            _ = try APIObject.body(request, allowed: [], required: [])
            return try await APIEncoding.response(service.createChallenge(), status: .created)
        }
        version.post("auth", "apple") { request async throws -> Response in
            try await APIEncoding.response(service.login(request))
        }
        version.get("me") { request async throws -> Response in
            let id = try await service.authenticate(request)
            return try await APIEncoding.response(loadShoppingUser(id: id, on: service.databases.database()))
        }
        version.delete("session") { request async throws -> Response in
            try await service.logout(request)
            return Response(status: .noContent)
        }
    }
}
