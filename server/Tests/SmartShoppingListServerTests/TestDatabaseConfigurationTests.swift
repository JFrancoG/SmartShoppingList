@testable import SmartShoppingListServer
import Testing
import Vapor

@Suite("Test database safety")
struct TestDatabaseConfigurationTests {
    @Test
    func `rejects development database`() {
        #expect(throws: TestDatabaseConfiguration.ConfigurationError.unsafeDatabaseName) {
            _ = try TestDatabaseConfiguration.make { key in
                key == "TEST_DATABASE_NAME" ? "vapor_database" : nil
            }
        }
    }

    @Test
    func `rejects shared database even with testing suffix`() {
        #expect(throws: TestDatabaseConfiguration.ConfigurationError.unsafeDatabaseName) {
            _ = try TestDatabaseConfiguration.make { key in
                ["DATABASE_NAME", "TEST_DATABASE_NAME"].contains(key) ? "shared_testing" : nil
            }
        }
    }

    @Test
    func `rejects remote database`() {
        #expect(throws: TestDatabaseConfiguration.ConfigurationError.nonlocalDatabaseHost) {
            _ = try TestDatabaseConfiguration.make { key in
                key == "TEST_DATABASE_HOST" ? "production.example.com" : nil
            }
        }
    }

    @Test(arguments: ["", "0", "65536", "postgres"])
    func `rejects invalid database port`(port: String) {
        #expect(throws: TestDatabaseConfiguration.ConfigurationError.invalidPort) {
            _ = try TestDatabaseConfiguration.make { key in
                key == "TEST_DATABASE_PORT" ? port : nil
            }
        }
    }

    @Test
    func `testing application refuses an implicit database configuration`() async throws {
        let application = try await Application.make(.testing)
        await #expect(throws: AppConfigurationError.self) {
            try await configure(application)
        }
        try await application.asyncShutdown()
    }
}
