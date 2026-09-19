import Foundation

/// Editable input may remain incomplete until the person prepares the reviewed batch.
struct ShoppingDraftItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var quantity = ""
    var store = ""
}

struct ShoppingDraftSnapshot: Codable, Equatable {
    var text = ""
    var items: [ShoppingDraftItem] = []
    var interpretedText: String? = nil
}

struct PreparedDraftItem: Identifiable, Equatable {
    private let itemID: UUID
    private let productName: String
    private let literalQuantity: String?
    private let storeName: String

    var id: UUID { itemID }
    var name: String { productName }
    var quantity: String? { literalQuantity }
    var store: String { storeName }
}

extension PreparedDraftItem {
    init(validating item: ShoppingDraftItem) throws(DraftValidationError) {
        itemID = item.id
        productName = try ShoppingDraftRules.validated(
            item.name,
            itemID: item.id,
            field: .name,
            limit: 160,
            required: true
        )
        let quantity = try ShoppingDraftRules.validated(
            item.quantity,
            itemID: item.id,
            field: .quantity,
            limit: 80,
            required: false
        )
        // Deleting an optional quantity in the form becomes null in the API contract.
        literalQuantity = quantity.isEmpty ? nil : quantity
        storeName = try ShoppingDraftRules.validated(
            item.store,
            itemID: item.id,
            field: .store,
            limit: 80,
            required: true
        )
    }
}

enum DraftField: Equatable {
    case name
    case quantity
    case store
}

enum DraftFieldIssue: Equatable {
    case required
    case tooLong
    case invalidCharacters
}

enum DraftValidationError: Error, Equatable {
    case emptyBatch
    case tooManyItems
    case invalidField(itemID: UUID, field: DraftField, reason: DraftFieldIssue)
}

enum ShoppingDraftRules {
    static func prepare(_ items: [ShoppingDraftItem]) throws(DraftValidationError) -> [PreparedDraftItem] {
        guard !items.isEmpty else { throw .emptyBatch }
        guard items.count <= 50 else { throw .tooManyItems }

        var prepared: [PreparedDraftItem] = []
        prepared.reserveCapacity(items.count)
        for item in items {
            prepared.append(try PreparedDraftItem(validating: item))
        }
        return prepared
    }

    static func normalized(_ text: String) -> String? {
        // Foundation's precomposed mapping truncates long combining sequences on iOS 27.
        // ICU's NFC transform preserves them; reject any failed or lossy transformation.
        guard let canonical = text.applyingTransform(StringTransform("Any-NFC"), reverse: false),
              canonical == text else { return nil }

        var scalars = String.UnicodeScalarView()
        var pendingSpace = false

        for scalar in canonical.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if pendingSpace {
                scalars.append(" ")
                pendingSpace = false
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    fileprivate static func validated(
        _ raw: String,
        itemID: UUID,
        field: DraftField,
        limit: Int,
        required: Bool
    ) throws(DraftValidationError) -> String {
        guard raw.unicodeScalars.count <= limit else {
            throw .invalidField(itemID: itemID, field: field, reason: .tooLong)
        }
        let containsInvalidControl = raw.unicodeScalars.contains {
            $0.properties.generalCategory == .control && !$0.properties.isWhitespace
        }
        guard !containsInvalidControl else {
            throw .invalidField(itemID: itemID, field: field, reason: .invalidCharacters)
        }

        guard let value = normalized(raw) else {
            throw .invalidField(itemID: itemID, field: field, reason: .invalidCharacters)
        }
        guard value.unicodeScalars.count <= limit else {
            throw .invalidField(itemID: itemID, field: field, reason: .tooLong)
        }
        guard !required || !value.isEmpty else { throw .invalidField(itemID: itemID, field: field, reason: .required) }
        return value
    }
}
