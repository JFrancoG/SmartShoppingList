import SwiftUI

@main
struct SmartShoppingListApp: App {
    @State private var shopping: SharedShoppingViewModel? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-shopping-notice-validation") {
            return nil
        }
        #endif
        return SharedAppFactory.make()
    }()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let shopping {
                ContentView(viewModel: shopping.draft, shared: shopping)
            } else {
                ShoppingNoticeValidationView()
            }
            #else
            if let shopping {
                ContentView(viewModel: shopping.draft, shared: shopping)
            }
            #endif
        }
    }
}
