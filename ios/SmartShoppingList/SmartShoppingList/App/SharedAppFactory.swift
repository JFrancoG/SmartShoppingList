import Foundation

@MainActor
enum SharedAppFactory {
    static func make() -> SharedShoppingViewModel {
        let language = AppLanguage.current
        let draft = ShoppingDraftViewModel(
            interpreter: FoundationModelsDraftInterpreter(appLocale: language.locale),
            speech: SpeechCaptureService(localeIdentifier: language.locale.identifier),
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
            draft: draft,
            storeQuery: StoreQueryViewModel(speech: SpeechCaptureService(localeIdentifier: language.locale.identifier))
        )
    }
}
