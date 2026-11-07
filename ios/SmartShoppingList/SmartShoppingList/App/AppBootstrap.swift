import Foundation
import Observation

@Observable @MainActor
final class AppBootstrap {
    enum State: Equatable {
        case idle
        case resolving
        case ready
        case recovery(AppBootstrapError)
    }

    private(set) var state = State.idle
    private(set) var environment: AppEnvironment?
    private(set) var shopping: SharedShoppingViewModel?
    var invitationNotice: LocalizedStringResource?

    @ObservationIgnored private let resolve: @MainActor () async throws -> AppEnvironment
    @ObservationIgnored private let makeShopping: @MainActor (AppEnvironment) throws -> SharedShoppingViewModel
    @ObservationIgnored private var resolution: Task<SharedShoppingViewModel, any Error>?
    @ObservationIgnored private var resolutionID: UUID?
    @ObservationIgnored private var incomingURL: URL?
    @ObservationIgnored private var isDeliveringInvitation = false

    init(
        resolve: @escaping @MainActor () async throws -> AppEnvironment = AppEnvironmentResolver.live,
        makeShopping: @escaping @MainActor (AppEnvironment) throws -> SharedShoppingViewModel = SharedAppFactory.make
    ) {
        self.resolve = resolve
        self.makeShopping = makeShopping
    }

    /// UI and headless intents share this resolution. Cancelling one caller never switches or recreates its context.
    func context() async throws -> SharedShoppingViewModel {
        try Task.checkCancellation()
        if let shopping { return shopping }
        if case .recovery(let error) = state { throw error }
        if let resolution {
            let result = try await resolution.value
            try Task.checkCancellation()
            return result
        }
        state = .resolving
        let identifier = UUID()
        resolutionID = identifier
        let task = Task { @MainActor in
            do {
                let selected = try await resolve()
                try Task.checkCancellation()
                let context = try makeShopping(selected)
                environment = selected
                shopping = context
                state = .ready
                return context
            } catch {
                let failure: AppBootstrapError
                if error is CancellationError {
                    failure = .cancelled
                } else if let bootstrapError = error as? AppBootstrapError {
                    failure = bootstrapError
                } else if error as? SharedAPIError == .configuration {
                    failure = .configuration
                } else {
                    failure = .unavailable
                }
                if resolutionID == identifier {
                    state = .recovery(failure)
                }
                throw failure
            }
        }
        resolution = task
        let result = try await task.value
        try Task.checkCancellation()
        return result
    }

    func cancelPreparation() {
        guard state == .resolving else { return }
        resolutionID = nil
        resolution?.cancel()
        state = .recovery(.cancelled)
    }

    func prepare() async {
        do {
            _ = try await context()
            await deliverInvitation()
        } catch {
            // The recovery state is visible; persisted data has not been opened on a guessed destination.
        }
    }

    func retry() async {
        guard case .recovery = state else { return }
        resolution = nil
        state = .idle
        await prepare()
    }

    func receiveInvitation(_ url: URL) async {
        incomingURL = url
        await prepare()
    }

    private func deliverInvitation() async {
        guard !isDeliveringInvitation, let shopping, let environment else { return }
        isDeliveringInvitation = true
        defer { isDeliveringInvitation = false }
        while let url = incomingURL {
            incomingURL = nil
            if let other = try? environment.other.configuration, (try? other.invitation(from: url)) != nil {
                invitationNotice = "This invitation belongs to the other version of the app. Open test invitations in TestFlight and real invitations in the App Store version."
            } else {
                await shopping.receiveInvitation(url)
            }
        }
    }
}

#if DEBUG
extension AppBootstrap {
    convenience init(previewShopping: SharedShoppingViewModel, environment: AppEnvironment) {
        self.init(resolve: { environment }, makeShopping: { _ in previewShopping })
        self.environment = environment
        shopping = previewShopping
        state = .ready
    }
}
#endif
