import Foundation
import FluentKit
import FluentSQL
import Vapor

extension ShoppingService {
    enum Resource: String, Sendable {
        case stores
        case invitations
        case items
        case members
    }

    func page(
        user: UUID,
        group: UUID,
        resource: Resource,
        store: UUID?,
        limit: Int,
        cursor: String?,
        state: StoreState = .active
    ) async throws -> APIReply {
        guard (1...100).contains(limit) else { throw APIProblem.invalidRequest }
        let cursorResource = resource == .stores ? state.cursorResource : resource.rawValue
        let position = try cursor.map {
            try ShoppingCursor(
                token: $0,
                key: cursorKey,
                resource: cursorResource,
                group: group,
                store: store
            )
        }
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            if resource == .invitations {
                try await requireAdministrator(user, group: group, on: sql)
            } else {
                try await lockGroup(group, on: sql)
                try await requireMembership(user, group: group, on: sql)
            }
            let capacity = resource == .stores ? try await storeCapacity(group: group, on: sql) : nil
            var query: SQLQueryString
            if resource == .members {
                query = """
                    SELECT users.* FROM users JOIN group_memberships ON group_memberships.user_id = users.id
                    WHERE group_memberships.group_id = \(bind: group)
                    """
            } else if resource == .stores {
                query = """
                    SELECT stores.*, (SELECT COUNT(*) FROM items
                        WHERE store_id = stores.id AND group_id = stores.group_id
                            AND status = 'pending') AS pending_count
                    FROM stores WHERE group_id = \(bind: group)
                    """
                query += state == .active ? " AND archived_at IS NULL" : " AND archived_at IS NOT NULL"
            } else {
                query = "SELECT * FROM \(ident: resource.rawValue) WHERE group_id = \(bind: group)"
            }
            if resource == .items {
                guard let store else { throw APIProblem.invalidRequest }
                guard try await sql.raw("""
                    SELECT id FROM stores WHERE group_id = \(bind: group) AND id = \(bind: store)
                    """).first() != nil
                else {
                    throw APIProblem.notFound
                }
                query += " AND store_id = \(bind: store) AND status = 'pending'"
            }
            if let position {
                query += " AND (created_at,id) > (\(bind: position.createdAt),\(bind: position.id))"
            }
            query += " ORDER BY created_at ASC,id ASC LIMIT \(bind: limit + 1)"
            let rows = try await sql.raw(query).all()
            let page = Array(rows.prefix(limit))
            let values = try page.map { row -> APIJSON in
                switch resource {
                case .stores:
                    guard let capacity else { throw APIProblem.unavailable }
                    return try ShoppingStore(row: row).json(user: user, capacity: capacity)
                case .invitations:
                    return try Self.invitationJSON(row)
                case .items:
                    return try Self.itemJSON(row)
                case .members:
                    return try Self.memberJSON(row)
                }
            }
            let next: String?
            if rows.count > limit, let last = page.last {
                next = try ShoppingCursor(
                    resource: cursorResource,
                    groupID: group,
                    storeID: store,
                    createdAt: last.decode(column: "created_at", as: Date.self),
                    id: last.decode(column: "id", as: UUID.self)
                ).encoded(key: cursorKey)
            } else {
                next = nil
            }
            return try APIReply(status: .ok, json: .object([
                (resource == .members ? "data" : resource.rawValue): .array(values), "nextCursor": .optional(next)
            ]))
        }
    }

    static func memberJSON(_ row: any SQLRow) throws -> APIJSON {
        .object([
            "id": .string(try row.decode(column: "id", as: UUID.self).uuidString.lowercased()),
            "displayName": .optional(try row.decode(column: "display_name", as: String?.self))
        ])
    }

    static func itemJSON(_ row: any SQLRow) throws -> APIJSON {
        .object([
            "id": .string(try row.decode(column: "id", as: UUID.self).uuidString.lowercased()),
            "groupId": .string(try row.decode(column: "group_id", as: UUID.self).uuidString.lowercased()),
            "storeId": .string(try row.decode(column: "store_id", as: UUID.self).uuidString.lowercased()),
            "name": .string(try row.decode(column: "name", as: String.self)),
            "quantity": .optional(try row.decode(column: "quantity", as: String?.self)),
            "status": .string(try row.decode(column: "status", as: String.self)),
            "version": .integer(try row.decode(column: "version", as: Int64.self)),
            "createdBy": .string(try row.decode(column: "created_by", as: UUID.self).uuidString.lowercased()),
            "createdAt": .string(APIEncoding.timestamp(try row.decode(column: "created_at", as: Date.self))),
            "purchasedBy": .optional(try row.decode(column: "purchased_by", as: UUID?.self)?.uuidString.lowercased()),
            "purchasedAt": .optional(try row.decode(column: "purchased_at", as: Date?.self).map(APIEncoding.timestamp))
        ])
    }

    static func invitationJSON(_ row: any SQLRow) throws -> APIJSON {
        .object([
            "id": .string(try row.decode(column: "id", as: UUID.self).uuidString.lowercased()),
            "groupId": .string(try row.decode(column: "group_id", as: UUID.self).uuidString.lowercased()),
            "createdAt": .string(APIEncoding.timestamp(try row.decode(column: "created_at", as: Date.self))),
            "expiresAt": .string(APIEncoding.timestamp(try row.decode(column: "expires_at", as: Date.self))),
            "revokedAt": .optional(try row.decode(column: "revoked_at", as: Date?.self).map(APIEncoding.timestamp)),
            "acceptedAt": .optional(try row.decode(column: "accepted_at", as: Date?.self).map(APIEncoding.timestamp)),
            "acceptedBy": .optional(try row.decode(column: "accepted_by", as: UUID?.self)?.uuidString.lowercased())
        ])
    }
}


