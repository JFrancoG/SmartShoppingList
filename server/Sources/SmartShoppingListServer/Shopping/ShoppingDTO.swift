import Foundation
import FluentKit
import FluentSQL

struct ShoppingGroupDTO: Codable, Sendable {
    let id: String
    let name: String
    let creatorUserId: String
    let createdAt: String

    var json: APIJSON {
        .object([
            "id": .string(id), "name": .string(name),
            "creatorUserId": .string(creatorUserId), "createdAt": .string(createdAt)
        ])
    }
}

struct ShoppingUserDTO: Codable, Sendable {
    let id: String
    let displayName: String?
    let group: ShoppingGroupDTO?

    func encode(to encoder: any Encoder) throws {
        try APIJSON.object([
            "id": .string(id), "displayName": .optional(displayName), "group": group?.json ?? .null
        ]).encode(to: encoder)
    }
}

func loadShoppingUser(id: UUID, on database: any Database) async throws -> ShoppingUserDTO {
    let sql = try shoppingSQL(database)
    guard let row = try await sql.raw(
        "SELECT id, display_name, group_id FROM users WHERE id = \(bind: id)"
    ).first() else {
        throw APIProblem.notFound
    }
    let groupID = try row.decode(column: "group_id", as: UUID?.self)
    let group: ShoppingGroupDTO?
    if let groupID {
        group = try await loadShoppingGroup(id: groupID, on: sql)
    } else {
        group = nil
    }
    return ShoppingUserDTO(
        id: id.uuidString.lowercased(),
        displayName: try row.decode(column: "display_name", as: String?.self),
        group: group
    )
}

func loadShoppingGroup(id: UUID, on sql: any SQLDatabase) async throws -> ShoppingGroupDTO {
    guard let row = try await sql.raw("SELECT * FROM groups WHERE id = \(bind: id)").first() else {
        throw APIProblem.notFound
    }
    return ShoppingGroupDTO(
        id: id.uuidString.lowercased(),
        name: try row.decode(column: "name", as: String.self),
        creatorUserId: try row.decode(column: "creator_user_id", as: UUID.self).uuidString.lowercased(),
        createdAt: APIEncoding.timestamp(try row.decode(column: "created_at", as: Date.self))
    )
}
