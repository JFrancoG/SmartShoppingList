import AppIntents
import SwiftUI
import UIKit

@main
struct SmartShoppingListApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var iconController = AppIconController()
    @State private var bootstrap: AppBootstrap

    init() {
        // Scope the adaptive selection tint to tab bars; alerts use the global NativeAccent.
        let tabAppearance = UITabBarAppearance()
        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.selected.iconColor = UIColor(resource: .appPrimary)
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(resource: .appPrimary)]
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        let bootstrap = AppBootstrap(makeShopping: Self.makeShopping)
        _bootstrap = State(initialValue: bootstrap)
        AppDependencyManager.shared.add(dependency: bootstrap)
        ShoppingAppShortcuts.updateAppShortcutParameters()
    }

    private static func makeShopping(environment: AppEnvironment) throws -> SharedShoppingViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-shopping-ai-validation")
            || ProcessInfo.processInfo.arguments.contains("-shopping-ai-empty-validation") {
            return try SharedPreviewSupport.aiValidationViewModel(
                emptyInterpretation: ProcessInfo.processInfo.arguments.contains("-shopping-ai-empty-validation")
            )
        }
        if ProcessInfo.processInfo.arguments.contains("-shopping-ui-validation") {
            let fixture = try SharedPreviewFixture.sample()
            return SharedPreviewSupport.viewModel(fixture: fixture, state: .group)
        }
        #endif
        return try SharedAppFactory.make(environment: environment)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-shopping-notice-validation") {
                    ShoppingNoticeValidationView()
                } else {
                    AppBootstrapView(bootstrap: bootstrap)
                }
                #else
                AppBootstrapView(bootstrap: bootstrap)
                #endif
            }
            .background {
                ShoppingWindowAccent()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            Task { await iconController.sceneDidChange(to: phase) }
        }
    }
}
