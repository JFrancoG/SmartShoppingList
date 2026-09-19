import Foundation
import Testing
@testable import SmartShoppingList

@Suite(.tags(.fast))
struct ShoppingDraftTests {
    @Test
    func `Preparing three reviewed products preserves quantities variants stores and order`() throws {
        let draft = [
            item(1, name: "  leche  sin lactosa ", quantity: " 2 litros ", store: " Mercadona "),
            item(2, name: "pan integral", quantity: "1 barra", store: "Día"),
            item(3, name: "café molido", quantity: "250 g", store: "Mercadona Centro")
        ]

        let prepared = try ShoppingDraftRules.prepare(draft)

        #expect(prepared.map(\.id) == [identifier(1), identifier(2), identifier(3)])
        #expect(prepared.map(\.name) == ["leche sin lactosa", "pan integral", "café molido"])
        #expect(prepared.map(\.quantity) == ["2 litros", "1 barra", "250 g"])
        #expect(prepared.map(\.store) == ["Mercadona", "Día", "Mercadona Centro"])
    }

    @Test
    func `Human edits remain authoritative when preparing a proposal`() throws {
        var draft = item(1, name: "leche", quantity: "1 litro", store: "Mercadona")
        draft.name = "leche SIN LACTOSA"
        draft.quantity = "3 briks"
        draft.store = "Día Norte"

        let prepared = try #require(ShoppingDraftRules.prepare([draft]).first)

        #expect(prepared.name == "leche SIN LACTOSA")
        #expect(prepared.quantity == "3 briks")
        #expect(prepared.store == "Día Norte")
    }

    @Test
    func `Two identical requested products remain two separate entries`() throws {
        let prepared = try ShoppingDraftRules.prepare([item(1), item(2)])

        #expect(prepared.count == 2)
        #expect(prepared.map(\.id) == [identifier(1), identifier(2)])
    }

    @Test
    func `Fifty items can be prepared as one batch`() throws {
        let prepared = try ShoppingDraftRules.prepare((1...50).map { item(UInt8($0)) })

        #expect(prepared.count == 50)
        #expect(prepared.first?.id == identifier(1))
        #expect(prepared.last?.id == identifier(50))
    }

    @Test
    func `Fifty one items are rejected without splitting the batch`() {
        #expect(throws: DraftValidationError.tooManyItems) {
            try ShoppingDraftRules.prepare((1...51).map { item(UInt8($0)) })
        }
    }

    @Test
    func `An empty batch cannot be prepared`() {
        #expect(throws: DraftValidationError.emptyBatch) {
            try ShoppingDraftRules.prepare([])
        }
    }

    @Test(arguments: ["", " \t\n\u{00A0}"])
    func `Deleting an optional quantity prepares an absent value`(quantity: String) throws {
        let prepared = try #require(ShoppingDraftRules.prepare([item(1, quantity: quantity)]).first)

        #expect(prepared.quantity == nil)
    }

    @Test(arguments: [
        (" \tCafe\u{0301}\u{00A0}\u{2003}molido\n", "Café molido"),
        ("leche\r\nSIN LACTOSA", "leche SIN LACTOSA"),
        ("Día–Norte", "Día–Norte"),
        (" \u{0085}\u{2028}\u{2029} ", "")
    ])
    func `Normalization preserves meaning and canonicalizes Unicode whitespace`(raw: String, expected: String) {
        #expect(ShoppingDraftRules.normalized(raw) == expected)
    }

    @Test
    func `Name limit counts Unicode scalars instead of grapheme clusters`() throws {
        let prepared = try #require(
            ShoppingDraftRules.prepare([item(1, name: String(repeating: "👍🏽", count: 80))]).first
        )

        #expect(prepared.name.unicodeScalars.count == 160)

        #expect(throws: DraftValidationError.invalidField(itemID: identifier(1), field: .name, reason: .tooLong)) {
            try ShoppingDraftRules.prepare([item(1, name: String(repeating: "👍🏽", count: 81))])
        }
    }

    @Test(arguments: [String(repeating: " ", count: 160) + "a", String(repeating: "e\u{0301}", count: 81)])
    func `Raw limits apply before whitespace removal or NFC composition`(rawName: String) {
        #expect(throws: DraftValidationError.invalidField(itemID: identifier(1), field: .name, reason: .tooLong)) {
            try ShoppingDraftRules.prepare([item(1, name: rawName)])
        }
    }

    @Test
    func `Normalized output must still fit when NFC expands scalars`() {
        #expect(throws: DraftValidationError.invalidField(itemID: identifier(1), field: .name, reason: .tooLong)) {
            try ShoppingDraftRules.prepare([item(1, name: String(repeating: "\u{0344}", count: 81))])
        }
    }

    @Test(arguments: [33, 80])
    func `Long combining sequences retain every scalar when prepared`(count: Int) throws {
        let prepared = try #require(
            ShoppingDraftRules.prepare([item(1, name: String(repeating: "\u{0344}", count: count))]).first
        )
        // U+0344 has the canonical decomposition U+0308 U+0301 and is excluded from composition.
        let expectedScalars: [UInt32] = (0..<count).flatMap { _ in [0x0308, 0x0301] }

        #expect(prepared.name.unicodeScalars.map(\.value) == expectedScalars)
    }

    @Test
    func `Store and literal quantity accept eighty scalars`() throws {
        let prepared = try #require(
            ShoppingDraftRules.prepare([
                item(1, quantity: String(repeating: "q", count: 80), store: String(repeating: "s", count: 80))
            ]).first
        )

        #expect(prepared.quantity?.unicodeScalars.count == 80)
        #expect(prepared.store.unicodeScalars.count == 80)
    }

    @Test(arguments: [DraftField.name, .quantity, .store])
    func `Non whitespace controls cannot enter a prepared item`(field: DraftField) {
        var draft = item(1)
        set("texto\u{0000}oculto", for: field, in: &draft)
        let error = DraftValidationError.invalidField(itemID: identifier(1), field: field, reason: .invalidCharacters)

        #expect(throws: error) {
            try ShoppingDraftRules.prepare([draft])
        }
    }

    @Test(arguments: [DraftField.quantity, .store])
    func `Eighty one scalars exceed store and quantity limits`(field: DraftField) {
        var draft = item(1)
        set(String(repeating: "a", count: 81), for: field, in: &draft)

        #expect(throws: DraftValidationError.invalidField(itemID: identifier(1), field: field, reason: .tooLong)) {
            try ShoppingDraftRules.prepare([draft])
        }
    }

    @Test(arguments: [DraftField.name, .store])
    func `A missing required field rejects the whole batch and identifies the invalid item`(field: DraftField) {
        var invalidItem = item(2)
        set(" \n\u{00A0}", for: field, in: &invalidItem)

        #expect(throws: DraftValidationError.invalidField(itemID: identifier(2), field: field, reason: .required)) {
            try ShoppingDraftRules.prepare([item(1), invalidItem, item(3)])
        }
    }

    private func item(
        _ number: UInt8,
        name: String = "pan integral",
        quantity: String = "1 barra",
        store: String = "Mercadona"
    ) -> ShoppingDraftItem {
        ShoppingDraftItem(
            id: identifier(number),
            name: name,
            quantity: quantity,
            store: store
        )
    }

    private func identifier(_ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
    }

    private func set(_ value: String, for field: DraftField, in item: inout ShoppingDraftItem) {
        switch field {
        case .name:
            item.name = value
        case .quantity:
            item.quantity = value
        case .store:
            item.store = value
        }
    }
}
