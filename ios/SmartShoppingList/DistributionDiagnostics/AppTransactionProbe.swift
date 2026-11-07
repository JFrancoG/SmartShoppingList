import StoreKit

enum AppTransactionObservation: Equatable {
    case verified(AppEnvironment)
    case unverified
    case unavailable
    case cancelled

    enum AppEnvironment: String {
        case sandbox
        case production
        case xcode
        case unknown
    }
}

struct AppTransactionProbe {
    func read() async -> AppTransactionObservation {
        guard !Task.isCancelled else { return .cancelled }
        do {
            let result = try await AppTransaction.shared
            guard !Task.isCancelled else { return .cancelled }
            switch result {
            case .verified(let transaction):
                switch transaction.environment {
                case .sandbox: return .verified(.sandbox)
                case .production: return .verified(.production)
                case .xcode: return .verified(.xcode)
                default: return .verified(.unknown)
                }
            case .unverified:
                return .unverified
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return Task.isCancelled ? .cancelled : .unavailable
        }
    }
}
