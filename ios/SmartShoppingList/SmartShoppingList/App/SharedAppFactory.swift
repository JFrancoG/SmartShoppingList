import Foundation

@MainActor
enum SharedAppFactory {
    static func make(environment: AppEnvironment) throws -> SharedShoppingViewModel {
        let language = AppLanguage.current
        let configuration = try environment.configuration
        let storage = SharedAppStorage(configuration: configuration)
        let draft = ShoppingDraftViewModel(
            interpreter: FoundationModelsDraftInterpreter(appLocale: language.locale),
            speech: SpeechCaptureService(localeIdentifier: language.locale.identifier),
            persistence: FileDraftPersistence(fileURL: storage.draftFileURL)
        )
        let api = SharedHTTPAPI(configuration: configuration)
        return SharedShoppingViewModel(
            api: api,
            configuration: configuration,
            credentials: SharedKeychainStore(service: storage.keychainService),
            draft: draft,
            storeQuery: StoreQueryViewModel(speech: SpeechCaptureService(localeIdentifier: language.locale.identifier)),
            subscriptionStore: StoreKitSubscriptionStore(expectedEnvironment: environment.subscriptionEnvironment)
        )
    }
}
