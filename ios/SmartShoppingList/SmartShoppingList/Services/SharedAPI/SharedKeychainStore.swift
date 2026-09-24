import Foundation
import Security

enum SharedCredentialError: Error, Equatable {
    case unavailable(status: Int32)
    case corruptData
    case tooLarge
}

/// Each update replaces one value atomically; a locked or unreadable item is never treated as absent.
actor SharedKeychainStore: SharedCredentialStoring {
    private let service: String
    private let maximumBytes = 512 * 1_024

    init(service: String = "com.plusprojects.SmartShoppingList.shared-v1") {
        self.service = service
    }

    func loadSession() throws -> SharedSession? {
        try load(SharedSession.self, account: "session")
    }

    func saveSession(_ session: SharedSession?) throws {
        try save(session, account: "session")
    }

    func loadInvitation() throws -> PendingInvitation? {
        try load(PendingInvitation.self, account: "invitation")
    }

    func saveInvitation(_ invitation: PendingInvitation?) throws {
        try save(invitation, account: "invitation")
    }

    func loadIncomingInvitation() throws -> PendingInvitation? {
        try load(PendingInvitation.self, account: "incoming-invitation")
    }

    func saveIncomingInvitation(_ invitation: PendingInvitation) throws {
        try save(invitation, account: "incoming-invitation")
    }

    /// No actor suspension occurs between comparison and deletion; a newer received link survives promotion.
    func clearIncomingInvitation(matching invitation: PendingInvitation) throws -> Bool {
        guard try loadIncomingInvitation() == invitation else { return false }
        try save(Optional<PendingInvitation>.none, account: "incoming-invitation")
        return true
    }

    func loadOperation() throws -> PendingSharedOperation? {
        try load(PendingSharedOperation.self, account: "operation")
    }

    func saveOperation(_ operation: PendingSharedOperation?) throws {
        try save(operation, account: "operation")
    }

    private func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw SharedCredentialError.unavailable(status: status) }
        guard let data = result as? Data else { throw SharedCredentialError.corruptData }
        guard data.count <= maximumBytes else { throw SharedCredentialError.tooLarge }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SharedCredentialError.corruptData
        }
    }

    private func save<Value: Encodable>(_ value: Value?, account: String) throws {
        let query = query(account: account)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SharedCredentialError.unavailable(status: status)
            }
            return
        }
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw SharedCredentialError.tooLarge }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertion = query
            insertion.merge(attributes) { _, new in new }
            let status = SecItemAdd(insertion as CFDictionary, nil)
            guard status == errSecSuccess else { throw SharedCredentialError.unavailable(status: status) }
        } else if updateStatus != errSecSuccess {
            throw SharedCredentialError.unavailable(status: updateStatus)
        }
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}
