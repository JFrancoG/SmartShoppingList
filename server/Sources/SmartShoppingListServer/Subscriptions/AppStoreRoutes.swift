import Vapor

struct AppStoreRoutes: RouteCollection, Sendable {
    let service: SubscriptionService
    let authentication: any SessionAuthenticating

    func boot(routes: any RoutesBuilder) throws {
        let version = routes.grouped("v1").grouped(APIErrorMiddleware())
        version.get("account", "subscription") { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            return try await APIEncoding.response(service.status(user: user).json)
        }
        version.post(
            "account",
            "subscription",
            "transactions"
        ) { request async throws -> Response in
            let user = try await authentication.authenticate(request)
            let body = try APIObject.body(request, allowed: ["signedTransaction"], required: ["signedTransaction"])
            return try await APIEncoding.response(service.submit(user: user, signed: body.string("signedTransaction")))
        }
        version.post("app-store", "notifications") { request async throws -> Response in
            let body = try APIObject.body(request, allowed: ["signedPayload"], required: ["signedPayload"])
            try await service.notification(signed: body.string("signedPayload"))
            return Response(status: .noContent)
        }
    }
}
