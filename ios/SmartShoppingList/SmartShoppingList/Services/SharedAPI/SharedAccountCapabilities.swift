import Foundation

struct SharedAccountCapabilities: Codable, Equatable {
    private let count: Int
    private let permitsCreation: Bool
    private let permitsJoining: Bool
    private let accountLimits: SharedAccountLimits

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
        limits: SharedAccountLimits
    ) throws {
        guard membershipCount >= 0, let maximum = limits.groupsPerAccount.maximum,
              maximum > 0, limits.groupsPerAccount.enforced,
              canCreateGroup == (membershipCount < maximum), canJoinGroup == (membershipCount < maximum) else {
            throw SharedAPIError.invalidResponse
        }
        count = membershipCount
        permitsCreation = canCreateGroup
        permitsJoining = canJoinGroup
        accountLimits = limits
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            membershipCount: values.decode(Int.self, forKey: .membershipCount),
            canCreateGroup: values.decode(Bool.self, forKey: .canCreateGroup),
            canJoinGroup: values.decode(Bool.self, forKey: .canJoinGroup),
            limits: values.decode(SharedAccountLimits.self, forKey: .limits)
        )
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(count, forKey: .membershipCount)
        try values.encode(permitsCreation, forKey: .canCreateGroup)
        try values.encode(permitsJoining, forKey: .canJoinGroup)
        try values.encode(accountLimits, forKey: .limits)
    }

    private enum CodingKeys: String, CodingKey {
        case membershipCount, canCreateGroup, canJoinGroup, limits
    }
}

struct SharedAccountLimits: Codable, Equatable {
    let groupsPerAccount: SharedResourceLimit
}
