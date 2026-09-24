import Foundation
import FluentKit
import FluentSQL
import Vapor

extension ShoppingService {
    enum Resource: String, Sendable {
        case stores
        case invitations
        case items
    }

    func page(
        user: UUID,
        group: UUID,
        resource: Resource,
        store: UUID?,
        limit: Int,
        cursor: String?
    ) async throws -> APIReply {
        guard (1...100).contains(limit) else { throw APIProblem.invalidRequest }
        let position = try cursor.map {
            try ShoppingCursor(
                token: $0,
                key: cursorKey,
                resource: resource.rawValue,
                group: group,
                store: store
            )
        }
        return try await database.transaction { transaction in
            let sql = try shoppingSQL(transaction)
            if resource == .invitations {
                try await requireCreator(user, group: group, on: sql)
            } else {
                guard try await lockUser(user, on: sql) == group else { throw APIProblem.notFound }
            }
            var query: SQLQueryString = "SELECT * FROM \(ident: resource.rawValue) WHERE group_id = \(bind: group)"
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
            let values = try page.map { row in
                switch resource {
                case .stores: try Self.storeJSON(row)
                case .invitations: try Self.invitationJSON(row)
                case .items: try Self.itemJSON(row)
                }
            }
            let next: String?
            if rows.count > limit, let last = page.last {
                next = try ShoppingCursor(
                    resource: resource.rawValue,
                    groupID: group,
                    storeID: store,
                    createdAt: last.decode(column: "created_at", as: Date.self),
                    id: last.decode(column: "id", as: UUID.self)
                ).encoded(key: cursorKey)
            } else {
                next = nil
            }
            return try APIReply(status: .ok, json: .object([
                resource.rawValue: .array(values), "nextCursor": .optional(next)
            ]))
        }
    }

    static func storeJSON(_ row: any SQLRow) throws -> APIJSON {
        .object([
            "id": .string(try row.decode(column: "id", as: UUID.self).uuidString.lowercased()),
            "groupId": .string(try row.decode(column: "group_id", as: UUID.self).uuidString.lowercased()),
            "name": .string(try row.decode(column: "name", as: String.self))
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
