import Foundation
import FluentKit
import FluentSQL

struct ShoppingGroupDTO: Codable, Sendable {
    let id: String
    let name: String
    let creatorUserId: String
    let administratorUserId: String
    let createdAt: String
    let capabilities: APIJSON

    var json: APIJSON {
        .object([
            "id": .string(id), "name": .string(name),
            "creatorUserId": .string(creatorUserId), "administratorUserId": .string(administratorUserId),
            "createdAt": .string(createdAt), "capabilities": capabilities
        ])
    }
}

struct ShoppingUserDTO: Codable, Sendable {
    let id: String
    let displayName: String?
    let group: ShoppingGroupDTO?
    let accountCapabilities: APIJSON

    func encode(to encoder: any Encoder) throws {
        try APIJSON.object([
            "id": .string(id), "displayName": .optional(displayName), "group": group?.json ?? .null,
            "accountCapabilities": accountCapabilities
        ]).encode(to: encoder)
    }
}

func loadShoppingUser(
    id: UUID,
    on database: any Database,
    capacity: AccountCapacityPolicy = .init()
) async throws -> ShoppingUserDTO {
    try await database.transaction { transaction in
        let sql = try shoppingSQL(transaction)
        guard try await sql.raw("SELECT id FROM users WHERE id = \(bind: id) FOR NO KEY UPDATE").first() != nil else {
            throw APIProblem.notFound
        }
        let access = try await capacity.access(for: id, on: sql)
        // The account lock keeps access, membership count and legacy projection coherent with selection and departure.
        guard let row = try await sql.raw("""
            SELECT users.id, users.display_name, groups.id AS group_id, groups.name AS group_name,
                groups.creator_user_id, groups.administrator_user_id, groups.created_at AS group_created_at,
                (SELECT COUNT(*) FROM group_memberships JOIN groups AS member_group ON member_group.id = group_memberships.group_id
                    WHERE user_id = users.id AND member_group.closed_at IS NULL) AS membership_count
            FROM users
            LEFT JOIN group_memberships AS legacy ON legacy.user_id = users.id AND legacy.group_id = users.group_id
            LEFT JOIN groups ON groups.id = legacy.group_id AND groups.closed_at IS NULL
            WHERE users.id = \(bind: id)
            """).first() else {
            throw APIProblem.notFound
        }
        let groupID = try row.decode(column: "group_id", as: UUID?.self)
        let group: ShoppingGroupDTO?
        if let groupID {
            group = try ShoppingGroupDTO(
                id: groupID.uuidString.lowercased(),
                name: row.decode(column: "group_name", as: String.self),
                creatorUserId: row.decode(column: "creator_user_id", as: UUID.self).uuidString.lowercased(),
                administratorUserId: row.decode(column: "administrator_user_id", as: UUID.self).uuidString.lowercased(),
                createdAt: APIEncoding.timestamp(row.decode(column: "group_created_at", as: Date.self)),
                capabilities: access.groupCapabilities(groupID)
            )
        } else {
            group = nil
        }
        let count = try row.decode(column: "membership_count", as: Int64.self)
        return ShoppingUserDTO(
            id: id.uuidString.lowercased(),
            displayName: try row.decode(column: "display_name", as: String?.self),
            group: group,
            accountCapabilities: access.capabilities(membershipCount: count)
        )
    }
}

func loadShoppingGroup(id: UUID, capabilities: APIJSON, on sql: any SQLDatabase) async throws -> ShoppingGroupDTO {
    guard let row = try await sql.raw("SELECT * FROM groups WHERE id = \(bind: id) AND closed_at IS NULL").first() else {
        throw APIProblem.notFound
    }
    return ShoppingGroupDTO(
        id: id.uuidString.lowercased(),
        name: try row.decode(column: "name", as: String.self),
        creatorUserId: try row.decode(column: "creator_user_id", as: UUID.self).uuidString.lowercased(),
        administratorUserId: try row.decode(column: "administrator_user_id", as: UUID.self).uuidString.lowercased(),
        createdAt: APIEncoding.timestamp(try row.decode(column: "created_at", as: Date.self)),
        capabilities: capabilities
    )
}


extension ShoppingService {
    func loadGroup(id: UUID, user: UUID, on sql: any SQLDatabase) async throws -> ShoppingGroupDTO {
        let access = try await accountCapacity.access(for: user, on: sql)
        return try await loadShoppingGroup(id: id, capabilities: access.groupCapabilities(id), on: sql)
    }
}