extension ShoppingService {
    func groups(user: UUID, limit: Int, cursor: String?) async throws -> APIReply {
        guard (1...100).contains(limit) else { throw APIProblem.invalidRequest }
        // This resource binds the signed scope to the account, not to its legacy or locally selected group.
        let position = try cursor.map {
            try ShoppingCursor(
                token: $0,
                key: cursorKey,
                resource: "groups",
                group: user,
                store: nil
            )
        }
        let sql = try shoppingSQL(database)
        var query: SQLQueryString = """
            SELECT groups.* FROM group_memberships JOIN groups ON groups.id = group_memberships.group_id
            WHERE group_memberships.user_id = \(bind: user) AND groups.closed_at IS NULL
            """
        if let position {
            query += " AND (groups.created_at,groups.id) > (\(bind: position.createdAt),\(bind: position.id))"
        }
        query += " ORDER BY groups.created_at ASC,groups.id ASC LIMIT \(bind: limit + 1)"
        let rows = try await sql.raw(query).all()
        let page = Array(rows.prefix(limit))
        let values = try page.map { row in
            ShoppingGroupDTO(
                id: try row.decode(column: "id", as: UUID.self).uuidString.lowercased(),
                name: try row.decode(column: "name", as: String.self),
                creatorUserId: try row.decode(column: "creator_user_id", as: UUID.self).uuidString.lowercased(),
                administratorUserId: try row.decode(
                    column: "administrator_user_id",
                    as: UUID.self
                ).uuidString.lowercased(),
                createdAt: APIEncoding.timestamp(try row.decode(column: "created_at", as: Date.self))
            ).json
        }
        let next: String?
        if rows.count > limit, let last = page.last {
            next = try ShoppingCursor(
                resource: "groups",
                groupID: user,
                storeID: nil,
                createdAt: last.decode(column: "created_at", as: Date.self),
                id: last.decode(column: "id", as: UUID.self)
            ).encoded(key: cursorKey)
        } else {
            next = nil
        }
        return try APIReply(status: .ok, json: .object(["data": .array(values), "nextCursor": .optional(next)]))
    }
}
