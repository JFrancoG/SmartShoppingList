import Foundation
import Observation

@MainActor
@Observable
final class DistributionDiagnosticsViewModel {
    let version: String
    let build: String
    private(set) var observation: AppTransactionObservation?
    private(set) var isChecking = false
    private(set) var requestCount = 0

    @ObservationIgnored private let read: @Sendable () async -> AppTransactionObservation
    @ObservationIgnored private var isReading = false

    init(
        version: String,
        build: String,
        observation: AppTransactionObservation? = nil,
        read: @escaping @Sendable () async -> AppTransactionObservation
    ) {
        self.version = version
        self.build = build
        self.observation = observation
        self.read = read
    }

    var status: LocalizedStringResource {
        if isChecking {
            return "Checking…"
        }
        switch observation {
        case nil: return "Not checked"
        case .verified: return "Verified"
        case .unverified: return "Unverified"
        case .unavailable: return "Unavailable"
        case .cancelled: return "Cancelled"
        }
    }

    var environment: String? {
        guard !isChecking, case .verified(let environment) = observation else { return nil }
        return environment.rawValue
    }

    func requestCheck() {
        guard !isChecking else { return }
        isChecking = true
        requestCount += 1
    }

    func checkIfRequested() async {
        guard requestCount > 0, isChecking, !isReading else { return }
        isReading = true
        defer {
            isReading = false
            isChecking = false
        }
        guard !Task.isCancelled else {
            observation = .cancelled
            return
        }
        let result = await read()
        observation = Task.isCancelled ? .cancelled : result
    }
}
