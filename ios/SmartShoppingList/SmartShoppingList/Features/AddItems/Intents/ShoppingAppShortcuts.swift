import AppIntents

struct ShoppingAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to my list in \(.applicationName)",
                "Add to my shopping list in \(.applicationName)"
            ],
            shortTitle: "Add to list",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: AddDraftItemIntent(),
            phrases: [
                "Add a product in \(.applicationName)",
                "Add to my draft in \(.applicationName)"
            ],
            shortTitle: "Add product",
            systemImageName: "cart.badge.plus"
        )
    }
}
