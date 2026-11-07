import StoreKit

enum AppDistributionEvidence {
    case sandbox
    case production
    case unverified
    case unsupported
}

/// Reads app evidence only; it never refreshes receipts, starts purchases or selects a fallback server.
struct AppEnvironmentResolver {
    var read: @MainActor () async throws -> AppDistributionEvidence = readAppTransaction

    @MainActor
    func resolve() async throws -> AppEnvironment {
        try Task.checkCancellation()
        let evidence = try await read()
        try Task.checkCancellation()
        switch evidence {
        case .sandbox: return .sandbox
        case .production: return .production
        case .unverified: throw AppBootstrapError.unverified
        case .unsupported: throw AppBootstrapError.unsupportedEnvironment
        }
    }

    @MainActor
    static func live() async throws -> AppEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return try await AppEnvironmentResolver().resolve()
        #endif
    }

    @MainActor
    private static func readAppTransaction() async throws -> AppDistributionEvidence {
        switch try await AppTransaction.shared {
        case .verified(let transaction):
            switch transaction.environment {
            case .sandbox: .sandbox
            case .production: .production
            default: .unsupported
            }
        case .unverified: .unverified
        }
    }
}
