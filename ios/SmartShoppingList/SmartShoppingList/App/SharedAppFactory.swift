import Foundation

@MainActor
enum SharedAppFactory {
    static func make() -> SharedShoppingViewModel {
        let language = AppLanguage.current
        let configuration = try? SharedAPIConfiguration(bundle: .main)
        let storage = SharedAppStorage(configuration: configuration)
        let draft = ShoppingDraftViewModel(
            interpreter: FoundationModelsDraftInterpreter(appLocale: language.locale),
            speech: SpeechCaptureService(localeIdentifier: language.locale.identifier),
            persistence: FileDraftPersistence(fileURL: storage.draftFileURL)
        )
        let api = configuration.map { SharedHTTPAPI(configuration: $0) }
        return SharedShoppingViewModel(
            api: api,
            configuration: configuration,
            credentials: SharedKeychainStore(service: storage.keychainService),
            draft: draft,
            storeQuery: StoreQueryViewModel(speech: SpeechCaptureService(localeIdentifier: language.locale.identifier)),
            subscriptionStore: StoreKitSubscriptionStore()
        )
    }
}
