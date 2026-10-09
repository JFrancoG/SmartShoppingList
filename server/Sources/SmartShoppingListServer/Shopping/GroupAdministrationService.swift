import Foundation
import FluentKit
import FluentSQL
import Vapor

extension ShoppingService {
    enum TransferAction: String, Sendable {
        case accept
        case reject
        case withdraw

        var resolvedStatus: String {
            switch self {
            case .accept: "accepted"
            case .reject: "rejected"
            case .withdraw: "withdrawn"
            }
        }
    }

    func administration(user: UUID, group: UUID) async throws -> APIReply {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await lockGroup(group, on: sql)
            try await requireMembership(user, group: group, on: sql)
            try await refreshTransfers(group: group, on: sql)
            let actual = try await loadShoppingGroup(id: group, on: sql)
            let capacity = try await storeCapacity(group: group, on: sql)
            let count = try await memberCount(group: group, on: sql)
            let pending = try await pendingTransfer(group: group, on: sql)
            let accountMaximum = capacity.owner == user ? capacity.limits.groups : accountCapacity.maximum(for: user)
            return try APIReply(status: .ok, json: .object([
                "group": actual.json, "memberCount": .integer(count), "pendingTransfer": pending?.json ?? .null,
                "capabilities": GroupCapabilityPolicy.capabilities(
                    user: user,
                    administrator: actual.administratorUserId,
                    memberCount: count,
                    pending: pending,
                    accountMaximum: accountMaximum,
                    groupLimits: capacity.limits
                )
            ]))
        }
    }

    func proposeTransfer(
        user: UUID,
        group: UUID,
        operation: UUID,
        recipient: UUID
    ) async throws -> APIReply {
        let fingerprint = try fingerprint(
            type: "proposeAdministrationTransfer",
            group: group,
            value: .object(["recipientUserId": .string(recipient.uuidString.lowercased())])
        )
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await lockGroup(group, on: sql)
            try await requireMembership(user, group: group, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: "proposeAdministrationTransfer",
                group: group,
                fingerprint: fingerprint,
                on: sql
            ) {
                return replay
            }
            let actual = try await loadShoppingGroup(id: group, on: sql)
            guard actual.administratorUserId == user.uuidString.lowercased() else {
                throw Self.administrationProblem("administrator_required", forbidden: true)
            }
            guard recipient != user, try await sql.raw("""
                SELECT user_id FROM group_memberships WHERE user_id = \(bind: recipient) AND group_id = \(bind: group)
                """).first() != nil else {
                return try await saveAdministrationConflict(
                    "invalid_transfer_recipient",
                    user: user,
                    operation: operation,
                    group: group,
                    on: sql
                )
            }
            try await refreshTransfers(group: group, on: sql)
            guard try await pendingTransfer(group: group, on: sql) == nil else {
                return try await saveAdministrationConflict(
                    "transfer_pending",
                    user: user,
                    operation: operation,
                    group: group,
                    on: sql
                )
            }
            let id = UUID()
            let now = try await databaseClock(sql)
            try await sql.raw("""
                INSERT INTO group_administration_transfers
                    (id,group_id,proposer_user_id,recipient_user_id,status,created_at,expires_at)
                VALUES (\(bind: id),\(bind: group),\(bind: user),\(bind: recipient),'pending',
                    \(bind: now),\(bind: now.addingTimeInterval(7 * 86_400)))
                """).run()
            let transfer = try await loadTransfer(id: id, group: group, on: sql)
            return try await save(
                APIReply(status: .created, json: .object(["group": actual.json, "transfer": transfer.json])),
                user: user,
                operation: operation,
                group: group,
                on: sql
            )
        }
    }

    func resolveTransfer(
        user: UUID,
        group: UUID,
        operation: UUID,
        transferID: UUID,
        action: TransferAction
    ) async throws -> APIReply {
        let type = "administrationTransfer.\(action.rawValue)"
        let fingerprint = try fingerprint(type: type, group: group, value: .object([
            "transferId": .string(transferID.uuidString.lowercased())
        ]))
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await lockGroup(group, on: sql)
            try await requireMembership(user, group: group, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: type,
                group: group,
                fingerprint: fingerprint,
                on: sql
            ) {
                return replay
            }
            try await refreshTransfers(group: group, on: sql)
            let transfer = try await loadTransfer(id: transferID, group: group, on: sql)
            let actual = try await loadShoppingGroup(id: group, on: sql)
            if action == .withdraw {
                guard transfer.proposerID == user, actual.administratorUserId == user.uuidString.lowercased() else {
                    throw Self.administrationProblem("administrator_required", forbidden: true)
                }
            } else {
                guard transfer.recipientID == user else {
                    throw Self.administrationProblem("transfer_recipient_required", forbidden: true)
                }
            }
            guard transfer.status == "pending" else {
                let reply = try APIReply(
                    status: .conflict,
                    json: Self.administrationProblem("transfer_not_pending").json
                )
                return try await save(
                    reply,
                    user: user,
                    operation: operation,
                    group: group,
                    on: sql
                )
            }
            if action == .accept {
                try await sql.raw("""
                    UPDATE groups SET administrator_user_id = \(bind: user) WHERE id = \(bind: group)
                    """).run()
            }
            try await sql.raw("""
                UPDATE group_administration_transfers
                SET status = \(bind: action.resolvedStatus), resolved_at = clock_timestamp() WHERE id = \(bind: transferID)
                """).run()
            let updated = try await loadShoppingGroup(id: group, on: sql)
            let resolved = try await loadTransfer(id: transferID, group: group, on: sql)
            return try await save(
                APIReply(status: .ok, json: .object(["group": updated.json, "transfer": resolved.json])),
                user: user,
                operation: operation,
                group: group,
                on: sql
            )
        }
    }

    func departGroup(
        user: UUID,
        group: UUID,
        operation: UUID,
        confirmClosure: Bool
    ) async throws -> APIReply {
        let fingerprint = try fingerprint(
            type: "groupDeparture",
            group: group,
            value: .object(["confirmClosure": .bool(confirmClosure)])
        )
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            // A closed group may only expose the caller's exact, minimal confirmed departure receipt.
            guard try await sql.raw("SELECT id FROM groups WHERE id = \(bind: group) FOR UPDATE").first() != nil else {
                throw APIProblem.notFound
            }
            try await lockUser(user, on: sql)
            if let replay = try await departureReceipt(
                user: user,
                operation: operation,
                fingerprint: fingerprint,
                on: sql
            ) {
                return replay
            }
            guard try await isMember(user, group: group, on: sql) else { throw APIProblem.notFound }
            let actual = try await loadShoppingGroup(id: group, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: "groupDeparture",
                group: group,
                fingerprint: fingerprint,
                on: sql
            ) {
                return replay
            }
            let count = try await memberCount(group: group, on: sql)
            let closing = count == 1
            if actual.administratorUserId == user.uuidString.lowercased(), !closing {
                return try await saveAdministrationConflict(
                    "transfer_required",
                    user: user,
                    operation: operation,
                    group: group,
                    on: sql
                )
            }
            guard !closing || confirmClosure else {
                return try await saveAdministrationConflict(
                    "closure_confirmation_required",
                    user: user,
                    operation: operation,
                    group: group,
                    on: sql
                )
            }
            let now = try await databaseClock(sql)
            try await sql.raw("""
                UPDATE group_administration_transfers SET status = 'invalidated', resolved_at = \(bind: now)
                WHERE group_id = \(bind: group) AND status = 'pending'
                    AND (recipient_user_id = \(bind: user) OR proposer_user_id = \(bind: user))
                """).run()
            if closing {
                try await sql.raw("""
                    UPDATE groups SET administrator_user_id = NULL, closed_at = \(bind: now) WHERE id = \(bind: group)
                    """).run()
                try await sql.raw("""
                    UPDATE invitations SET revoked_at = COALESCE(revoked_at, \(bind: now))
                    WHERE group_id = \(bind: group) AND accepted_by IS NULL
                    """).run()
            }
            try await sql.raw("""
                DELETE FROM group_memberships WHERE user_id = \(bind: user) AND group_id = \(bind: group)
                """).run()
            try await sql.raw("""
                UPDATE users SET group_id = NULL WHERE id = \(bind: user) AND group_id = \(bind: group)
                """).run()
            return try await save(
                APIReply(status: .ok, json: .object([
                    "userId": .string(user.uuidString.lowercased()), "groupId": .string(group.uuidString.lowercased()),
                    "leftAt": .string(APIEncoding.timestamp(now)), "groupClosed": .bool(closing)
                ])),
                user: user,
                operation: operation,
                group: group,
                on: sql
            )
        }
    }
}

