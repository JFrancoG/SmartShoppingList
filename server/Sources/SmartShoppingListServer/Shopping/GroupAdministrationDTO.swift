import Foundation
import FluentSQL

struct GroupAdministrationTransfer: Sendable {
    let id: UUID
    let groupID: UUID
    let proposerID: UUID
    let recipientID: UUID
    let status: String
    let createdAt: Date
    let expiresAt: Date
    let resolvedAt: Date?

    init(row: any SQLRow) throws {
        id = try row.decode(column: "id", as: UUID.self)
        groupID = try row.decode(column: "group_id", as: UUID.self)
        proposerID = try row.decode(column: "proposer_user_id", as: UUID.self)
        recipientID = try row.decode(column: "recipient_user_id", as: UUID.self)
        status = try row.decode(column: "status", as: String.self)
        createdAt = try row.decode(column: "created_at", as: Date.self)
        expiresAt = try row.decode(column: "expires_at", as: Date.self)
        resolvedAt = try row.decode(column: "resolved_at", as: Date?.self)
    }

    var json: APIJSON {
        .object([
            "id": .string(id.uuidString.lowercased()), "groupId": .string(groupID.uuidString.lowercased()),
            "proposerUserId": .string(proposerID.uuidString.lowercased()),
            "recipientUserId": .string(recipientID.uuidString.lowercased()), "status": .string(status),
            "createdAt": .string(APIEncoding.timestamp(createdAt)),
            "expiresAt": .string(APIEncoding.timestamp(expiresAt)),
            "resolvedAt": .optional(resolvedAt.map(APIEncoding.timestamp))
        ])
    }
}

/// The current release exposes its effective limits without pretending a paid entitlement exists.
enum GroupCapabilityPolicy {
    static func capabilities(
        user: UUID,
        administrator: String,
        memberCount: Int64,
        pending: GroupAdministrationTransfer?,
        accountMaximum: Int64
    ) -> APIJSON {
        let isAdministrator = administrator == user.uuidString.lowercased()
        let isRecipient = pending?.recipientID == user
        return .object([
            "canManageInvitations": .bool(isAdministrator),
            "canProposeTransfer": .bool(isAdministrator && memberCount > 1 && pending == nil),
            "canAcceptTransfer": .bool(isRecipient), "canRejectTransfer": .bool(isRecipient),
            "canWithdrawTransfer": .bool(isAdministrator && pending?.proposerID == user),
            "canLeave": .bool(!isAdministrator || memberCount == 1),
            "requiresClosureConfirmation": .bool(memberCount == 1),
            "capacityOwnerUserId": .string(administrator),
            "limits": .object([
                "groupsPerAccount": .object(["maximum": .integer(accountMaximum), "enforced": .bool(true)]),
                "storesPerGroup": .object(["maximum": .null, "enforced": .bool(false)]),
                "pendingItemsPerStore": .object(["maximum": .null, "enforced": .bool(false)])
            ])
        ])
    }
}
