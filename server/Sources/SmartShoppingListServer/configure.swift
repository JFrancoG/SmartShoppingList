import NIOSSL
import FluentKit
import FluentPostgresDriver
import Vapor
/// configures your application
func configure(_ app: Application, databases suppliedDatabases: Databases? = nil) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    let databases = suppliedDatabases ?? Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)

    databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: .prefer(try .init(configuration: .clientDefault)))
    ), as: .psql)

    // close database connections cleanly on shutdown
    app.addService(databases)

    // run migrations before the app boots
    app.addLifecycleHandler(MigrateLifecycleHandler(databases: databases, migrations: CreateTodo()))

    // register routes
    try await routes(app, databases: databases)
}