extension ShoppingService {
    private func refreshTransfers(group: UUID, on sql: any SQLDatabase) async throws {
        try await sql.raw("""
            UPDATE group_administration_transfers SET status = 'expired', resolved_at = clock_timestamp()
            WHERE group_id = \(bind: group) AND status = 'pending' AND expires_at <= clock_timestamp()
            """).run()
        try await sql.raw("""
            UPDATE group_administration_transfers AS transfer SET status = 'invalidated', resolved_at = clock_timestamp()
            WHERE transfer.group_id = \(bind: group) AND transfer.status = 'pending'
                AND (NOT EXISTS (SELECT 1 FROM group_memberships
                    WHERE user_id = transfer.recipient_user_id AND group_id = transfer.group_id)
                    OR NOT EXISTS (SELECT 1 FROM groups WHERE id = transfer.group_id
                        AND administrator_user_id = transfer.proposer_user_id AND closed_at IS NULL))
            """).run()
    }

    private func memberCount(group: UUID, on sql: any SQLDatabase) async throws -> Int64 {
        guard let row = try await sql.raw("""
            SELECT COUNT(*) AS count FROM group_memberships WHERE group_id = \(bind: group)
            """).first() else { throw APIProblem.unavailable }
        return try row.decode(column: "count", as: Int64.self)
    }

