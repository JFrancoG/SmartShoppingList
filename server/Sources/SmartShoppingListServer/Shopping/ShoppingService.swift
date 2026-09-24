import Foundation
import FluentKit
import FluentSQL
import Vapor

struct ShoppingService: Sendable {
    let database: any Database
    let invitationOrigin: String?
    let cursorKey: SymmetricKey

    func createGroup(user: UUID, operation: UUID, name: String) async throws -> APIReply {
        let normalized = try ShoppingText.normalize(name, maximum: 80)
        let fingerprint = try fingerprint(
            type: "createGroup",
            group: nil,
            value: .object(["name": .string(normalized)])
        )
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            let current = try await lockUser(user, on: sql)
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: "createGroup",
                group: nil,
                fingerprint: fingerprint,
                currentGroup: current,
                on: sql
            ) {
                return replay
            }
            guard current == nil else {
                let conflict = try APIReply(status: .conflict, json: Self.alreadyInGroup.json)
                return try await save(
                    conflict,
                    user: user,
                    operation: operation,
                    group: nil,
                    on: sql
                )
            }
            let id = UUID()
            let now = try await databaseClock(sql)
            try await sql.raw("""
                INSERT INTO groups(id,name,creator_user_id,created_at)
                VALUES (\(bind: id),\(bind: normalized),\(bind: user),\(bind: now))
                """).run()
            try await sql.raw("UPDATE users SET group_id = \(bind: id) WHERE id = \(bind: user)").run()
            let group = try await loadShoppingGroup(id: id, on: sql)
            return try await save(
                APIReply(status: .created, json: group.json),
                user: user,
                operation: operation,
                group: id,
                on: sql
            )
        }
    }

    func addItems(
        user: UUID,
        group: UUID,
        operation: UUID,
        items: [ShoppingNewItem]
    ) async throws -> APIReply {
        guard (1...50).contains(items.count) else { throw APIProblem.invalidRequest }
        let fingerprint = try fingerprint(type: "addItems", group: group, value: .array(items.map(\.json)))
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            let current = try await lockUser(user, on: sql)
            guard current == group else { throw APIProblem.notFound }
            if let replay = try await reserve(
                user: user,
                operation: operation,
                type: "addItems",
                group: group,
                fingerprint: fingerprint,
                currentGroup: current,
                on: sql
            ) {
                return replay
            }
            // Resolve stores in one stable order to avoid inverted unique-index locks across members.
            let stores = try await resolveStores(items, group: group, on: sql)
            var result: [APIJSON] = []
            for item in items {
                let store: UUID
                switch item.store {
                case .existing(let id): store = id
                case .named(_, let key):
                    guard let id = stores[key] else { throw APIProblem.unavailable }
                    store = id
                }
                let id = UUID()
                let now = try await databaseClock(sql)
                try await sql.raw("""
                    INSERT INTO items(id,group_id,store_id,name,quantity,status,version,created_by,created_at)
                    VALUES (\(bind: id),\(bind: group),\(bind: store),\(bind: item.name),\(bind: item.quantity),
                        'pending',1,\(bind: user),\(bind: now))
                    """).run()
                guard let row = try await sql.raw("SELECT * FROM items WHERE id = \(bind: id)").first() else {
                    throw APIProblem.unavailable
                }
                result.append(try Self.itemJSON(row))
            }
            return try await save(
                APIReply(status: .created, json: .object(["items": .array(result)])),
                user: user,
                operation: operation,
                group: group,
                on: sql
            )
        }
    }

    func createInvitation(user: UUID, group: UUID) async throws -> APIReply {
        guard let origin = invitationOrigin, let url = URLComponents(string: origin),
            url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/"
        else {
            throw APIProblem.unavailable
        }
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await requireCreator(user, group: group, on: sql)
            let id = UUID()
            let secret = ShoppingSecret.generate()
            let now = try await databaseClock(sql)
            let expires = now.addingTimeInterval(86_400)
            let hash = ShoppingSecret.hash(secret)
            try await sql.raw("""
                INSERT INTO invitations(id,group_id,secret_hash,created_at,expires_at)
                VALUES (\(bind: id),\(bind: group),\(bind: hash),\(bind: now),\(bind: expires))
                """).run()
            guard let row = try await sql.raw("SELECT * FROM invitations WHERE id = \(bind: id)").first() else {
                throw APIProblem.unavailable
            }
            var link = url
            link.path = "/invite/\(id.uuidString.lowercased())"
            link.fragment = "token=\(secret)"
            guard let invitationURL = link.string else { throw APIProblem.unavailable }
            return try APIReply(status: .created, json: .object([
                "invitation": try Self.invitationJSON(row),
                "url": .string(invitationURL)
            ]))
        }
    }

    func invitation(
        user: UUID,
        id: UUID,
        secret: String,
        accepting: Bool
    ) async throws -> APIReply {
        try ShoppingSecret.validate(secret)
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            let currentGroup = try await lockUser(user, on: sql)
            let hash = ShoppingSecret.hash(secret)
            let row: (any SQLRow)?
            if accepting {
                row = try await sql.raw("""
                    SELECT * FROM invitations WHERE id = \(bind: id) AND secret_hash = \(bind: hash) FOR UPDATE
                    """).first()
            } else {
                row = try await sql.raw("""
                    SELECT * FROM invitations WHERE id = \(bind: id) AND secret_hash = \(bind: hash)
                    """).first()
            }
            guard let row else { throw APIProblem.notFound }
            let groupID = try row.decode(column: "group_id", as: UUID.self)
            let acceptedBy = try row.decode(column: "accepted_by", as: UUID?.self)
            let expires = try row.decode(column: "expires_at", as: Date.self)
            let alreadyAccepted = acceptedBy == user && currentGroup == groupID
            if !alreadyAccepted {
                if acceptedBy != nil {
                    throw Self.invitationProblem("invitation_consumed")
                }
                if try row.decode(column: "revoked_at", as: Date?.self) != nil {
                    throw Self.invitationProblem("invitation_revoked")
                }
                let now = try await databaseClock(sql)
                guard expires > now else { throw Self.invitationProblem("invitation_expired") }
                if accepting {
                    guard currentGroup == nil else { throw Self.alreadyInGroup }
                    try await sql.raw("UPDATE users SET group_id = \(bind: groupID) WHERE id = \(bind: user)").run()
                    try await sql.raw("""
                        UPDATE invitations SET accepted_by = \(bind: user), accepted_at = \(bind: now) WHERE id = \(bind: id)
                        """).run()
                }
            }
            let group = try await loadShoppingGroup(id: groupID, on: sql)
            if accepting {
                return try APIReply(status: .ok, json: group.json)
            }
            return try APIReply(status: .ok, json: .object([
                "group": group.json, "expiresAt": .string(APIEncoding.timestamp(expires)),
                "alreadyAccepted": .bool(alreadyAccepted)
            ]))
        }
    }

    func revokeInvitation(user: UUID, group: UUID, id: UUID) async throws {
        try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            try await requireCreator(user, group: group, on: sql)
            guard let row = try await sql.raw("""
                SELECT * FROM invitations WHERE id = \(bind: id) AND group_id = \(bind: group) FOR UPDATE
                """).first()
            else {
                throw APIProblem.notFound
            }
            guard try row.decode(column: "accepted_by", as: UUID?.self) == nil else {
                throw APIProblem(
                    status: .conflict,
                    code: "invitation_consumed",
                    message: "La invitación ya se ha aceptado."
                )
            }
            if try row.decode(column: "revoked_at", as: Date?.self) == nil {
                try await sql.raw("UPDATE invitations SET revoked_at = clock_timestamp() WHERE id = \(bind: id)").run()
            }
        }
    }
}

