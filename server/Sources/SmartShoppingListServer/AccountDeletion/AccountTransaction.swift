import Foundation
import FluentKit
import FluentSQL
import Vapor

extension Database {
    /// Ordinary transactions share a barrier; deletion briefly owns it exclusively before taking row locks.
    /// Never hold this barrier while contacting Apple. This also makes the affected group set stable during purge.
    func accountTransaction<T: Sendable>(
        exclusive: Bool = false,
        _ body: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await transaction { database in
            let sql = try shoppingSQL(database)
            if exclusive {
                try await sql.raw("SELECT pg_advisory_xact_lock(1936487268, 1)").run()
            } else {
                try await sql.raw("SELECT pg_advisory_xact_lock_shared(1936487268, 1)").run()
            }
            return try await body(database)
        }
    }
}

func requireActiveAccount(_ user: UUID, on sql: any SQLDatabase) async throws {
    guard try await sql.raw("SELECT id FROM users WHERE id = \(bind: user) AND deleting_at IS NULL").first() != nil else {
        throw APIProblem(status: .unauthorized, code: "invalid_session", message: "Vuelve a acceder a tu cuenta.")
    }
}

extension APIProblem {
    static let removedResult = Self(
        status: .gone,
        code: "result_removed",
        message: "El resultado ya no está disponible. Actualiza la lista; la operación no se ha repetido."
    )
}
