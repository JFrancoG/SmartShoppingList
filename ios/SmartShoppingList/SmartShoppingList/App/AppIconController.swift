import FoundationModels
import OSLog
import SwiftUI
import UIKit

@MainActor
protocol AppIconChanging {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func setAlternateIconName(_ name: String?) async throws
}

@MainActor
struct SystemAppIconChanger: AppIconChanging {
    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
    var alternateIconName: String? { UIApplication.shared.alternateIconName }

    func setAlternateIconName(_ name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}

/// Coordinates a single system icon request across all app scenes in this launch.
@MainActor
final class AppIconController {
    private let client: any AppIconChanging
    private let availability: @MainActor () -> SystemLanguageModel.Availability
    private let isEnabled: Bool
    private var hasAttemptedChange = false
    private static let logger = Logger(subsystem: "com.plusprojects.SmartShoppingList", category: "AppIcon")

    init(
        client: any AppIconChanging = SystemAppIconChanger(),
        availability: @escaping @MainActor () -> SystemLanguageModel.Availability = {
            SystemLanguageModel.default.availability
        },
        isEnabled: Bool = AppIconController.isLiveApplication
    ) {
        self.client = client
        self.availability = availability
        self.isEnabled = isEnabled
    }

    func sceneDidChange(to phase: ScenePhase) async {
        guard isEnabled, phase == .active, !hasAttemptedChange, !Task.isCancelled else { return }
        guard client.supportsAlternateIcons else { return }
        let iconName: String?
        switch availability() {
        case .unavailable(.deviceNotEligible):
            iconName = "SmartShoppingListIconCheck"
        default:
            iconName = nil
        }
        guard client.alternateIconName != iconName else { return }
        // Set this before suspension: multiple scenes and the system alert can reactivate the app.
        hasAttemptedChange = true
        do {
            try await client.setAlternateIconName(iconName)
        } catch {
            Self.logger.error("Unable to change app icon: \(String(describing: error), privacy: .private)")
        }
    }

    private static var isLiveApplication: Bool {
        let process = ProcessInfo.processInfo
        return process.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1"
            && process.environment["XCTestConfigurationFilePath"] == nil
            && process.environment["XCTestBundlePath"] == nil
            && NSClassFromString("XCTestCase") == nil
            && !process.arguments.contains("-shopping-notice-validation")
            && !process.arguments.contains("-shopping-ai-validation")
            && !process.arguments.contains("-shopping-ai-empty-validation")
    }
}