    private func pendingTransfer(group: UUID, on sql: any SQLDatabase) async throws -> GroupAdministrationTransfer? {
        try await sql.raw("""
            SELECT * FROM group_administration_transfers WHERE group_id = \(bind: group) AND status = 'pending'
            """).first().map(GroupAdministrationTransfer.init(row:))
    }

    private func loadTransfer(
        id: UUID,
        group: UUID,
        on sql: any SQLDatabase
    ) async throws -> GroupAdministrationTransfer {
        guard let row = try await sql.raw("""
            SELECT * FROM group_administration_transfers WHERE id = \(bind: id) AND group_id = \(bind: group)
            """).first() else { throw APIProblem.notFound }
        return try GroupAdministrationTransfer(row: row)
    }

    private func departureReceipt(
        user: UUID,
        operation: UUID,
        fingerprint: String,
        on sql: any SQLDatabase
    ) async throws -> APIReply? {
        guard let row = try await sql.raw("""
            SELECT * FROM mutation_receipts WHERE user_id = \(bind: user) AND operation_id = \(bind: operation)
            """).first() else { return nil }
        guard try row.decode(column: "operation_type", as: String.self) == "groupDeparture",
              try row.decode(column: "fingerprint", as: String.self) == fingerprint else {
            throw APIProblem(
                status: .conflict,
                code: "idempotency_key_reused",
                message: "La clave pertenece a otra intención."
            )
        }
        guard let status = try row.decode(column: "status", as: Int?.self),
              let body = try row.decode(column: "body", as: String?.self) else { throw APIProblem.unavailable }
        guard status == 200 else { return nil }
        return APIReply(status: .init(statusCode: status), body: Data(body.utf8))
    }

    private func saveAdministrationConflict(
        _ code: String,
        user: UUID,
        operation: UUID,
        group: UUID,
        on sql: any SQLDatabase
    ) async throws -> APIReply {
        try await save(
            APIReply(status: .conflict, json: Self.administrationProblem(code).json),
            user: user,
            operation: operation,
            group: group,
            on: sql
        )
    }

    private static func administrationProblem(_ code: String, forbidden: Bool = false) -> APIProblem {
        let message: String
        switch code {
        case "administrator_required": message = "Se requiere el administrador del grupo."
        case "transfer_recipient_required": message = "Solo el destinatario puede responder al traspaso."
        case "invalid_transfer_recipient": message = "El sucesor debe ser otro miembro del grupo."
        case "transfer_pending": message = "Resuelve o retira la propuesta pendiente."
        case "transfer_not_pending": message = "La propuesta ya no está pendiente."
        case "transfer_required": message = "Traspasa la administración antes de salir del grupo."
        case "closure_confirmation_required": message = "Confirma el cierre del grupo para salir como último miembro."
        default: message = "La operación no está disponible."
        }
        return APIProblem(status: forbidden ? .forbidden : .conflict, code: code, message: message)
    }
}
