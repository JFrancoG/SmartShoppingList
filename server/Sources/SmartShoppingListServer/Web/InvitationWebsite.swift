import Foundation
import Vapor

/// The public website never receives the fragment secret and never reads invitation records.
struct InvitationWebsite: RouteCollection {
    let teamID: String?
    let origin: String?

    func boot(routes: any RoutesBuilder) throws {
        routes.get(".well-known", "apple-app-site-association") { _ async throws -> Response in
            guard let teamID, teamID.utf8.count == 10,
                  teamID.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
                  let origin, let components = URLComponents(string: origin),
                  components.scheme == "https", components.host?.isEmpty == false,
                  components.user == nil, components.password == nil,
                  components.query == nil, components.fragment == nil,
                  components.path.isEmpty || components.path == "/" else {
                throw APIProblem.unavailable
            }
            let association = APIJSON.object([
                "applinks": .object([
                    "details": .array([.object([
                        "appIDs": .array([.string("\(teamID).com.plusprojects.SmartShoppingList")]),
                        "components": .array([.object(["/": .string("/invite/*")])])
                    ])])
                ])
            ])
            let response = try APIEncoding.response(association)
            response.headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=3600")
            return response
        }
        routes.get("invite", ":invitationId") { request async throws -> Response in
            guard let identifier = request.parameters.get("invitationId") else { throw APIProblem.notFound }
            _ = try APIObject.uuid(identifier)
            let response = Response(status: .ok, body: .init(string: Self.landingPage))
            response.headers.contentType = .html
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
            response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
            response.headers.replaceOrAdd(
                name: "Content-Security-Policy",
                value: "default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
            )
            return response
        }
    }

    private static let landingPage = """
        <!doctype html>
        <html lang="es">
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Invitación · SmartShoppingList</title>
        <main>
          <h1>Invitación a SmartShoppingList</h1>
          <p>Necesitas tener instalada la app para abrir esta invitación.</p>
          <p>Desde tu iPhone, abre el enlace original que te han compartido y continúa en la app.</p>
          <p>Esta página no acepta la invitación ni muestra datos del grupo.</p>
        </main>
        </html>
        """
}
