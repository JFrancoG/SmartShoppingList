import FluentKit
import Vapor

func routes(_ app: Application, databases: Databases) throws {
    app.get { req async in
        "It works!"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    // Keep the original infrastructure probe local; it has no product authorization model.
    if app.environment != .production {
        try app.register(collection: TodoController(databases: databases))
    }

    let gateway: any AppleGateway
    if let configuration = try AppleSignInConfiguration.load() {
        gateway = LiveAppleGateway(configuration: configuration)
    } else {
        gateway = UnconfiguredAppleGateway()
    }
    let authentication = AppleAuthenticationService(
        databases: databases,
        gateway: gateway,
        vault: try RefreshTokenVault.load()
    )
    try app.register(collection: AppleAuthenticationRoutes(service: authentication))
    try app.register(collection: ShoppingRoutes(
        databases: databases,
        authentication: authentication,
        invitationOrigin: app.environment == .testing ? "https://links.test" : Environment.get("INVITATION_ORIGIN")
    ))
    try app.register(collection: InvitationWebsite(
        teamID: app.environment == .testing ? "NWN8JUE438" : Environment.get("APPLE_TEAM_ID"),
        origin: app.environment == .testing ? "https://links.test" : Environment.get("INVITATION_ORIGIN")
    ))
}
