import Foundation

enum DraftExtractionRules {
    /// Rejects the whole proposal when a name has no distinct, ordered mention in the source.
    /// This checks literal grounding; the model still determines shopping intent and field relationships.
    static func validate(_ products: [SuggestedProduct], source: String) throws {
        // A model can represent no matches with blank rows. Never discard a blank row from a mixed proposal.
        guard products.contains(where: { product in
            !normalizedWhitespace(product.name).isEmpty
                || !normalizedWhitespace(product.quantity ?? "").isEmpty
                || !normalizedWhitespace(product.store ?? "").isEmpty
        }) else {
            throw DraftInterpretationError.noProducts
        }
        let input = normalizedWhitespace(source)
        var cursor = input.startIndex

        for product in products {
            let name = normalizedWhitespace(product.name)
            guard !name.isEmpty, let mention = mention(of: name, in: input, from: cursor) else {
                throw DraftInterpretationError.failed
            }
            cursor = mention.upperBound
        }
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func mention(of name: String, in input: String, from start: String.Index) -> Range<String.Index>? {
        var cursor = start
        while cursor < input.endIndex,
              let range = input.range(of: name, options: .caseInsensitive, range: cursor..<input.endIndex) {
            let previous = input[..<range.lowerBound].last
            let next = input[range.upperBound...].first
            if !isWordCharacter(previous), !isWordCharacter(next) {
                return range
            }
            cursor = range.upperBound
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_"
    }
}
