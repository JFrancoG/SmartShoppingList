// Manual integration probe: copy into SmartShoppingListTests only for a compatible runtime.
// This file is not part of the automatic test target. Keep console output with the environment.
import Foundation
import Speech
import Testing
@testable import SmartShoppingList

@MainActor
struct Issue3ModelProbe {
    @Test(.timeLimit(.minutes(1)))
    func realModelExtractsThreeExplicitProducts() async throws {
        let interpreter = FoundationModelsDraftInterpreter()
        print("ISSUE3_MODEL_AVAILABILITY=\(interpreter.availability)")
        print("ISSUE3_SPEECH_AVAILABLE=\(SpeechTranscriber.isAvailable)")
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "es-ES"))
        print("ISSUE3_SPEECH_LOCALE=\(locale?.identifier ?? "none")")
        try #require(interpreter.availability == .available, "A real model is required; this is not a mocked test")

        let clock = ContinuousClock()
        let start = clock.now
        let products = try await interpreter.interpret("Necesito 2 litros de leche, una barra de pan y café en Mercadona")
        print("ISSUE3_MODEL_DURATION=\(start.duration(to: clock.now))")
        for product in products {
            print("ISSUE3_PRODUCT name=\(product.name) quantity=\(product.quantity ?? "nil") store=\(product.store ?? "nil")")
        }
        #expect(products.count == 3)
        #expect(products.allSatisfy { $0.store == "Mercadona" })
        #expect(products.map(\.name) == ["leche", "pan", "café"])
        #expect(products.last?.quantity == nil)
    }
}
