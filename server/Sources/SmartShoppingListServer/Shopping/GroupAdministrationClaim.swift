import Foundation
import FluentSQL
import Vapor

extension ShoppingService {
    static let pendingAdministration = APIProblem(
        status: .conflict,
        code: "administration_pending",
        message: "Un miembro debe asumir la administración antes de añadir o modificar contenido."
    )

    func claimAdministration(user: UUID, group: UUID, operation: UUID) async throws -> APIReply {
        let fingerprint = try fingerprint(type: "claimAdministration", group: group, value: .null)
        return try await database.accountTransaction { database in
            let sql = try shoppingSQL(database)
            try await lockGroup(group, on: sql)
            try await requireMembership(user, group: group, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: "claimAdministration",
                group: group,
                fingerprint: fingerprint,
                on: sql
            ) { return replay }
            guard try await sql.raw("""
                UPDATE groups SET administrator_user_id = \(bind: user),pending_administration = FALSE
                WHERE id = \(bind: group) AND pending_administration = TRUE AND administrator_user_id IS NULL
                RETURNING id
                """).first() != nil else {
                throw APIProblem(status: .conflict, code: "administration_already_assigned", message: "El grupo ya tiene administrador. Actualiza para consultarlo.")
            }
            return try await save(
                APIReply(status: .ok, json: loadGroup(id: group, user: user, on: sql).json),
                user: user,
                operation: operation,
                group: group,
                on: sql
            )
        }
    }
}
