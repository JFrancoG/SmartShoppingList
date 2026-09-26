import Foundation

/// Describes interpreted proposals and immutable confirmed submissions, including uncertain retries.
enum SharedAdditionMessage {
    static func proposed(items: [ShoppingDraftItem]) -> LocalizedStringResource {
        guard let prepared = try? ShoppingDraftRules.prepare(items) else { return "Review products before adding." }
        if let item = prepared.first, prepared.count == 1 {
            if let quantity = item.quantity {
                return "Add \(quantity) \(item.name) to the list for \(item.store)?"
            }
            return "Add \(item.name) to the list for \(item.store)?"
        }
        let lines = prepared.map { item in
            let product = [item.quantity, item.name].compactMap { $0 }.joined(separator: " ")
            return "\(product) · \(item.store)"
        }.joined(separator: "\n")
        return "Add these products to their lists?\n\(lines)"
    }

    static func confirmed(
        request: AddItemsRequest,
        sourceDraft: ShoppingDraftSnapshot,
        stores: [SharedStore]
    ) -> LocalizedStringResource {
        let destinations = request.items.enumerated().compactMap { index, item -> (id: String, name: String)? in
            switch item.store {
            case .newName(let name):
                let key = name.folding(options: .caseInsensitive, locale: Locale(identifier: "und"))
                return ("new:\(key)", name)
            case .existing(let id):
                if let store = stores.first(where: { $0.id == id }) {
                    return ("id:\(id)", store.name)
                }
                guard sourceDraft.items.indices.contains(index),
                      let name = ShoppingDraftRules.normalized(sourceDraft.items[index].store) else { return nil }
                return ("id:\(id)", name)
            }
        }
        guard destinations.count == request.items.count else {
            return "Added \(request.items.count) products to your shopping lists."
        }
        var seen = Set<String>()
        let storeNames = destinations.filter { seen.insert($0.id).inserted }.map(\.name)
        if let store = storeNames.first, storeNames.count == 1 {
            if let item = request.items.first, request.items.count == 1 {
                if let quantity = item.quantity, !quantity.isEmpty {
                    return "Added \(quantity) \(item.name) to the list for \(store)."
                }
                return "Added \(item.name) to the list for \(store)."
            }
            return "Added \(request.items.count) products to the list for \(store)."
        }
        return "Added \(request.items.count) products to the lists for \(storeNames, format: .list(type: .and))."
    }
}
