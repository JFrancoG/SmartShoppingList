import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
struct AppLanguageTests {
    @Test(arguments: [
        (["en-GB", "es"], "en"),
        (["es-MX", "en"], "es"),
        (["fr", "es-ES", "en-US"], "es"),
        (["en_US"], "en"),
        (["es_ES"], "es"),
        (["de"], "en"),
        ([], "en")
    ])
    func `App preferences choose the first supported language with English fallback`(
        preferences: [String], expectedLanguage: String
    ) {
        let language = AppLanguage(preferredLocalizations: preferences)

        #expect(language.locale.language.languageCode?.identifier == expectedLanguage)
    }

    @MainActor
    @Test(arguments: [
        ("en-GB", "Interpretation is unavailable in the selected language. You can continue manually."),
        ("en-US", "Interpretation is unavailable in the selected language. You can continue manually."),
        ("es", "La interpretación en el idioma seleccionado no está disponible. Puedes continuar a mano.")
    ])
    func `Unavailable language offers localized manual recovery without translating draft data`(
        localeIdentifier: String, expectedMessage: String
    ) throws {
        let draft = ShoppingDraftSnapshot(text: "café at Sainsbury’s")
        let model = ShoppingDraftViewModel(
            interpreter: UnsupportedLanguageInterpreter(),
            speech: LocalizationTestSpeech(),
            persistence: MemoryDraftPersistence(),
            initialDraft: draft
        )
        var message = model.availabilityMessage
        message.locale = Locale(identifier: localeIdentifier)
        #expect(String(localized: message) == expectedMessage)
        #expect(!model.canInterpret)

        model.beginAddingItem()
        model.editorItem.name = "café molido"
        model.editorItem.quantity = "two packs"
        model.editorItem.store = "Sainsbury’s"
        model.saveEditor()
        model.reviewDraft()

        let items = try #require(model.preparedItems)
        #expect(items.map(\.name) == ["café molido"])
        #expect(items.map(\.quantity) == ["two packs"])
        #expect(items.map(\.store) == ["Sainsbury’s"])
        #expect(model.text == "café at Sainsbury’s")
    }
}

private struct LocalizationTestSpeech: SpeechCapturing {
    func start() async throws -> AsyncThrowingStream<SpeechCaptureEvent, any Error> {
        throw SpeechCaptureError.unavailable
    }

    func finish() async throws {}
    func cancel() async {}
}

@MainActor
private struct UnsupportedLanguageInterpreter: DraftInterpreting {
    var availability: DraftInterpretationAvailability { .unsupportedLanguage }

    func interpret(_ text: String) async throws -> [SuggestedProduct] {
        throw DraftInterpretationError.unavailable
    }
}
