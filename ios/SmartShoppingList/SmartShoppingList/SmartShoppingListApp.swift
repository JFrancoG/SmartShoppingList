import SwiftUI

@main
struct SmartShoppingListApp: App {
    @State private var draft = ShoppingDraftViewModel(
        interpreter: FoundationModelsDraftInterpreter(),
        speech: SpeechCaptureService(),
        persistence: FileDraftPersistence(
            fileURL: URL.applicationSupportDirectory.appending(path: "SmartShoppingList/draft-v1.json")
        )
    )

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: draft)
        }
    }
}
