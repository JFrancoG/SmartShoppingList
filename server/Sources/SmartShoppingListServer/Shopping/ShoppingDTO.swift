import Foundation
import FluentKit
import FluentSQL

struct ShoppingGroupDTO: Codable, Sendable {
    let id: String
    let name: String
    let creatorUserId: String
    let administratorUserId: String
    let createdAt: String

    var json: APIJSON {
        .object([
            "id": .string(id), "name": .string(name),
            "creatorUserId": .string(creatorUserId), "administratorUserId": .string(administratorUserId),
            "createdAt": .string(createdAt)
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
    let sql = try shoppingSQL(database)
    // One statement keeps membership and its group in the same snapshot during a concurrent departure.
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
            createdAt: APIEncoding.timestamp(row.decode(column: "group_created_at", as: Date.self))
        )
    } else {
        group = nil
    }
    return ShoppingUserDTO(
        id: id.uuidString.lowercased(),
        displayName: try row.decode(column: "display_name", as: String?.self),
        group: group,
        accountCapabilities: try capacity.capabilities(
            user: id,
            membershipCount: row.decode(column: "membership_count", as: Int64.self)
        )
    )
}

func loadShoppingGroup(id: UUID, on sql: any SQLDatabase) async throws -> ShoppingGroupDTO {
    guard let row = try await sql.raw("SELECT * FROM groups WHERE id = \(bind: id) AND closed_at IS NULL").first() else {
        throw APIProblem.notFound
    }
    return ShoppingGroupDTO(
        id: id.uuidString.lowercased(),
        name: try row.decode(column: "name", as: String.self),
        creatorUserId: try row.decode(column: "creator_user_id", as: UUID.self).uuidString.lowercased(),
        administratorUserId: try row.decode(column: "administrator_user_id", as: UUID.self).uuidString.lowercased(),
        createdAt: APIEncoding.timestamp(try row.decode(column: "created_at", as: Date.self))
    )
}
