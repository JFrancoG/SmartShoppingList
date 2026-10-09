import FluentKit
import FluentSQL

struct AddStoreArchiving: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let sql = try shoppingSQL(database)
        try await sql.raw("ALTER TABLE stores ADD COLUMN archived_at TIMESTAMPTZ").run()
    }

    func revert(on database: any Database) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await sql.raw("LOCK TABLE stores IN ACCESS EXCLUSIVE MODE").run()
            // Dropping this state would silently reactivate stores and consume capacity.
            guard try await sql.raw("SELECT 1 FROM stores WHERE archived_at IS NOT NULL LIMIT 1").first() == nil else {
                throw ReversionError.archivedStoresCannotBeRepresented
            }
            try await sql.raw("ALTER TABLE stores DROP COLUMN archived_at").run()
        }
    }

    enum ReversionError: Error, Equatable {
        case archivedStoresCannotBeRepresented
    }
}
