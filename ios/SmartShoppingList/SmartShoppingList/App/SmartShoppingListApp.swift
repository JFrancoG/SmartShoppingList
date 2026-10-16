import AppIntents
import SwiftUI
import UIKit

@main
struct SmartShoppingListApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var iconController = AppIconController()
    @State private var shopping: SharedShoppingViewModel?

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
        let shopping = Self.makeShopping()
        _shopping = State(initialValue: shopping)
        if let shopping {
            AppDependencyManager.shared.add(dependency: shopping)
            ShoppingAppShortcuts.updateAppShortcutParameters()
        }
    }

    private static func makeShopping() -> SharedShoppingViewModel? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-shopping-notice-validation") {
            return nil
        }
        if ProcessInfo.processInfo.arguments.contains("-shopping-ai-validation")
            || ProcessInfo.processInfo.arguments.contains("-shopping-ai-empty-validation") {
            return try? SharedPreviewSupport.aiValidationViewModel(
                emptyInterpretation: ProcessInfo.processInfo.arguments.contains("-shopping-ai-empty-validation")
            )
        }
        if ProcessInfo.processInfo.arguments.contains("-shopping-ui-validation") {
            guard let fixture = try? SharedPreviewFixture.sample() else { return nil }
            return SharedPreviewSupport.viewModel(fixture: fixture, state: .group)
        }
        #endif
        return SharedAppFactory.make()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let shopping {
                    AppRootView(viewModel: shopping.draft, shared: shopping)
                } else {
                    ShoppingNoticeValidationView()
                }
                #else
                if let shopping {
                    AppRootView(viewModel: shopping.draft, shared: shopping)
                }
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
