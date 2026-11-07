import Foundation

/// One immutable destination for identity, persistence, invitations and purchases.
enum AppEnvironment {
    case sandbox
    case production

    var configuration: SharedAPIConfiguration {
        get throws {
            let origin = switch self {
            case .sandbox: "https://smartshoppinglistsandbox-sandbox.up.railway.app"
            case .production: "https://smartshoppinglist-production.up.railway.app"
            }
            return try SharedAPIConfiguration(baseURL: origin, invitationOrigin: origin)
        }
    }

    var subscriptionEnvironment: SharedStoreEnvironment {
        switch self {
        case .sandbox: .sandbox
        case .production: .production
        }
    }

    var other: AppEnvironment { self == .sandbox ? .production : .sandbox }
}

enum AppBootstrapError: Error, Equatable {
    case unavailable
    case unverified
    case unsupportedEnvironment
    case configuration
    case cancelled
}
