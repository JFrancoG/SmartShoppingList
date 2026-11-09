import Vapor

struct ClientContractMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if request.url.path.hasPrefix("/v1/"), request.url.path != "/v1/app-store/notifications",
           request.headers["X-SmartList-Contract"] != ["0.6"] {
            return try APIEncoding.response(APIProblem(
                status: .upgradeRequired,
                code: "client_update_required",
                message: "Actualiza Smart List para continuar usando tu cuenta."
            ).json, status: .upgradeRequired)
        }
        return try await next.respond(to: request)
    }
}
