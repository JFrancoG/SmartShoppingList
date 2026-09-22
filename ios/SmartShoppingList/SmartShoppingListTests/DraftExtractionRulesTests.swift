import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
struct DraftExtractionRulesTests {
    @Test
    func `A non shopping sentence cannot produce placeholder products`() {
        let products = [product("producto1"), product("producto2")]

        #expect(throws: DraftInterpretationError.failed) {
            try DraftExtractionRules.validate(products, source: "Hoy hace buen tiempo y voy a dar un paseo.")
        }
    }

    @Test
    func `One invented name rejects a proposal even when another product was requested`() {
        #expect(throws: DraftInterpretationError.failed) {
            try DraftExtractionRules.validate([product("pan"), product("café")], source: "Necesito pan")
        }
    }

    @Test(arguments: ["pantalla", "mazapán", "pan2", "pan_integral"])
    func `A product name cannot be fabricated from part of another word`(requestedName: String) {
        #expect(throws: DraftInterpretationError.failed) {
            try DraftExtractionRules.validate([product("pan")], source: "Comprar \(requestedName)")
        }
    }

    @Test
    func `Explicit names allow capitalization Unicode and whitespace variations`() throws {
        let products = [product("leche sin lactosa"), product("café"), product("producto1")]

        try DraftExtractionRules.validate(
            products,
            source: "Dos litros de LECHE\nsin  lactosa, cafe\u{0301} y producto1 de Mercadona."
        )
    }

    @Test
    func `Repeated products need separate mentions and keep their original order`() throws {
        let products = [product("pan"), product("café"), product("pan")]
        try DraftExtractionRules.validate(products, source: "Pan en Aldi, café y pan en Lidl")

        #expect(throws: DraftInterpretationError.failed) {
            try DraftExtractionRules.validate(products, source: "Pan y café en Aldi")
        }
        #expect(throws: DraftInterpretationError.failed) {
            try DraftExtractionRules.validate(products, source: "Pan, pan y café en Aldi")
        }
    }

    @Test
    func `A partial word match does not hide a later explicit mention`() throws {
        try DraftExtractionRules.validate([product("pan")], source: "Una pantalla y pan")
    }

    @Test
    func `An empty extraction reports no products`() {
        #expect(throws: DraftInterpretationError.noProducts) {
            try DraftExtractionRules.validate([], source: "Hoy hace buen tiempo")
        }
    }

    private func product(_ name: String) -> SuggestedProduct {
        SuggestedProduct(name: name, quantity: nil, store: nil)
    }
}
