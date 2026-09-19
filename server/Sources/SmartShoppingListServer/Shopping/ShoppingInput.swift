import Foundation
import Vapor

enum ShoppingText {
    /// Scalar limits apply both before and after NFC; canonical equivalence must not lose scalars.
    static func normalize(_ text: String, maximum: Int) throws -> String {
        guard (1...maximum).contains(text.unicodeScalars.count),
            !text.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) && !$0.properties.isWhitespace
            }),
            let canonical = text.applyingTransform(StringTransform("Any-NFC"), reverse: false), canonical == text
        else {
            throw APIProblem.invalidRequest
        }
        let result = canonical.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard (1...maximum).contains(result.unicodeScalars.count) else { throw APIProblem.invalidRequest }
        return result
    }

    /// Root-locale case folding preserves diacritics and punctuation; no fuzzy matching is performed.
    static func storeKey(_ name: String) throws -> String {
        let folded = name.folding(options: [.caseInsensitive], locale: Locale(identifier: "und"))
        guard let canonical = folded.applyingTransform(StringTransform("Any-NFC"), reverse: false), canonical == folded
        else {
            throw APIProblem.invalidRequest
        }
        return canonical
    }
}

enum ShoppingSecret {
    static func generate() -> String {
        let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return base64(bytes)
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func validate(_ value: String) throws {
        guard value.utf8.count == 43, let bytes = decode(value), bytes.count == 32, base64(bytes) == value else {
            throw APIProblem.invalidRequest
        }
    }

    static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var padded = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.utf8.count % 4) % 4)
        return Data(base64Encoded: padded)
    }
}

struct ShoppingNewItem: Sendable {
    enum Store: Sendable {
        case existing(UUID)
        case named(String, key: String)

        var json: APIJSON {
            switch self {
            case .existing(let id): .object(["id": .string(id.uuidString.lowercased())])
            case .named(let name, _): .object(["newName": .string(name)])
            }
        }
    }

    private let normalizedName: String
    private let normalizedQuantity: String?
    private let confirmedStore: Store

    var name: String { normalizedName }
    var quantity: String? { normalizedQuantity }
    var store: Store { confirmedStore }

    var json: APIJSON {
        .object(["name": .string(name), "quantity": .optional(quantity), "store": store.json])
    }
}

extension ShoppingNewItem {
    init(_ value: APIJSON) throws {
        let object = try APIObject(
            value,
            allowed: ["name", "quantity", "store"],
            required: ["name", "quantity", "store"]
        )
        normalizedName = try ShoppingText.normalize(object.string("name"), maximum: 160)
        normalizedQuantity = try object.optionalString("quantity").map { try ShoppingText.normalize($0, maximum: 80) }
        guard let value = object.values["store"] else { throw APIProblem.invalidRequest }
        let reference = try APIObject(value, allowed: ["id", "newName"], required: [])
        guard reference.values.count == 1 else { throw APIProblem.invalidRequest }
        if reference.values["id"] != nil {
            confirmedStore = .existing(try reference.uuid("id"))
        } else {
            let name = try ShoppingText.normalize(reference.string("newName"), maximum: 80)
            confirmedStore = .named(name, key: try ShoppingText.storeKey(name))
        }
    }
}

struct ShoppingCursor: Codable, Sendable {
    let resource: String
    let groupID: UUID
    let storeID: UUID?
    let createdAt: Date
    let id: UUID

    func encoded(key: SymmetricKey) throws -> String {
        let data = try APIEncoding.data(self)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
        return ShoppingSecret.base64(data) + "." + ShoppingSecret.base64(signature)
    }
}

extension ShoppingCursor {
    init(
        token: String,
        key: SymmetricKey,
        resource: String,
        group: UUID,
        store: UUID?
    ) throws {
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard token.utf8.count <= 512, components.count == 2,
            let data = ShoppingSecret.decode(String(components[0])),
            let signature = ShoppingSecret.decode(String(components[1])),
            ShoppingSecret.base64(data) == components[0], ShoppingSecret.base64(signature) == components[1],
            HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: data, using: key)
        else {
            throw APIProblem.invalidRequest
        }
        let cursor: Self
        do {
            cursor = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw APIProblem.invalidRequest
        }
        guard cursor.resource == resource, cursor.groupID == group, cursor.storeID == store else {
            throw APIProblem.invalidRequest
        }
        self = cursor
    }
}
