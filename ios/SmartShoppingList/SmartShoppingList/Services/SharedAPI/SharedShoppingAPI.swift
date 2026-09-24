import Foundation

protocol SharedShoppingAPI: Sendable {
    func createChallenge() async throws -> SharedChallenge
    func loginWithApple(_ request: AppleLoginRequest) async throws -> SharedSession
    func currentUser(token: String) async throws -> SharedUser
    func logout(token: String) async throws
    func createGroup(_ request: CreateGroupRequest, token: String) async throws -> SharedGroup
    func stores(groupID: UUID, token: String) async throws -> [SharedStore]
    func createInvitation(groupID: UUID, token: String) async throws -> CreatedInvitation
    func invitations(groupID: UUID, token: String) async throws -> [SharedInvitation]
    func revokeInvitation(groupID: UUID, invitationID: UUID, token: String) async throws
    func previewInvitation(_ invitation: PendingInvitation, token: String) async throws -> InvitationPreview
    func acceptInvitation(_ invitation: PendingInvitation, token: String) async throws -> SharedGroup
    func addItems(_ request: AddItemsRequest, groupID: UUID, token: String) async throws -> [SharedItem]
    func pendingItems(groupID: UUID, storeID: UUID, token: String) async throws -> [SharedItem]
}

enum SharedAPIError: Error, Equatable {
    case configuration
    case invalidInvitation
    case invalidResponse
    case requestTooLarge
    case transport
    case server(status: Int, code: String, requestID: UUID?, retryAfter: Int?)

    var isSessionInvalid: Bool {
        guard case .server(401, let code, _, _) = self else { return false }
        return Self.matchesContract(status: 401, code: code)
    }

    var isUncertain: Bool {
        switch self {
        case .transport, .invalidResponse: true
        case .server(let status, let code, _, _):
            status >= 500 || status == 429 || !Self.matchesContract(status: status, code: code)
        default: false
        }
    }

    /// A proxy or malformed error body cannot prove the outcome of a mutation or consume an invitation.
    private static func matchesContract(status: Int, code: String) -> Bool {
        switch status {
        case 400: code == "invalid_request"
        case 401: ["invalid_session", "invalid_apple_credentials", "challenge_expired"].contains(code)
        case 403: code == "creator_required"
        case 404: code == "not_found"
        case 409:
            ["already_in_group", "challenge_consumed", "idempotency_key_reused", "item_conflict", "invitation_consumed"]
                .contains(code)
        case 410: ["invitation_expired", "invitation_revoked", "invitation_consumed"].contains(code)
        case 413: code == "body_too_large"
        default: false
        }
    }
}

struct SharedChallenge: Codable, Equatable {
    let id: UUID
    let nonce: String
    let expiresAt: Date
}

struct SharedGroup: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let creatorUserId: UUID
    let createdAt: Date
}

struct SharedUser: Identifiable, Codable, Equatable {
    let id: UUID
    let displayName: String?
    var group: SharedGroup?
}

extension SharedUser {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        displayName = try values.decode(String?.self, forKey: .displayName)
        group = try values.decode(SharedGroup?.self, forKey: .group)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(group, forKey: .group)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case group
    }
}

struct SharedSession: Codable, Equatable {
    let accessToken: String
    let tokenType: String
    let expiresAt: Date
    var user: SharedUser
}

struct SharedStore: Identifiable, Codable, Equatable {
    let id: UUID
    let groupId: UUID
    let name: String
}

struct SharedItem: Identifiable, Codable, Equatable {
    let id: UUID
    let groupId: UUID
    let storeId: UUID
    let name: String
    let quantity: String?
    let status: String
    let version: Int
    let createdBy: UUID
    let createdAt: Date
    let purchasedBy: UUID?
    let purchasedAt: Date?
}

struct SharedInvitation: Identifiable, Codable, Equatable {
    let id: UUID
    let groupId: UUID
    let createdAt: Date
    let expiresAt: Date
    let revokedAt: Date?
    let acceptedAt: Date?
    let acceptedBy: UUID?
}

struct CreatedInvitation: Codable, Equatable {
    let invitation: SharedInvitation
    let url: URL
}

struct InvitationPreview: Codable, Equatable {
    let group: SharedGroup
    let expiresAt: Date
    let alreadyAccepted: Bool
}

struct PendingInvitation: Codable, Equatable {
    let id: UUID
    let token: String
}

