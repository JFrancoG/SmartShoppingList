@testable import SmartShoppingListServer
import Testing
import Vapor
import FluentKit
import FluentPostgresDriver

@TaskLocal var _application: Application?

var app: Application {
    get throws { try #require(_application) }
}
@TaskLocal var _database: (any Database)?
@TaskLocal var _databases: Databases?

var testDatabases: Databases {
    get throws {
        try #require(_databases)
    }
}

var database: any Database {
    get throws { try #require(_database) }
}
struct AppTrait: TestTrait, SuiteTrait, TestScoping {
    // Each serialized test gets fresh migrations and its own application.
    let isRecursive = true

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable @concurrent () async throws -> Void
    ) async throws {
        let app = try await Application.make(.testing)
        let databases = Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)
        var configured = false
        var failure: (any Error)?

        do {
            // Application initialization loads .env.testing before this safety check.
            let configuration = try TestDatabaseConfiguration.make()
            try await configure(app, databases: databases, databaseConfiguration: configuration)
            configured = true
            try await app.asyncBoot()
            try await $_databases.withValue(databases) {
                try await $_database.withValue(databases.database()) {
                    try await $_application.withValue(app) {
                        try await function()
                    }
                }
            }
        } catch {
            failure = error
        }

        if configured {
            do {
                try await databases.revert(
                    migrations: CreateTodo(), CreateSharedShopping(), CreateAppleAuthentication(),
                    on: app
                )
            } catch {
                if failure == nil {
                    failure = error
                } else {
                    Issue.record(error, "Could not revert the isolated test database")
                }
            }
        }

        // Once configured, MigrateLifecycleHandler owns database shutdown, including failed boots.
        if !configured {
            await databases.shutdownAsync()
        }
        do {
            try await app.asyncShutdown()
        } catch {
            if failure == nil {
                failure = error
            } else {
                Issue.record(error, "Could not shut down the test application")
            }
        }
        if let failure {
            throw failure
        }
    }
}

extension Trait where Self == AppTrait {
    static func withApp() -> Self { .init() }
}

enum TestDatabaseConfiguration {
    enum ConfigurationError: Error, Equatable {
        case unsafeDatabaseName
        case nonlocalDatabaseHost
        case invalidPort
    }

    static func make(environment: (String) -> String? = Environment.get) throws -> DatabaseConfigurationFactory {
        let hostname = environment("TEST_DATABASE_HOST") ?? "127.0.0.1"
        let portValue = environment("TEST_DATABASE_PORT") ?? "5433"
        let databaseName = environment("TEST_DATABASE_NAME") ?? "smartshoppinglist_testing"
        let developmentDatabaseName = environment("DATABASE_NAME") ?? "vapor_database"

        guard databaseName.hasSuffix("_testing"), databaseName != developmentDatabaseName else {
            throw ConfigurationError.unsafeDatabaseName
        }
        guard ["127.0.0.1", "localhost", "::1", "db-test"].contains(hostname) else {
            throw ConfigurationError.nonlocalDatabaseHost
        }
        guard let port = Int(portValue), (1...65535).contains(port) else { throw ConfigurationError.invalidPort }

        return .postgres(configuration: .init(
            hostname: hostname,
            port: port,
            username: environment("TEST_DATABASE_USERNAME") ?? "vapor_test",
            password: environment("TEST_DATABASE_PASSWORD") ?? "vapor_test_password",
            database: databaseName,
            tls: .disable
        ), maxConnectionsPerEventLoop: 4)
    }
}
