import FluentKit
import Logging
import NIOCore
import NIOPosix
import Vapor

struct MigrateLifecycleHandler: LifecycleHandler {
    let databases: Databases
    let migrations: [any Migration]

    init(databases: Databases, migrations: any Migration...) {
        self.databases = databases
        self.migrations = migrations
    }

    func willBootAsync(_ application: Application) async throws {
        let migrations = Migrations()
        migrations.add(self.migrations)

        let migrator = Migrator(
            databases: databases,
            migrations: migrations,
            logger: application.logger,
            on: MultiThreadedEventLoopGroup.singleton.any()
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()
    }

    func shutdownAsync(_ application: Application) async {
        // Vapor shuts down lifecycle handlers before its stored ServeCommand.
        // Drain HTTP while its requests can still use the database, then close the pools.
        await application.server.shutdown()
        await databases.shutdownAsync()
    }
}
