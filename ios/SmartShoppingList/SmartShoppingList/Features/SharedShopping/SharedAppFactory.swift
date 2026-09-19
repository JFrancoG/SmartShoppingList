import Foundation

@MainActor
enum SharedAppFactory {
    static func make() -> SharedShoppingViewModel {
        let draft = ShoppingDraftViewModel(
            interpreter: FoundationModelsDraftInterpreter(),
            speech: SpeechCaptureService(),
            persistence: FileDraftPersistence(
                fileURL: URL.applicationSupportDirectory.appending(path: "SmartShoppingList/draft-v1.json")
            )
        )
        let configuration = try? SharedAPIConfiguration(bundle: .main)
        let api = configuration.map { SharedHTTPAPI(configuration: $0) }
        return SharedShoppingViewModel(
            api: api,
            configuration: configuration,
            credentials: SharedKeychainStore(),
            draft: draft
        )
    }
}
