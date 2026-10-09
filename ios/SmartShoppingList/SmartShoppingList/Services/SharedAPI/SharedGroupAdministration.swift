import Foundation

struct SharedGroupMember: Identifiable, Codable, Equatable {
    let id: UUID
    let displayName: String?

    var visibleName: String? {
        guard let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
}

struct SharedGroupAdministration: Codable, Equatable {
    let group: SharedGroup
    let memberCount: Int
    let pendingTransfer: SharedGroupTransfer?
    let capabilities: SharedGroupCapabilities
}

struct SharedGroupCapabilities: Codable, Equatable {
    let canManageInvitations: Bool
    let canProposeTransfer: Bool
    let canAcceptTransfer: Bool
    let canRejectTransfer: Bool
    let canWithdrawTransfer: Bool
    let canLeave: Bool
    let requiresClosureConfirmation: Bool
    let capacityOwnerUserId: UUID
    let limits: SharedGroupLimits
}

struct SharedGroupLimits: Codable, Equatable {
    let groupsPerAccount: SharedResourceLimit
    let storesPerGroup: SharedResourceLimit
    let pendingItemsPerStore: SharedResourceLimit
}

struct SharedResourceLimit: Codable, Equatable {
    let maximum: Int?
    let enforced: Bool
}

struct SharedGroupTransfer: Identifiable, Codable, Equatable {
    let id: UUID
    let groupId: UUID
    let proposerUserId: UUID
    let recipientUserId: UUID
    let status: SharedGroupTransferStatus
    let createdAt: Date
    let expiresAt: Date
    let resolvedAt: Date?
}

enum SharedGroupTransferStatus: String, Codable {
    case pending, accepted, rejected, withdrawn, expired, invalidated
}

enum SharedGroupTransferAction: String, Codable {
    case accept, reject, withdraw
}

struct SharedGroupTransferResult: Codable, Equatable {
    let group: SharedGroup
    let transfer: SharedGroupTransfer
}

struct SharedGroupDeparture: Codable, Equatable {
    let userId: UUID
    let groupId: UUID
    let leftAt: Date
    let groupClosed: Bool
}

extension SharedGroupTransfer {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        groupId = try values.decode(UUID.self, forKey: .groupId)
        proposerUserId = try values.decode(UUID.self, forKey: .proposerUserId)
        recipientUserId = try values.decode(UUID.self, forKey: .recipientUserId)
        status = try values.decode(SharedGroupTransferStatus.self, forKey: .status)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        resolvedAt = try values.decode(Date?.self, forKey: .resolvedAt)
    }
}

extension SharedGroupAdministration {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        group = try values.decode(SharedGroup.self, forKey: .group)
        memberCount = try values.decode(Int.self, forKey: .memberCount)
        pendingTransfer = try values.decode(SharedGroupTransfer?.self, forKey: .pendingTransfer)
        capabilities = try values.decode(SharedGroupCapabilities.self, forKey: .capabilities)
    }
}

extension SharedGroupMember {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String?.self, forKey: .displayName)
    }
}

extension SharedResourceLimit {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        maximum = try values.decode(Int?.self, forKey: .maximum)
        enforced = try values.decode(Bool.self, forKey: .enforced)
    }
}

struct ProposeGroupTransferRequest: Codable, Equatable {
    let operationId: UUID
    let recipientUserId: UUID
}

struct ResolveGroupTransferRequest: Codable, Equatable {
    let operationId: UUID
}

struct LeaveGroupRequest: Codable, Equatable {
    let operationId: UUID
    let confirmClosure: Bool
}

extension ProposeGroupTransferRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(recipientUserId.uuidString.lowercased(), forKey: .recipientUserId)
    }
}

extension ResolveGroupTransferRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
    }
}

extension LeaveGroupRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(confirmClosure, forKey: .confirmClosure)
    }
}