struct AppleLoginRequest: Codable, Equatable {
    let challengeId: UUID
    let identityToken: String
    let authorizationCode: String
    let displayName: String?
}

extension AppleLoginRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(challengeId.uuidString.lowercased(), forKey: .challengeId)
        try values.encode(identityToken, forKey: .identityToken)
        try values.encode(authorizationCode, forKey: .authorizationCode)
        try values.encodeIfPresent(displayName, forKey: .displayName)
    }
}

struct CreateGroupRequest: Codable, Equatable {
    let operationId: UUID
    let name: String
}

extension CreateGroupRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(name, forKey: .name)
    }
}

enum SharedStoreReference: Codable, Equatable {
    case existing(UUID)
    case newName(String)

    private enum CodingKeys: String, CodingKey {
        case id
        case newName
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .existing(let id):
            try values.encode(id.uuidString.lowercased(), forKey: .id)
        case .newName(let name):
            try values.encode(name, forKey: .newName)
        }
    }
}

extension SharedStoreReference {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try values.decodeIfPresent(UUID.self, forKey: .id), !values.contains(.newName) {
            self = .existing(id)
        } else if let name = try values.decodeIfPresent(String.self, forKey: .newName), !values.contains(.id) {
            self = .newName(name)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid store"))
        }
    }
}

struct SharedNewItem: Codable, Equatable {
    let name: String
    let quantity: String?
    let store: SharedStoreReference
}

extension SharedNewItem {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(name, forKey: .name)
        try values.encode(quantity, forKey: .quantity)
        try values.encode(store, forKey: .store)
    }
}

struct AddItemsRequest: Codable, Equatable {
    let operationId: UUID
    let items: [SharedNewItem]
}

extension AddItemsRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(items, forKey: .items)
    }
}

/// Retained until the same authenticated user resolves the original server result.
enum PendingSharedOperation: Codable, Equatable {
    case createGroup(userID: UUID, request: CreateGroupRequest)
    case addItems(userID: UUID, groupID: UUID, request: AddItemsRequest, sourceDraft: ShoppingDraftSnapshot)

    var userID: UUID {
        switch self {
        case .createGroup(let userID, _), .addItems(let userID, _, _, _): userID
        }
    }

    var operationID: UUID {
        switch self {
        case .createGroup(_, let request): request.operationId
        case .addItems(_, _, let request, _): request.operationId
        }
    }
}

protocol SharedCredentialStoring: Sendable {
    func loadSession() async throws -> SharedSession?
    func saveSession(_ session: SharedSession?) async throws
    func loadInvitation() async throws -> PendingInvitation?
    func saveInvitation(_ invitation: PendingInvitation?) async throws
    func loadIncomingInvitation() async throws -> PendingInvitation?
    func saveIncomingInvitation(_ invitation: PendingInvitation) async throws
    func clearIncomingInvitation(matching invitation: PendingInvitation) async throws -> Bool
    func loadOperation() async throws -> PendingSharedOperation?
    func saveOperation(_ operation: PendingSharedOperation?) async throws
}

actor MemorySharedCredentialStore: SharedCredentialStoring {
    private var session: SharedSession?
    private var invitation: PendingInvitation?
    private var incomingInvitation: PendingInvitation?
    private var operation: PendingSharedOperation?

    init(
        session: SharedSession? = nil,
        invitation: PendingInvitation? = nil,
        operation: PendingSharedOperation? = nil
    ) {
        self.session = session
        self.invitation = invitation
        self.operation = operation
    }

    func loadSession() -> SharedSession? { session }
    func loadInvitation() -> PendingInvitation? { invitation }
    func loadIncomingInvitation() -> PendingInvitation? { incomingInvitation }
    func loadOperation() -> PendingSharedOperation? { operation }

    func saveSession(_ session: SharedSession?) {
        self.session = session
    }

    func saveInvitation(_ invitation: PendingInvitation?) {
        self.invitation = invitation
    }

    func saveIncomingInvitation(_ invitation: PendingInvitation) {
        incomingInvitation = invitation
    }

    func clearIncomingInvitation(matching invitation: PendingInvitation) -> Bool {
        guard incomingInvitation == invitation else { return false }
        incomingInvitation = nil
        return true
    }

    func saveOperation(_ operation: PendingSharedOperation?) {
        self.operation = operation
    }
}
