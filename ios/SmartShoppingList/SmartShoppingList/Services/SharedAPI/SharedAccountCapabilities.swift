import Foundation

struct SharedAccountCapabilities: Codable, Equatable {
    private let count: Int
    private let permitsCreation: Bool
    private let permitsJoining: Bool
    private let accountLimits: SharedAccountLimits
    var membershipAccess: SharedMembershipAccess? = nil

    var membershipCount: Int { count }
    var canCreateGroup: Bool { permitsCreation }
    var canJoinGroup: Bool { permitsJoining }
    var limits: SharedAccountLimits { accountLimits }
}

extension SharedAccountCapabilities {
    init(
        membershipCount: Int,
        canCreateGroup: Bool,
        canJoinGroup: Bool,
        limits: SharedAccountLimits,
        membershipAccess: SharedMembershipAccess? = nil
    ) throws {
        guard membershipCount >= 0, let maximum = limits.groupsPerAccount.maximum,
              maximum > 0, limits.groupsPerAccount.enforced,
              (!canCreateGroup || membershipCount < maximum), (!canJoinGroup || membershipCount < maximum) else {
            throw SharedAPIError.invalidResponse
        }
        count = membershipCount
        permitsCreation = canCreateGroup
        permitsJoining = canJoinGroup
        accountLimits = limits
        self.membershipAccess = membershipAccess
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            membershipCount: values.decode(Int.self, forKey: .membershipCount),
            canCreateGroup: values.decode(Bool.self, forKey: .canCreateGroup),
            canJoinGroup: values.decode(Bool.self, forKey: .canJoinGroup),
            limits: values.decode(SharedAccountLimits.self, forKey: .limits)
        )
        if values.contains(.premiumActive) {
            membershipAccess = try SharedMembershipAccess(from: decoder)
        }
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(count, forKey: .membershipCount)
        try values.encode(permitsCreation, forKey: .canCreateGroup)
        try values.encode(permitsJoining, forKey: .canJoinGroup)
        try values.encode(accountLimits, forKey: .limits)
        if let membershipAccess {
            try membershipAccess.encode(to: encoder)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case membershipCount, canCreateGroup, canJoinGroup, limits, premiumActive
    }
}

struct SharedAccountLimits: Codable, Equatable {
    let groupsPerAccount: SharedResourceLimit
}

/// Current account authority, independent of the device's active shopping group.
struct SharedMembershipAccess: Codable, Equatable {
    let premiumActive: Bool
    let premiumExpiresAt: Date?
    let transitionEndsAt: Date?
    let freeGroupId: UUID?
    let freeGroupChangeAvailableAt: Date?
    let canChangeFreeGroup: Bool
}

struct SelectFreeGroupRequest: Codable, Equatable {
    let operationId: UUID
    let groupId: UUID
}

extension SelectFreeGroupRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(groupId.uuidString.lowercased(), forKey: .groupId)
    }
}

struct SharedGroupAccess: Codable, Equatable {
    let canUseShopping: Bool
    let isFreeGroup: Bool

    // Existing explicit factories remain readable; a missing wire field decodes as nil and fails closed.
    static let ordinary = SharedGroupAccess(canUseShopping: true, isFreeGroup: false)
}
