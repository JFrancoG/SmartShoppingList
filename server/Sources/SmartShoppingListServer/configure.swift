import NIOSSL
import FluentKit
import FluentPostgresDriver
import Vapor

enum AppConfigurationError: Error, Equatable {
    case missingTestDatabaseConfiguration
    case invalidDatabaseCACertificatePEM
}

/// Configures the server; tests must provide their isolated database explicitly.
func configure(
    _ app: Application,
    databases suppliedDatabases: Databases? = nil,
    databaseConfiguration suppliedConfiguration: DatabaseConfigurationFactory? = nil
) async throws {
    // Vapor's low-level trace logs dump HTTP headers, including Authorization.
    // Preserve operational diagnostics while preventing credential dumps even with LOG_LEVEL=trace.
    app.logger.logLevel = max(app.logger.logLevel, .info)
    app.http.server.configuration.logger.logLevel = max(app.http.server.configuration.logger.logLevel, .info)

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
            tls: try DatabaseTLSConfiguration.make(caCertificatePEM: Environment.get("DATABASE_CA_CERTIFICATE_PEM"))
        ))
    }
    let databases = suppliedDatabases ?? Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)
    databases.use(databaseConfiguration, as: .psql)

    // Run migrations before boot; the lifecycle handler also closes database connections.
    app.lifecycle.use(MigrateLifecycleHandler(
        databases: databases,
        migrations: CreateTodo(), CreateSharedShopping(), CreateAppleAuthentication()
    ))

    app.routes.defaultMaxBodySize = "128kb"
    app.middleware.use(APIErrorMiddleware(), at: .beginning)

    // register routes
    try routes(app, databases: databases)
}

enum DatabaseTLSConfiguration {
    static func make(caCertificatePEM: String?) throws -> PostgresConnection.Configuration.TLS {
        guard let caCertificatePEM else { return .prefer(try .init(configuration: .clientDefault)) }
        guard !caCertificatePEM.isEmpty else { throw AppConfigurationError.invalidDatabaseCACertificatePEM }
        do {
            let certificates = try NIOSSLCertificate.fromPEMBytes(Array(caCertificatePEM.utf8))
            guard !certificates.isEmpty else { throw AppConfigurationError.invalidDatabaseCACertificatePEM }
            var configuration = TLSConfiguration.makeClientConfiguration()
            configuration.trustRoots = .certificates(certificates)
            configuration.certificateVerification = .fullVerification
            // A configured CA requires TLS; never fall back to an unencrypted connection.
            return .require(try .init(configuration: configuration))
        } catch {
            throw AppConfigurationError.invalidDatabaseCACertificatePEM
        }
    }
}
