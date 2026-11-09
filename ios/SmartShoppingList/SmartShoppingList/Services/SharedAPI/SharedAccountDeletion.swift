import Foundation

protocol SharedAccountDeletionAPI: Sendable {
    func deletionPreview(token: String) async throws -> SharedDeletionPreview
    func deletionChallenge(_ request: SharedDeletionPreparation, token: String) async throws -> SharedChallenge
    func deleteAccount(_ request: SharedDeletionRequest, token: String) async throws -> SharedDeletionStatus
    func deletionStatus(_ receipt: SharedDeletionReceipt) async throws -> SharedDeletionStatus
    func cancelDeletion(_ receipt: SharedDeletionReceipt) async throws -> SharedDeletionStatus
    func deletionSessionStatus(token: String) async throws -> Bool
    func claimAdministration(_ request: ResolveGroupTransferRequest, groupID: UUID, token: String) async throws -> SharedGroup
}

struct SharedDeletionPreview: Codable, Equatable {
    let revision: String
    let groups: [Group]
    let ownContentCount: Int
    let legacyContentCount: Int

    struct Group: Identifiable, Codable, Equatable {
        let id: UUID
        let name: String
        let memberCount: Int
        let administers: Bool
        let willDelete: Bool
    }
}

struct SharedDeletionReceipt: Codable, Equatable {
    let operationId: UUID
    let statusSecret: String
}

struct SharedDeletionPreparation: Encodable {
    let operationId: UUID
    let statusSecret: String
    let revision: String
    enum CodingKeys: String, CodingKey { case operationId, statusSecret, revision }
}

struct SharedDeletionRequest: Encodable {
    let operationId: UUID
    let statusSecret: String
    let revision: String
    let challengeId: UUID
    let identityToken: String
    let authorizationCode: String
    enum CodingKeys: String, CodingKey {
        case operationId, statusSecret, revision, challengeId, identityToken, authorizationCode
    }
}

struct SharedDeletionStatus: Codable, Equatable {
    let operationId: UUID
    let status: State
    var appleRevocationOutcome: AppleRevocationOutcome? = nil

    enum State: String, Codable {
        case prepared, accepted, purging, completed, cancelled
        case dataDeleted = "data_deleted"

        var wasAccepted: Bool {
            switch self {
            case .accepted, .purging, .dataDeleted, .completed: true
            case .prepared, .cancelled: false
            }
        }
    }

    enum AppleRevocationOutcome: String, Codable {
        case confirmed
        case manualActionRequired = "manual_action_required"
    }
}

/// Saved before any preparation or destructive request. Contains no Apple authorization credentials.
struct PendingAccountDeletion: Codable, Equatable {
    let userID: UUID
    let receipt: SharedDeletionReceipt
    var revision: String
    var submitted = false
    var lastStatus: SharedDeletionStatus? = nil
    var localDataCleared = false
}

protocol SharedDeletionCredentialStoring: Sendable {
    func loadAccountDeletion() async throws -> PendingAccountDeletion?
    func saveAccountDeletion(_ deletion: PendingAccountDeletion?) async throws
}

extension SharedDeletionReceipt {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(statusSecret, forKey: .statusSecret)
    }
}

extension SharedDeletionPreparation {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(statusSecret, forKey: .statusSecret)
        try values.encode(revision, forKey: .revision)
    }
}

extension SharedDeletionRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
        try values.encode(statusSecret, forKey: .statusSecret)
        try values.encode(revision, forKey: .revision)
        try values.encode(challengeId.uuidString.lowercased(), forKey: .challengeId)
        try values.encode(identityToken, forKey: .identityToken)
        try values.encode(authorizationCode, forKey: .authorizationCode)
    }
}

/// A server-confirmed remote deletion can outlive partial local cleanup without using an expired session again.
protocol SharedDeletedAccountCleanupStoring: Sendable {
    func loadDeletedAccountUserID() async throws -> UUID?
    func saveDeletedAccountUserID(_ userID: UUID?) async throws
}
