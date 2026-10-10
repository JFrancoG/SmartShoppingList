import Foundation

struct SharedStoreCapabilities: Codable, Equatable {
    let canAddItems: Bool
    let canArchive: Bool
    let canRestore: Bool
}

struct SharedStoreState: Codable, Equatable {
    private let archiveDate: Date?
    private let pendingCount: Int
    private let permissions: SharedStoreCapabilities

    var archivedAt: Date? { archiveDate }
    var pendingItemCount: Int { pendingCount }
    var capabilities: SharedStoreCapabilities { permissions }
}

extension SharedStoreState {
    init(archivedAt: Date?, pendingItemCount: Int, capabilities: SharedStoreCapabilities) throws {
        guard pendingItemCount >= 0,
              archivedAt == nil || (pendingItemCount == 0 && !capabilities.canAddItems && !capabilities.canArchive),
              !capabilities.canArchive || pendingItemCount == 0,
              !capabilities.canRestore || archivedAt != nil else {
            throw SharedAPIError.invalidResponse
        }
        archiveDate = archivedAt
        pendingCount = pendingItemCount
        permissions = capabilities
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            archivedAt: values.decode(Date?.self, forKey: .archivedAt),
            pendingItemCount: values.decode(Int.self, forKey: .pendingItemCount),
            capabilities: values.decode(SharedStoreCapabilities.self, forKey: .capabilities)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(archiveDate, forKey: .archivedAt)
        try values.encode(pendingCount, forKey: .pendingItemCount)
        try values.encode(permissions, forKey: .capabilities)
    }

    private enum CodingKeys: String, CodingKey {
        case archivedAt, pendingItemCount, capabilities
    }
}

extension SharedStore {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        groupId = try values.decode(UUID.self, forKey: .groupId)
        name = try values.decode(String.self, forKey: .name)
        if values.contains(.archivedAt) || values.contains(.pendingItemCount) || values.contains(.capabilities) {
            state = try SharedStoreState(from: decoder)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(groupId, forKey: .groupId)
        try values.encode(name, forKey: .name)
        if let state {
            try values.encode(state.archivedAt, forKey: .archivedAt)
            try values.encode(state.pendingItemCount, forKey: .pendingItemCount)
            try values.encode(state.capabilities, forKey: .capabilities)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, groupId, name, archivedAt, pendingItemCount, capabilities
    }
}

struct SharedStoreLimits: Decodable, Equatable {
    let storesPerGroup: SharedResourceLimit
    let pendingItemsPerStore: SharedResourceLimit
}

struct SharedGroupCapacity: Decodable, Equatable {
    private let groupIdentifier: UUID
    private let ownerIdentifier: UUID
    private let storeCount: Int
    private let resourceLimits: SharedStoreLimits
    private let permitsCreation: Bool

    var groupId: UUID { groupIdentifier }
    var capacityOwnerUserId: UUID { ownerIdentifier }
    var activeStoreCount: Int { storeCount }
    var limits: SharedStoreLimits { resourceLimits }
    var canCreateStore: Bool { permitsCreation }
}

extension SharedGroupCapacity {
    init(
        groupId: UUID,
        capacityOwnerUserId: UUID,
        activeStoreCount: Int,
        limits: SharedStoreLimits,
        canCreateStore: Bool
    ) throws {
        guard activeStoreCount >= 0, let storeMaximum = limits.storesPerGroup.maximum, storeMaximum > 0,
              let itemMaximum = limits.pendingItemsPerStore.maximum, itemMaximum > 0,
              limits.storesPerGroup.enforced, limits.pendingItemsPerStore.enforced,
              (!canCreateStore || activeStoreCount < storeMaximum) else {
            throw SharedAPIError.invalidResponse
        }
        groupIdentifier = groupId
        ownerIdentifier = capacityOwnerUserId
        storeCount = activeStoreCount
        resourceLimits = limits
        permitsCreation = canCreateStore
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            groupId: values.decode(UUID.self, forKey: .groupId),
            capacityOwnerUserId: values.decode(UUID.self, forKey: .capacityOwnerUserId),
            activeStoreCount: values.decode(Int.self, forKey: .activeStoreCount),
            limits: values.decode(SharedStoreLimits.self, forKey: .limits),
            canCreateStore: values.decode(Bool.self, forKey: .canCreateStore)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case groupId, capacityOwnerUserId, activeStoreCount, limits, canCreateStore
    }
}

enum SharedStoreAction: String, Codable {
    case archive, restore
}

struct ChangeStoreStateRequest: Codable, Equatable {
    let operationId: UUID
}

extension ChangeStoreStateRequest {
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(operationId.uuidString.lowercased(), forKey: .operationId)
    }
}
