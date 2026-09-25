import Foundation

/// Conservative matching offers real stores for review; it never creates a store from a transcript.
enum StoreQueryMatcher {
    static func matches(_ query: String, stores: [SharedStore]) -> [SharedStore] {
        let input = normalized(query)
        guard !input.isEmpty else { return [] }
        let prefixes = [
            "dame la lista de", "muestrame la lista de", "quiero la lista de", "la lista de",
            "show me the list for", "show me the list from", "give me the list for", "the list for"
        ]
        let name = prefixes.first { input.hasPrefix($0 + " ") }
            .map { String(input.dropFirst($0.count + 1)) } ?? input
        return stores.filter { store in
            let candidate = normalized(store.name)
            guard !candidate.isEmpty else { return false }
            return containsWords(candidate, in: input) || containsWords(name, in: candidate)
        }
    }

    private static func containsWords(_ words: String, in text: String) -> Bool {
        (" " + text + " ").contains(" " + words + " ")
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }
}
