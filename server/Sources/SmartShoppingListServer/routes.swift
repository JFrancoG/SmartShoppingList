import FluentKit
import Vapor

func routes(
    _ app: Application,
    databases: Databases,
    accountCapacity: AccountCapacityPolicy = .init(),
    appStoreGateway: any AppStoreGateway = UnconfiguredAppStoreGateway()
) throws {
    app.get { req async in
        "It works!"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    // Keep the original infrastructure probe local; it has no product authorization model.
    if app.environment == .development || app.environment == .testing {
        try app.register(collection: TodoController(databases: databases))
    }

    let gateway: any AppleGateway
    if let configuration = try AppleSignInConfiguration.load(logger: app.logger) {
        gateway = LiveAppleGateway(configuration: configuration)
    } else {
        gateway = UnconfiguredAppleGateway()
    }
    let vault = try RefreshTokenVault.load(logger: app.logger)
    let authentication = AppleAuthenticationService(
        databases: databases,
        gateway: gateway,
        vault: vault,
        accountCapacity: accountCapacity
    )
    try app.register(collection: AppleAuthenticationRoutes(service: authentication))
    try app.register(collection: ShoppingRoutes(
        databases: databases,
        authentication: authentication,
        invitationOrigin: app.environment == .testing ? "https://links.test" : Environment.get("INVITATION_ORIGIN"),
        accountCapacity: accountCapacity
    ))
    let deletion = AccountDeletionService(databases: databases, gateway: gateway, vault: vault)
    try app.register(collection: AccountDeletionRoutes(service: deletion, authentication: authentication))
    if app.environment != .testing {
        app.lifecycle.use(AccountDeletionLifecycle(worker: AccountDeletionWorker(service: deletion)))
    }
    let recovery: SubscriptionRecoveryService?
    if app.environment != .testing, let configuration = try AppAttestConfiguration.load() {
        recovery = SubscriptionRecoveryService(
            databases: databases,
            gateway: appStoreGateway,
            attestation: try LiveAppAttestVerifier.live(configuration: configuration)
        )
    } else {
        recovery = nil
    }
    try app.register(collection: AppStoreRoutes(
        service: SubscriptionService(databases: databases, gateway: appStoreGateway, accountCapacity: accountCapacity),
        authentication: authentication,
        recovery: recovery
    ))
    try app.register(collection: InvitationWebsite(
        teamID: app.environment == .testing ? "NWN8JUE438" : Environment.get("APPLE_TEAM_ID"),
        origin: app.environment == .testing ? "https://links.test" : Environment.get("INVITATION_ORIGIN")
    ))
}
