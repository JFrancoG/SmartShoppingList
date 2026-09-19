import NIOSSL
import FluentKit
import FluentPostgresDriver
import Vapor

enum AppConfigurationError: Error {
    case missingTestDatabaseConfiguration
}

/// Configures the server; tests must provide their isolated database explicitly.
func configure(
    _ app: Application,
    databases suppliedDatabases: Databases? = nil,
    databaseConfiguration suppliedConfiguration: DatabaseConfigurationFactory? = nil
) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let databaseConfiguration: DatabaseConfigurationFactory
    if let suppliedConfiguration {
        databaseConfiguration = suppliedConfiguration
    } else {
        guard app.environment != .testing else { throw AppConfigurationError.missingTestDatabaseConfiguration }
        databaseConfiguration = .postgres(configuration: .init(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
            database: Environment.get("DATABASE_NAME") ?? "vapor_database",
            tls: .prefer(try .init(configuration: .clientDefault))
        ))
    }
    let databases = suppliedDatabases ?? Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)
    databases.use(databaseConfiguration, as: .psql)

    // Run migrations before boot; the lifecycle handler also closes database connections.
    app.lifecycle.use(MigrateLifecycleHandler(databases: databases, migrations: CreateTodo()))

    // register routes
    try routes(app, databases: databases)
}
