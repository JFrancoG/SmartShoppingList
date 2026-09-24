import SwiftUI

@main
struct SmartShoppingListApp: App {
    @State private var shopping = SharedAppFactory.make()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: shopping.draft, shared: shopping)
        }
    }
}