extension ShoppingService {
    static var alreadyInGroup: APIProblem {
        .init(status: .conflict, code: "already_in_group", message: "El usuario ya pertenece a un grupo.")
    }

    static func invitationProblem(_ code: String) -> APIProblem {
        .init(status: .gone, code: code, message: "La invitación ya no está disponible.")
    }

    func lockUser(_ id: UUID, on sql: any SQLDatabase) async throws -> UUID? {
        guard let row = try await sql.raw("SELECT group_id FROM users WHERE id = \(bind: id) FOR UPDATE").first() else {
            throw APIProblem.notFound
        }
        return try row.decode(column: "group_id", as: UUID?.self)
    }

    func requireCreator(_ user: UUID, group: UUID, on sql: any SQLDatabase) async throws {
        guard try await lockUser(user, on: sql) == group else { throw APIProblem.notFound }
        let actual = try await loadShoppingGroup(id: group, on: sql)
        guard actual.creatorUserId == user.uuidString.lowercased() else {
            throw APIProblem(status: .forbidden, code: "creator_required", message: "Se requiere el creador del grupo.")
        }
    }

    func fingerprint(type: String, group: UUID?, value: APIJSON) throws -> String {
        let data = try APIEncoding.data(APIJSON.object([
            "operation": .string(type), "group": .optional(group?.uuidString.lowercased()), "payload": value
        ]))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func reserve(
        user: UUID,
        operation: UUID,
        type: String,
        group: UUID?,
        fingerprint: String,
        currentGroup: UUID?,
        on sql: any SQLDatabase
    ) async throws -> APIReply? {
        let inserted = try await sql.raw("""
            INSERT INTO mutation_receipts(user_id,operation_id,operation_type,group_id,fingerprint)
            VALUES (\(bind: user),\(bind: operation),\(bind: type),\(bind: group),\(bind: fingerprint))
            ON CONFLICT(user_id,operation_id) DO NOTHING RETURNING operation_id
            """).first()
        guard inserted == nil else { return nil }
        // A separate statement sees a concurrently committed receipt under READ COMMITTED.
        guard let row = try await sql.raw("""
            SELECT * FROM mutation_receipts WHERE user_id = \(bind: user) AND operation_id = \(bind: operation)
            """).first()
        else {
            throw APIProblem.unavailable
        }
        guard try row.decode(column: "fingerprint", as: String.self) == fingerprint else {
            throw APIProblem(
                status: .conflict,
                code: "idempotency_key_reused",
                message: "La clave pertenece a otra intención."
            )
        }
        if let receiptGroup = try row.decode(column: "group_id", as: UUID?.self), receiptGroup != currentGroup {
            throw APIProblem.notFound
        }
        guard let status = try row.decode(column: "status", as: Int?.self),
            let body = try row.decode(column: "body", as: String?.self)
        else {
            throw APIProblem.unavailable
        }
        return APIReply(status: .init(statusCode: status), body: Data(body.utf8))
    }

    func save(
        _ reply: APIReply,
        user: UUID,
        operation: UUID,
        group: UUID?,
        on sql: any SQLDatabase
    ) async throws -> APIReply {
        let body = String(decoding: reply.body, as: UTF8.self)
        try await sql.raw("""
            UPDATE mutation_receipts SET status = \(bind: Int(reply.status.code)), body = \(bind: body), group_id = \(bind: group)
            WHERE user_id = \(bind: user) AND operation_id = \(bind: operation)
            """).run()
        return reply
    }

    func resolveStores(
        _ items: [ShoppingNewItem],
        group: UUID,
        on sql: any SQLDatabase
    ) async throws -> [String: UUID] {
        var names: [String: String] = [:]
        var existing: Set<UUID> = []
        for item in items {
            switch item.store {
            case .existing(let id): existing.insert(id)
            case .named(let name, let key):
                if names[key] == nil {
                    names[key] = name
                }
            }
        }
        for id in existing.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard try await sql.raw("""
                SELECT id FROM stores WHERE id = \(bind: id) AND group_id = \(bind: group)
                """).first() != nil
            else {
                throw APIProblem.notFound
            }
        }
        var result: [String: UUID] = [:]
        for key in names.keys.sorted() {
            guard let name = names[key] else { throw APIProblem.unavailable }
            try await sql.raw("""
                INSERT INTO stores(id,group_id,name,normalized_key) VALUES (\(bind: UUID()),\(bind: group),\(bind: name),\(bind: key))
                ON CONFLICT(group_id,normalized_key) DO NOTHING
                """).run()
            guard let row = try await sql.raw("""
                SELECT id FROM stores WHERE group_id = \(bind: group) AND normalized_key = \(bind: key)
                """).first()
            else {
                throw APIProblem.unavailable
            }
            result[key] = try row.decode(column: "id", as: UUID.self)
        }
        return result
    }
}
