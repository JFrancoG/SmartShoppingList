import FoundationModels
import SwiftUI
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast)) @MainActor
struct AppIconControllerTests {
    @Test("Unsupported hardware gets Check only once per launch")
    func unsupportedDevice() async {
        let client = RecordingIconClient()
        let controller = AppIconController(
            client: client,
            availability: { .unavailable(.deviceNotEligible) },
            isEnabled: true
        )
        await controller.sceneDidChange(to: .background)
        #expect(client.requests.isEmpty)
        await controller.sceneDidChange(to: .active)
        await controller.sceneDidChange(to: .inactive)
        await controller.sceneDidChange(to: .active)
        #expect(client.requests == ["SmartShoppingListIconCheck"])
    }

    @Test("Capable devices use Brain even when Intelligence is disabled or downloading", arguments: [0, 1, 2])
    func capableDevice(state: Int) async {
        let client = RecordingIconClient()
        client.alternateIconName = "SmartShoppingListIconCheck"
        let availability: SystemLanguageModel.Availability = switch state {
        case 0: .available
        case 1: .unavailable(.appleIntelligenceNotEnabled)
        default: .unavailable(.modelNotReady)
        }
        let controller = AppIconController(client: client, availability: { availability }, isEnabled: true)
        await controller.sceneDidChange(to: .active)
        #expect(client.requests.count == 1)
        #expect(client.requests.first == .some(nil))
    }

    @Test("Correct icon, unsupported platform and disabled runtime never request a change")
    func noUnnecessaryChanges() async {
        let current = RecordingIconClient()
        current.alternateIconName = "SmartShoppingListIconCheck"
        let correct = AppIconController(
            client: current,
            availability: { .unavailable(.deviceNotEligible) },
            isEnabled: true
        )
        await correct.sceneDidChange(to: .active)
        #expect(current.requests.isEmpty)
        let unsupported = RecordingIconClient()
        unsupported.supportsAlternateIcons = false
        let noSupport = AppIconController(
            client: unsupported,
            availability: { .unavailable(.deviceNotEligible) },
            isEnabled: true
        )
        await noSupport.sceneDidChange(to: .active)
        #expect(unsupported.requests.isEmpty)
        let isolated = RecordingIconClient()
        let disabled = AppIconController(
            client: isolated,
            availability: {
                Issue.record("Must not probe model")
                return .available
            },
            isEnabled: false
        )
        await disabled.sceneDidChange(to: .active)
        #expect(isolated.requests.isEmpty)
    }

    @Test("A second scene cannot submit while the system request is suspended")
    func concurrentScenes() async {
        let client = RecordingIconClient()
        client.suspends = true
        let controller = AppIconController(
            client: client,
            availability: { .unavailable(.deviceNotEligible) },
            isEnabled: true
        )
        async let first: Void = controller.sceneDidChange(to: .active)
        await client.waitForRequest()
        await controller.sceneDidChange(to: .active)
        #expect(client.requests.count == 1)
        client.finishRequest()
        await first
    }

    @Test("System failure does not repeat requests on foreground")
    func failureDoesNotLoop() async {
        let client = RecordingIconClient()
        client.fails = true
        let controller = AppIconController(
            client: client,
            availability: { .unavailable(.deviceNotEligible) },
            isEnabled: true
        )
        await controller.sceneDidChange(to: .active)
        await controller.sceneDidChange(to: .active)
        #expect(client.requests.count == 1)
        #expect(client.alternateIconName == nil)
    }
}

@MainActor
private final class RecordingIconClient: AppIconChanging {
    var supportsAlternateIcons = true
    var alternateIconName: String?
    var requests: [String?] = []
    var fails = false
    var suspends = false
    private var requestStarted: CheckedContinuation<Void, Never>?
    private var pendingRequest: CheckedContinuation<Void, Never>?

    func setAlternateIconName(_ name: String?) async throws {
        requests.append(name)
        if suspends {
            await withCheckedContinuation { continuation in
                pendingRequest = continuation
                requestStarted?.resume()
                requestStarted = nil
            }
        }
        if fails {
            throw IconFailure.rejected
        }
        alternateIconName = name
    }

    func waitForRequest() async {
        guard requests.isEmpty else { return }
        await withCheckedContinuation { requestStarted = $0 }
    }

    func finishRequest() {
        pendingRequest?.resume()
        pendingRequest = nil
    }

    private enum IconFailure: Error { case rejected }
}
