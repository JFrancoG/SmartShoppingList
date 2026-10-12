import CryptoKit
import Foundation

/// Production keeps its existing data; every other backend owns separate credentials and draft files.
struct SharedAppStorage {
    private let namespace: String?
    private let directory: URL

    var keychainService: String {
        "com.plusprojects.SmartShoppingList.shared-v1" + (namespace.map { ".\($0)" } ?? "")
    }

    var draftFileURL: URL {
        let path = namespace.map { "SmartShoppingList/backends/\($0)/draft-v1.json" }
            ?? "SmartShoppingList/draft-v1.json"
        return directory.appending(path: path)
    }
}

extension SharedAppStorage {
    init(configuration: SharedAPIConfiguration?, supportDirectory: URL = .applicationSupportDirectory) {
        let productionOrigin = "https://smartshoppinglist-production.up.railway.app:443"
        let origins = configuration.map {
            [Self.origin($0.baseURL), Self.origin($0.invitationOrigin)]
        }
        let scope: String?
        if origins == [productionOrigin, productionOrigin] {
            scope = nil
        } else if let origins {
            let digest = SHA256.hash(data: Data(origins.joined(separator: "\n").utf8))
            scope = digest.map { String(format: "%02x", $0) }.joined()
        } else {
            scope = "unconfigured"
        }
        namespace = scope
        directory = supportDirectory
    }

    private static func origin(_ url: URL) -> String {
        "https://\(url.host?.lowercased() ?? ""):\(url.port ?? 443)"
    }
}
