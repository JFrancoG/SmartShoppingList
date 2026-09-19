import FluentKit
import Logging
import NIOCore
import NIOPosix
import Vapor

extension Databases {
    enum Error: Swift.Error {
        case noDatabaseConfigured
    }

    func database() throws(Error) -> any Database {
        // The driver's SQL diagnostics include bind values (nonces and encrypted grants).
        // Its configuration cannot disable query logging; isolate database diagnostics even at trace level.
        let logger = Logger(label: "shopping.database") { _ in SwiftLogNoOpLogHandler() }
        guard let database = self.database(logger: logger, on: MultiThreadedEventLoopGroup.singleton.any()) else {
            throw Error.noDatabaseConfigured
        }
        return database
    }

    func revert(migrations: any Migration..., on application: Application) async throws {
        let container = Migrations()
        container.add(migrations)

        let migrator = Migrator(
            databases: self,
            migrations: container,
            logger: Logger.current,
            on: MultiThreadedEventLoopGroup.singleton.any()
        )
        try await migrator.revertAllBatches().get()
    }
}
